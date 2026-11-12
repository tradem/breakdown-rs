// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! The **durable** AI-import apply run (issue #899, design D3).
//!
//! # What changed
//!
//! Before #899 `apply_ai_import` awaited the whole row loop inside the HTTP
//! handler, so the run's lifetime *was* the connection's: an Android suspend, a
//! Wi-Fi→cellular handover or any closed socket dropped the handler future and
//! the apply stopped mid-row (`ApplyRunGuard` then cleared the progress payload,
//! which left the client with nothing but "not applied").
//!
//! Now the handler validates, persists the resolved request and answers `202`;
//! this module is what actually executes it. Two consequences matter:
//!
//! * **A dropped request cannot cancel a run.** The work lives in a task owned
//!   by this loop, not in the request that asked for it.
//! * **Any replica can take it over.** The request and the outcome are columns
//!   on the job row (`apply_request` / `apply_result`) plus the slot state
//!   (`apply_state`), so a rolling deploy, a crashed worker or a restart between
//!   claim and dispatch all converge: the row stays `requested`/`running` and
//!   the next poll picks it up (`AiImportQueue::requested_apply_runs`).
//!
//! # Why this lives in `api`
//!
//! It is the composition-root half of the apply: it needs the *port set* to
//! build the infra workers (`ApplyWorker`, `ScheduleApplyWorker`), and the port
//! set is `api`'s `Ports` trait. The generic work (claim, fence, converge) stays
//! in `core`/`infra`; this file only assembles and drives. That is also why the
//! same entry point serves the handler tests (`run_claimed`): the wiring they
//! used to exercise through the POST is exercised here instead, unchanged.
//!
//! # Crash and shutdown contract
//!
//! A run interrupted by shutdown is **not** rolled back — rows already committed
//! stay committed (the protocol is idempotent-and-converging, never atomic). The
//! slot is left `running` with a stale silence stamp, and the next poll's
//! takeover path (`begin_apply_run` under a fresh run id) re-drives it. Two runs
//! can therefore overlap for a few recovered appends; they can never create a
//! duplicate aggregate, because every create goes through `derive_id` +
//! `ExpectedVersion::Empty` + `created_now` recovery.

use std::sync::Arc;
use std::time::Duration;

use breakdown_core::ai::{
    AiImportJobId, ApplyImportSummary, ApplyRunAccepted, ApplyRunId, ApplyRunOutcome,
    ApplyRunRequest, ApplyStage, ClaimedApplyRun, ScheduleApplyRunRequest, ScriptApplyRunRequest,
    ScriptContext,
};
use breakdown_core::error::DomainError;
use infra::ai::worker_loop::ShutdownSignal;
use infra::ai::{
    ApplyScriptRequest, ApplyWorker, CachedMappings, ScheduleApplyRequest, ScheduleApplyWorker,
};
use tracing::{info, warn};

// Imported for method resolution on `P::AiImportQueue` / `P::AiPreviewStore`.
use breakdown_core::ai::AiImportQueue as _;
use infra::ai::AiPreviewStore as _;

use crate::state::{AppState, Ports};

/// How long the loop sleeps when no run is waiting. Bounded so a shutdown
/// signal is noticed within one interval (the same rule the import workers
/// follow).
const EMPTY_APPLY_SLEEP: Duration = Duration::from_secs(2);

/// How many requested runs one poll claims. Small on purpose: each claim starts
/// a real apply (minutes of writes), and single-flight is per preview anyway.
const APPLY_POLL_BATCH: i64 = 4;

/// How many apply runs one replica executes **concurrently** (issue #899
/// review).
///
/// The poll batch alone is not a bound: a tick claims up to
/// [`APPLY_POLL_BATCH`] rows, and claiming a row moves it out of `requested`, so
/// the next tick two seconds later claims the next four — a backlog of previews
/// would otherwise fan out to hundreds of concurrent applies on one replica,
/// each with its own command-service traffic and pool connections. The batch is
/// therefore additionally capped by the free capacity of this bound, and a full
/// runner skips claiming entirely (the rows stay `requested` and are adopted by
/// the next tick with capacity, or by another replica).
const APPLY_MAX_CONCURRENCY: usize = 4;

/// The script apply worker this app's port set produces.
///
/// A named alias, not an inline nine-parameter type: the type is instantiated in
/// exactly one place (`ApplyRunner::script_worker`) and named once, which keeps
/// `clippy::type_complexity` quiet without an `#[allow]`.
type ScriptApplyWorker<P> = ApplyWorker<
    <P as Ports>::SceneCommands,
    <P as Ports>::CharacterCommands,
    <P as Ports>::WardrobeCommands,
    <P as Ports>::EpisodeCommands,
    <P as Ports>::ShootingDayCommands,
    <P as Ports>::SceneShootCommands,
    infra::ai::CachedMappings<<P as Ports>::AiImportMappingRepo>,
    <P as Ports>::AiImportQueue,
    <P as Ports>::SeasonRepo,
>;

/// Execute one claimed apply run (issue #899).
///
/// Assembles the same infra worker the handler used to build, so the write path
/// is byte-for-byte the pre-#899 one: only the *lifetime* and the *outcome
/// persistence* changed.
pub struct ApplyRunner<P: Ports> {
    state: AppState<P>,
}

impl<P: Ports> ApplyRunner<P> {
    pub fn new(state: AppState<P>) -> Self {
        Self { state }
    }

    /// Run one already-claimed slot to its terminal state.
    ///
    /// Every exit path lands the slot in `done` or `failed`, so a client that
    /// attaches afterwards always gets an outcome instead of a silence. A failed
    /// write of the terminal state is logged and swallowed: the slot then stays
    /// `running` and the takeover path re-drives it — the documented backstop,
    /// which is strictly better than a panic in a detached task.
    pub async fn run_claimed(
        &self,
        claimed: ClaimedApplyRun,
    ) -> Result<ApplyRunOutcome, DomainError> {
        let ClaimedApplyRun {
            job_id,
            run_id,
            request,
        } = claimed;
        info!(
            job_id = %job_id.as_uuid(),
            run_id = %run_id.as_uuid(),
            "starting a durable AI import apply run"
        );
        let outcome = self.execute(job_id, run_id, request).await;
        let outcome = match outcome {
            Ok(summary) => ApplyRunOutcome::Succeeded(Box::new(summary)),
            Err(error) => {
                // Classify once, persist the registered code: the client
                // branches on `code`, never on a prose detail (ADR-031).
                warn!(
                    job_id = %job_id.as_uuid(),
                    run_id = %run_id.as_uuid(),
                    code = error.code().code,
                    %error,
                    "AI import apply run failed"
                );
                ApplyRunOutcome::Failed {
                    code: error.code().code.to_owned(),
                }
            }
        };
        let persisted = match &outcome {
            ApplyRunOutcome::Succeeded(summary) => {
                self.state
                    .ports
                    .ai_import_queue()
                    .complete_apply_run(job_id, run_id, summary)
                    .await
            }
            ApplyRunOutcome::Failed { code } => {
                self.state
                    .ports
                    .ai_import_queue()
                    .fail_apply_run(job_id, run_id, code)
                    .await
            }
        };
        if let Err(error) = persisted {
            // Not fatal for the run (its rows are committed), but the slot now
            // misdescribes reality: report it, and let the staleness window
            // hand the slot to the next poll.
            warn!(
                job_id = %job_id.as_uuid(),
                run_id = %run_id.as_uuid(),
                %error,
                "failed to persist the AI import apply run outcome; \
                 the slot stays running and is recovered by the staleness window"
            );
        }
        Ok(outcome)
    }

    /// The run itself: load the preview, execute the persisted request, record
    /// telemetry. Returns the counters, or the error that must be persisted.
    async fn execute(
        &self,
        job_id: AiImportJobId,
        run_id: ApplyRunId,
        request: ApplyRunRequest,
    ) -> Result<ApplyImportSummary, DomainError> {
        let job = self
            .state
            .ports
            .ai_import_queue()
            .get(job_id)
            .await?
            .ok_or_else(|| DomainError::not_found("ai import job"))?;
        let handle = job
            .preview_handle
            .as_deref()
            .ok_or_else(|| DomainError::not_found("ai import preview"))?;
        let payload = self
            .state
            .ports
            .ai_preview_store()
            .get(handle)
            .await?
            .ok_or_else(|| DomainError::not_found("ai import preview"))?;
        match request {
            ApplyRunRequest::Script(script) => {
                self.run_script(job_id, run_id, *script, &payload).await
            }
            ApplyRunRequest::Schedule(schedule) => {
                self.run_schedule(job_id, run_id, schedule, &payload).await
            }
        }
    }

    /// Execute a script apply and record its telemetry (issue #899).
    ///
    /// `apply_script_run` is the entry point that does **not** claim the slot:
    /// this run already owns it (`begin_apply_run` proved that), and claiming
    /// again would fail the single-flight predicate against our own claim.
    async fn run_script(
        &self,
        job_id: AiImportJobId,
        run_id: ApplyRunId,
        request: ScriptApplyRunRequest,
        payload: &[u8],
    ) -> Result<ApplyImportSummary, DomainError> {
        let preview: ScriptContext = serde_json::from_slice(payload).map_err(|error| {
            tracing::error!(error = %error, "invalid ScriptContext preview");
            DomainError::validation("invalid AI preview payload")
        })?;
        let telemetry = request.telemetry.clone();
        let skipped_day_groups: Vec<String> = request
            .shooting_days
            .iter()
            .filter(|day| !day.accepted)
            .map(|day| day.day_ref.clone())
            .collect();
        let applied = self
            .script_worker()
            .apply_script_run(
                ApplyScriptRequest {
                    actor: request.actor,
                    preview_id: job_id,
                    preview: &preview,
                    decisions: &request.decisions,
                    episode_id: request.episode_id,
                    season_id: request.season_id,
                    project_id: request.project_id,
                    block_id: request.block_id,
                    episode_groups: request.episode_groups,
                    known_episodes: request.known_episodes,
                    shooting_days: request.shooting_days,
                    acknowledged_uncertainties: request.acknowledged_uncertainties,
                    categories: request.categories,
                    continuity_selections: request.continuity_selections,
                    telemetry,
                },
                run_id,
            )
            .await?;
        // NOTE: the script apply records its own telemetry (`run_script_apply`,
        // issue #675): the counters and the accept signal belong to the run, so
        // recording it again here would double the row.
        Ok(ApplyImportSummary {
            applied_count: u32::try_from(applied.applied.len()).unwrap_or(u32::MAX),
            created_days: applied.created_days,
            planned_scene_shoots: applied.planned_scene_shoots,
            created_characters: applied.created_characters,
            created_pieces: applied.created_pieces,
            created_outfits: applied.created_outfits,
            created_episodes: applied.created_episodes,
            // Day groups the reviewer rejected: their rows applied unscheduled
            // — reported, never silent (issue #706). Derived from the persisted
            // decisions, exactly as the handler did before #899.
            skipped_day_groups,
            unapplied_outfits: applied.unapplied_outfits,
            applied_episodes: applied.applied_episodes,
        })
    }

    /// Execute a schedule apply and record its telemetry (issue #899).
    ///
    /// The schedule worker publishes no progress frames (a merge is one row
    /// loop without the script path's per-row protocol), so the telemetry write
    /// that the handler used to do after the merge happens here — fenced to this
    /// run, and never fatal: the merge already committed.
    async fn run_schedule(
        &self,
        job_id: AiImportJobId,
        run_id: ApplyRunId,
        request: ScheduleApplyRunRequest,
        payload: &[u8],
    ) -> Result<ApplyImportSummary, DomainError> {
        let preview: breakdown_core::ai::MergedPreview =
            serde_json::from_slice(payload).map_err(|error| {
                tracing::error!(error = %error, "invalid merged preview");
                DomainError::validation("invalid merged preview")
            })?;
        let result = ScheduleApplyWorker {
            scene_commands: Arc::new(self.state.ports.scene_commands().clone()),
            shooting_day_commands: Arc::new(self.state.ports.shooting_day_commands().clone()),
            scene_shoot_commands: Arc::new(self.state.ports.scene_shoot_commands().clone()),
            // Same per-run cache as the script branch: the schedule apply
            // resolves its pair rows through the same protocol.
            mappings: Arc::new(CachedMappings::new(
                self.state.ports.ai_import_mapping().clone(),
            )),
        }
        .apply(ScheduleApplyRequest {
            actor: request.actor,
            preview_id: job_id,
            preview: &preview,
            project_id: request.project_id,
        })
        .await?;
        // Telemetry is not part of the apply success contract (the merge is
        // committed): log a failed or fenced-out record so the caller still
        // gets its summary — the same non-fatal rule the handler followed.
        if let Some(telemetry) = request.telemetry {
            match self
                .state
                .ports
                .ai_import_queue()
                .record_run_telemetry(job_id, run_id, telemetry)
                .await
            {
                Ok(true) => {}
                Ok(false) => {
                    warn!(
                        job_id = %job_id.as_uuid(),
                        run_id = %run_id.as_uuid(),
                        "skipped the schedule apply telemetry: the run no longer owns the slot"
                    );
                }
                Err(error) => {
                    warn!(
                        job_id = %job_id.as_uuid(),
                        run_id = %run_id.as_uuid(),
                        %error,
                        "failed to record AI import telemetry after a successful schedule apply"
                    );
                }
            }
        }
        Ok(ApplyImportSummary {
            applied_count: 0,
            created_days: result.created_days,
            planned_scene_shoots: result.planned_scene_shoots,
            // A schedule apply touches no figures, pieces or episodes.
            created_characters: 0,
            created_pieces: 0,
            created_outfits: 0,
            created_episodes: 0,
            // A schedule apply decides no script day groups.
            skipped_day_groups: Vec::new(),
            unapplied_outfits: Vec::new(),
            // A schedule merge lands rows in the project's existing scenes and
            // days; it names no target episode, so it records none (issue #763
            // — never an invented one).
            applied_episodes: Vec::new(),
        })
    }

    /// The script apply worker over this app's ports (same wiring the handler
    /// used before #899 moved the run out of the request).
    fn script_worker(&self) -> ScriptApplyWorker<P> {
        ApplyWorker {
            scene_commands: Arc::new(self.state.ports.scene_commands().clone()),
            character_commands: Arc::new(self.state.ports.character_commands().clone()),
            wardrobe_commands: Arc::new(self.state.ports.wardrobe_commands().clone()),
            episode_commands: Arc::new(self.state.ports.episode_commands().clone()),
            shooting_day_commands: Arc::new(self.state.ports.shooting_day_commands().clone()),
            scene_shoot_commands: Arc::new(self.state.ports.scene_shoot_commands().clone()),
            // Per-run read-through cache (live-test finding): the apply is an
            // idempotency-checked write loop whose per-aggregate `find` used to
            // be its own SQL round trip.
            mappings: Arc::new(CachedMappings::new(
                self.state.ports.ai_import_mapping().clone(),
            )),
            queue: Arc::new(self.state.ports.ai_import_queue().clone()),
            // CR-002/D2: the worker refuses the outfit step of an archived
            // target season itself (the piece steps stay valid).
            season_repo: Arc::new(self.state.ports.season_repo().clone()),
        }
    }
}

/// Build the `202 Accepted` descriptor for a dispatched run (design D2).
pub fn accepted_run(
    run_id: ApplyRunId,
    started_at: chrono::DateTime<chrono::Utc>,
) -> ApplyRunAccepted {
    ApplyRunAccepted {
        run_id,
        stage: ApplyStage::Applying,
        started_at,
        apply_state: breakdown_core::ai::ApplyState::Requested,
    }
}

/// Spawn the durable apply-run loop (issue #899, design D3).
///
/// Each tick claims the waiting slots (`requested`, plus stale-`running` for
/// crash recovery) and starts one task per run. The returned handle must be kept
/// alive and joined during graceful shutdown: in-flight runs write through the
/// same pool the shutdown sequence tears down, so a missed join leaves a task
/// writing into a dead pool.
///
/// A run cancelled here stays `running` with a stale silence stamp and is
/// re-driven by the takeover path — the same behaviour a crashed replica has.
/// Deliberately **not** generic over `P: Ports` (issue #899).
///
/// The core write ports declare their methods as native `async fn`
/// (`#[allow(async_fn_in_trait)]`), so a generic caller cannot prove their
/// futures are `Send` — only a concrete adapter leaks that auto-trait. The
/// production composition root is the one place that is allowed to know the
/// concrete port set, so the spawned loop is typed for it. Tests drive
/// [`ApplyRunner::run_claimed`] directly instead of spawning.
pub fn spawn_apply_run_worker(
    state: AppState<crate::state::ProductionPorts>,
    shutdown: ShutdownSignal,
) -> tokio::task::JoinHandle<()> {
    let mut shutdown = shutdown;
    tokio::spawn(async move {
        let mut in_flight: Vec<tokio::task::JoinHandle<()>> = Vec::new();
        loop {
            if *shutdown.borrow() {
                break;
            }
            // A full runner claims nothing: the rows stay `requested` and the
            // next tick with free capacity (or another replica) adopts them.
            // Without this the batch bound would only pace the fan-out, never
            // cap it (see APPLY_MAX_CONCURRENCY).
            let free = APPLY_MAX_CONCURRENCY.saturating_sub(in_flight.len());
            let waiting = if free == 0 {
                Vec::new()
            } else {
                let batch = i64::try_from(free)
                    .unwrap_or(APPLY_POLL_BATCH)
                    .min(APPLY_POLL_BATCH);
                match state
                    .ports
                    .ai_import_queue()
                    .requested_apply_runs(batch)
                    .await
                {
                    Ok(waiting) => waiting,
                    Err(error) => {
                        warn!(%error, "failed to poll the AI import apply-run slot");
                        Vec::new()
                    }
                }
            };
            for job_id in waiting {
                // A fresh identity for the takeover case; the adopt case keeps
                // the dispatching client's run id (the queue decides which).
                let takeover_run_id = ApplyRunId::new();
                match state
                    .ports
                    .ai_import_queue()
                    .begin_apply_run(job_id, takeover_run_id)
                    .await
                {
                    Ok(Some(claimed)) => {
                        let runner = ApplyRunner::new(state.clone());
                        in_flight.push(tokio::spawn(async move {
                            if let Err(error) = runner.run_claimed(claimed).await {
                                // `run_claimed` only reports an unpersistable
                                // outcome; the run's own failure is persisted.
                                warn!(%error, "AI import apply run ended without a persisted outcome");
                            }
                        }));
                    }
                    Ok(None) => {
                        // Another worker won the race (or the run already
                        // finished). Nothing to do — not an error.
                    }
                    Err(error) => {
                        warn!(
                            job_id = %job_id.as_uuid(),
                            %error,
                            "failed to claim an AI import apply run"
                        );
                    }
                }
            }
            in_flight.retain(|handle| !handle.is_finished());
            tokio::select! {
                _ = shutdown.changed() => {}
                _ = tokio::time::sleep(EMPTY_APPLY_SLEEP) => {}
            }
        }
        // Cancel-and-join: a run interrupted by shutdown leaves a reclaimable
        // slot, so this must not block the shutdown budget indefinitely.
        for handle in in_flight {
            handle.abort();
            match handle.await {
                Ok(()) => {}
                Err(error) if error.is_cancelled() => {}
                Err(error) => {
                    warn!(%error, "an AI import apply-run task failed during shutdown");
                }
            }
        }
    })
}
