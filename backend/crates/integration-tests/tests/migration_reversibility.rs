// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Migration reversibility test (Tier 1, Postgres-only).
//!
//! Verifies that every database migration can be cleanly reverted,
//! ensuring safe rollbacks in production.
//!
//! ## Non-reversible migration policy
//!
//! If a migration cannot be reversed (e.g. a data backfill), add
//! `-- no-undo` at the top of its `.down.sql` file AND register the
//! version and reason in [`NON_REVERSIBLE_MIGRATIONS`]. The test
//! will skip the undo step for that version and fail loudly if a
//! `-- no-undo` migration is added without an allowlist entry.
//!
//! ## How it works
//!
//! 1. Scans all `.down.sql` files for `-- no-undo` markers.
//! 2. Asserts every such marker has a documented entry in the allowlist.
//! 3. Undoes all reversible migrations one-by-one (newest-first).
//! 4. Asserts the public schema is empty (no leftover tables).
//! 5. Re-applies all migrations to confirm idempotency.

mod fixtures;

use anyhow::{Context, Result};
use std::collections::BTreeSet;

/// Allowlist of intentionally non-reversible migrations.
///
/// Each entry documents:
/// - version: the migration version as an `i64`
/// - reason: why it cannot be reversed (e.g. data backfill, destructive column change)
///
/// To add a non-reversible migration:
/// 1. Add `-- no-undo` at the top of the `.down.sql` file.
/// 2. Register the version here with a clear reason.
/// 3. The test will skip the undo step for that version.
///
/// If you add `-- no-undo` without an allowlist entry, the test fails loudly.
const NON_REVERSIBLE_MIGRATIONS: &[(i64, &str)] = &[
    // Example: (20250703000001, "irreversible data backfill — see PR #123"),
];

/// Absolute path to the migrations directory, resolved at compile time.
const MIGRATIONS_DIR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../infra/migrations");

#[tokio::test]
async fn migrations_are_reversible() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;

    // ── 1. Build the embedded migrator from the compile-time source ──────
    let migrator = sqlx::migrate!("../infra/migrations");

    // ── 2. Detect --no-undo markers at runtime ──────────────────────────
    let no_undo_versions = detect_non_reversible_migrations()?;
    let allowlist: BTreeSet<i64> = NON_REVERSIBLE_MIGRATIONS.iter().map(|(v, _)| *v).collect();

    // Fail loudly: --no-undo marker without allowlist entry
    for version in &no_undo_versions {
        assert!(
            allowlist.contains(version),
            "Migration v{version} is marked -- no-undo but NOT in NON_REVERSIBLE_MIGRATIONS allowlist.\n\
             Either provide a proper .down.sql or register the version + reason in the allowlist.",
        );
    }

    // Fail loudly: allowlist entry without matching migration (stale entry)
    let all_versions: BTreeSet<i64> = migrator.iter().map(|m| m.version).collect();
    for (version, reason) in NON_REVERSIBLE_MIGRATIONS {
        assert!(
            all_versions.contains(version),
            "NON_REVERSIBLE_MIGRATIONS entry v{version} ({reason}) does not match any existing migration. \
             Remove the stale entry.",
        );
    }

    // ── 3. spawn_postgres already applied all migrations up ─────────────
    //       Now we undo them one by one, newest first.

    let versions: Vec<i64> = migrator
        .iter()
        .map(|m| m.version)
        .filter(|v| !no_undo_versions.contains(v))
        .collect();

    for i in (0..versions.len()).rev() {
        let target = if i == 0 { 0 } else { versions[i - 1] };
        migrator
            .undo(&pool, target)
            .await
            .with_context(|| format!("undo migration v{} (target v{target})", versions[i]))?;
    }

    // ── 4. Assert no projection / application tables remain ─────────────
    assert_no_projection_tables(&pool).await?;

    // ── 5. Re-apply all up to confirm idempotency ───────────────────────
    migrator
        .run(&pool)
        .await
        .context("re-apply all migrations up (idempotency check)")?;

    Ok(())
}

/// Scan all `.down.sql` files for `-- no-undo` markers and return the set
/// of migration versions marked as non-reversible.
fn detect_non_reversible_migrations() -> Result<BTreeSet<i64>> {
    let dir = std::path::Path::new(MIGRATIONS_DIR);
    let mut no_undo = BTreeSet::new();

    for entry in std::fs::read_dir(dir).context("read migrations directory")? {
        let entry = entry?;
        let path = entry.path();

        // Only check .down.sql files
        let filename = match path.file_name().and_then(|n| n.to_str()) {
            Some(name) if name.ends_with(".down.sql") => name,
            _ => continue,
        };

        let content = std::fs::read_to_string(&path).with_context(|| format!("read {:?}", path))?;

        if content.contains("-- no-undo") {
            // Extract version from filename:
            //   "20250623000001_projection_schema.down.sql"
            //   → strip ".down.sql" → "20250623000001_projection_schema"
            //   → split('_').next() → "20250623000001"
            let stem = filename.strip_suffix(".down.sql").unwrap_or(filename);
            if let Some(version_str) = stem.split('_').next()
                && let Ok(version) = version_str.parse::<i64>()
            {
                no_undo.insert(version);
            }
        }
    }

    Ok(no_undo)
}

/// Assert that no application/projection tables exist in the `public` schema.
///
/// The internal `_sqlx_migrations` table (used by sqlx to track migration
/// state) is exempt — it is created and managed purely by sqlx.
async fn assert_no_projection_tables(pool: &sqlx::PgPool) -> Result<()> {
    let rows: Vec<String> = sqlx::query_scalar(
        r#"
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name NOT LIKE '_sqlx%'
        ORDER BY table_name
        "#,
    )
    .fetch_all(pool)
    .await?;

    assert!(
        rows.is_empty(),
        "Expected no projection tables after undoing all migrations, found: {rows:?}",
    );

    Ok(())
}
