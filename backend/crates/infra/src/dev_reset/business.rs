// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! Level `business` — full business-data reset, configuration preserved.
//!
//! The level runs in the [`ResetPhase`]s the wrapper script drives, because the
//! one thing this process cannot do is empty the event store: SierraDB 0.3.1
//! has no delete command of any kind (`FLUSHALL`, `FLUSHDB`, `KEYS`, `SCAN`,
//! `EDELETE` all answer `-INVALIDARG unknown command`), so the data volume has
//! to go. `scripts/reset-dev-data.sh business` therefore does:
//!
//! ```text
//! 1. reset-dev-data --level business --phase export   (API stopped)
//! 2. docker compose stop sierradb && docker volume rm backend_sierradb_dev_data
//!    docker compose up -d sierradb
//! 3. reset-dev-data --level business --phase wipe     (event store must be empty)
//! 4. reset-dev-data --level business --phase replay
//! 5. start the API, wait for health
//! 6. reset-dev-data --level business --phase verify
//! ```
//!
//! What survives: the keep-list streams (`ai_config`, `settings`,
//! `membership`) — exported verbatim in phase 1 and replayed in phase 4 — the
//! `ai_model_pricing` rows, and **Vault** (never touched: the `settings` →
//! Vault credential bindings stay resolvable because the settings stream keeps
//! its id). The keep projections are not restored by hand: after the wipe the
//! projector checkpoints are empty too, so the replayed keep events rebuild
//! them from the event store, exactly like a fresh boot.

use std::sync::Arc;

use anyhow::{Context as _, Result, bail};
use chrono::Utc;
use sqlx::PgPool;

use breakdown_core::photo::ports::PhotoStorage;

use crate::ai::payload_storage::OpenDalAiPayloadStorage;
use crate::ai::preview_store::{AiDocumentStore, AiPreviewStore};
use crate::photo::storage::OpenDalPhotoStorage;
use crate::vault::VaultClient;

use super::backup::{self, BackupManifest, MANIFEST_FORMAT_VERSION};
use super::classification::AggregateCategory;
use super::events::{self, KeepListExport};
use super::plan::ResetPhase;
use super::{Context, ResetOptions, ResetPlan, ResetReport};

/// File name of the keep-list export inside the backup directory.
pub const KEEP_LIST_FILE: &str = "keep-list.json";

/// File name of the pricing export inside the backup directory.
pub const PRICING_FILE: &str = "pricing.json";

/// Extra artifacts the wrapper script writes when backups are enabled.
pub const SCRIPT_ARTIFACTS: &[&str] = &["postgres.dump", "sierradb-data.tgz"];

/// `report_ops.report_job` references the shooting-day projection with
/// `ON DELETE RESTRICT`, so it must go before any projection category.
const REPORT_JOB_DELETE: &str = "DELETE FROM report_ops.report_job";

/// Tables the wipe clears through the `ON DELETE CASCADE` of their parent row
/// rather than with a statement of their own — listed so the plan's table
/// counts and the wipe cannot drift apart silently.
const CASCADE_CLEARED_TABLES: &[&str] = &[
    "ai_import.ai_import_job_attempt",
    "ai_import.ai_payload_cleanup",
];

/// Operational tables cleared after the projection categories, in this order:
/// audit/dead-letter/checkpoint state is meaningless once the store is empty.
const OPERATIONAL_DELETES: &[&str] = &[
    "DELETE FROM ai_import.projection_ai_import_mapping",
    "DELETE FROM ai_import.ai_import_job",
    "DELETE FROM ai_import.concurrency_permit",
    "DELETE FROM ai_import.projection_ai_payload_gc_run",
    "DELETE FROM projection_photo_gc_run",
    "DELETE FROM projection_audit",
    "DELETE FROM projection_dead_letter",
    "DELETE FROM sierradb_event_checkpoints",
];

/// Category delete order for the wipe: children first, then the keep
/// projections (they are rebuilt from the replayed events).
const WIPE_ORDER: &[AggregateCategory] = &[
    AggregateCategory::Photo,
    AggregateCategory::SceneShoot,
    AggregateCategory::Scene,
    AggregateCategory::ShootingDay,
    AggregateCategory::Episode,
    AggregateCategory::Block,
    AggregateCategory::Season,
    AggregateCategory::Character,
    AggregateCategory::Outfit,
    AggregateCategory::Piece,
    AggregateCategory::CostumeCategory,
    AggregateCategory::Reservation,
    AggregateCategory::Membership,
    AggregateCategory::Settings,
    AggregateCategory::AiConfig,
];

/// Runs one phase of the level.
pub async fn execute(
    context: &mut Context,
    plan: &ResetPlan,
    options: &ResetOptions,
) -> Result<ResetReport> {
    match plan.phase {
        ResetPhase::Export => export_phase(context, plan, options).await,
        ResetPhase::Wipe => wipe_phase(context, plan, options).await,
        ResetPhase::Replay => replay_phase(context, plan, options).await,
        ResetPhase::Verify => verify_phase(context, plan, options).await,
        ResetPhase::All => bail!(
            "level `business` cannot run in one phase: the event store can only be emptied by \
             removing its data volume. Run `scripts/reset-dev-data.sh business`, which drives \
             --phase export / wipe / replay / verify around the volume drop"
        ),
    }
}

fn headline(plan: &ResetPlan) -> String {
    format!(
        "level business / phase {} | target {} | keep {} rows | reset {} rows",
        plan.phase.as_str(),
        plan.database_target,
        plan.keep_rows(),
        plan.reset_rows()
    )
}

/// Phase 1 — export the keep-list, the pricing rows and the manifest.
async fn export_phase(
    context: &mut Context,
    plan: &ResetPlan,
    options: &ResetOptions,
) -> Result<ResetReport> {
    let mut report = ResetReport {
        headline: headline(plan),
        ..ResetReport::default()
    };
    backup::prepare_dir(&options.backup_dir)
        .with_context(|| format!("create {}", options.backup_dir.display()))?;

    let export = events::export_keep_list(
        &context.pool,
        &mut context.connection,
        &context.database_target,
    )
    .await?;
    if export.streams.is_empty() {
        report.lines.push(
            "warning: no keep-list streams found — the AI config, settings and membership \
             projections are empty, so there is no configuration to preserve"
                .to_string(),
        );
    }
    backup::write_json(&options.backup_dir, KEEP_LIST_FILE, &export)
        .context("write keep-list.json")?;
    report.lines.push(format!(
        "exported {} keep stream(s) with {} event(s) → {}",
        export.streams.len(),
        export.event_count(),
        options.backup_dir.join(KEEP_LIST_FILE).display()
    ));

    let pricing = events::export_pricing(&context.pool).await?;
    backup::write_json(&options.backup_dir, PRICING_FILE, &pricing)
        .context("write pricing.json")?;
    report.lines.push(format!(
        "exported {} ai_model_pricing row(s) (kept, never deleted)",
        pricing.len()
    ));

    let manifest = BackupManifest {
        format_version: MANIFEST_FORMAT_VERSION,
        created_at: Utc::now(),
        level: plan.level.as_str().to_string(),
        phase: plan.phase.as_str().to_string(),
        database_target: plan.database_target.clone(),
        event_store_target: plan.event_store_target.clone(),
        keep_rows: plan.keep_rows(),
        reset_rows: plan.reset_rows(),
        files: vec![KEEP_LIST_FILE.to_string(), PRICING_FILE.to_string()],
        external_artifacts: if options.backup {
            SCRIPT_ARTIFACTS
                .iter()
                .map(|name| name.to_string())
                .collect()
        } else {
            Vec::new()
        },
    };
    backup::write_json(&options.backup_dir, backup::MANIFEST_FILE, &manifest)
        .context("write manifest.json")?;
    report.backup_path = Some(options.backup_dir.clone());
    if !options.backup {
        report.lines.push(
            "--no-backup: only the keep-list and pricing exports exist; there is no database \
             dump and no event-store volume tarball for this run"
                .to_string(),
        );
    }
    report.lines.push(
        "next: stop the API, take the database/volume backup, drop the sierradb volume, then \
         run --phase wipe"
            .to_string(),
    );
    Ok(report)
}

/// Phase 3 — clear the read model, the operational tables and the business
/// buckets. Refuses unless the event store has already been emptied.
async fn wipe_phase(
    context: &mut Context,
    plan: &ResetPlan,
    options: &ResetOptions,
) -> Result<ResetReport> {
    let mut report = ResetReport {
        headline: headline(plan),
        ..ResetReport::default()
    };
    let export: KeepListExport = backup::read_json(&options.backup_dir, KEEP_LIST_FILE)
        .with_context(|| {
            format!(
                "read {} — phase wipe needs the keep-list export from phase export",
                options.backup_dir.join(KEEP_LIST_FILE).display()
            )
        })?;
    report.backup_path = Some(options.backup_dir.clone());

    require_empty_event_store(context, &export, &mut report).await?;

    // 0. AI payload objects first and strictly: their handles exist only in the
    //    job rows, so a purge that cannot run must stop the wipe before those
    //    rows go (issue #770 review).
    if let Err(error) = purge_payloads(context, options, &mut report).await {
        report.failures.push(error);
        report.failures.push(
            "aborted the wipe before deleting the job rows: their payload handles are the only \
             way to find the objects. Configure AI_PAYLOAD_S3_* or pass --skip-payload-purge"
                .to_string(),
        );
        return Ok(report);
    }

    // 1. Report jobs reference the shooting-day projection with ON DELETE
    //    RESTRICT — they must go first.
    delete_static(&context.pool, REPORT_JOB_DELETE, &mut report).await;

    // 2. Business projection categories, children first.
    for category in WIPE_ORDER {
        delete_static(&context.pool, category.truncate_sql(), &mut report).await;
    }

    // 3. Operational bookkeeping.
    for statement in OPERATIONAL_DELETES {
        delete_static(&context.pool, statement, &mut report).await;
    }
    report.lines.push(format!(
        "cleared through the job delete's ON DELETE CASCADE: {}",
        CASCADE_CLEARED_TABLES.join(", ")
    ));

    // 4. Business buckets.
    purge_photos(&mut report).await;

    let pricing = events::export_pricing(&context.pool).await?;
    report
        .lines
        .push(format!("ai_model_pricing kept: {} row(s)", pricing.len()));
    report.lines.push(
        "next: run --phase replay (the projectors rebuild the keep projections after the API \
         starts)"
            .to_string(),
    );
    Ok(report)
}

/// Phase 4 — replay the exported keep-list verbatim.
async fn replay_phase(
    context: &mut Context,
    plan: &ResetPlan,
    options: &ResetOptions,
) -> Result<ResetReport> {
    let mut report = ResetReport {
        headline: headline(plan),
        ..ResetReport::default()
    };
    let export: KeepListExport = backup::read_json(&options.backup_dir, KEEP_LIST_FILE)
        .with_context(|| format!("read {}", options.backup_dir.join(KEEP_LIST_FILE).display()))?;
    report.backup_path = Some(options.backup_dir.clone());

    let appended = events::replay_keep_list(&mut context.connection, &export).await?;
    report.lines.push(format!(
        "replayed {} event(s) over {} stream(s)",
        appended,
        export.streams.len()
    ));

    let pricing: Vec<serde_json::Value> =
        backup::read_json(&options.backup_dir, PRICING_FILE).unwrap_or_default();
    let present = events::export_pricing(&context.pool).await?;
    if present.is_empty() && !pricing.is_empty() {
        let restored = events::restore_pricing(&context.pool, &pricing).await?;
        report
            .lines
            .push(format!("re-seeded {restored} ai_model_pricing row(s)"));
    } else {
        report.lines.push(format!(
            "ai_model_pricing present: {} row(s)",
            present.len()
        ));
    }
    report
        .lines
        .push("next: start the API and wait for /v1/health, then run --phase verify".to_string());
    Ok(report)
}

/// Phase 6 — assert the post-conditions.
async fn verify_phase(
    context: &mut Context,
    plan: &ResetPlan,
    options: &ResetOptions,
) -> Result<ResetReport> {
    let mut report = ResetReport {
        headline: headline(plan),
        ..ResetReport::default()
    };

    // Business projections must be empty.
    for category in AggregateCategory::ALL {
        if category.class() != super::AggregateClass::Reset {
            continue;
        }
        let rows = super::count(&context.pool, category.count_sql()).await?;
        if rows == 0 {
            continue;
        }
        report.failures.push(format!(
            "business projection {} still holds {rows} row(s)",
            category.projection_table()
        ));
    }

    // Keep-list streams must still carry their events.
    let export: KeepListExport = backup::read_json(&options.backup_dir, KEEP_LIST_FILE)
        .with_context(|| format!("read {}", options.backup_dir.join(KEEP_LIST_FILE).display()))?;
    for stream in &export.streams {
        let replayed = events::read_stream(&mut context.connection, &stream.stream_id).await?;
        // Exact equality, not "<": a stream carrying MORE events than the export
        // means the store was not empty when the replay ran, and a configuration
        // projector would apply events the export never authorised (issue #770
        // review). The replay itself is strict-versioned, so this is a backstop.
        if replayed.len() != stream.events.len() {
            report.failures.push(format!(
                "keep stream {} holds {} event(s) after the replay, expected exactly {}",
                stream.stream_id,
                replayed.len(),
                stream.events.len()
            ));
        }
    }

    // Keep projections must be rebuilt by the projectors.
    for category in AggregateCategory::ALL {
        if category.class() != super::AggregateClass::Keep {
            continue;
        }
        let rows = super::count(&context.pool, category.count_sql()).await?;
        report.lines.push(format!(
            "keep projection {}: {rows} row(s)",
            category.projection_table()
        ));
        // Scope the expectation to THIS category: a global event count would
        // flag every empty keep projection as soon as one category has events
        // (issue #770 review).
        let category_events: usize = export
            .streams
            .iter()
            .filter(|stream| stream.category == category.as_str())
            .map(|stream| stream.events.len())
            .sum();
        if rows == 0 && category_events > 0 {
            report.failures.push(format!(
                "keep projection {} is empty although {} replayed event(s) carry category \
                 `{}` — the projector has not caught up yet (check GET /v1/ops/projector-health)",
                category.projection_table(),
                category_events,
                category.as_str()
            ));
        }
    }

    let pricing = events::export_pricing(&context.pool).await?;
    if pricing.is_empty() {
        report
            .failures
            .push("ai_model_pricing is empty: the cost snapshot would have no rows".to_string());
    } else {
        report
            .lines
            .push(format!("ai_model_pricing: {} row(s)", pricing.len()));
    }

    let checkpoints = super::count(
        &context.pool,
        "SELECT count(*) FROM sierradb_event_checkpoints",
    )
    .await?;
    report.lines.push(format!(
        "{checkpoints} projector checkpoint(s) recorded (grows as the API catches up)"
    ));

    report.lines.push(
        "API-level checks (the wrapper script runs them): GET /v1/ai-import/config/{id} returns \
         the provider/model/decision triple, re-uploading a previously imported document answers \
         202 with a new job id, GET /v1/ops/projector-health is green"
            .to_string(),
    );
    Ok(report)
}

/// The wipe must never run against a store that still holds events.
async fn require_empty_event_store(
    context: &mut Context,
    export: &KeepListExport,
    report: &mut ResetReport,
) -> Result<()> {
    let Some(probe) = export
        .streams
        .iter()
        .find(|stream| !stream.events.is_empty())
    else {
        report.lines.push(
            "no keep stream to probe: skipping the empty-event-store assertion (the export was \
             empty)"
                .to_string(),
        );
        return Ok(());
    };
    let remaining = events::read_stream(&mut context.connection, &probe.stream_id).await?;
    if !remaining.is_empty() {
        bail!(
            "refusing to wipe: the event store still holds events (stream {} has {}). SierraDB \
             cannot delete events — remove the volume first \
             (`docker compose -f docker-compose.dev.yml stop sierradb && docker volume rm \
             backend_sierradb_dev_data && docker compose -f docker-compose.dev.yml up -d \
             sierradb`), or run scripts/reset-dev-data.sh business",
            probe.stream_id,
            remaining.len()
        );
    }
    Ok(())
}

/// Executes one static statement and records the affected rows.
async fn delete_static(pool: &PgPool, statement: &'static str, report: &mut ResetReport) {
    match sqlx::query(statement).execute(pool).await {
        Ok(result) => report.lines.push(format!(
            "cleared {} row(s): {}",
            result.rows_affected(),
            statement
        )),
        Err(error) => report
            .failures
            .push(format!("statement failed ({statement}): {error}")),
    }
}

/// Purges the AI payload objects of the jobs that are about to be deleted.
///
/// Returns an error when the objects could not be purged: the caller then
/// aborts before deleting the job rows, whose handles are the only way to find
/// them. `--skip-payload-purge` is the explicit opt-out.
async fn purge_payloads(
    context: &mut Context,
    options: &ResetOptions,
    report: &mut ResetReport,
) -> Result<(), String> {
    let Some(storage) = OpenDalAiPayloadStorage::from_env() else {
        if options.skip_payload_purge {
            report.lines.push(
                "--skip-payload-purge: AI payload storage is not configured, so the objects were \
                 left in place (unreachable once the job rows go)"
                    .to_string(),
            );
            return Ok(());
        }
        return Err(
            "AI payload storage is not configured (AI_PAYLOAD_S3_* unset), so the payload \
             objects cannot be purged"
                .to_string(),
        );
    };
    let jobs = match super::imports::load_jobs(&context.pool).await {
        Ok(jobs) => jobs,
        Err(error) => {
            return Err(format!(
                "load AI import jobs for the payload purge: {error}"
            ));
        }
    };
    let mut purged = 0usize;
    let mut failures = Vec::new();
    for job in &jobs {
        match storage.delete_source(&job.source_handle).await {
            Ok(()) => purged += 1,
            Err(error) => failures.push(format!(
                "purge source {} of job {}: {error}",
                job.source_handle, job.id
            )),
        }
        if let Some(handle) = job.preview_handle.as_deref() {
            match storage.delete(handle).await {
                Ok(()) => purged += 1,
                Err(error) => {
                    failures.push(format!("purge preview {handle} of job {}: {error}", job.id))
                }
            }
        }
    }
    report
        .lines
        .push(format!("purged {purged} AI payload object(s)"));
    if failures.is_empty() {
        Ok(())
    } else {
        Err(failures.join("; "))
    }
}

/// Deletes every photo object (SSE-C, resolved through Vault).
async fn purge_photos(report: &mut ResetReport) {
    let vault = match VaultClient::from_env() {
        Ok(vault) => vault,
        Err(error) => {
            report.lines.push(format!(
                "Vault unavailable ({error}): photo objects were not purged — run the photo GC \
                 once Vault is reachable"
            ));
            return;
        }
    };
    let storage = OpenDalPhotoStorage::recoverable(Arc::new(vault));
    let ids = match storage.list().await {
        Ok(ids) => ids,
        Err(error) => {
            report.failures.push(format!("list photo objects: {error}"));
            return;
        }
    };
    let mut deleted = 0usize;
    for id in &ids {
        match storage.delete_all(*id).await {
            Ok(()) => deleted += 1,
            Err(error) => report
                .failures
                .push(format!("delete photo {}: {error}", id.0)),
        }
    }
    report.lines.push(format!(
        "deleted {deleted} of {} photo object group(s)",
        ids.len()
    ));
}

/// `true` when the plan's phase list is complete (used by the CLI help/tests).
pub fn phases() -> [ResetPhase; 4] {
    [
        ResetPhase::Export,
        ResetPhase::Wipe,
        ResetPhase::Replay,
        ResetPhase::Verify,
    ]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dev_reset::plan::BOOKKEEPING_TABLES;

    /// Every business category is wiped exactly once, and the keep categories
    /// come last (they are rebuilt from the replayed events).
    #[test]
    fn wipe_order_covers_every_category_once() {
        let mut seen: Vec<&str> = WIPE_ORDER.iter().map(|c| c.as_str()).collect();
        let total = seen.len();
        seen.sort_unstable();
        seen.dedup();
        assert_eq!(total, seen.len(), "duplicate category in WIPE_ORDER");
        assert_eq!(total, AggregateCategory::ALL.len());
        for category in AggregateCategory::ALL {
            assert!(
                WIPE_ORDER.contains(&category),
                "{} missing from WIPE_ORDER",
                category.as_str()
            );
        }
        let position = |category: AggregateCategory| {
            WIPE_ORDER
                .iter()
                .position(|entry| *entry == category)
                .unwrap_or(0)
        };
        assert!(position(AggregateCategory::Scene) < position(AggregateCategory::Character));
        assert!(
            position(AggregateCategory::AiConfig) > position(AggregateCategory::Membership),
            "keep categories are wiped after the business data"
        );
    }

    /// The operational deletes are static literals and clear the checkpoint
    /// table (otherwise the projectors would never re-read the replayed events).
    #[test]
    fn operational_deletes_clear_the_checkpoints() {
        assert!(
            OPERATIONAL_DELETES
                .iter()
                .any(|statement| statement.contains("sierradb_event_checkpoints"))
        );
        for statement in OPERATIONAL_DELETES {
            assert!(
                statement.starts_with("DELETE FROM "),
                "unexpected statement {statement}"
            );
        }
    }

    /// The bookkeeping table list and the operational deletes must not drift:
    /// every table the plan counts is cleared by the wipe.
    #[test]
    fn every_counted_bookkeeping_table_is_cleared() {
        for (table, _) in BOOKKEEPING_TABLES {
            // `report_ops.report_job` is cleared first (its RESTRICT foreign key
            // would otherwise block the shooting-day delete), so it lives
            // outside `OPERATIONAL_DELETES`.
            let cleared = OPERATIONAL_DELETES
                .iter()
                .chain(std::iter::once(&REPORT_JOB_DELETE))
                .any(|statement| statement.contains(table))
                || CASCADE_CLEARED_TABLES.contains(table);
            assert!(cleared, "{table} is counted in the plan but never cleared");
        }
    }

    #[test]
    fn phase_helpers_name_the_four_business_phases() {
        assert_eq!(
            phases().map(|phase| phase.as_str()),
            ["export", "wipe", "replay", "verify"]
        );
    }
}
