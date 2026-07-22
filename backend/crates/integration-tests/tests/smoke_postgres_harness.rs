// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

mod fixtures;

use anyhow::{Context, Result};
use breakdown_core::shared::SeasonId;
use fixtures::spawn_postgres;
use sqlx::Row;
use std::collections::BTreeSet;
use uuid::Uuid;

/// Allowlist of intentionally non-reversible migrations.
///
/// If a migration cannot be reversed (e.g. a data backfill), add
/// `-- no-undo` at the top of its `.down.sql` file AND register the
/// version and reason here. The test will skip the undo step for that
/// version and fail loudly if a `-- no-undo` migration is added without
/// an allowlist entry.
const NON_REVERSIBLE_MIGRATIONS: &[(i64, &str)] = &[
    // Example: (20250703000001, "irreversible data backfill — see PR #123"),
];

/// Absolute path to the migrations directory, resolved at compile time.
const MIGRATIONS_DIR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../infra/migrations");

#[tokio::test]
async fn postgres_harness_spins_up_and_applies_migrations() -> Result<()> {
    let (pool, _container) = spawn_postgres().await?;

    let id = Uuid::now_v7();
    let season_id = SeasonId::new();

    sqlx::query(
        r#"
        INSERT INTO projection_character
            (id, season_id, name, category, measurements, contact, version, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
        "#,
    )
    .bind(id)
    .bind(season_id.0)
    .bind("Smoke Test")
    .bind(serde_json::json!("main_cast"))
    .bind(serde_json::json!({}))
    .bind(serde_json::json!({}))
    .bind(1_i64)
    .execute(&pool)
    .await?;

    let row_name: String = sqlx::query("SELECT name FROM projection_character WHERE id = $1")
        .bind(id)
        .fetch_one(&pool)
        .await?
        .try_get("name")?;

    assert_eq!(row_name, "Smoke Test");

    Ok(())
}

#[tokio::test]
async fn migrations_are_reversible() -> Result<()> {
    let (pool, _container) = spawn_postgres().await?;

    // ── 1. Build the embedded migrator ──────────────────────────────────
    let migrator = sqlx::migrate!("../infra/migrations");

    // ── 2. Detect --no-undo markers and validate allowlist ──────────────
    let no_undo_versions = detect_non_reversible_migrations()?;
    let allowlist: BTreeSet<i64> = NON_REVERSIBLE_MIGRATIONS.iter().map(|(v, _)| *v).collect();

    for version in &no_undo_versions {
        assert!(
            allowlist.contains(version),
            "Migration v{version} is marked -- no-undo but NOT in NON_REVERSIBLE_MIGRATIONS allowlist.\n\
             Either provide a proper .down.sql or register the version + reason in the allowlist.",
        );
    }

    let all_versions: BTreeSet<i64> = migrator.iter().map(|m| m.version).collect();
    for (version, reason) in NON_REVERSIBLE_MIGRATIONS {
        assert!(
            all_versions.contains(version),
            "NON_REVERSIBLE_MIGRATIONS entry v{version} ({reason}) does not match any existing migration. \
             Remove the stale entry.",
        );
    }

    // ── 3. spawn_postgres already applied all migrations up ─────────────
    //       Now undo them one by one, newest first.

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
