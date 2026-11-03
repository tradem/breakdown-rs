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
        options.allow_empty_keep_list,
    )
    .await?;
    if export.streams.is_empty() {
        report.lines.push(
            "warning: no keep-list streams found — the AI config, settings and membership \
             projections are empty, so there is no configuration to preserve"
                .to_string(),
        );
    }
    report.lines.extend(keep_event_summary(plan, &export));
    if options.allow_empty_keep_list && export.event_count() == 0 {
        report.lines.push(
            "--allow-empty-keep-list: this export carries no events, so the replay will restore \
             nothing — the configuration will be gone after the wipe"
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

    // A store that still holds keep events must abort the wipe — and an export
    // without events must not switch that assertion off (issue #810).
    if let Err(error) = require_empty_event_store(context, &export, &mut report).await {
        report.failures.push(format!("{error:#}"));
        report.failures.push(recovery_hint(options));
        return Ok(report);
    }

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

    let expected = export.event_count();
    // An export without events restores nothing. That is only tolerable when
    // there is no configuration left in the read model either — if the keep
    // projections still hold rows, the wipe never ran (or this is a post-loss
    // export) and the next wipe destroys the configuration (issue #810).
    if expected == 0 && plan.keep_rows() > 0 {
        report.failures.push(format!(
            "the keep-list export {} carries 0 events although the keep projections still hold {} \
             row(s): replaying nothing leaves the configuration in the read model only, where the \
             next wipe destroys it",
            options.backup_dir.join(KEEP_LIST_FILE).display(),
            plan.keep_rows()
        ));
    }

    let appended = match events::replay_keep_list(&mut context.connection, &export).await {
        Ok(appended) => appended,
        Err(error) => {
            report.failures.push(format!("{error:#}"));
            report.failures.push(recovery_hint(options));
            return Ok(report);
        }
    };
    report.lines.push(format!(
        "replayed {} of {} event(s) over {} stream(s)",
        appended,
        expected,
        export.streams.len()
    ));

    // The replay asserts its own result (issue #810): `replayed 0 event(s)` and
    // exit 0 was exactly the silent loss this issue is about.
    if appended != expected {
        report.failures.push(format!(
            "replayed {appended} event(s) but the keep-list export expects {expected}: the \
             configuration is NOT restored"
        ));
        report.failures.push(recovery_hint(options));
    }
    // …and every stream is re-read, so a partial append is caught as well
    // (`verify` keeps the same check as a backstop).
    for stream in &export.streams {
        let replayed = events::read_stream(&mut context.connection, &stream.stream_id).await?;
        if replayed.len() != stream.events.len() {
            report.failures.push(format!(
                "keep stream {} holds {} event(s) after the replay, expected exactly {}",
                stream.stream_id,
                replayed.len(),
                stream.events.len()
            ));
        }
    }

    // Persist what the replay did: `verify` (and the next run) must be able to
    // tell this receipt apart from a later export (issue #810).
    let record = backup::ReplayReport::new(&export, appended);
    match backup::write_json(&options.backup_dir, backup::REPLAY_REPORT_FILE, &record) {
        Ok(path) => report.lines.push(format!(
            "{} → {}",
            backup::REPLAY_REPORT_FILE,
            path.display()
        )),
        Err(error) => report.failures.push(format!(
            "write {}/{}: {error}",
            options.backup_dir.display(),
            backup::REPLAY_REPORT_FILE
        )),
    }

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
    // The replay recorded what it appended; compare that receipt against the
    // export *and* the store (issue #810). Without it, a post-loss export (0
    // events) would verify cleanly against a store that holds nothing.
    match backup::read_json::<backup::ReplayReport>(&options.backup_dir, backup::REPLAY_REPORT_FILE)
    {
        Ok(record) => {
            report.lines.push(record.render());
            report.failures.extend(record.mismatches(&export));
        }
        Err(error) => report.failures.push(format!(
            "no {} in the backup directory ({error}): the replay did not record what it appended, \
             so this export cannot be verified against the restore it produced — re-run --phase \
             replay",
            options
                .backup_dir
                .join(backup::REPLAY_REPORT_FILE)
                .display()
        )),
    }
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
///
async fn require_empty_event_store(
    context: &mut Context,
    export: &KeepListExport,
    report: &mut ResetReport,
) -> Result<()> {
    // Probe every stream the export names **and** every keep stream the
    // projections currently resolve to: an export with no events must not
    // switch this assertion off (issue #810) — the projections still name the
    // streams, and a non-empty one means the export is stale or lossy.
    let mut probes: Vec<String> = export
        .streams
        .iter()
        .map(|stream| stream.stream_id.clone())
        .collect();
    for stream in events::current_keep_streams(&context.pool).await? {
        if !probes.contains(&stream) {
            probes.push(stream);
        }
    }
    if probes.is_empty() {
        report.lines.push(
            "no keep stream to probe: the keep projections are empty and the export carries no \
             stream, so the event store holds no configuration to lose"
                .to_string(),
        );
        return Ok(());
    }
    let mut remaining = Vec::new();
    for probe in &probes {
        let events = events::read_stream(&mut context.connection, probe).await?;
        if !events.is_empty() {
            remaining.push(format!("{probe} has {}", events.len()));
        }
    }
    if remaining.is_empty() {
        return Ok(());
    }
    if export.event_count() == 0 {
        bail!(
            "refusing to wipe: the keep-list export carries 0 events but the event store still \
             holds keep events ({}). The export is stale or lossy — re-run --phase export before \
             wiping",
            remaining.join(", ")
        );
    }
    bail!(
        "refusing to wipe: the event store still holds events ({}). SierraDB cannot delete events — \
         remove the volume first (`docker compose -f docker-compose.dev.yml stop sierradb && docker \
         volume rm backend_sierradb_dev_data && docker compose -f docker-compose.dev.yml up -d \
         sierradb`), or run scripts/reset-dev-data.sh business",
        remaining.join(", ")
    )
}

/// Per-category keep-list event counts (issue #810).
///
/// The plan can only count rows; an operator deciding whether to drop the volume
/// also has to see `ai_config: 0 events`, which is exactly the state that lost
/// the configuration on 2026-11-03.
pub fn keep_event_summary(plan: &ResetPlan, export: &KeepListExport) -> Vec<String> {
    let counts = export.category_counts();
    let mut lines = vec!["KEEP-LIST EVENTS — what the replay puts back".to_string()];
    for entry in &plan.keep {
        let category = entry.category;
        let count = counts.iter().find(|count| count.category == category);
        lines.push(format!(
            "  keep {:<12} {:>5} row(s) → {:>3} stream(s), {:>4} event(s)",
            category.as_str(),
            entry.rows,
            count.map(|count| count.streams).unwrap_or(0),
            count.map(|count| count.events).unwrap_or(0)
        ));
    }
    if export.event_count() == 0 && plan.keep_rows() > 0 {
        lines.push(
            "  WARNING: the keep projections hold rows but the event store returned no keep \
             events — the export refuses unless --allow-empty-keep-list is passed"
                .to_string(),
        );
    }
    lines
}

/// The exact recovery command for a replay that did not restore the keep-list.
fn recovery_hint(options: &ResetOptions) -> String {
    format!(
        "recovery: the keep-list is in {} — recreate the empty event store (docker compose -f \
         docker-compose.dev.yml stop sierradb && docker volume rm backend_sierradb_dev_data && \
         docker compose -f docker-compose.dev.yml up -d sierradb) and re-run `--level business \
         --phase replay --backup-dir {}` (or scripts/reset-dev-data.sh business --backup-dir {})",
        options.backup_dir.join(KEEP_LIST_FILE).display(),
        options.backup_dir.display(),
        options.backup_dir.display()
    )
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
    use crate::dev_reset::plan::{BOOKKEEPING_TABLES, CategoryCount};
    use crate::dev_reset::{ResetLevel, ResetPhase};

    fn keep_list_without_events() -> KeepListExport {
        KeepListExport {
            format_version: events::EXPORT_FORMAT_VERSION,
            created_at: Utc::now(),
            database_target: "localhost/breakdown".to_string(),
            streams: vec![events::ExportedStream {
                stream_id: "ai_config-0199a0c0-0000-7000-8000-000000000000".to_string(),
                category: "ai_config".to_string(),
                events: Vec::new(),
            }],
        }
    }

    fn plan_with_keep_rows(rows: i64) -> ResetPlan {
        ResetPlan {
            level: ResetLevel::Business,
            phase: ResetPhase::Replay,
            database_target: "localhost/breakdown".to_string(),
            event_store_target: "127.0.0.1:9090".to_string(),
            keep: vec![
                CategoryCount {
                    category: AggregateCategory::AiConfig,
                    rows,
                },
                CategoryCount {
                    category: AggregateCategory::Settings,
                    rows: 0,
                },
                CategoryCount {
                    category: AggregateCategory::Membership,
                    rows: 0,
                },
            ],
            reset: Vec::new(),
            tables: Vec::new(),
            buckets: Vec::new(),
            notes: Vec::new(),
            imports_scope: None,
        }
    }

    /// Defect 2 of issue #810: the pre-drop view must expose the event side, not
    /// just the row count — `ai_config: 1 row` looked healthy while its stream
    /// was empty.
    #[test]
    fn keep_event_summary_exposes_the_event_count_beside_the_row_count() {
        let lines = keep_event_summary(&plan_with_keep_rows(1), &keep_list_without_events());
        let rendered = lines.join("\n");
        assert!(rendered.contains("KEEP-LIST EVENTS"), "{rendered}");
        assert!(rendered.contains("ai_config"), "{rendered}");
        assert!(rendered.contains("0 event(s)"), "{rendered}");
        assert!(rendered.contains("WARNING"), "{rendered}");

        // A configuration that really is empty must not warn.
        let quiet = keep_event_summary(&plan_with_keep_rows(0), &keep_list_without_events());
        assert!(!quiet.join("\n").contains("WARNING"), "{quiet:?}");
    }

    /// The recovery hint must name the backup path and the replay command: the
    /// operator reads it while the event store is empty (issue #810).
    #[test]
    fn the_recovery_hint_names_the_backup_path_and_the_replay() {
        let options = ResetOptions {
            level: ResetLevel::Business,
            phase: ResetPhase::Replay,
            dry_run: false,
            assume_yes: true,
            dev_ack: true,
            backup: true,
            skip_payload_purge: false,
            backup_dir: std::path::PathBuf::from("backups/reset-20261103T045807Z"),
            confirmation: None,
            allow_empty_keep_list: false,
        };
        let hint = recovery_hint(&options);
        assert!(
            hint.contains("backups/reset-20261103T045807Z/keep-list.json"),
            "{hint}"
        );
        assert!(hint.contains("--phase replay"), "{hint}");
        assert!(hint.contains("docker volume rm"), "{hint}");
    }

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
