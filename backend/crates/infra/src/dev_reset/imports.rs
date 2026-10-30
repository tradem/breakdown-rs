// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! Level `imports` — undo the AI imports, keep the rest of the business data.
//!
//! Three things block a re-import of an already imported document, and this
//! level removes all three:
//!
//! 1. the **dedup row** — `ai_import.ai_import_job` is unique on
//!    `(user_id, dedup_key)`, so a re-upload returns the old (succeeded) job
//!    instead of extracting again;
//! 2. the **payload objects** — source document and preview payload in the AI
//!    payload bucket;
//! 3. the **aggregates the import created** — removed through real domain
//!    commands ([`DELETE_ORDER`]), never by truncating projections behind the
//!    event store's back.
//!
//! `ai_config`, `settings` and `membership` are untouched: the re-import runs
//! with the same provider/model/Decision-Model triple and the same credentials.
//!
//! ## Provenance limits (documented, not hidden)
//!
//! `ai_import.projection_ai_import_mapping` records `scene`, `character`,
//! `piece`, `outfit`, `scene_shoot`, `shooting_day` and the beat kinds — but
//! **not** `episode` (episode groups only report a count, #763). Import-created
//! episodes are therefore resolved **heuristically** from the job's `block_id`
//! plus `created_at` recency, and the report says so.

use std::collections::{BTreeMap, BTreeSet};

use anyhow::{Context as _, Result};
use chrono::{DateTime, Utc};
use kameo_es::command_service::CommandService;
use serde::{Deserialize, Serialize};
use sierradb_client::ExpectedVersion;
use sqlx::PgPool;
use uuid::Uuid;

use breakdown_core::character::aggregate::CharacterAggregate;
use breakdown_core::character::commands::DeleteCharacter;
use breakdown_core::episode::aggregate::EpisodeAggregate;
use breakdown_core::episode::commands::DeleteEpisode;
use breakdown_core::outfit::aggregate::OutfitAggregate;
use breakdown_core::outfit::commands::DeleteOutfit;
use breakdown_core::piece::aggregate::PieceAggregate;
use breakdown_core::piece::commands::DeletePiece;
use breakdown_core::scene::aggregate::SceneAggregate;
use breakdown_core::scene::commands::DeleteScene;
use breakdown_core::scene_shoot::aggregate::SceneShootAggregate;
use breakdown_core::scene_shoot::commands::DeleteSceneShoot;
use breakdown_core::shared::{EventMetadata, ProjectId, Provenance, SceneShootId, ShootingDayId};
use breakdown_core::shooting_day::aggregate::ShootingDayAggregate;
use breakdown_core::shooting_day::commands::DeleteShootingDay;

use crate::ai::payload_storage::OpenDalAiPayloadStorage;
use crate::ai::preview_store::{AiDocumentStore, AiPreviewStore};
use crate::reservations::event::{episode_number_key, scene_shoot_pair_key};
use crate::reservations::store::{LifecycleVariant, ReservationStore};

use super::backup::{self, BackupManifest, MANIFEST_FORMAT_VERSION};
use super::{Context, ResetOptions, ResetPlan, ResetReport};

/// Deletion order — **children before parents**.
///
/// The projection schema cascades child rows from the parent (a `scene` delete
/// removes its beats, its casting rows and its `scene_shoot` rows), so deleting
/// a parent first would remove child projections without the child stream
/// carrying its own deleted event. The next replay of that child stream would
/// then fail its foreign key and dead-letter (#37). Every entry here is deleted
/// through its own domain command instead.
pub const DELETE_ORDER: &[&str] = &[
    "scene_shoot",
    "scene",
    "shooting_day",
    "outfit",
    "piece",
    "character",
    "episode",
];

/// Mapping kinds that own a deletable aggregate. Every other kind (the beat
/// kinds, the retired `costume` kind) needs no aggregate delete, so its
/// provenance rows are removed with the job.
const MAPPING_KINDS: &[&str] = &[
    "scene",
    "character",
    "piece",
    "outfit",
    "shooting_day",
    "scene_shoot",
    // Episodes have no import provenance of their own (#763), so the reset
    // **writes** an `episode` row for every episode delete that failed — that is
    // the retry path once the job rows (the heuristic's input) are gone
    // (issue #770 review).
    "episode",
];

/// `draft_ref` of the synthetic provenance row written for a failed episode
/// delete.
const FAILED_EPISODE_DRAFT_REF: &str = "reset-episode-heuristic";

/// One AI import job row (the dedup blocker).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, sqlx::FromRow)]
pub struct ImportJobRow {
    pub id: Uuid,
    pub user_id: String,
    pub block_id: Option<Uuid>,
    pub status: String,
    pub created_at: DateTime<Utc>,
    pub source_handle: String,
    pub preview_handle: Option<String>,
}

/// One import → aggregate provenance row.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, sqlx::FromRow)]
pub struct MappingRow {
    pub preview_id: Uuid,
    pub aggregate_kind: String,
    pub aggregate_id: Uuid,
}

/// What the `imports` backup holds before anything is deleted.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ImportsBackup {
    pub jobs: Vec<ImportJobRow>,
    pub mapping: Vec<MappingRow>,
}

/// An episode the heuristic attributed to the import.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, sqlx::FromRow)]
pub struct EpisodeTarget {
    pub id: Uuid,
    pub project_id: Uuid,
    pub number: i32,
}

/// The aggregates an import created, grouped by category.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Targets {
    pub scene_shoot: BTreeSet<Uuid>,
    pub scene: BTreeSet<Uuid>,
    pub shooting_day: BTreeSet<Uuid>,
    pub outfit: BTreeSet<Uuid>,
    pub piece: BTreeSet<Uuid>,
    pub character: BTreeSet<Uuid>,
    pub episode: BTreeSet<EpisodeTarget>,
    /// Episode ids recorded in the provenance by a previous run (a failed delete
    /// left the row behind) — resolved against the projection afterwards.
    pub episode_ids: BTreeSet<Uuid>,
    /// Mapping kinds with no aggregate of their own (beats live inside the
    /// scene stream; `costume` is the retired pre-split kind).
    pub ignored_kinds: BTreeMap<String, usize>,
}

impl Targets {
    pub fn total(&self) -> usize {
        self.scene_shoot.len()
            + self.scene.len()
            + self.shooting_day.len()
            + self.outfit.len()
            + self.piece.len()
            + self.character.len()
            + self.episode.len()
    }
}

/// Buckets the provenance rows by aggregate category.
pub fn collect_targets(mapping: &[MappingRow]) -> Targets {
    let mut targets = Targets::default();
    for row in mapping {
        let bucket = match row.aggregate_kind.as_str() {
            "scene" => Some(&mut targets.scene),
            "character" => Some(&mut targets.character),
            "piece" => Some(&mut targets.piece),
            "outfit" => Some(&mut targets.outfit),
            "shooting_day" => Some(&mut targets.shooting_day),
            "scene_shoot" => Some(&mut targets.scene_shoot),
            "episode" => {
                targets.episode_ids.insert(row.aggregate_id);
                None
            }
            other => {
                *targets.ignored_kinds.entry(other.to_string()).or_insert(0) += 1;
                None
            }
        };
        if let Some(bucket) = bucket {
            bucket.insert(row.aggregate_id);
        }
    }
    targets
}

/// Dispatches one delete command against its aggregate.
///
/// The maintenance binary is its own composition root: the delete commands are
/// deliberately **not** on the production write ports (no HTTP route, issue
/// #770), so this dispatches straight to the aggregate actor with `System`
/// provenance for the audit trail.
macro_rules! delete_one {
    ($aggregate:ty, $service:expr, $id:expr, $command:expr, $project_id:expr) => {{
        use kameo_es::command_service::ExecuteExt;

        <$aggregate>::execute($service, $id, $command)
            .expected_version(ExpectedVersion::Any)
            .metadata(EventMetadata {
                actor: None,
                provenance: Provenance::System,
                // `GET /audit?project_id=…` filters on this column, so a reset
                // deletion must be attributable (issue #770 review). Best
                // effort: a projection miss leaves `None` and never blocks the
                // delete (CQRS audit doctrine).
                project_id: $project_id.map(ProjectId),
            })
            .await
            .map(|_| ())
    }};
}

/// Runs the level.
pub async fn execute(
    context: &mut Context,
    plan: &ResetPlan,
    options: &ResetOptions,
) -> Result<ResetReport> {
    let mut report = ResetReport {
        headline: format!(
            "level imports / phase all | target {} | keep {} rows | reset {} rows",
            plan.database_target,
            plan.keep_rows(),
            plan.reset_rows()
        ),
        ..ResetReport::default()
    };

    let jobs = load_jobs(&context.pool).await?;
    let mapping = load_mapping(&context.pool).await?;
    if jobs.is_empty() && mapping.is_empty() {
        report
            .lines
            .push("nothing to reset: no AI import jobs and no provenance rows".to_string());
        return Ok(report);
    }

    if options.backup {
        backup::prepare_dir(&options.backup_dir)
            .with_context(|| format!("create {}", options.backup_dir.display()))?;
        let document = ImportsBackup {
            jobs: jobs.clone(),
            mapping: mapping.clone(),
        };
        backup::write_json(&options.backup_dir, "imports.json", &document)
            .context("write imports.json")?;
        let manifest = BackupManifest {
            format_version: MANIFEST_FORMAT_VERSION,
            created_at: Utc::now(),
            level: plan.level.as_str().to_string(),
            phase: plan.phase.as_str().to_string(),
            database_target: plan.database_target.clone(),
            event_store_target: plan.event_store_target.clone(),
            keep_rows: plan.keep_rows(),
            reset_rows: plan.reset_rows(),
            files: vec!["imports.json".to_string()],
            external_artifacts: Vec::new(),
        };
        backup::write_json(&options.backup_dir, backup::MANIFEST_FILE, &manifest)
            .context("write manifest.json")?;
        report.backup_path = Some(options.backup_dir.clone());
    } else {
        report.lines.push(
            "backup disabled (--no-backup): the job rows are deleted without a copy".to_string(),
        );
    }

    let mut targets = collect_targets(&mapping);
    // Episodes recorded by a previous run whose delete failed: the provenance
    // row is the only retry path once those job rows are gone.
    if !targets.episode_ids.is_empty() {
        let retained = resolve_episodes_by_id(&context.pool, &targets.episode_ids).await?;
        report.lines.push(format!(
            "episodes: {} retained from the provenance of an earlier failed delete",
            retained.len()
        ));
        targets.episode.extend(retained);
    }
    let episodes = resolve_episodes(&context.pool, &jobs).await?;
    if !episodes.is_empty() {
        report.lines.push(format!(
            "episodes: {} resolved heuristically from job.block_id + created_at recency \
             (no import→episode provenance yet, #763)",
            episodes.len()
        ));
        targets.episode.extend(episodes);
    }
    for (kind, count) in &targets.ignored_kinds {
        report.lines.push(format!(
            "{count} provenance row(s) of kind {kind:?} need no aggregate delete \
             (beats live inside the scene stream; `costume` is the retired pre-split kind)"
        ));
    }
    report.lines.push(format!(
        "aggregates to delete: {} (order: {})",
        targets.total(),
        DELETE_ORDER.join(" → ")
    ));

    // Payload objects first: their handles exist **only** in the job rows, so a
    // purge that cannot run has to stop the reset before those rows go —
    // otherwise the objects are unreachable garbage (issue #770 review).
    if let Err(error) = purge_payloads(&jobs, options, &mut report).await {
        report.failures.push(error);
        report.failures.push(
            "aborted before deleting the job rows: their payload handles are the only way to \
             find the objects. Configure AI_PAYLOAD_S3_* (see \
             scripts/enable-dev-ai-import.sh) or pass --skip-payload-purge deliberately"
                .to_string(),
        );
        return Ok(report);
    }

    delete_aggregates(context, &targets, &mut report).await;

    // A failed episode delete has no provenance row of its own (episode groups
    // only report a count, #763) and the heuristic that found it reads the job
    // rows, which are deleted below — so the target is persisted first, or the
    // retry path is lost (issue #770 review).
    let deleted_aggregates = report.deleted_aggregates.clone();
    persist_failed_episodes(&context.pool, &targets, &deleted_aggregates, &mut report).await;

    // Only the provenance of the aggregates that are actually gone is deleted:
    // a failed delete keeps its mapping row so a re-run can still find it
    // (issue #770 review).
    delete_job_rows(&context.pool, &jobs, &deleted_aggregates, &mut report).await;

    report.lines.push(format!(
        "deleted {} job row(s); re-uploading the same document now enqueues a fresh job",
        jobs.len()
    ));
    report.lines.push(
        "the delete events are projected by the running API: let it catch up (GET /v1/ops/projector-health) before re-importing"
            .to_string(),
    );
    Ok(report)
}

/// Reads the AI import jobs (the dedup blocker) in creation order.
pub async fn load_jobs(pool: &PgPool) -> Result<Vec<ImportJobRow>> {
    let jobs = sqlx::query_as::<_, ImportJobRow>(
        r#"
        SELECT id, user_id, block_id, status, created_at, source_handle, preview_handle
        FROM ai_import.ai_import_job
        ORDER BY created_at, id
        "#,
    )
    .fetch_all(pool)
    .await
    .context("load AI import jobs")?;
    Ok(jobs)
}

/// Reads the import → aggregate provenance rows.
pub async fn load_mapping(pool: &PgPool) -> Result<Vec<MappingRow>> {
    let rows = sqlx::query_as::<_, MappingRow>(
        r#"
        SELECT preview_id, aggregate_kind, aggregate_id
        FROM ai_import.projection_ai_import_mapping
        ORDER BY preview_id, aggregate_kind, aggregate_id
        "#,
    )
    .fetch_all(pool)
    .await
    .context("load AI import provenance")?;
    Ok(rows)
}

/// Resolves episode targets by id (the provenance rows of an earlier failed
/// delete). A row whose projection is gone is dropped — that episode no longer
/// exists, so there is nothing left to delete.
pub async fn resolve_episodes_by_id(
    pool: &PgPool,
    ids: &BTreeSet<Uuid>,
) -> Result<Vec<EpisodeTarget>> {
    let ids: Vec<Uuid> = ids.iter().copied().collect();
    let episodes = sqlx::query_as::<_, EpisodeTarget>(
        r#"
        SELECT id, project_id, number
        FROM projection_episode
        WHERE id = ANY($1)
        ORDER BY project_id, number
        "#,
    )
    .bind(&ids)
    .fetch_all(pool)
    .await
    .context("resolve retained episode targets")?;
    Ok(episodes)
}

/// Writes a provenance row for every episode whose delete failed, so a re-run
/// can find it after the job rows are gone.
async fn persist_failed_episodes(
    pool: &PgPool,
    targets: &Targets,
    deleted_aggregates: &[Uuid],
    report: &mut ResetReport,
) {
    let failed: Vec<Uuid> = targets
        .episode
        .iter()
        .map(|episode| episode.id)
        .filter(|id| !deleted_aggregates.contains(id))
        .collect();
    if failed.is_empty() {
        return;
    }
    let inserted = sqlx::query(
        r#"
        INSERT INTO ai_import.projection_ai_import_mapping
            (preview_id, draft_ref, aggregate_kind, aggregate_id, aggregate_version, ordinal)
        SELECT $1, $2, 'episode', id, 0, 0
        FROM unnest($3::uuid[]) AS id
        ON CONFLICT (preview_id, draft_ref, aggregate_kind, ordinal) DO NOTHING
        "#,
    )
    .bind(Uuid::nil())
    .bind(FAILED_EPISODE_DRAFT_REF)
    .bind(&failed)
    .execute(pool)
    .await;
    match inserted {
        Ok(result) => report.lines.push(format!(
            "retained {} failed episode target(s) in the import provenance for a re-run",
            result.rows_affected()
        )),
        Err(error) => report.failures.push(format!(
            "could not persist the {} failed episode target(s): {error} — a re-run cannot \
             rediscover them once the job rows are gone",
            failed.len()
        )),
    }
}

/// Episode heuristic: episodes in a job's block, created at or after the
/// earliest job. Deliberately conservative (it can only over-select inside the
/// import's own block) and reported as a heuristic.
pub async fn resolve_episodes(pool: &PgPool, jobs: &[ImportJobRow]) -> Result<Vec<EpisodeTarget>> {
    let block_ids: Vec<Uuid> = jobs.iter().filter_map(|job| job.block_id).collect();
    let Some(earliest) = jobs.iter().map(|job| job.created_at).min() else {
        return Ok(Vec::new());
    };
    if block_ids.is_empty() {
        return Ok(Vec::new());
    }
    let episodes = sqlx::query_as::<_, EpisodeTarget>(
        r#"
        SELECT id, project_id, number
        FROM projection_episode
        WHERE block_id = ANY($1)
          AND updated_at >= $2
        ORDER BY project_id, number
        "#,
    )
    .bind(&block_ids)
    .bind(earliest)
    .fetch_all(pool)
    .await
    .context("resolve import-created episodes")?;
    Ok(episodes)
}

/// Dispatches one delete and records the outcome, rebuilding the command
/// service when a poisoned stream killed it.
macro_rules! delete_and_record {
    (
        $context:expr, $report:expr, $aggregate:ty,
        $label:expr, $command:expr, $id:expr, $id_display:expr, $command_value:expr
    ) => {{
        let project_id = project_id_for(&$context.pool, $label, $id_display).await;
        let outcome = classify_delete(delete_one!(
            $aggregate,
            &$context.command_service,
            $id,
            $command_value,
            project_id
        ));
        match outcome {
            DeleteOutcome::Deleted => {
                $report
                    .lines
                    .push(format!("deleted {} {}", $label, $id_display));
                $report.deleted_aggregates.push($id_display);
            }
            DeleteOutcome::Failed(message) => $report
                .failures
                .push(format!("{} {} failed: {}", $command, $id_display, message)),
            DeleteOutcome::ServiceDead(message) => {
                $report.failures.push(format!(
                    "{} {} failed: {} — the aggregate stream could not be replayed (a retired \
                     event variant in old dev data does that); the reset is PARTIAL, use \
                     `--level business` for a clean slate",
                    $command, $id_display, message
                ));
                rebuild_command_service($context);
            }
        }
    }};
}

async fn delete_aggregates(context: &mut Context, targets: &Targets, report: &mut ResetReport) {
    let reservations = ReservationStore::new(kameo_es::ConnectionPool::from(
        context.command_service.conn(),
    ));

    // 1. scene_shoot — before scene and shooting_day (their deletes cascade).
    let scene_shoots: Vec<Uuid> = targets.scene_shoot.iter().copied().collect();
    for id in scene_shoots {
        let pair = scene_shoot_pair(&context.pool, id).await;
        delete_and_record!(
            context,
            report,
            SceneShootAggregate,
            "scene_shoot",
            "DeleteSceneShoot",
            SceneShootId(id),
            id,
            DeleteSceneShoot {
                id: SceneShootId(id)
            }
        );
        let deleted = report.deleted_aggregates.contains(&id);
        match pair {
            Some((scene_id, shooting_day_id)) => {
                let key = scene_shoot_pair_key(scene_id, shooting_day_id.0);
                release_claim(&reservations, &key, id, report).await;
            }
            // The ADR-036 key is built from the projection row; without it the
            // claim stays held and a re-import of the same (scene, day) pair is
            // refused with a 409 (issue #770 review).
            None if deleted => report.failures.push(format!(
                "released no ADR-036 claim for the deleted scene_shoot {id}: its projection row \
                 was already gone, so the pair key could not be rebuilt — a re-import of the same \
                 (scene, day) pair would answer 409; the reset is PARTIAL"
            )),
            None => {}
        }
    }

    // 2. scene.
    for id in targets.scene.iter().copied() {
        delete_and_record!(
            context,
            report,
            SceneAggregate,
            "scene",
            "DeleteScene",
            id,
            id,
            DeleteScene { id }
        );
    }

    // 3. shooting_day.
    for id in targets.shooting_day.iter().copied() {
        delete_and_record!(
            context,
            report,
            ShootingDayAggregate,
            "shooting_day",
            "DeleteShootingDay",
            ShootingDayId(id),
            id,
            DeleteShootingDay {
                id: ShootingDayId(id)
            }
        );
    }

    // 4. outfit — before piece and character.
    for id in targets.outfit.iter().copied() {
        delete_and_record!(
            context,
            report,
            OutfitAggregate,
            "outfit",
            "DeleteOutfit",
            id,
            id,
            DeleteOutfit { id }
        );
    }

    // 5. piece.
    for id in targets.piece.iter().copied() {
        delete_and_record!(
            context,
            report,
            PieceAggregate,
            "piece",
            "DeletePiece",
            id,
            id,
            DeletePiece { id }
        );
    }

    // 6. character.
    for id in targets.character.iter().copied() {
        delete_and_record!(
            context,
            report,
            CharacterAggregate,
            "character",
            "DeleteCharacter",
            id,
            id,
            DeleteCharacter { id }
        );
    }

    // 7. episode — last, and with the ADR-036 numbering claim released so a
    // re-import may reuse the number.
    for episode in targets.episode.iter().copied() {
        let id = episode.id;
        delete_and_record!(
            context,
            report,
            EpisodeAggregate,
            "episode",
            "DeleteEpisode",
            id,
            id,
            DeleteEpisode { id }
        );
        let key = episode_number_key(episode.project_id, episode.number);
        release_claim(&reservations, &key, id, report).await;
    }
}

/// What one delete dispatch did.
enum DeleteOutcome {
    Deleted,
    /// The aggregate rejected the command or the append failed.
    Failed(String),
    /// The **command service actor** died. An entity actor panics while
    /// resyncing a stream it cannot deserialize (a retired event variant in old
    /// dev data — e.g. the pre-split `CostumeBeatAdded`), and that panic takes
    /// the shared service actor with it. The service is rebuilt and the loop
    /// continues, so one unreplayable stream cannot block the whole reset.
    ServiceDead(String),
}

fn classify_delete<E: std::fmt::Debug>(
    result: Result<(), kameo_es::error::ExecuteError<E>>,
) -> DeleteOutcome {
    use kameo_es::error::ExecuteError;

    match result {
        Ok(()) => DeleteOutcome::Deleted,
        Err(ExecuteError::CommandServiceStopped)
        | Err(ExecuteError::CommandServiceNotRunning)
        | Err(ExecuteError::EventStoreActorStopped)
        | Err(ExecuteError::EventStoreActorNotRunning) => {
            DeleteOutcome::ServiceDead("command service stopped".to_string())
        }
        Err(error) => DeleteOutcome::Failed(error.to_string()),
    }
}

/// Rebuilds the command service after an entity-actor panic.
fn rebuild_command_service(context: &mut Context) {
    context.command_service = CommandService::new(context.connection.clone());
    tracing::warn!(
        "rebuilt the command service after an entity actor panic (one aggregate stream could not \
         be replayed)"
    );
}

/// Best-effort project id of an aggregate, resolved from the read model.
///
/// The delete event's `EventMetadata.project_id` is what the audit projector
/// stores, and `GET /audit?project_id=…` filters on that column — a reset
/// deletion with `None` would be invisible in a project-scoped audit view
/// (issue #770 review). Resolution is **best effort by doctrine**: a projection
/// miss (lag, already-deleted row) yields `None` and never blocks the delete.
///
/// One static statement per category; the join chain is the aggregate's
/// hierarchy path (`season` → `project`).
// ast-grep-ignore: cqrs-boundary
// Justification (AGENTS.md §1 escape hatch): this is a dev-only maintenance
// binary, not a command adapter — the read exists solely to attribute the
// delete event in the audit trail, it is best-effort (a miss leaves `None`) and
// it can never block the delete, which is exactly the "audit metadata must never
// block command processing" doctrine.
async fn project_id_for(pool: &PgPool, label: &str, id: Uuid) -> Option<Uuid> {
    let sql = match label {
        "episode" => "SELECT project_id FROM projection_episode WHERE id = $1",
        "scene" => {
            "SELECT e.project_id FROM projection_scene s \
             JOIN projection_episode e ON e.id = s.episode_id WHERE s.id = $1"
        }
        "shooting_day" => {
            "SELECT e.project_id FROM projection_shooting_day d \
             JOIN projection_episode e ON e.id = d.episode_id WHERE d.id = $1"
        }
        "scene_shoot" => {
            "SELECT e.project_id FROM projection_scene_shoot ss \
             JOIN projection_scene s ON s.id = ss.scene_id \
             JOIN projection_episode e ON e.id = s.episode_id WHERE ss.id = $1"
        }
        "character" => {
            "SELECT s.project_id FROM projection_character c \
             JOIN projection_season s ON s.id = c.season_id WHERE c.id = $1"
        }
        "piece" => {
            "SELECT s.project_id FROM projection_piece_season ps \
             JOIN projection_season s ON s.id = ps.season_id WHERE ps.piece_id = $1 LIMIT 1"
        }
        "outfit" => {
            "SELECT s.project_id FROM projection_outfit o \
             JOIN projection_character c ON c.id = o.character_id \
             JOIN projection_season s ON s.id = c.season_id WHERE o.id = $1"
        }
        _ => return None,
    };
    match sqlx::query_scalar::<_, Uuid>(sql)
        .bind(id)
        .fetch_optional(pool)
        .await
    {
        Ok(project_id) => project_id,
        Err(error) => {
            tracing::warn!(label, %id, %error, "could not resolve the project id for the audit row");
            None
        }
    }
}

/// `(scene_id, shooting_day_id)` of a scene shoot, read **before** the delete
/// removes the projection row.
async fn scene_shoot_pair(pool: &PgPool, id: Uuid) -> Option<(Uuid, ShootingDayId)> {
    let row = sqlx::query_as::<_, (Uuid, Uuid)>(
        "SELECT scene_id, shooting_day_id FROM projection_scene_shoot WHERE id = $1",
    )
    .bind(id)
    .fetch_optional(pool)
    .await
    .ok()
    .flatten()?;
    Some((row.0, ShootingDayId(row.1)))
}

/// Releases an ADR-036 claim after its aggregate is gone (best effort, always
/// reported). A `Reserved`/`Consumed` claim is released at the observed stream
/// version; an already `Released` claim is left alone.
async fn release_claim(
    store: &ReservationStore,
    key: &str,
    aggregate_id: Uuid,
    report: &mut ResetReport,
) {
    let state = match store.last_state(key).await {
        Ok(state) => state,
        Err(error) => {
            report
                .failures
                .push(format!("reservation read {key} failed: {error}"));
            return;
        }
    };
    let Some(state) = state else {
        return;
    };
    if state.variant == LifecycleVariant::Released {
        return;
    }
    match store.release(key, aggregate_id, state.stream_version).await {
        Ok(true) => report.lines.push(format!("released claim {key}")),
        Ok(false) => report
            .lines
            .push(format!("claim {key} already resolved (CAS miss)")),
        Err(error) => report
            .failures
            .push(format!("claim release {key} failed: {error}")),
    }
}

/// Deletes the source document and preview objects of every job.
///
/// Returns an error when the objects could **not** be purged — the caller then
/// aborts before deleting the job rows, because those rows are the only place
/// the object handles are recorded. `--skip-payload-purge` is the explicit
/// opt-out for a deliberately unreachable bucket.
async fn purge_payloads(
    jobs: &[ImportJobRow],
    options: &ResetOptions,
    report: &mut ResetReport,
) -> Result<(), String> {
    let Some(storage) = OpenDalAiPayloadStorage::from_env() else {
        if options.skip_payload_purge {
            report.lines.push(
                "--skip-payload-purge: AI payload storage is not configured, so the source and \
                 preview objects were left in place (they become unreachable once the job rows \
                 go)"
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
    let mut purged = 0usize;
    let mut failures = Vec::new();
    for job in jobs {
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

/// Deletes the job rows (cascading attempts and cleanup bookkeeping), their
/// provenance rows and their users' concurrency permits.
async fn delete_job_rows(
    pool: &PgPool,
    jobs: &[ImportJobRow],
    deleted_aggregates: &[Uuid],
    report: &mut ResetReport,
) {
    let job_ids: Vec<Uuid> = jobs.iter().map(|job| job.id).collect();
    let user_ids: Vec<String> = jobs
        .iter()
        .map(|job| job.user_id.clone())
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();

    let mut transaction = match pool.begin().await {
        Ok(transaction) => transaction,
        Err(error) => {
            report
                .failures
                .push(format!("open delete transaction: {error}"));
            return;
        }
    };

    // Provenance first: the mapping table has no foreign key to the job row.
    // Two independent scopes: the non-aggregate rows of THESE jobs (beats, the
    // retired `costume` kind) go, and so does any row whose aggregate was just
    // deleted — the latter also matches the synthetic `episode` rows a previous
    // run wrote with no job behind them.
    let mapping = sqlx::query(
        r#"
        DELETE FROM ai_import.projection_ai_import_mapping
        WHERE (preview_id = ANY($1) AND NOT (aggregate_kind = ANY($3)))
           OR aggregate_id = ANY($2)
        "#,
    )
    .bind(&job_ids)
    .bind(deleted_aggregates)
    .bind(MAPPING_KINDS)
    .execute(&mut *transaction)
    .await;
    let permits = sqlx::query("DELETE FROM ai_import.concurrency_permit WHERE user_id = ANY($1)")
        .bind(&user_ids)
        .execute(&mut *transaction)
        .await;
    let jobs_deleted = sqlx::query("DELETE FROM ai_import.ai_import_job WHERE id = ANY($1)")
        .bind(&job_ids)
        .execute(&mut *transaction)
        .await;

    let (mapping, permits, jobs_deleted) = match (mapping, permits, jobs_deleted) {
        (Ok(mapping), Ok(permits), Ok(jobs)) => (mapping, permits, jobs),
        (mapping, permits, jobs) => {
            let mut message = String::from("delete AI import rows:");
            if let Err(error) = mapping {
                message.push_str(&format!(" mapping: {error};"));
            }
            if let Err(error) = permits {
                message.push_str(&format!(" permits: {error};"));
            }
            if let Err(error) = jobs {
                message.push_str(&format!(" jobs: {error};"));
            }
            report.failures.push(message);
            return;
        }
    };

    if let Err(error) = transaction.commit().await {
        report
            .failures
            .push(format!("commit AI import delete: {error}"));
        return;
    }

    report.lines.push(format!(
        "deleted {} provenance row(s), {} concurrency permit(s), {} job row(s)",
        mapping.rows_affected(),
        permits.rows_affected(),
        jobs_deleted.rows_affected()
    ));
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Mapping kinds this level can delete, mapped to their delete order index.
    const TEST_MAPPING_KINDS: &[&str] = &[
        "scene",
        "character",
        "piece",
        "outfit",
        "shooting_day",
        "scene_shoot",
    ];

    fn mapping(kind: &str, id: Uuid) -> MappingRow {
        MappingRow {
            preview_id: Uuid::now_v7(),
            aggregate_kind: kind.to_string(),
            aggregate_id: id,
        }
    }

    #[test]
    fn provenance_rows_are_bucketed_by_category() {
        let scene = Uuid::now_v7();
        let piece = Uuid::now_v7();
        let targets = collect_targets(&[
            mapping("scene", scene),
            mapping("piece", piece),
            mapping("scene", scene),
            mapping("scene_costume_beat", Uuid::now_v7()),
            mapping("costume", Uuid::now_v7()),
        ]);
        assert_eq!(targets.scene.len(), 1, "duplicate rows must dedupe");
        assert_eq!(targets.piece.len(), 1);
        assert_eq!(targets.ignored_kinds.get("scene_costume_beat"), Some(&1));
        assert_eq!(targets.ignored_kinds.get("costume"), Some(&1));
        assert_eq!(targets.total(), 2);
    }

    #[test]
    fn every_mapping_kind_has_a_delete_bucket() {
        for kind in TEST_MAPPING_KINDS {
            let targets = collect_targets(&[mapping(kind, Uuid::now_v7())]);
            assert_eq!(
                targets.total(),
                1,
                "kind {kind:?} must map to a deletable aggregate"
            );
            assert!(
                targets.ignored_kinds.is_empty(),
                "kind {kind:?} was ignored"
            );
        }
    }

    /// Children must be deleted before the parents whose projection delete
    /// cascades into them (`ON DELETE CASCADE` on the scene/scene_shoot rows).
    #[test]
    fn delete_order_puts_children_first() {
        let position = |category: &str| {
            DELETE_ORDER
                .iter()
                .position(|entry| *entry == category)
                .unwrap_or_else(|| panic!("{category} missing from DELETE_ORDER"))
        };
        assert!(position("scene_shoot") < position("scene"));
        assert!(position("scene_shoot") < position("shooting_day"));
        assert!(position("outfit") < position("piece"));
        assert!(position("outfit") < position("character"));
        assert_eq!(position("episode"), DELETE_ORDER.len() - 1);
    }

    /// A poisoned stream panics the entity actor, which takes the shared
    /// command service with it — the loop must classify that distinctly so it
    /// can rebuild the service and keep going (found in the #770 E2E run: 15
    /// legacy scenes with the retired `CostumeBeatAdded` variant killed the
    /// service and every later delete failed).
    #[test]
    fn a_dead_command_service_is_classified_as_service_dead() {
        use kameo_es::error::ExecuteError;

        let dead: Result<(), ExecuteError<breakdown_core::episode::error::EpisodeError>> =
            Err(ExecuteError::CommandServiceStopped);
        assert!(matches!(
            classify_delete(dead),
            DeleteOutcome::ServiceDead(_)
        ));

        let not_running: Result<(), ExecuteError<breakdown_core::episode::error::EpisodeError>> =
            Err(ExecuteError::CommandServiceNotRunning);
        assert!(matches!(
            classify_delete(not_running),
            DeleteOutcome::ServiceDead(_)
        ));

        let store_dead: Result<(), ExecuteError<breakdown_core::episode::error::EpisodeError>> =
            Err(ExecuteError::EventStoreActorStopped);
        assert!(matches!(
            classify_delete(store_dead),
            DeleteOutcome::ServiceDead(_)
        ));
    }

    #[test]
    fn a_successful_and_a_rejected_delete_are_classified_apart() {
        use kameo_es::error::ExecuteError;

        let ok: Result<(), ExecuteError<breakdown_core::episode::error::EpisodeError>> = Ok(());
        assert!(matches!(classify_delete(ok), DeleteOutcome::Deleted));

        let rejected: Result<(), ExecuteError<breakdown_core::episode::error::EpisodeError>> =
            Err(ExecuteError::Handle(
                breakdown_core::episode::error::EpisodeError::NotFound { id: Uuid::now_v7() },
            ));
        assert!(matches!(
            classify_delete(rejected),
            DeleteOutcome::Failed(_)
        ));
    }

    #[test]
    fn delete_order_covers_the_mapping_kinds_and_the_episode_heuristic() {
        for kind in TEST_MAPPING_KINDS {
            assert!(
                DELETE_ORDER.contains(kind),
                "mapping kind {kind:?} has no entry in DELETE_ORDER"
            );
        }
        // Episodes have no provenance rows (#763) and are resolved heuristically,
        // so they are the one extra entry.
        assert_eq!(DELETE_ORDER.len(), TEST_MAPPING_KINDS.len() + 1);
        assert!(DELETE_ORDER.contains(&"episode"));
    }
}
