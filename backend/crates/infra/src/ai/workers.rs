// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: longcat-2.0-free (opencode)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

use std::sync::Arc;
use std::time::Instant;

use anyhow::Error as AnyhowError;
use std::collections::HashMap;

use breakdown_core::ai::{
    AiImportBounds, AiImportJob, AiImportJobId, AiImportMapping, AiImportMappingRepository,
    AiImportProgress, AiImportQueue, AiImportStage, AiModelPricingRepository, AppliedEpisode,
    ApplyGateError, ApplyMapping, ApplyMappingDecision, CategoryVocabularyEntry,
    CharacterApplyPlan, CostBreakdown, DecisionClient, DecisionOutcome, DecisionTelemetry,
    DocumentKind, DraftScene, EpisodeGroupPlan, LlmCallUsage, LlmChatRequest, LlmClient,
    MergedPreview, OutfitApplyPlan, PRIMARY_ORDINAL, PieceApplyPlan, PlannedEpisode,
    PlannedShootingDay, ReviewerDecisions, SceneApplyCommand, SceneApplyPlan, ScriptContext,
    ShootingDayPlan, ShootingSchedule, SourceFormat, Telemetry, TelemetryApplyState,
    UnappliedOutfit, UnappliedOutfitReason, Uncertainty, UncertaintyAcknowledgement,
    UncertaintyKind, category_conflict_uncertainties, character_mapping_ref, draft_row_ref,
    ensure_merge_applyable, extract_scenes, mapping_kind, merge_schedule_to_scenes,
    parse_script_day, plan_scene_apply, sanitize_meta_summary, scene_beat_lanes, stable_draft_ref,
    verify_draft_outfits,
};
use breakdown_core::character::commands::CreateCharacter;
use breakdown_core::character::ports::CharacterCommands;
use breakdown_core::episode::commands::CreateEpisode;
use breakdown_core::episode::ports::EpisodeCommands;
use breakdown_core::error::DomainError;
use breakdown_core::error_registry::{
    AI_IMPORT_APPLY_MISSING_EPISODE_GROUP, AI_IMPORT_APPLY_MISSING_MAPPING,
    AI_IMPORT_APPLY_MISSING_SHOOTING_DAY_GROUP, AI_IMPORT_APPLY_UNKNOWN_CONTINUITY_CANDIDATE,
};
use breakdown_core::error_registry::{SCENE_CHARACTER_ALREADY_ASSIGNED, SCENE_VALIDATION};
use breakdown_core::outfit::commands::{AddPieceToOutfit, CreateOutfit, UpdateOutfitNotes};
use breakdown_core::outfit::ports::OutfitCommands;
use breakdown_core::piece::commands::{CreatePiece, SetPieceCategory, UpdatePieceNotes};
use breakdown_core::piece::ports::PieceCommands;
use breakdown_core::scene::commands::{AddOutfitBeat, AssignCharacter, CreateScene};
use breakdown_core::scene::events::{SceneDetails, SceneSource};
use breakdown_core::scene::ports::SceneCommands;
use breakdown_core::scene_shoot::commands::PlanSceneShoot;
use breakdown_core::scene_shoot::ports::SceneShootCommands;
use breakdown_core::season::ports::SeasonRepository;
use breakdown_core::shared::{
    AggregateVersion, BlockId, EpisodeId, LexicalSortKey, ProjectId, SceneShootId, SeasonId,
    ShootingDayId, UserId,
};
use breakdown_core::shooting_day::ports::ShootingDayCommands;

#[cfg(test)]
#[path = "worker_mutation_tests.rs"]
mod worker_mutation_tests;
use serde_json::to_vec;
use uuid::Uuid;

use super::heartbeat::LeaseHeartbeat;
use super::pdf::PdfTextExtractor;
use super::pg_concurrency::{PgAiConcurrencyLimiter, PgAiConcurrencyPermit};
use super::preview_store::{AiDocumentSource, AiPreviewStore};
use super::runtime::run_with_renewal;
use super::schedule_apply::{
    AppliedDay, DayDraft, ScheduleApplyWorker, derive_id, recover_version,
};
use crate::photo::sagas::is_transient;
use crate::projectors::supervisor;

/// Acquire capacity for an already-claimed job and link the permit to it.
///
/// The job is claimed first so the permit can be charged to
/// `job.user_id` — the user whose work it is — rather than to a synthetic
/// per-worker identity that would make the per-user ceiling meaningless
/// (issue #180).
///
/// `Ok(None)` means the ceiling is saturated. The claim is then handed back so
/// the job is immediately runnable by another worker instead of sitting
/// `running` until its lease lapses, and it is *not* charged a retry: it never
/// ran, so a saturated ceiling must not be able to dead-letter it.
///
/// A failure to hand the claim back is logged rather than propagated: the
/// job's lease still expires, so recovery is delayed, not lost, and reporting
/// the release failure would mask the real outcome ("no capacity").
async fn acquire_for_claim<Q: AiImportQueue + ?Sized>(
    queue: &Q,
    limiter: &PgAiConcurrencyLimiter,
    job: &AiImportJob,
    worker_id: &str,
) -> Result<Option<PgAiConcurrencyPermit>, DomainError> {
    let Some(permit) = limiter
        .try_acquire_as(job.user_id.as_str(), worker_id)
        .await?
    else {
        tracing::info!(
            job_id = %job.id.as_uuid(),
            worker_id,
            "AI import capacity saturated; returning the claim unrun"
        );
        if let Err(error) = queue.release_claim(job.id, worker_id).await {
            tracing::warn!(
                job_id = %job.id.as_uuid(),
                worker_id,
                %error,
                "failed to return an unrun AI import claim; it will be \
                 recovered when the lease expires"
            );
        }
        return Ok(None);
    };

    // Link the permit to the claim so a future reclaim of this job can release
    // it if *this* worker dies.
    //
    // A failure here aborts the job rather than proceeding unlinked, for two
    // reasons. `attach_permit` is owner-fenced, so the overwhelmingly likely
    // error is `Conflict` — this worker's lease lapsed and another worker
    // already owns the job. Continuing would burn LLM spend on work whose
    // every terminal write is destined to be rejected. And on any other error
    // the permit would be invisible to reclaim, so a crash from here on would
    // leak the capacity until the lease expires — the exact leak this change
    // exists to close.
    if let Err(error) = queue.attach_permit(job.id, worker_id, permit.id()).await {
        tracing::warn!(
            job_id = %job.id.as_uuid(),
            worker_id,
            permit_id = %permit.id(),
            %error,
            "failed to link the AI concurrency permit to its job; abandoning \
             the claim rather than running it untracked"
        );
        release_permit_logging_errors(permit, job.id).await;
        return Err(error);
    }
    Ok(Some(permit))
}

/// Publish throttled extraction progress (issue #664), treating the write
/// as **advisory**: a lost claim ([`DomainError::Conflict`]) still propagates
/// — a displaced worker must abort before its next billable LLM call — but
/// every other error (e.g. a transient queue/DB failure) is logged and
/// swallowed. Propagating those would abort the job WITHOUT a `mark_failed`
/// call, leaving it stuck `running` until its lease lapses; a missed
/// progress frame costs a stale-looking spinner for one stage interval, a
/// killed job costs the whole run.
pub(crate) async fn publish_progress<Q: AiImportQueue + ?Sized>(
    queue: &Q,
    id: AiImportJobId,
    worker_id: &str,
    progress: &AiImportProgress,
) -> Result<(), DomainError> {
    if let Err(error) = queue.mark_progress(id, worker_id, progress).await {
        if matches!(error, DomainError::Conflict { .. }) {
            return Err(error);
        }
        tracing::warn!(
            job_id = %id.as_uuid(),
            worker_id,
            %error,
            "advisory AI import progress write failed; continuing the job"
        );
    }
    Ok(())
}

/// Terminate a job whose payload could not be loaded, choosing the terminal
/// state by *why* the load failed (issue #181).
///
/// A `NotFound` means the durable bytes are gone. Retrying could only
/// re-discover the same absence while consuming a claim and a concurrency
/// permit each time, so the job goes straight to
/// [`JobStatus::PayloadUnavailable`](breakdown_core::ai::JobStatus::PayloadUnavailable),
/// bypassing the remaining retry budget.
///
/// Every other error keeps the ordinary retry semantics: a
/// `ServiceUnavailable` is transient (the storage backend is unreachable, the
/// bytes may well still be there) and stays retryable; anything else fails
/// this attempt permanently and dead-letters through the budget.
pub(crate) async fn fail_payload_load<Q: AiImportQueue + ?Sized>(
    queue: &Q,
    id: AiImportJobId,
    worker_id: &str,
    error: &DomainError,
) -> Result<(), DomainError> {
    if matches!(error, DomainError::NotFound { .. }) {
        return queue
            .mark_payload_unavailable(id, worker_id, &error.to_string(), Some(error.code().code))
            .await;
    }
    queue
        .mark_failed(
            id,
            worker_id,
            &error.to_string(),
            Some(error.code().code),
            matches!(error, DomainError::ServiceUnavailable { .. }),
        )
        .await
}

/// Return capacity, logging rather than propagating a release failure.
///
/// The job's own outcome is what the caller must report. A failed release is
/// recovered by the permit's drop hook or its lease, so masking the job result
/// with it would trade a real signal for a recoverable one.
async fn release_permit_logging_errors(permit: PgAiConcurrencyPermit, job_id: AiImportJobId) {
    let permit_id = permit.id();
    if let Err(error) = permit.release().await {
        tracing::warn!(
            job_id = %job_id.as_uuid(),
            %permit_id,
            %error,
            "failed to release an AI concurrency permit; it will be reclaimed \
             by its drop hook or lease"
        );
    }
}

/// Script import pipeline. It is deliberately independent of HTTP and can be
/// driven by a queue worker or deterministic integration tests.
pub struct ScriptImportWorker<Q, C> {
    pub queue: Arc<Q>,
    pub client: Arc<C>,
    pub previews: Arc<dyn AiPreviewStore>,
    pub extractor: PdfTextExtractor,
    pub provider: breakdown_core::ai::LlmProvider,
    pub model: String,
    pub prompt: String,
    pub bounds: AiImportBounds,
    /// Pricing read model for the completion cost snapshot (issue #675).
    /// `None` in test fakes — the snapshot then degrades to
    /// [`CostStatus::Unknown`], never a fabricated price.
    pub pricing: Option<Arc<dyn AiModelPricingRepository>>,
    /// Optional best-effort Decision Model scoring pass (issue #722).
    /// `None` = no decision model configured — the extraction runs exactly
    /// like a pre-#722 job and every score stays honestly `None`.
    ///
    /// Since issue #767 the slot also carries *why* no pass exists: a
    /// configured-but-unbuildable client is a different user-visible fact than
    /// "nothing was configured", and the completion telemetry records which
    /// one happened.
    pub decision: Option<DecisionResolution>,
}

/// Why a claimed job has — or has not — a Decision Model scoring pass
/// (issue #767).
///
/// The worker used to receive a bare `Option<Arc<DecisionPass>>`, which cannot
/// distinguish "the user configured no Decision Model" from "a Decision Model
/// was configured but its client could not be built". Both produced no stars
/// and no explanation, which is exactly the defect #767 reports. The worker
/// loop resolves the configuration and now hands the reason over, so the
/// completion write records the outcome class instead of silence.
#[derive(Clone)]
pub enum DecisionResolution {
    /// Configured and built: the pass runs, and each unit's own failure
    /// (after the bounded quick retry) is recorded per row.
    Available(Arc<DecisionPass>),
    /// Configured, but the credential fetch or the transport build failed.
    /// Best-effort by contract: the job still runs, without scoring.
    Unavailable {
        provider: breakdown_core::ai::LlmProvider,
        model: String,
    },
}

impl DecisionResolution {
    /// The built pass, when this resolution produced one. The only scoring
    /// entry point — callers cannot accidentally score with a resolution that
    /// failed to build.
    fn pass(&self) -> Option<&Arc<DecisionPass>> {
        match self {
            Self::Available(pass) => Some(pass),
            Self::Unavailable { .. } => None,
        }
    }
}

/// The job-level Decision Model outcome recorded with the completion telemetry
/// (issue #767).
///
/// `native_csv` distinguishes the one legitimate "nothing to score" case: a
/// native CSV schedule's rows came from the production tool, so no model
/// produced them and there is no scoring pass to miss. It is therefore decided
/// **before** the resolution: a configured Decision Model must never make a
/// CSV parse report `ran`, because no request was issued for it.
fn decision_telemetry(
    resolution: Option<&DecisionResolution>,
    native_csv: bool,
    scoring: super::decision_scoring::ScoringReport,
) -> DecisionTelemetry {
    if native_csv {
        return DecisionTelemetry {
            provider: None,
            model: None,
            outcome: DecisionOutcome::SkippedNotApplicable,
            failed_rows: 0,
        };
    }
    match resolution {
        Some(DecisionResolution::Available(pass)) => DecisionTelemetry {
            provider: Some(pass.provider),
            model: Some(pass.model.clone()),
            // `is_failure` — NOT `failed_rows > 0`: a pass whose requests never
            // answered is a failure even when no row had anything to score
            // (issue #767 review).
            outcome: if scoring.is_failure() {
                DecisionOutcome::ScoringFailed
            } else {
                DecisionOutcome::Ran
            },
            failed_rows: scoring.failed_rows,
        },
        Some(DecisionResolution::Unavailable { provider, model }) => DecisionTelemetry {
            provider: Some(*provider),
            model: Some(model.clone()),
            outcome: DecisionOutcome::ClientUnavailable,
            failed_rows: 0,
        },
        None => DecisionTelemetry {
            provider: None,
            model: None,
            outcome: DecisionOutcome::SkippedNoConfig,
            failed_rows: 0,
        },
    }
}

/// The resolved Decision Model configuration for one worker (issue #722,
/// design D3): client + `(provider, model)` pair the worker scores with.
pub struct DecisionPass {
    pub client: Arc<dyn DecisionClient>,
    pub provider: breakdown_core::ai::LlmProvider,
    pub model: String,
}

impl<Q, C> ScriptImportWorker<Q, C>
where
    Q: AiImportQueue + 'static,
    C: LlmClient + 'static,
{
    /// Claim and process the next runnable script job.
    ///
    /// Uses the plain `claim_next_kind` (no permit reconciliation). Use this
    /// for ad-hoc invocations where a concurrency permit is not held.
    pub async fn run_once(
        &self,
        worker_id: &str,
        source: &dyn AiDocumentSource,
    ) -> Result<bool, DomainError> {
        let job = match self
            .queue
            .claim_next_kind(worker_id, DocumentKind::Script)
            .await?
        {
            Some(job) => job,
            None => return Ok(false),
        };
        let bytes = match source.load(&job.source_handle).await {
            Ok(bytes) => bytes,
            Err(error) => {
                fail_payload_load(&*self.queue, job.id, worker_id, &error).await?;
                return Err(error);
            }
        };
        self.process(&job, worker_id, &bytes).await.map(|_| true)
    }

    /// Claim and process the next runnable script job under a concurrency
    /// permit charged to the job's own user (issue #180).
    ///
    /// The order is **claim, then acquire**, not the reverse. Acquiring first
    /// would mean acquiring before the owning user is known — the permit could
    /// only be charged to a synthetic per-worker identity, and the per-user
    /// ceiling (`AI_IMPORT_MAX_CONCURRENT_JOBS_PER_USER`) would never bind.
    /// Claiming first yields the job's `user_id`, so the slot is charged to
    /// the user whose work it is.
    ///
    /// The claim also releases the permit of a worker that died holding this
    /// job, *before* the acquisition below — otherwise, at a saturated
    /// ceiling, the reclaiming worker would be refused the very slot the dead
    /// worker is still occupying, and the job could never make progress.
    ///
    /// When no capacity is available the claim is handed back with
    /// `release_claim` so the job is runnable again immediately, without being
    /// charged a retry.
    ///
    /// **Both** leases are renewed for the whole run. The permit lease is kept
    /// alive by [`run_with_renewal`], and the job claim by a [`LeaseHeartbeat`]
    /// started *before* the source load — a slow or hung fetch of a large PDF
    /// can outlive a lease on its own, and without the heartbeat the claim
    /// would lapse while this worker was still working on it.
    pub async fn run_once_with_permit(
        &self,
        worker_id: &str,
        source: &dyn AiDocumentSource,
        limiter: &PgAiConcurrencyLimiter,
    ) -> Result<bool, DomainError> {
        let Some((job, _released)) = self
            .queue
            .claim_next_kind_reconciling(worker_id, DocumentKind::Script)
            .await?
        else {
            return Ok(false);
        };
        // Captured before the acquisition so the renewal loop can only
        // under-estimate the lease window it has, never over-estimate it.
        let acquired_no_later_than = tokio::time::Instant::now();
        let Some(permit) = acquire_for_claim(&*self.queue, limiter, &job, worker_id).await? else {
            return Ok(false);
        };
        let result = run_with_renewal(&permit, acquired_no_later_than, async {
            // Started before the load: `process` starts its own heartbeat for
            // the LLM loop, but the fetch and PDF extraction ahead of it are
            // unprotected otherwise.
            let heartbeat = self.start_heartbeat(job.id, worker_id);
            let bytes = match source.load(&job.source_handle).await {
                Ok(bytes) => bytes,
                Err(error) => {
                    // Stop renewing before the terminal write so the heartbeat
                    // cannot race the failure.
                    if let Some(heartbeat) = heartbeat {
                        heartbeat.stop();
                    }
                    fail_payload_load(&*self.queue, job.id, worker_id, &error).await?;
                    return Err(error);
                }
            };
            if super::heartbeat::claim_lost(heartbeat.as_ref()) {
                // Another worker owns the job now; every terminal write of
                // ours would be rejected, so stop before the LLM spend.
                return Err(DomainError::conflict(format!(
                    "AI import job {} was reclaimed while its source loaded",
                    job.id.as_uuid()
                )));
            }
            if let Some(heartbeat) = heartbeat {
                heartbeat.stop();
            }
            self.process(&job, worker_id, &bytes).await
        })
        .await;
        release_permit_logging_errors(permit, job.id).await;
        result.map(|_| true)
    }

    /// `worker_id` must be the id that claimed `job`: every lifecycle write is
    /// owner-fenced, so passing a foreign id makes the job's completion fail
    /// with `DomainError::Conflict`.
    pub async fn process(
        &self,
        job: &AiImportJob,
        worker_id: &str,
        pdf_bytes: &[u8],
    ) -> Result<String, DomainError> {
        if job.document_kind != DocumentKind::Script {
            return Err(DomainError::validation(
                "script worker received a non-script job",
            ));
        }
        let text = self.extractor.extract(pdf_bytes).await?;
        self.process_text(job, worker_id, &text).await
    }

    /// Process already extracted text. This seam keeps PDF subprocess tests
    /// separate from deterministic worker tests.
    ///
    /// A script job makes one LLM call per chunk (up to `max_chunks_per_script`
    /// of up to `request_timeout_secs` each), which far outlives a single lease
    /// window. A [`LeaseHeartbeat`] therefore renews the claim while the loop
    /// runs, and the loop aborts as soon as the heartbeat reports the claim
    /// was lost — continuing would burn LLM spend on a job another worker has
    /// already taken over.
    pub async fn process_text(
        &self,
        job: &AiImportJob,
        worker_id: &str,
        text: &str,
    ) -> Result<String, DomainError> {
        let started = Instant::now();
        let heartbeat = self.start_heartbeat(job.id, worker_id);
        let chunks = extract_scenes(text);
        let chunk_count = u32::try_from(chunks.len()).map_err(|error| {
            DomainError::validation(format!(
                "script chunk count exceeds telemetry range: {error}"
            ))
        })?;
        if let Err(error) = validate_chunk_count(chunks.len(), self.bounds.max_chunks_per_script) {
            self.fail(job.id, worker_id, &error).await?;
            return Err(error);
        }
        if chunks.is_empty() {
            let error =
                DomainError::validation("script did not contain an INT./EXT. scene heading");
            self.fail(job.id, worker_id, &error).await?;
            return Err(error);
        }

        let mut context = ScriptContext::default();
        // Issue #675: real token/energy usage accumulated across all chunks.
        let mut total_usage = LlmCallUsage::default();
        // Globally unique scene counter across all chunks — the tail of
        // `stable_draft_ref`, which needs a stable identity per preview row
        // that survives the model's own (hallucinated) `draft_ref`.
        let mut scene_ordinal = 0usize;
        // Issue #668: count of meta-summaries the deterministic guard
        // rewrote to `null` across the whole job — the prompt/model
        // regression signal logged before the job succeeds.
        let mut meta_rewrites = 0usize;
        // Per-chunk scoring signals (issue #722): sanitized-summary flags
        // and dropped-costume counts, aligned with the scenes each chunk
        // pushes into `context.scenes`.
        let mut sanitized_flags: Vec<bool> = Vec::new();
        let mut dropped_costumes: Vec<usize> = Vec::new();
        // Scene reconciliation counters (issue #758). `scenes_extracted` counts
        // the rows the MODEL returned; `scenes_synthesized` counts rows rebuilt
        // from the deterministic heading after a chunk returned no rows at all.
        // The two never overlap, so `chunk_count > scenes_extracted` keeps
        // naming the shortfall even when the synthesized rows preserve every
        // scene.
        let mut scenes_extracted = 0u32;
        let mut scenes_synthesized = 0u32;
        // Preview rows whose own Decision Model scoring request failed after
        // the bounded quick retry, plus whether any request failed at all
        // (issue #767). Summed across chunks and recorded in the job's decision
        // telemetry, which is what turns "no stars on some rows" into an
        // explainable, persisted fact.
        let mut decision_scoring = super::decision_scoring::ScoringReport::default();
        // Throttled live progress (issue #664): published once after
        // chunking, once per completed chunk, and at the storing boundary —
        // NEVER per LLM token. Owner-fenced, so a displaced worker's write
        // is rejected and it aborts before its next billable call.
        let mut progress = AiImportProgress {
            stage: AiImportStage::Extracting,
            chunk: Some(0),
            chunks_total: Some(chunk_count),
            episodes_seen: Vec::new(),
        };
        if let Some(first) = chunks.first() {
            progress.record_episode(first.episode.as_ref());
        }
        super::workers::publish_progress(&*self.queue, job.id, worker_id, &progress).await?;
        for (chunk_index, chunk) in chunks.into_iter().enumerate() {
            // Hoisted because the grounding check below must verify a quote
            // against *exactly* the bytes the model was given. Grounding against
            // a differently assembled string would drop real quotes and pass
            // invented ones near a boundary.
            let source_text = format!("{}\n{}", chunk.heading, chunk.text);
            let request = LlmChatRequest {
                provider: self.provider,
                model: self.model.clone(),
                prompt: self.prompt.clone(),
                source_text: source_text.clone(),
                max_tokens: self.bounds.max_tokens_per_req,
                response_schema: None,
            };
            if super::heartbeat::claim_lost(heartbeat.as_ref()) {
                // Stop before the next paid call: another worker owns the job.
                return Err(claim_lost_error(job.id, worker_id));
            }
            let partial = retry_chat(
                self.client.as_ref(),
                request,
                self.bounds.max_retries as usize,
            )
            .await;
            match partial {
                Ok((partial, call_usage)) => {
                    // Index of the first scene THIS chunk pushes (issue
                    // #722): the scoring pass slices the chunk's scenes out
                    // of the preview.
                    let chunk_first_scene = context.scenes.len();
                    // Issue #758: the model's own row count for THIS chunk,
                    // captured before the loop consumes the vector. Zero rows
                    // is the one unambiguous loss signal; a merged
                    // index+body heading legitimately yields a single row, so
                    // "fewer rows than headings" is NOT a defect.
                    let chunk_model_rows = partial.scenes.len();
                    scenes_extracted = scenes_extracted
                        .saturating_add(u32::try_from(chunk_model_rows).unwrap_or(u32::MAX));
                    // Issue #675: accumulate real token/energy usage across
                    // every chunk of the job.
                    total_usage.accumulate(call_usage);
                    if context.title.is_none() {
                        context.title = partial.title;
                    }
                    for (index_in_chunk, mut scene) in partial.scenes.into_iter().enumerate() {
                        scene_ordinal += 1;
                        // Server-side truth beats the model's draft_ref: the
                        // heading comes from the document (extract_scenes) and
                        // the ordinal guarantees uniqueness, so the apply
                        // mapping can no longer resolve several preview rows
                        // to one decision via a repeated placeholder.
                        scene.draft_ref =
                            stable_draft_ref(scene_ordinal, &chunk.heading, index_in_chunk);
                        // Server-side truth beats the prompt (same doctrine as
                        // `draft_ref` above): `extract_scenes` read the leading
                        // number out of the document heading. When the model
                        // omits `scene_number` despite the heading carrying one,
                        // the preview row rendered "?" for a number the document
                        // states (issue #581 user report). Only the FIRST scene
                        // of a chunk backfills — the heading is that scene's
                        // heading; a model-split further scene is not.
                        if scene.scene_number.is_none() && index_in_chunk == 0 {
                            scene.scene_number = chunk.scene_number;
                        }

                        // Set-shorthand mood (issue #721): `extract_scenes`
                        // parsed the heading's interior/exterior + time token
                        // into the canonical shorthand (`I/T`, `A/N`, …). The
                        // backfill is narrowly scoped: ONLY the first scene of
                        // a chunk (the heading is that scene's heading) and
                        // ONLY when the model left `mood` empty — any
                        // model-provided value remains unchanged. The
                        // deterministic scan then fills the gap (same
                        // server-truth doctrine as `scene_number` above).
                        if scene.mood.is_none() && index_in_chunk == 0 {
                            scene.mood = chunk.mood.clone();
                        }

                        // Episode metadata: the deterministic `Ep.:` scan of the
                        // document is authoritative — INCLUDING the title-page
                        // title enrichment (the scan carries the `(294)
                        // "Freundschaft"` heading the bare page-header markers
                        // never had); the LLM's `episode` field (issue #581
                        // prompt rule) only fills in when the scan found no
                        // marker for this chunk (foreign notation). The old
                        // model-wins rule let the model's titleless
                        // `{number: 294}` overwrite the scan's enriched value.
                        // Symmetrically (CodeRabbit review): a model TITLE
                        // survives when the scan carries none and the numbers
                        // agree — the bare page-header marker must not erase
                        // the model's extracted episode heading.
                        if chunk.episode.is_some() {
                            let mut effective = chunk.episode.clone().unwrap_or_default();
                            let model_title = scene
                                .episode
                                .as_ref()
                                .filter(|model| model.number == effective.number)
                                .and_then(|model| model.title.clone());
                            if effective.title.is_none() {
                                effective.title = model_title;
                            }
                            scene.episode = Some(effective);
                        }
                        // Shooting-day metadata (issue #706): the deterministic
                        // day scan of the document is authoritative (same
                        // doctrine as the `Ep.:` scan above); the model's
                        // verbatim `script_day` (grounded prompt rule) only
                        // normalizes into a day group when the scan found no
                        // marker for this chunk. An unparseable label still
                        // groups by its verbatim text; a blank one stays
                        // unscheduled — never invented.
                        if chunk.shooting_day.is_some() {
                            scene.shooting_day = chunk.shooting_day.clone();
                        } else if scene.shooting_day.is_none() {
                            scene.shooting_day =
                                scene.script_day.as_deref().and_then(parse_script_day);
                        }
                        // Issue #668: deterministic post-extraction guard —
                        // the prompt bans meta-summaries, but a prompt is an
                        // instruction, not a guarantee (same doctrine as the
                        // costume check below). A summary that describes the
                        // block's shape/emptiness instead of scene content is
                        // set to `null` BEFORE the preview is stored, so the
                        // garbage can no longer flow through apply →
                        // projection → app. Each rewrite is counted and
                        // logged so prompt/model regressions stay observable.
                        // Issue #722: remember whether the guard fired for
                        // THIS scene — the synopsis score degrades to the
                        // honest 0.0 for it (issue #722 §3.2).
                        let sanitized = sanitize_meta_summary(&mut scene);
                        if sanitized {
                            meta_rewrites += 1;
                            tracing::warn!(
                                job_id = %job.id.as_uuid(),
                                draft_ref = %scene.draft_ref,
                                "ai-extraction: meta-summary rewritten to null — model violated the #607 prompt ban (issue #668)"
                            );
                        }
                        sanitized_flags.push(sanitized);
                        // Server-side truth beats the prompt too (design D5): a
                        // prompt forbids inventing an outfit, but a prompt is an
                        // instruction, not a guarantee. Everything the check drops
                        // is recorded as a non-blocking `DroppedRow` uncertainty,
                        // so a hallucinated outfit cannot reach the reviewer and
                        // a missing one is still visible as missing — without
                        // making the whole preview unappliable (design D9).
                        // Issue #722: count the drops of THIS scene — a
                        // grounding penalty input for the scene score.
                        let mut scene_dropped = 0usize;
                        for rejected in verify_draft_outfits(&mut scene, &source_text) {
                            scene_dropped += 1;
                            context.uncertainties.push(Uncertainty {
                                // 0-based index of the row pushed just below.
                                // `scene_ordinal` is a 1-based GLOBAL counter, so
                                // using it here attached every drop to the NEXT
                                // preview row — and pointed past the end of the
                                // list for the last scene, so the reviewer would
                                // see the missing outfit on the wrong scene.
                                scene_index: context.scenes.len(),
                                field: "outfits".to_owned(),
                                note: format!(
                                    "{}: outfit of {:?} ({:?}) was dropped; row {}",
                                    rejected.reason,
                                    rejected.character_name,
                                    rejected.name,
                                    scene.draft_ref,
                                ),
                                suggested_value: Some(rejected.name),
                                kind: UncertaintyKind::DroppedRow,
                                candidates: Vec::new(),
                            });
                        }
                        dropped_costumes.push(scene_dropped);
                        context.scenes.push(scene);
                    }
                    context.uncertainties.extend(partial.uncertainties);
                    // Best-effort Decision Model scoring pass (issue #722,
                    // design D3): ONE single-pass decision request per chunk
                    // evaluates the whole rubric; any failure logs a warning
                    // and leaves the scores honestly `None`. The extraction
                    // result above is never discarded because of it.
                    if let Some(decision) =
                        self.decision.as_ref().and_then(DecisionResolution::pass)
                    {
                        let ambiguities: Vec<usize> = (chunk_first_scene..context.scenes.len())
                            .map(|scene_index| {
                                context
                                    .uncertainties
                                    .iter()
                                    .filter(|uncertainty| {
                                        uncertainty.scene_index == scene_index
                                            && uncertainty.kind.blocks_apply()
                                    })
                                    .count()
                            })
                            .collect();
                        let scenes = &mut context.scenes[chunk_first_scene..];
                        let scoring = super::decision_scoring::score_script_chunk(
                            decision,
                            &chunk.heading,
                            &chunk.text,
                            chunk.scene_number,
                            chunk.mood.as_deref(),
                            chunk.shooting_day.as_ref(),
                            scenes,
                            // The guard vectors are job-wide (one entry per
                            // pushed scene); the scoring pass receives the
                            // CHUNK-LOCAL slice aligned with `scenes` —
                            // otherwise scene i of chunk n+1 reads the
                            // signals of scene i of chunk 1.
                            &sanitized_flags[chunk_first_scene..],
                            &dropped_costumes[chunk_first_scene..],
                            &ambiguities,
                            &mut total_usage,
                        )
                        .await;
                        // Rows whose own scoring request failed (issue #767):
                        // summed across chunks into the job-level decision
                        // telemetry, so a partially scored import says so.
                        decision_scoring.merge(scoring);
                    }
                    // Issue #758 (silent data loss): a chunk that returned no
                    // rows used to vanish without a trace — the job still
                    // reached `succeeded` and the preview simply carried fewer
                    // rows than the document had headings (measured live: 57
                    // headings, 4 rows). Dropping the row must never be the
                    // default behaviour, so the scene is rebuilt from the
                    // document metadata the deterministic scan already parsed
                    // (`heading`, `scene_number`, `mood`, `episode`,
                    // `shooting_day`) with empty content fields, plus a
                    // non-blocking `DroppedRow` uncertainty that names the
                    // degradation for the reviewer. Deliberately placed AFTER
                    // the Decision scoring pass: a row without content has
                    // nothing to score, and scoring must not invent a value for
                    // it.
                    if chunk_model_rows == 0 {
                        tracing::warn!(
                            job_id = %job.id.as_uuid(),
                            chunk_index = chunk.index,
                            chunk = chunk_index + 1,
                            chunks = chunk_count,
                            heading = %chunk.heading,
                            "ai-extraction: chunk produced no scenes; rebuilding the row from the document heading (issue #758)"
                        );
                        scenes_synthesized = scenes_synthesized.saturating_add(1);
                        scene_ordinal += 1;
                        context.uncertainties.push(Uncertainty {
                            // 0-based index of the row pushed just below.
                            scene_index: context.scenes.len(),
                            field: "extraction".to_owned(),
                            note: format!(
                                "chunk produced no rows; row carries document metadata only (heading {:?})",
                                chunk.heading
                            ),
                            suggested_value: None,
                            kind: UncertaintyKind::DroppedRow,
                            candidates: Vec::new(),
                        });
                        context.scenes.push(DraftScene {
                            draft_ref: stable_draft_ref(scene_ordinal, &chunk.heading, 0),
                            scene_number: chunk.scene_number,
                            mood: chunk.mood.clone(),
                            episode: chunk.episode.clone(),
                            shooting_day: chunk.shooting_day.clone(),
                            // Every content field stays empty: this row states
                            // what the DOCUMENT says about the scene and never
                            // what a model failed to extract.
                            ..DraftScene::default()
                        });
                    }
                }
                Err(error) => {
                    self.fail(job.id, worker_id, &error).await?;
                    return Err(error);
                }
            }
            // Chunk completed (issue #664): 1-based counter + episodes
            // discovered up to and including this chunk, in first-seen order.
            progress.chunk = Some(u32::try_from(chunk_index + 1).map_err(|error| {
                DomainError::validation(format!(
                    "script chunk index exceeds telemetry range: {error}"
                ))
            })?);
            progress.record_episode(chunk.episode.as_ref());
            super::workers::publish_progress(&*self.queue, job.id, worker_id, &progress).await?;
        }
        // Pass 2 (OpenSpec `ai-import-decision-outfit-continuity`): after EVERY
        // chunk is extracted and merged, a cross-scene scan asks the Decision
        // Model what each undressed figure most probably wears. Best-effort by
        // contract — a provider failure logs and ends the pass, and the preview
        // is stored either way (the extraction is already paid for). It runs
        // BEFORE the storing announcement so the progress stage never claims
        // "storing" while a paid request is still outstanding.
        let continuity = match self.decision.as_ref().and_then(DecisionResolution::pass) {
            Some(decision) => {
                super::outfit_continuity::run_outfit_continuity_pass(
                    decision,
                    &mut context,
                    &mut total_usage,
                    || super::heartbeat::claim_lost(heartbeat.as_ref()),
                )
                .await
            }
            None => super::outfit_continuity::ContinuityPassReport::default(),
        };

        // Storing boundary (issue #664): the last visibility gap is the
        // preview upload, not a silent stall at "extracting".
        progress.stage = AiImportStage::StoringPreview;
        progress.chunk = Some(chunk_count);
        super::workers::publish_progress(&*self.queue, job.id, worker_id, &progress).await?;
        // Issue #695: document-global category conflicts only become visible
        // once every chunk's rows are merged — collect them here, where the
        // whole preview exists, so the reviewer sees the conflict before the
        // apply instead of the plan's first-non-default reconciliation rule.
        context
            .uncertainties
            .extend(category_conflict_uncertainties(&context));
        // Issue #758: stamp the reconciliation counters on the stored preview so
        // the reviewer sees "detected vs extracted" BEFORE applying and the
        // shortfall cannot hide behind the row count. Server-derived truth, set
        // here rather than taken from the model's answer.
        context.scenes_detected = chunk_count;
        context.scenes_extracted = scenes_extracted;
        context.scenes_synthesized = scenes_synthesized;
        // One job-level line for the reconciliation outcome: a nonzero
        // `scenes_synthesized`, or any divergence between the document's
        // heading count and the model's row count, is the prompt/model
        // regression signal an operator can alert on.
        if scenes_synthesized > 0 || scenes_extracted != chunk_count {
            tracing::warn!(
                job_id = %job.id.as_uuid(),
                scenes_detected = chunk_count,
                scenes_extracted,
                scenes_synthesized,
                preview_rows = context.scenes.len(),
                "ai-extraction: preview rows diverge from the detected scene headings (issue #758)"
            );
        }
        let payload = to_vec(&context).map_err(|error| {
            DomainError::validation(format!("could not serialize script preview: {error}"))
        })?;
        // Issue #668: the job-level rewrite count as the counter signal —
        // nonzero means the configured extraction model ignored the #607
        // prompt ban and the guard had to enforce it mechanically.
        if meta_rewrites > 0 {
            tracing::warn!(
                job_id = %job.id.as_uuid(),
                rewrites = meta_rewrites,
                chunks = chunk_count,
                "ai-extraction: meta-summary guard rewrote {} scene summaries to null (issue #668)",
                meta_rewrites
            );
        }
        // Pass-2 telemetry: the counters a prompt/model regression would move.
        if continuity.gaps > 0 {
            tracing::info!(
                job_id = %job.id.as_uuid(),
                gaps = continuity.gaps,
                continued = continuity.continued,
                inferred = continuity.inferred,
                reported = continuity.gaps_reported,
                undecided = continuity.undecided,
                unresolved = continuity.unresolved(),
                "ai-extraction: outfit-continuity pass finished"
            );
        }
        let handle = self.previews.put(job.id, payload).await?;
        // Stop renewing before the terminal writes so a heartbeat cannot race
        // the completion and re-extend a lease that is about to be released.
        if let Some(heartbeat) = heartbeat {
            heartbeat.stop();
        }
        self.queue
            .record_worker_telemetry(
                job.id,
                worker_id,
                Telemetry {
                    provider: Some(self.provider),
                    model: Some(self.model.clone()),
                    doc_kind: Some(DocumentKind::Script),
                    chunk_count,
                    // Fully specified (no `..Default` spread) so a deleted
                    // field is a compile error, not a surviving mutant
                    // (issue #307): real token/energy counts measured across
                    // all chunks (issue #675).
                    tokens_in: total_usage.tokens_in,
                    tokens_out: total_usage.tokens_out,
                    cached_tokens_in: total_usage.cached_tokens_in,
                    energy_millijoules: total_usage.energy_millijoules,
                    latency_total: started.elapsed().as_millis().min(u128::from(u64::MAX)) as u64,
                    // Scene reconciliation counters (issue #758): what the
                    // document said, what the model produced, and how many rows
                    // had to be rebuilt from the heading.
                    scenes_detected: chunk_count,
                    scenes_extracted,
                    scenes_synthesized,
                    // Cost snapshot computed from the pricing row active at
                    // completion, persisted before `mark_succeeded` (issue
                    // #675). The job only reached preview; the apply outcome
                    // (if any) is recorded by the apply path as `Applied`.
                    cost: Some(
                        compute_cost_snapshot(
                            self.pricing.as_deref(),
                            self.provider,
                            &self.model,
                            &total_usage,
                        )
                        .await,
                    ),
                    apply_state: TelemetryApplyState::NotApplied,
                    // Whether the Decision Model ran, was never configured, or
                    // could not be built (issue #767) — the job-level answer a
                    // star-less preview cannot give on its own.
                    decision: Some(decision_telemetry(
                        self.decision.as_ref(),
                        false,
                        decision_scoring,
                    )),
                },
            )
            .await?;
        self.queue
            .mark_succeeded(job.id, worker_id, &handle)
            .await?;
        Ok(handle)
    }

    fn start_heartbeat(&self, id: AiImportJobId, worker_id: &str) -> Option<LeaseHeartbeat> {
        let lease = self.queue.lease_window()?;
        LeaseHeartbeat::start(Arc::clone(&self.queue), id, worker_id, lease)
    }

    async fn fail(
        &self,
        id: AiImportJobId,
        worker_id: &str,
        error: &DomainError,
    ) -> Result<(), DomainError> {
        self.queue
            .mark_failed(
                id,
                worker_id,
                &error.to_string(),
                Some(error.code().code),
                matches!(error, DomainError::ServiceUnavailable { .. }),
            )
            .await
    }
}

/// Compute the immutable per-import cost snapshot (issue #675, design D3/D4).
///
/// Looks `(provider, model)` up in the pricing read model and folds the
/// accumulated usage into a `CostBreakdown`. Honest-degradation rule: a
/// missing pricing row (e.g. Ollama, unpriced custom model) or an unwired /
/// failing repository yields [`CostStatus::Unknown`] — never a fabricated
/// zero price — while the raw token/energy telemetry is still recorded.
async fn compute_cost_snapshot(
    pricing: Option<&dyn AiModelPricingRepository>,
    provider: breakdown_core::ai::LlmProvider,
    model: &str,
    usage: &LlmCallUsage,
) -> CostBreakdown {
    let Some(repo) = pricing else {
        tracing::debug!(
            provider = provider.as_str(),
            model,
            "ai-extraction: pricing repository not wired; recording unknown cost"
        );
        return CostBreakdown::unknown();
    };
    match repo.find_for_model(provider, model).await {
        Ok(Some(snapshot)) => breakdown_core::ai::cost::cost_breakdown(
            usage.tokens_in,
            usage.tokens_out,
            usage.cached_tokens_in,
            usage.energy_millijoules,
            Some(&snapshot),
        ),
        Ok(None) => CostBreakdown::unknown(),
        Err(error) => {
            // A pricing read-model outage must not fail a succeeded import:
            // degrade to `unknown` and keep the honest telemetry.
            tracing::warn!(
                provider = provider.as_str(),
                model,
                %error,
                "ai-extraction: pricing lookup failed; recording unknown cost"
            );
            CostBreakdown::unknown()
        }
    }
}

/// The job was reclaimed by another worker while this one was still working.
/// Surfaced as a `Conflict` so the caller abandons the job instead of retrying
/// — the new owner is already redoing the work.
fn claim_lost_error(id: AiImportJobId, worker_id: &str) -> DomainError {
    DomainError::conflict(format!(
        "worker {worker_id} lost its claim on AI import job {} mid-processing",
        id.as_uuid()
    ))
}

/// Schedule import pipeline. CSV is parsed native; PDF/plain-text input is
/// extracted to text and passed to an LLM client implementing
/// `extract_schedule`. The extraction path is derived from the job's persisted
/// `source_format`, never from a caller-supplied flag (issue #221).
pub struct ScheduleImportWorker<Q, C> {
    pub queue: Arc<Q>,
    pub client: Arc<C>,
    pub previews: Arc<dyn AiPreviewStore>,
    pub extractor: PdfTextExtractor,
    pub provider: breakdown_core::ai::LlmProvider,
    pub model: String,
    pub prompt: String,
    pub bounds: AiImportBounds,
    /// See [`ScriptImportWorker::pricing`] (issue #675).
    pub pricing: Option<Arc<dyn AiModelPricingRepository>>,
    /// See [`ScriptImportWorker::decision`] (issue #767 for the resolution
    /// enum).
    pub decision: Option<DecisionResolution>,
}

impl<Q, C> ScheduleImportWorker<Q, C>
where
    Q: AiImportQueue + 'static,
    C: LlmClient + 'static,
{
    pub async fn run_once(
        &self,
        worker_id: &str,
        source: &dyn AiDocumentSource,
    ) -> Result<bool, DomainError> {
        let job = match self
            .queue
            .claim_next_kind(worker_id, DocumentKind::Schedule)
            .await?
        {
            Some(job) => job,
            None => return Ok(false),
        };
        let bytes = match source.load(&job.source_handle).await {
            Ok(bytes) => bytes,
            Err(error) => {
                fail_payload_load(&*self.queue, job.id, worker_id, &error).await?;
                return Err(error);
            }
        };
        self.process(&job, worker_id, &bytes).await.map(|_| true)
    }

    /// Claim and process the next runnable schedule job under a concurrency
    /// permit charged to the job's own user. See
    /// [`ScriptImportWorker::run_once_with_permit`] for the full
    /// claim-then-acquire and dual-lease-renewal rationale (issue #180).
    pub async fn run_once_with_permit(
        &self,
        worker_id: &str,
        source: &dyn AiDocumentSource,
        limiter: &PgAiConcurrencyLimiter,
    ) -> Result<bool, DomainError> {
        let Some((job, _released)) = self
            .queue
            .claim_next_kind_reconciling(worker_id, DocumentKind::Schedule)
            .await?
        else {
            return Ok(false);
        };
        let acquired_no_later_than = tokio::time::Instant::now();
        let Some(permit) = acquire_for_claim(&*self.queue, limiter, &job, worker_id).await? else {
            return Ok(false);
        };
        let result = run_with_renewal(&permit, acquired_no_later_than, async {
            let heartbeat = self.start_heartbeat(job.id, worker_id);
            let bytes = match source.load(&job.source_handle).await {
                Ok(bytes) => bytes,
                Err(error) => {
                    if let Some(heartbeat) = heartbeat {
                        heartbeat.stop();
                    }
                    fail_payload_load(&*self.queue, job.id, worker_id, &error).await?;
                    return Err(error);
                }
            };
            if super::heartbeat::claim_lost(heartbeat.as_ref()) {
                return Err(DomainError::conflict(format!(
                    "AI import job {} was reclaimed while its source loaded",
                    job.id.as_uuid()
                )));
            }
            if let Some(heartbeat) = heartbeat {
                heartbeat.stop();
            }
            self.process(&job, worker_id, &bytes).await
        })
        .await;
        release_permit_logging_errors(permit, job.id).await;
        result.map(|_| true)
    }

    /// `worker_id` must be the id that claimed `job`: every lifecycle write is
    /// owner-fenced, so passing a foreign id makes the job's completion fail
    /// with `DomainError::Conflict`.
    pub async fn process(
        &self,
        job: &AiImportJob,
        worker_id: &str,
        bytes: &[u8],
    ) -> Result<String, DomainError> {
        if job.document_kind != DocumentKind::Schedule {
            return Err(DomainError::validation(
                "schedule worker received a non-schedule job",
            ));
        }
        let started = Instant::now();
        // The extraction path is derived from the job's persisted source
        // format, never from a caller-supplied flag — the worker loop and the
        // processor cannot disagree (issue #221).
        let native_csv = job.source_format.uses_native_csv();
        // Native CSV parsing is fast and needs no heartbeat; the LLM path can
        // outlive the lease, so renew the claim while it runs.
        let heartbeat = (!native_csv)
            .then(|| self.start_heartbeat(job.id, worker_id))
            .flatten();
        // Throttled live progress (issue #664): one frame at the extraction
        // boundary and one at the storing boundary — a schedule job is a
        // single LLM/Native-CSV unit, so there is no per-chunk cadence.
        let mut progress = AiImportProgress {
            stage: if native_csv {
                AiImportStage::Extracting
            } else {
                AiImportStage::ExtractingText
            },
            chunk: Some(0),
            chunks_total: Some(1),
            episodes_seen: Vec::new(),
        };
        super::workers::publish_progress(&*self.queue, job.id, worker_id, &progress).await?;
        // Issue #675: usage of the single LLM call (zeros for the native CSV
        // path, which never invokes an LLM).
        let mut total_usage = LlmCallUsage::default();
        // Rows the schedule scoring request left unscored and whether that
        // request failed (issue #767); both stay empty on the native CSV path,
        // which never scores at all.
        let mut decision_scoring = super::decision_scoring::ScoringReport::default();
        let mut schedule = if native_csv {
            super::csv_schedule::parse_schedule_csv(bytes)?
        } else {
            let source_text = match job.source_format {
                SourceFormat::Pdf => self.extractor.extract(bytes).await?,
                // `Csv` never reaches this branch (`native_csv` above), so the
                // fallback is exactly `PlainText`.
                _ => String::from_utf8(bytes.to_vec()).map_err(|error| {
                    DomainError::validation(format!("schedule document is not UTF-8 text: {error}"))
                })?,
            };
            let request = LlmChatRequest {
                provider: self.provider,
                model: self.model.clone(),
                prompt: self.prompt.clone(),
                source_text,
                max_tokens: self.bounds.max_tokens_per_req,
                response_schema: None,
            };
            let (parsed, call_usage) = retry_schedule(
                self.client.as_ref(),
                request,
                self.bounds.max_retries as usize,
            )
            .await?;
            total_usage.accumulate(call_usage);
            parsed
        };
        // Best-effort Decision Model scoring pass for LLM-extracted
        // schedules (issue #722 §3.3): one single-pass request scores the
        // day assignments; any failure degrades the scores to `None`
        // without failing the job. The native CSV path never scores — its
        // rows came from the production tool, not from a model.
        if let Some(decision) = self.decision.as_ref().and_then(DecisionResolution::pass)
            && !native_csv
        {
            let scoring = super::decision_scoring::score_schedule_rows(
                decision,
                &mut schedule.rows,
                &mut total_usage,
            )
            .await;
            // A schedule scores in ONE request, so a failure marks every row
            // that had an assignment to score (issue #767).
            decision_scoring.merge(scoring);
        }
        if schedule.block_id.is_none() {
            schedule.block_id = job.block_id;
        }
        // After extraction, before the preview upload (issue #664).
        progress.stage = AiImportStage::StoringPreview;
        progress.chunk = Some(1);
        super::workers::publish_progress(&*self.queue, job.id, worker_id, &progress).await?;
        let payload = to_vec(&schedule).map_err(|error| {
            DomainError::validation(format!("could not serialize schedule preview: {error}"))
        })?;
        let handle = self.previews.put(job.id, payload).await?;
        // Stop renewing before the terminal writes so a heartbeat cannot race
        // the completion.
        if let Some(heartbeat) = heartbeat {
            heartbeat.stop();
        }
        self.queue
            .record_worker_telemetry(
                job.id,
                worker_id,
                Telemetry {
                    provider: (!native_csv).then_some(self.provider),
                    model: (!native_csv).then(|| self.model.clone()),
                    doc_kind: Some(DocumentKind::Schedule),
                    // Fully specified (no `..Default` spread) so a deleted
                    // field is a compile error, not a surviving mutant
                    // (issue #307). Real token/energy counts (issue #675).
                    chunk_count: 0,
                    // A schedule document has no scene headings, so there is
                    // nothing to reconcile (issue #758).
                    scenes_detected: 0,
                    scenes_extracted: 0,
                    scenes_synthesized: 0,
                    tokens_in: total_usage.tokens_in,
                    tokens_out: total_usage.tokens_out,
                    cached_tokens_in: total_usage.cached_tokens_in,
                    energy_millijoules: total_usage.energy_millijoules,
                    latency_total: started.elapsed().as_millis().min(u128::from(u64::MAX)) as u64,
                    // Cost snapshot (issue #675): `not_applicable` for the
                    // native CSV path (no LLM), computed for the LLM path.
                    cost: Some(if native_csv {
                        CostBreakdown::not_applicable()
                    } else {
                        compute_cost_snapshot(
                            self.pricing.as_deref(),
                            self.provider,
                            &self.model,
                            &total_usage,
                        )
                        .await
                    }),
                    // The job only reached preview; the apply outcome (if any)
                    // is recorded by the apply path as `Applied`.
                    apply_state: TelemetryApplyState::NotApplied,
                    // The job-level decision outcome (issue #767); the native
                    // CSV path reports `skipped_not_applicable` because no
                    // model produced those rows.
                    decision: Some(decision_telemetry(
                        self.decision.as_ref(),
                        native_csv,
                        decision_scoring,
                    )),
                },
            )
            .await?;
        self.queue
            .mark_succeeded(job.id, worker_id, &handle)
            .await?;
        Ok(handle)
    }

    fn start_heartbeat(&self, id: AiImportJobId, worker_id: &str) -> Option<LeaseHeartbeat> {
        let lease = self.queue.lease_window()?;
        LeaseHeartbeat::start(Arc::clone(&self.queue), id, worker_id, lease)
    }

    // No `fail` helper here: this worker's only failure path is the payload
    // load, which routes through `fail_payload_load` so an absent payload is
    // distinguished from unreachable storage (issue #181). `process` surfaces
    // its own errors to the caller.
}

/// Deterministic merge operation. A zero-scene input is explicitly blocked so
/// schedules cannot be applied before the script has produced real scenes.
pub struct MergeWorker;

impl MergeWorker {
    pub fn merge(
        schedule: &ShootingSchedule,
        scenes: &[breakdown_core::scene::views::SceneView],
        episode_numbers: &std::collections::HashMap<EpisodeId, i32>,
    ) -> Result<MergedPreview, DomainError> {
        if scenes.is_empty() {
            return Err(DomainError::conflict(
                "merge is pending until the block has applied scenes",
            ));
        }
        Ok(merge_schedule_to_scenes(schedule, scenes, episode_numbers))
    }

    pub fn validate_for_apply(preview: &MergedPreview) -> Result<(), DomainError> {
        ensure_merge_applyable(preview).map_err(|error| DomainError::conflict(error.to_string()))
    }
}

/// Apply worker for reviewed script rows.
///
/// One accepted draft row applies as up to three kinds of aggregate: its
/// **scene**, the **figures** it names, and the **costumes** of those figures.
/// Every kind is checked against the persisted mapping before it dispatches, so
/// a crash or a concurrent duplicate cannot create a second Scene, Character or
/// Costume.
pub struct ApplyWorker<C, CH, CO, E, SD, SS, M, Q, SR> {
    pub scene_commands: Arc<C>,
    pub character_commands: Arc<CH>,
    pub wardrobe_commands: Arc<CO>,
    /// Episode creation for draft episode groups the reviewer mapped to a NEW
    /// episode (issue #581). Never used to look an episode up: targets that
    /// already exist reach the worker as a resolved id inside the plan.
    pub episode_commands: Arc<E>,
    /// Shooting-day creation for accepted draft day groups and the scene-link
    /// dispatch of the group's rows (issue #706). Never used to look a day up:
    /// accepted groups always create the day under the row's resolved episode
    /// via the shared reservation protocol.
    pub shooting_day_commands: Arc<SD>,
    /// Scene-shoot planning for the scene→day links of accepted day groups
    /// (issue #706) — the same pair idempotency the schedule apply runs.
    pub scene_shoot_commands: Arc<SS>,
    pub mappings: Arc<M>,
    pub queue: Arc<Q>,
    /// Season read model, used for exactly one thing: refusing the **outfit**
    /// step when the target season is archived (CR-002/D2, issue #533). See
    /// `apply_costume` step 3 for why this is a dispatch precondition and not
    /// an audit-context lookup.
    pub season_repo: Arc<SR>,
}

/// Parameters for one reserved scene create in the script apply path.
/// Bundled so `create_scene_reserved` stays under the `too_many_arguments`
/// lint (an `#[allow]` would violate AGENTS.md §3).
struct ReservedSceneDraft {
    preview_id: AiImportJobId,
    draft_ref: String,
    candidate_id: Uuid,
    episode_id: EpisodeId,
    project_id: Option<ProjectId>,
    details: SceneDetails,
}

/// Parameters for one reserved episode create in the script apply path
/// (issue #581). Bundled so `create_episode_reserved` stays under the
/// `too_many_arguments` lint (an `#[allow]` would violate AGENTS.md §3, cf.
/// `ReservedSceneDraft`).
struct ReservedEpisodeDraft {
    preview_id: AiImportJobId,
    /// The draft episode group's stable ref (`ep:<n>` / `ep-t:<title>`).
    episode_ref: String,
    block_id: BlockId,
    project_id: ProjectId,
    number: i32,
    name: Option<String>,
}

/// What one script apply produced.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ScriptApplyResult {
    /// Scene aggregates, one per applied draft row — the historical
    /// `applied_count` of the endpoint.
    pub applied: Vec<UuidVersion>,
    /// Figures this apply appended. A figure an earlier row of the same preview
    /// already created is not counted again: that dedup is the whole point of
    /// keying a figure's mapping row by its name identity.
    pub created_characters: u32,
    /// Fundus `Piece`s this apply created. A piece an earlier attempt already
    /// created is not counted again — its `piece` mapping row short-circuits.
    pub created_pieces: u32,
    /// `Outfit`s this apply created. A look an earlier attempt already created
    /// is not counted again (deterministic id + mapping row).
    pub created_outfits: u32,
    /// Outfit beats this apply appended to the row scenes' streams (issue
    /// #546 §5.8). A settled beat (already present from an earlier apply) is
    /// not counted again. Infra-internal reporting: the wire response carries
    /// the per-outfit refusals (`unapplied_outfits`), from which the applied
    /// beats are exactly the accepted outfits absent from that list.
    pub created_outfit_beats: u32,
    /// Episodes this apply created for draft episode groups mapped to a NEW
    /// episode (issue #581). A group an earlier attempt (or a concurrent
    /// duplicate) already created is not counted again — the mapping row
    /// short-circuits, mirroring the figure dedup.
    pub created_episodes: u32,
    /// Shooting days this apply created for accepted draft day groups
    /// (issue #706). A group an earlier attempt already created is not
    /// counted again — the mapping row short-circuits.
    pub created_days: u32,
    /// Scene→shooting-day links this apply planned (`scene_shoot` pairs,
    /// issue #706). A link an earlier attempt already confirmed is not
    /// counted again.
    pub planned_scene_shoots: u32,
    /// Outfits that did not become an `Outfit`, each with its reason. Reported,
    /// never dropped: a silently missing look is the failure mode this change
    /// exists to remove (design D5).
    pub unapplied_outfits: Vec<UnappliedOutfit>,
    /// The episodes this apply landed rows in, in first-applied order, each
    /// with its own row count (issue #763). The apply is the only place that
    /// knows both halves — the resolved target episode of every row and how
    /// many rows went there — so the summary is produced here and persisted by
    /// the API edge; no projection is consulted.
    pub applied_episodes: Vec<AppliedEpisode>,
}

/// A figure as far as this apply is concerned.
#[derive(Debug, Clone)]
enum Figure {
    Resolved(UuidVersion),
    /// `CreateCharacter` was refused; the detail is what the reviewer sees
    /// alongside the costumes that could therefore not be bound.
    Unavailable(String),
}

/// Outcome of one chain step: done, or refused for this row.
///
/// The two failure classes must not be collapsed. A `Refused` step is a per-row
/// outcome the reviewer can act on (reported in `unapplied_outfits`); an `Err`
/// from the surrounding `Result` is an infrastructure outage that fails the
/// whole apply, so the retry re-drives the unfinished rows from their
/// reservations instead of leaving them silently unwritten.
enum ChainStep<T> {
    Done(T),
    Refused(UnappliedOutfitReason, String),
}

/// What the piece chain of one outfit produced.
struct PieceChainOutcome {
    /// Pieces this call appended `PieceCreated` for (retries skip the rest).
    created: u32,
    /// The pieces in plan order — the outfit's `piece_ids`.
    piece_ids: Vec<Uuid>,
}

/// What the outfit step produced.
struct OutfitChainOutcome {
    /// This call appended `OutfitCreated`.
    created: bool,
    /// The outfit's aggregate id — the beat step casts it into the row's
    /// scene stream (issue #546 §5.8).
    outfit_id: Uuid,
}

/// What one beat dispatch produced (issue #546 §5.8).
enum BeatAttempt {
    /// This call appended the `CostumeBeatAdded`.
    Appended,
    /// The beat already exists (confirmed mapping row, a folded replay or
    /// the identical-last guard): settled without appending.
    Settled,
    /// The scene refused the beat for a costume that is fully applied —
    /// reported to the reviewer as `BeatRejected`, distinct from the
    /// plan-time drop where the costume never came into existence.
    Refused(DomainError),
}

/// Split "the domain refused this row" from "a dependency is down".
///
/// A refusal is a per-row outcome the reviewer can act on; an outage is not, and
/// must fail the whole apply so the retry re-drives the unfinished rows from
/// their reservations instead of leaving them silently unwritten.
fn is_infra_outage(error: &DomainError) -> bool {
    matches!(
        error,
        DomainError::ServiceUnavailable { .. } | DomainError::Internal { .. }
    )
}

/// The version chain one AI `Piece` leaves behind.
///
/// `projection_ai_import_mapping` stores the aggregate version after every step,
/// which makes the **version the phase record** of a crashed apply: a retry
/// re-drives only the steps above the stored version and can never append the
/// same event twice. The phase flags come from the plan, which is deterministic
/// for a given preview, so the thresholds a retry computes are the thresholds
/// the crashed attempt computed. The arithmetic is pinned by
/// `test_ai_apply_chain_advances_exactly_one_version_per_step`.
#[derive(Debug, Clone, Copy)]
struct PiecePhases {
    /// A resolved category hint makes the piece dispatch `SetPieceCategory`
    /// after the create; an unresolved hint must not dispatch a clearing
    /// command. It also shifts the notes event one version later.
    has_category: bool,
}

impl PiecePhases {
    /// `CreatePiece` appends exactly one event, landing on `INITIAL`.
    const CREATED: AggregateVersion = AggregateVersion::INITIAL;
    /// Version reached after `SetPieceCategory` appended.
    const CATEGORIZED: AggregateVersion = AggregateVersion(2);

    /// Version reached after `UpdatePieceNotes` appended: the notes event is the
    /// third event when a category was set first, the second otherwise.
    fn notes_version(&self) -> AggregateVersion {
        if self.has_category {
            AggregateVersion(3)
        } else {
            AggregateVersion(2)
        }
    }
}

/// Version reached on an outfit stream after `CreateOutfit` appended: the
/// outfit's chain is create (→ `INITIAL`) plus an optional
/// `UpdateOutfitNotes` (→ [`OUTFIT_NOTED`]). No guards are needed beyond these
/// two thresholds, so they stay plain constants (the piece chain needs the
/// category-dependent `notes_version` instead).
const OUTFIT_CREATED: AggregateVersion = AggregateVersion::INITIAL;
/// Version reached on an outfit stream after `UpdateOutfitNotes` appended.
const OUTFIT_NOTED: AggregateVersion = AggregateVersion(2);

/// Outcome of a create-style dispatch against a reserved aggregate id.
struct CreateOutcome {
    version: AggregateVersion,
    /// `false` when the stream already carried the event — a retry landing on its
    /// own reservation (issue #179), which must not be counted as a second
    /// creation in the apply report.
    appended: bool,
}

/// [`recover_version`] plus whether the append happened now. Same reasoning: the id came from *this* apply's reservation, so a
/// version conflict on that stream proves our own earlier append and not a
/// foreign writer.
fn created_now(
    result: Result<(Uuid, AggregateVersion), DomainError>,
) -> Result<CreateOutcome, DomainError> {
    match result {
        Ok((_, version)) => Ok(CreateOutcome {
            version,
            appended: true,
        }),
        Err(DomainError::VersionConflict { current, .. }) if current != AggregateVersion(0) => {
            tracing::info!(
                current = current.0,
                "recovered an AI apply aggregate from its own reserved stream"
            );
            Ok(CreateOutcome {
                version: current,
                appended: false,
            })
        }
        Err(error) => Err(error),
    }
}

/// The scene details as the planner resolved them — the same payload whichever
/// command the row was decided as.
fn planned_details(command: &SceneApplyCommand) -> SceneDetails {
    match command {
        SceneApplyCommand::Create(command) => command.details.clone(),
        SceneApplyCommand::Update(command) => command.details.clone(),
    }
}

/// A draft-row position as a mapping ordinal. i32 bounds are far above any
/// preview's row count, but a `as` cast would silently wrap; fail loudly.
fn ordinal_of(index: usize) -> Result<i32, DomainError> {
    i32::try_from(index).map_err(|_| {
        DomainError::validation("AI apply row index exceeds the mapping ordinal range")
    })
}

/// The aggregate name a planned outfit is created with.
///
/// The extraction names the look; the aggregate requires a non-blank name, so a
/// blank extraction falls back to the neutral `Outfit` (the notes carry the
/// script's own wording either way).
fn outfit_name(outfit: &OutfitApplyPlan) -> String {
    let name = outfit.name.trim();
    if name.is_empty() {
        "Outfit".to_string()
    } else {
        name.chars().take(120).collect()
    }
}

/// The aggregate name a planned piece is created with.
///
/// A piece name is derived by the model from the outfit (`OP-Kasack`), so it is
/// usually a label already; a blank one falls back to a neutral generic name
/// because `CreatePiece` rejects a blank name.
fn piece_name(piece: &PieceApplyPlan) -> String {
    let name = piece.name.trim();
    if name.is_empty() {
        "Kleidungsstück".to_string()
    } else {
        name.chars().take(120).collect()
    }
}

/// Reviewed script apply request. `episode_id`, `season_id`, `project_id` and
/// `block_id` are resolved by the API edge from the target episode / job block
/// and are never looked up by this write-side worker (CQRS boundary, AGENTS.md
/// §1). Figures and costumes are season-scoped aggregates, so the season
/// cannot be derived here. `episode_groups` carries the reviewer's per-group
/// episode targets (issue #581); a NEW episode is created under `block_id`.
pub struct ApplyScriptRequest<'a> {
    pub actor: UserId,
    pub preview_id: AiImportJobId,
    pub preview: &'a ScriptContext,
    pub decisions: &'a [ApplyMapping],
    pub episode_id: EpisodeId,
    pub season_id: SeasonId,
    pub project_id: Option<ProjectId>,
    /// Parent of episodes a group creates (issue #581) — the job's block,
    /// resolved at the API edge.
    pub block_id: BlockId,
    /// Per-group episode targets keyed by the preview's group refs. Absent
    /// groups (rows without episode metadata) apply to `episode_id`.
    pub episode_groups: Vec<EpisodeGroupPlan>,
    /// Display identities of the episodes rows can land in, resolved at the API
    /// edge (issue #763): the target episode plus every episode an *existing*
    /// group target names. The worker only reads them to label the
    /// [`ScriptApplyResult::applied_episodes`] summary it already counts; a
    /// missing entry degrades that entry's number/name to `None` and never
    /// fails the apply — a display label must not be able to block a write.
    pub known_episodes: Vec<AppliedEpisodeIdentity>,
    /// Per-day decisions keyed by the preview's day-group refs (issue #706).
    /// An accepted group's rows are scheduled onto a NEW episode-scoped day;
    /// a rejected group's rows apply unscheduled.
    pub shooting_days: Vec<ShootingDayPlan>,
    /// Reviewer acknowledgements of blocking uncertainties (issue #663).
    /// Request-carried: the stored preview is immutable, so the resolution
    /// travels with the other reviewer decisions and the apply gate counts
    /// only unacknowledged blockers.
    pub acknowledged_uncertainties: Vec<UncertaintyAcknowledgement>,
    /// The target season's category vocabulary, loaded at the API edge (CQRS
    /// boundary). The planner turns a piece's `category_hint` into one of these
    /// ids; the write side never reads that projection. An empty list is
    /// legitimate: every piece is then created uncategorized.
    pub categories: Vec<CategoryVocabularyEntry>,
    /// Per-gap continuity resolutions (OpenSpec
    /// `ai-import-decision-outfit-continuity`). Each entry names a gap scene and
    /// the candidate the reviewer picked; the planner validates every one
    /// against the preview's own candidate list.
    pub continuity_selections: Vec<breakdown_core::ai::OutfitContinuitySelection>,
    pub telemetry: Option<Telemetry>,
}

/// Whether one planned row was applied by **this** call, or settled by a
/// mapping an earlier attempt already confirmed (issue #763 review).
///
/// The distinction matters for the applied-episode summary: an already-applied
/// row sits where the earlier attempt put it, so the episode this request names
/// is not necessarily the scene's home. Counting it is still correct (the row
/// did land), labelling it from the request is not.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AppliedRowState {
    /// This call dispatched the row's command and confirmed its mapping.
    AppliedNow,
    /// The row's mapping was already confirmed; nothing was dispatched.
    AlreadyApplied,
}

/// Count one applied row into the per-episode summary (issue #763).
///
/// The label is taken from the first authoritative source, in order:
///
/// 1. `requested_label` — the plan's own number/title, passed ONLY when this
///    apply created the episode (and the row was applied by this call). A
///    reapply of an episode group keeps the mapped episode, so the request's
///    `Create` target can disagree with what is persisted; labelling from it
///    would make the summary and the episode contradict each other.
/// 2. `known_episodes` — the identities the API edge resolved before dispatch
///    (the primary target episode and every *existing* group target).
/// 3. nothing — the entry keeps its `applied_count` with `number`/`name` unset,
///    which every client renders as "no known target" instead of a guess.
fn record_applied_episode(
    applied: &mut Vec<AppliedEpisode>,
    episode_id: EpisodeId,
    requested_label: Option<(Option<i32>, Option<String>)>,
    known_episodes: &[AppliedEpisodeIdentity],
) {
    if let Some(entry) = applied.iter_mut().find(|entry| entry.id == episode_id.0) {
        entry.applied_count += 1;
        // A label found later outranks an unlabelled first sighting of the same
        // episode (a group's first row may precede the authoritative one).
        if entry.number.is_none() && entry.name.is_none() {
            if let Some((number, name)) = requested_label {
                entry.number = number;
                entry.name = name;
            } else if let Some(known) = known_episodes.iter().find(|known| known.id == episode_id) {
                entry.number = Some(known.number);
                entry.name = known.name.clone();
            }
        }
        return;
    }
    let identity = requested_label.or_else(|| {
        known_episodes
            .iter()
            .find(|known| known.id == episode_id)
            .map(|known| (Some(known.number), known.name.clone()))
    });
    let (number, name) = identity.unwrap_or((None, None));
    if number.is_none() && name.is_none() {
        // Expected on a reapply (the persisted episode owns the values) and on
        // a row an earlier attempt already applied. The count remains true.
        tracing::debug!(
            episode_id = %episode_id.0,
            "recording an unlabelled applied-episode entry: no authoritative identity for this apply"
        );
    }
    applied.push(AppliedEpisode {
        id: episode_id.0,
        number,
        name,
        applied_count: 1,
    });
}

/// Display identity of one episode an apply may land rows in (issue #763).
///
/// Resolved where a projection read is legitimate — the API edge — and carried
/// into the apply so the write path never queries one (CQRS boundary). The
/// worker only ever *labels* with it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppliedEpisodeIdentity {
    pub id: EpisodeId,
    pub number: i32,
    pub name: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UuidVersion {
    pub aggregate_id: uuid::Uuid,
    pub version: breakdown_core::shared::AggregateVersion,
}

/// The mapping address one beat is recorded under: kind, mapping `draft_ref`,
/// ordinal.
///
/// `draft_ref` is the FINAL key — consumers hand it to `find`/`reserve` verbatim
/// and never re-derive it. An extracted row's key is the figure's preview-wide
/// mapping reference ([`character_mapping_ref`], not the raw identity):
/// re-deriving it at one call site but not another is what made the
/// scene-version recovery loop look up a key no row is stored under (PR #746
/// review).
#[derive(Debug)]
struct BeatAddress<'a> {
    kind: &'static str,
    draft_ref: std::borrow::Cow<'a, str>,
    ordinal: usize,
}

/// Resolve the mapping address of one planned outfit's beat.
///
/// The ordinal comes from the planner, which derives it from the IMMUTABLE
/// preview (or, for a reviewer-selected gap row, from the draft's own character
/// list) — never from the plan. A plan-derived position shifts when the reviewer
/// changes a decision, and the shifted row would then find another row's
/// confirmed mapping row and silently get no beat (review finding).
///
/// Extracted rows are keyed per FIGURE: one figure can wear a look in several
/// scenes, and the ordinal is its position across the whole preview. Selected
/// gap rows are request-carried and have no preview index, so they get their own
/// kind and are keyed by the row plus the figure's draft position; the two
/// namespaces can therefore never collide.
fn beat_address<'a>(row: &'a SceneApplyPlan, outfit: &'a OutfitApplyPlan) -> BeatAddress<'a> {
    if outfit.from_continuity_selection {
        BeatAddress {
            kind: mapping_kind::SCENE_OUTFIT_BEAT_CONTINUITY,
            draft_ref: std::borrow::Cow::Borrowed(row.draft_ref.as_str()),
            ordinal: outfit.beat_ordinal,
        }
    } else {
        BeatAddress {
            kind: mapping_kind::SCENE_OUTFIT_BEAT,
            // The figure's preview-wide mapping reference — the same key the
            // `character` rows use and the one beat rows are stored under.
            draft_ref: std::borrow::Cow::Owned(character_mapping_ref(&outfit.character_identity)),
            ordinal: outfit.beat_ordinal,
        }
    }
}

/// Where one outfit beat's command points. Bundled so `apply_outfit_beat`
/// stays under the `too_many_arguments` lint (an `#[allow]` would violate
/// AGENTS.md §3, cf. `OutfitDispatch`).
struct BeatDispatch<'a> {
    actor: UserId,
    preview_id: AiImportJobId,
    project_id: Option<ProjectId>,
    /// The scene aggregate the beat mutates — the stream whose version the
    /// row's mapping rows jointly track.
    scene_id: Uuid,
    character_id: Uuid,
    /// The mapping address this beat is recorded under (see [`beat_address`]).
    beat: BeatAddress<'a>,
    outfit_id: Uuid,
    /// The running scene-stream version of the row, advanced in place.
    scene_version: &'a mut AggregateVersion,
}

impl<C, CH, CO, E, SD, SS, M, Q, SR> ApplyWorker<C, CH, CO, E, SD, SS, M, Q, SR>
where
    C: SceneCommands + 'static,
    CH: CharacterCommands + 'static,
    CO: PieceCommands + OutfitCommands + 'static,
    E: EpisodeCommands + 'static,
    SD: ShootingDayCommands + 'static,
    SS: SceneShootCommands + 'static,
    M: AiImportMappingRepository + 'static,
    Q: AiImportQueue + 'static,
    SR: SeasonRepository + 'static,
{
    /// Resolve the `Outfit` a continued look references (design D3).
    ///
    /// The SOURCE row's `outfit` mapping row is the durable record of the aggregate
    /// that row created; a continuation creates none. A missing row (the reviewer
    /// rejected the source outfit) and a row that never reached its create (the
    /// apply crashed earlier, or the source row was dropped from the plan) both mean
    /// there is no look to reference — reported as
    /// [`UnappliedOutfitReason::ContinuityUnresolved`], never fabricated.
    async fn resolve_continued_outfit(
        &self,
        preview_id: AiImportJobId,
        continuation: &breakdown_core::ai::ContinuationPlan,
    ) -> Result<Option<Uuid>, DomainError> {
        let ordinal = ordinal_of(continuation.source_outfit_ordinal)?;
        let stored = self
            .mappings
            .find(
                // ast-grep-ignore: cqrs-boundary
                preview_id,
                &continuation.source_draft_ref,
                mapping_kind::OUTFIT,
                ordinal,
            )
            .await?;
        match stored {
            Some(mapping) if mapping.aggregate_version >= OUTFIT_CREATED => {
                Ok(Some(mapping.aggregate_id))
            }
            _ => Ok(None),
        }
    }

    pub async fn apply_script(
        &self,
        request: ApplyScriptRequest<'_>,
    ) -> Result<ScriptApplyResult, DomainError> {
        let ApplyScriptRequest {
            actor,
            preview_id,
            preview,
            decisions,
            episode_id,
            season_id,
            project_id,
            block_id,
            episode_groups,
            known_episodes,
            shooting_days,
            acknowledged_uncertainties,
            categories,
            continuity_selections,
            telemetry,
        } = request;
        // The planner is the single source of what an apply dispatches; the
        // worker never re-derives the reviewer's decisions itself, so plan and
        // dispatch cannot drift apart.
        let decisions = self
            .resolved_decisions(preview_id, preview, decisions)
            .await?;
        // The two client-bug refusals answer their own registered codes
        // (issue #663) so the grouped apply screen can point at the stale
        // row/group instead of rendering the generic `domain.conflict`. The
        // uncertainty refusal keeps the generic conflict here: the API-edge
        // pre-check renders it as 409 `ai-import.apply-blocked` with the
        // blocking items in its extensions (this check stays authoritative).
        let plan = plan_scene_apply(
            preview,
            &decisions,
            episode_id,
            project_id,
            preview_id,
            &ReviewerDecisions {
                episode_groups: &episode_groups,
                shooting_days: &shooting_days,
                acknowledged_uncertainties: &acknowledged_uncertainties,
                // The target season's category vocabulary, loaded by the API
                // edge and carried in the request (CQRS boundary: the planner
                // never reads that projection).
                categories: &categories,
                continuity_selections: &continuity_selections,
            },
        )
        .map_err(|error| match error {
            ApplyGateError::MissingMapping(draft_ref) => DomainError::Conflict {
                code: &AI_IMPORT_APPLY_MISSING_MAPPING,
                reason: format!("no mapping decision for draft row {draft_ref}"),
            },
            ApplyGateError::MissingEpisodeGroup(episode_ref) => DomainError::Conflict {
                code: &AI_IMPORT_APPLY_MISSING_EPISODE_GROUP,
                reason: format!("no episode group {episode_ref} in the preview"),
            },
            ApplyGateError::MissingShootingDayGroup(day_ref) => DomainError::Conflict {
                code: &AI_IMPORT_APPLY_MISSING_SHOOTING_DAY_GROUP,
                reason: format!("no shooting day group {day_ref} in the preview"),
            },
            // OpenSpec `ai-import-decision-outfit-continuity`: a continuity
            // selection the immutable preview does not derive is the reviewer's
            // screen being stale, not a domain refusal.
            ApplyGateError::UnknownContinuityCandidate(draft_ref) => DomainError::Conflict {
                code: &AI_IMPORT_APPLY_UNKNOWN_CONTINUITY_CANDIDATE,
                reason: format!("draft row {draft_ref} has no such continuity candidate"),
            },
            other => DomainError::conflict(other.to_string()),
        })?;
        // Fully specified (no `..Default` spread) so a deleted field is a
        // compile error instead of a silent default (mutation hardening,
        // issue #585; same pattern as PR #358).
        let mut result = ScriptApplyResult {
            applied: Vec::with_capacity(plan.scenes.len()),
            created_characters: 0,
            created_pieces: 0,
            created_outfits: 0,
            created_outfit_beats: 0,
            created_episodes: 0,
            created_days: 0,
            planned_scene_shoots: 0,
            unapplied_outfits: plan.unapplied_outfits,
            applied_episodes: Vec::new(),
        };
        // Figures named by several draft rows are created once. This is a cache
        // of what *this* request resolved, not a projection read: everything that
        // crosses a request boundary goes through the mapping (CQRS boundary).
        let mut figures: HashMap<String, Figure> = HashMap::new();
        // Episodes a NEW group already resolved in *this* request (issue #581),
        // with the flag that says whether *this* apply created it. Same
        // rationale as `figures`: the mapping is the durable record, the map
        // only avoids re-driving it per row of the same group. The flag is what
        // decides whether the requested number/title may label the summary
        // entry (issue #763 review): on a reapply the mapping wins, so the
        // persisted episode keeps the values of the FIRST apply.
        let mut resolved_episodes: HashMap<String, (EpisodeId, bool)> = HashMap::new();
        // Shooting days an ACCEPTED group already resolved in *this* request
        // (issue #706). Same rationale as `resolved_episodes`: one day per
        // group, created on first sight, reused by every later row.
        let mut resolved_days: HashMap<String, AppliedDay> = HashMap::new();
        // Monotonic fallback planned-order counter for the scene-shoot links
        // (issue #706): script extraction carries no per-day order, so rows
        // apply in plan order. Every PLANNED row consumes one increment on
        // every attempt — including a row whose pair is already confirmed
        // (its early return runs after the increment) — so a partial-run
        // retry cannot reallocate a confirmed row's order to a later row
        // (CodeRabbit review). Deterministic across retries: the rows are
        // processed in the same plan order.
        let mut fallback_order: u32 = 0;

        for row in &plan.scenes {
            // `(episode, created by THIS apply)` — the flag decides whether the
            // requested number/title may label the summary entry (issue #763).
            let row_episode: (EpisodeId, bool) = match &row.episode {
                PlannedEpisode::Existing(episode_id) => (*episode_id, false),
                PlannedEpisode::New {
                    episode_ref,
                    number,
                    name,
                } => {
                    // `CreateEpisode` carries a denormalized series reference;
                    // the API edge always resolves it from the target episode.
                    // A missing series is an API-edge contract violation,
                    // surfaced as a validation failure instead of an episode
                    // without a series.
                    let Some(project_id) = project_id else {
                        return Err(DomainError::validation(
                            "apply cannot create an episode without a series context",
                        ));
                    };
                    let (episode_id, created_now) = match resolved_episodes.get(episode_ref) {
                        Some(resolved) => *resolved,
                        None => {
                            let (episode_id, created) = self
                                .create_episode_reserved(
                                    actor.clone(),
                                    ReservedEpisodeDraft {
                                        preview_id,
                                        episode_ref: episode_ref.clone(),
                                        block_id,
                                        project_id,
                                        number: *number,
                                        name: name.clone(),
                                    },
                                )
                                .await?;
                            if created {
                                result.created_episodes += 1;
                            }
                            resolved_episodes.insert(episode_ref.clone(), (episode_id, created));
                            (episode_id, created)
                        }
                    };
                    (episode_id, created_now)
                }
            };
            let (scene, row_state) = self
                .apply_scene_row(actor.clone(), preview_id, row_episode.0, project_id, row)
                .await?;
            result.applied.push(scene);
            // (issue #763) Count the row into the per-episode summary — but ONLY
            // when this call dispatched it. A row a confirmed mapping already
            // settled stays where that earlier attempt put it, so attributing it
            // to THIS request's episode would record an episode id that need not
            // hold the scene (CodeRabbit review): the retry's target is not the
            // scene's home, and neither its id nor its edge-resolved label may be
            // claimed. The persisted summary is merged, not replaced, so the
            // earlier apply's correct entry survives a retry.
            //
            // The plan's number/title may only label an entry when THIS apply
            // created the episode: on a reapply the mapping wins and the
            // persisted episode keeps the first apply's values, so the request's
            // `Create` target can disagree with it. Otherwise the edge-resolved
            // `known_episodes` identity labels the entry, and an unknown label
            // stays `None` (never a guess).
            if row_state == AppliedRowState::AppliedNow {
                let requested_label = match (&row.episode, row_episode.1) {
                    (PlannedEpisode::New { number, name, .. }, true) => {
                        Some((Some(*number), name.clone()))
                    }
                    _ => None,
                };
                record_applied_episode(
                    &mut result.applied_episodes,
                    row_episode.0,
                    requested_label,
                    &known_episodes,
                );
            }

            for character in &row.characters {
                if self
                    .resolve_figure(
                        actor.clone(),
                        preview_id,
                        season_id,
                        project_id,
                        character,
                        &mut figures,
                    )
                    .await?
                {
                    result.created_characters += 1;
                }
            }

            // ── Scene relation (issue #546 §5.8) ──
            // ScenePhases: the row's `scene` mapping row and its
            // `scene_costume_beat` rows hold versions of the SAME stream (the
            // scene aggregate). Recover the stream version as the MAX across
            // all of them — a single row can lag the stream when a previous
            // apply crashed between a beat append and its confirm. Confirms
            // stay only-moves-forward, so no row can exceed the stream and
            // the max is exact at every quiet point.
            let lanes = scene_beat_lanes(row);
            let mut scene_version = scene.version;
            for lane in &lanes {
                for slot in &lane.beats {
                    let address = beat_address(row, slot.outfit);
                    let stored = self
                        .mappings
                        .find(
                            // ast-grep-ignore: cqrs-boundary
                            preview_id,
                            &address.draft_ref,
                            address.kind,
                            ordinal_of(address.ordinal)?,
                        )
                        .await?;
                    if let Some(stored) = stored {
                        scene_version = scene_version.max(stored.aggregate_version);
                    }
                }
            }

            // One `AssignCharacter` per figure of the row, BEFORE any beat:
            // a beat may only exist for a figure in `assigned_characters`
            // (the handler answers 422 `scene.character-not-in-scene`
            // otherwise).
            for lane in &lanes {
                let Some(Figure::Resolved(resolved)) =
                    figures.get(&character_mapping_ref(&lane.character.identity))
                else {
                    // Unavailable figures are reported per costume below.
                    continue;
                };
                scene_version = self
                    .assign_figure_to_scene(
                        actor.clone(),
                        project_id,
                        scene.aggregate_id,
                        resolved.aggregate_id,
                        scene_version,
                    )
                    .await?;
            }

            for lane in &lanes {
                let lane_ref = character_mapping_ref(&lane.character.identity);
                let character_id = match figures.get(&lane_ref) {
                    Some(Figure::Resolved(resolved)) => resolved.aggregate_id,
                    Some(Figure::Unavailable(detail)) => {
                        for slot in &lane.beats {
                            result.unapplied_outfits.push(unapplied(
                                row,
                                slot.outfit,
                                UnappliedOutfitReason::CharacterUnavailable,
                                Some(detail.clone()),
                            ));
                        }
                        continue;
                    }
                    None => {
                        // Unreachable through the planner, which only pairs an
                        // outfit with a figure of the same row; reported rather
                        // than assumed, because an ownerless look is exactly
                        // what must never be created.
                        for slot in &lane.beats {
                            result.unapplied_outfits.push(unapplied(
                                row,
                                slot.outfit,
                                UnappliedOutfitReason::CharacterNotPlanned,
                                None,
                            ));
                        }
                        continue;
                    }
                };
                for slot in &lane.beats {
                    let outfit = slot.outfit;
                    // Continuation (OpenSpec `ai-import-decision-outfit-continuity`,
                    // design D3): a continued look creates NOTHING. The source
                    // scene already owns the `Outfit`; this row contributes only
                    // the beat, so the reference is by identity and no second
                    // aggregate (nor a duplicate piece set) can appear.
                    if let Some(continuation) = outfit.continuation.as_ref() {
                        let resolved = self
                            .resolve_continued_outfit(preview_id, continuation)
                            .await?;
                        let Some(outfit_id) = resolved else {
                            tracing::warn!(
                                draft_ref = %row.draft_ref,
                                outfit_ordinal = outfit.ordinal,
                                source_draft_ref = %continuation.source_draft_ref,
                                "AI apply could not resolve the source outfit of a continuation"
                            );
                            result.unapplied_outfits.push(unapplied(
                                row,
                                outfit,
                                UnappliedOutfitReason::ContinuityUnresolved,
                                Some(format!(
                                    "source outfit of row {} was not created by this apply",
                                    continuation.source_draft_ref
                                )),
                            ));
                            continue;
                        };
                        match self
                            .apply_outfit_beat(BeatDispatch {
                                actor: actor.clone(),
                                preview_id,
                                project_id,
                                scene_id: scene.aggregate_id,
                                character_id,
                                beat: beat_address(row, outfit),
                                outfit_id,
                                scene_version: &mut scene_version,
                            })
                            .await?
                        {
                            BeatAttempt::Appended => result.created_outfit_beats += 1,
                            BeatAttempt::Settled => {}
                            BeatAttempt::Refused(error) => {
                                tracing::warn!(
                                    draft_ref = %row.draft_ref,
                                    outfit_ordinal = outfit.ordinal,
                                    error = %error,
                                    "AI apply could not add one continued outfit beat"
                                );
                                result.unapplied_outfits.push(unapplied(
                                    row,
                                    outfit,
                                    UnappliedOutfitReason::BeatRejected,
                                    Some(error.to_string()),
                                ));
                            }
                        }
                        continue;
                    }
                    // Step 1 — the outfit's constituent pieces in the season
                    // fundus. They must exist before the outfit can reference
                    // them, so a refused piece stops the look here.
                    let pieces = match self
                        .apply_outfit_pieces(
                            actor.clone(),
                            OutfitPieceDispatch {
                                preview_id,
                                season_id,
                                project_id,
                                row,
                                outfit,
                            },
                        )
                        .await?
                    {
                        ChainStep::Done(pieces) => pieces,
                        ChainStep::Refused(reason, detail) => {
                            tracing::warn!(
                                draft_ref = %row.draft_ref,
                                outfit_ordinal = outfit.ordinal,
                                reason = ?reason,
                                error = %detail,
                                "AI apply could not create the pieces of one outfit"
                            );
                            result.unapplied_outfits.push(unapplied(
                                row,
                                outfit,
                                reason,
                                Some(detail),
                            ));
                            continue;
                        }
                    };
                    result.created_pieces += pieces.created;
                    // Step 2 — the look itself, referencing those pieces.
                    let applied = match self
                        .apply_outfit(
                            actor.clone(),
                            OutfitDispatch {
                                preview_id,
                                season_id,
                                project_id,
                                row,
                                outfit,
                                character_id,
                                piece_ids: pieces.piece_ids,
                            },
                        )
                        .await?
                    {
                        ChainStep::Done(applied) => applied,
                        ChainStep::Refused(reason, detail) => {
                            tracing::warn!(
                                draft_ref = %row.draft_ref,
                                outfit_ordinal = outfit.ordinal,
                                reason = ?reason,
                                error = %detail,
                                "AI apply could not finish one outfit row"
                            );
                            result.unapplied_outfits.push(unapplied(
                                row,
                                outfit,
                                reason,
                                Some(detail),
                            ));
                            continue;
                        }
                    };
                    if applied.created {
                        result.created_outfits += 1;
                    }
                    // Step 3 — the outfit chain fully succeeded: persist the
                    // scene relation as its beat (issue #546 §5.8).
                    match self
                        .apply_outfit_beat(BeatDispatch {
                            actor: actor.clone(),
                            preview_id,
                            project_id,
                            scene_id: scene.aggregate_id,
                            character_id,
                            beat: beat_address(row, outfit),
                            outfit_id: applied.outfit_id,
                            scene_version: &mut scene_version,
                        })
                        .await?
                    {
                        BeatAttempt::Appended => result.created_outfit_beats += 1,
                        BeatAttempt::Settled => {}
                        BeatAttempt::Refused(error) => {
                            tracing::warn!(
                                draft_ref = %row.draft_ref,
                                outfit_ordinal = outfit.ordinal,
                                error = %error,
                                "AI apply could not add one outfit beat"
                            );
                            result.unapplied_outfits.push(unapplied(
                                row,
                                outfit,
                                UnappliedOutfitReason::BeatRejected,
                                Some(error.to_string()),
                            ));
                        }
                    }
                }
            }

            // ── Shooting-day assignment (issue #706) ──
            // After the beats: `scene_version` now holds the row's current
            // scene-stream version (max across the row's mapping rows, advanced
            // in place by every dispatch above), so the link dispatches at the
            // reached version. A `None` row — no day metadata, ungroupable
            // label, or a group the reviewer rejected — stays unscheduled.
            if let PlannedShootingDay::Group {
                day_ref,
                label,
                score,
            } = &row.shooting_day
            {
                // Episode-scoped day key (CodeRabbit review, issue #706): a
                // day number is NOT episode-unique — a multi-episode script
                // repeats `Tag 1` per episode, so the same `day_ref` must
                // resolve to one day PER EPISODE. Keying by the row's
                // resolved episode keeps episode 2's scenes off episode 1's
                // day (and keeps the mapping draft_ref, which the id is
                // derived from, retry-stable).
                let day_key = format!("{}:{day_ref}", row_episode.0.0);
                let day = match resolved_days.get(&day_key) {
                    Some(day) => *day,
                    None => {
                        let day = self
                            .day_linker()
                            .resolve_day(
                                actor.clone(),
                                DayDraft {
                                    preview_id,
                                    draft_ref: day_key.clone(),
                                    episode_id: row_episode.0,
                                    label: label.clone(),
                                    date: None,
                                    project_id,
                                    // Issue #722: the accepted group's
                                    // hybrid day score becomes the created
                                    // day's `ShootingDaySource::AiExtracted
                                    // .confidence`; `None` stays honest.
                                    confidence: *score,
                                },
                            )
                            .await?;
                        if day.created {
                            result.created_days += 1;
                        }
                        resolved_days.insert(day_key, day);
                        day
                    }
                };
                let scheduled = self
                    .schedule_row_on_day(
                        actor.clone(),
                        RowDayLink {
                            preview_id,
                            project_id,
                            scene_id: scene.aggregate_id,
                            day: day.id,
                            scene_version: &mut scene_version,
                            fallback_order: &mut fallback_order,
                        },
                    )
                    .await?;
                if scheduled {
                    result.planned_scene_shoots += 1;
                }
            }
        }
        if let Some(telemetry) = telemetry {
            self.queue.record_telemetry(preview_id, telemetry).await?;
        }
        Ok(result)
    }

    /// Fill in the decisions the reviewer did not send because their rows are
    /// already applied.
    ///
    /// A retried apply legitimately carries no decisions at all: every row it
    /// completed is resolved by its confirmed mapping, which the dispatch below
    /// short-circuits on. The planner still needs a decision per row to plan that
    /// row's figures and costumes — the ones a first attempt may have crashed
    /// before reaching — so each already-mapped row gets a decision pointing at
    /// its own aggregate. It is never dispatched (a confirmed scene mapping is a
    /// no-op), and its costume rows default to accepted, which is the documented
    /// default for a row the reviewer did not touch.
    async fn resolved_decisions(
        &self,
        preview_id: AiImportJobId,
        preview: &ScriptContext,
        decisions: &[ApplyMapping],
    ) -> Result<Vec<ApplyMapping>, DomainError> {
        // Read the idempotency projection (non-audit): this is what lets a
        // retried apply skip the rows it already finished. Derived audit context
        // (`project_id`, `season_id`) comes from the API-edge request, never here.
        let confirmed: HashMap<String, AiImportMapping> = self
            .mappings
            .list_by_preview(preview_id) // ast-grep-ignore: cqrs-boundary
            .await?
            .into_iter()
            .filter(|mapping| {
                !mapping.is_reserved() && mapping.aggregate_kind == mapping_kind::SCENE
            })
            .map(|mapping| (mapping.draft_ref.clone(), mapping))
            .collect();
        let mut resolved: Vec<ApplyMapping> = decisions.to_vec();
        for (index, draft) in preview.scenes.iter().enumerate() {
            let reference = draft_row_ref(draft, index);
            if resolved
                .iter()
                .any(|decision| decision.draft_ref == reference)
            {
                continue;
            }
            if let Some(mapping) = confirmed.get(&reference) {
                resolved.push(ApplyMapping {
                    draft_ref: reference,
                    decision: ApplyMappingDecision::Update {
                        aggregate_id: mapping.aggregate_id,
                        version: mapping.aggregate_version,
                    },
                    outfit_decisions: Vec::new(),
                });
            }
        }
        Ok(resolved)
    }

    /// Apply one draft row's scene, returning the aggregate it now points at.
    ///
    /// A confirmed mapping is a no-op: the row's figures and costumes are still
    /// driven below, so a crash between the scene create and a costume create is
    /// finished by the retry instead of losing the costume.
    async fn apply_scene_row(
        &self,
        actor: UserId,
        preview_id: AiImportJobId,
        episode_id: EpisodeId,
        project_id: Option<ProjectId>,
        row: &SceneApplyPlan,
    ) -> Result<(UuidVersion, AppliedRowState), DomainError> {
        let draft_ref = row.draft_ref.clone();
        let stored = self
            .mappings
            .find(preview_id, &draft_ref, mapping_kind::SCENE, PRIMARY_ORDINAL) // ast-grep-ignore: cqrs-boundary
            .await?;
        // A confirmed mapping means this row already applied: a retry — or a
        // concurrent duplicate that confirmed first — is a no-op returning the
        // stored id/version instead of re-dispatching (issue #338).
        // Re-dispatching an `Update` here would also fail in production:
        // identical details are rejected as unchanged.
        if let Some(confirmed) = stored.as_ref().filter(|mapping| !mapping.is_reserved()) {
            return Ok((
                UuidVersion {
                    aggregate_id: confirmed.aggregate_id,
                    version: confirmed.aggregate_version,
                },
                // The row sits where an EARLIER attempt put it — this request's
                // episode target need not be that place (issue #763).
                AppliedRowState::AlreadyApplied,
            ));
        }
        // A reservation means a previous attempt already claimed an aggregate id
        // for this draft. The reservation wins over the client-supplied decision:
        // the reserved stream may already hold our append (crash after create,
        // before confirm), so switching targets would orphan it. Reusing the
        // reserved id also converges concurrent duplicates onto one stream, whose
        // `ExpectedVersion::Empty` guard turns the loser into a `recover_version`
        // success — mirroring the schedule apply path.
        let details = planned_details(&row.scene);
        let reserved_id = stored
            .filter(|mapping| mapping.is_reserved())
            .map(|mapping| mapping.aggregate_id);
        let mut appended = true;
        let (aggregate_id, version) = if let Some(candidate_id) = reserved_id {
            let (id, version, appended_now) = self
                .create_scene_reserved(
                    actor,
                    ReservedSceneDraft {
                        preview_id,
                        draft_ref,
                        candidate_id,
                        episode_id,
                        project_id,
                        details,
                    },
                )
                .await?;
            appended = appended_now;
            (id, version)
        } else {
            match &row.scene {
                SceneApplyCommand::Create(_) => {
                    let (id, version, appended_now) = self
                        .create_scene_reserved(
                            actor,
                            ReservedSceneDraft {
                                preview_id,
                                draft_ref: draft_ref.clone(),
                                // Derived, never the planner's fresh id: an apply id
                                // must be re-derivable after a crash so the
                                // aggregate's `ExpectedVersion::Empty` guard rejects
                                // the duplicate instead of creating a second scene
                                // (issue #182). The planner's id is not used.
                                candidate_id: derive_id(
                                    preview_id,
                                    &draft_ref,
                                    mapping_kind::SCENE,
                                    PRIMARY_ORDINAL,
                                ),
                                episode_id,
                                project_id,
                                details,
                            },
                        )
                        .await?;
                    appended = appended_now;
                    (id, version)
                }
                SceneApplyCommand::Update(command) => {
                    let command = command.clone();
                    let new_version = self
                        .scene_commands
                        .update_details(actor, command.clone())
                        .await?;
                    self.mappings
                        .insert(AiImportMapping {
                            preview_id,
                            draft_ref,
                            aggregate_kind: mapping_kind::SCENE.to_owned(),
                            ordinal: PRIMARY_ORDINAL,
                            aggregate_id: command.id,
                            aggregate_version: new_version,
                        })
                        .await?;
                    (command.id, new_version)
                }
            }
        };
        Ok((
            UuidVersion {
                aggregate_id,
                version,
            },
            if appended {
                AppliedRowState::AppliedNow
            } else {
                // The reserved stream already held our append: another attempt
                // (a crash retry, or the winner of a concurrent duplicate race)
                // created this scene, and it may live in a different episode than
                // this request names. Count nothing.
                AppliedRowState::AlreadyApplied
            },
        ))
    }

    /// Resolve the figure one draft row names to an aggregate id, creating it on
    /// first sight. Returns whether this call appended a `CharacterCreated`.
    ///
    /// The lookup key is the figure's *identity* rather than the draft row that
    /// mentioned it, so the same name across a whole preview becomes one
    /// Character — which is what makes its costumes continuous across scenes.
    async fn resolve_figure(
        &self,
        actor: UserId,
        preview_id: AiImportJobId,
        season_id: SeasonId,
        project_id: Option<ProjectId>,
        character: &CharacterApplyPlan,
        figures: &mut HashMap<String, Figure>,
    ) -> Result<bool, DomainError> {
        let key = character_mapping_ref(&character.identity);
        if figures.contains_key(&key) {
            return Ok(false);
        }
        let stored = self
            .mappings
            .find(preview_id, &key, mapping_kind::CHARACTER, PRIMARY_ORDINAL) // ast-grep-ignore: cqrs-boundary
            .await?;
        if let Some(confirmed) = stored.as_ref().filter(|mapping| !mapping.is_reserved()) {
            figures.insert(
                key,
                Figure::Resolved(UuidVersion {
                    aggregate_id: confirmed.aggregate_id,
                    version: confirmed.aggregate_version,
                }),
            );
            return Ok(false);
        }
        let row = match stored {
            // A reservation from a crashed attempt: re-drive onto that id.
            Some(reserved) => reserved,
            None => {
                self.mappings
                    .reserve(AiImportMapping::reservation(
                        preview_id,
                        key.clone(),
                        mapping_kind::CHARACTER.to_owned(),
                        PRIMARY_ORDINAL,
                        derive_id(preview_id, &key, mapping_kind::CHARACTER, PRIMARY_ORDINAL),
                    ))
                    .await?
            }
        };
        let attempt = self
            .character_commands
            .create(
                actor,
                CreateCharacter {
                    id: row.aggregate_id,
                    season_id,
                    project_id,
                    // Verbatim: the script's own wording is the figure's name.
                    // `character_identity` is a matching key, never a value.
                    name: character.name.clone(),
                    // The extracted role type (issue #677): the
                    // classification the extraction read from the
                    // document's cast sections. The serde default keeps
                    // this MainCast when the document does not say
                    // otherwise — a grounded default, never an invented
                    // guess; the reviewer corrects it in the Cast screen
                    // (issue #678) when the classification was wrong.
                    category: character.category,
                },
            )
            .await;
        let outcome = match created_now(attempt) {
            Ok(outcome) => outcome,
            Err(error) => {
                if is_infra_outage(&error) {
                    return Err(error);
                }
                tracing::warn!(
                    name = %character.name,
                    error = %error,
                    "AI apply could not create a figure; its costumes are reported unapplied"
                );
                figures.insert(key, Figure::Unavailable(error.to_string()));
                return Ok(false);
            }
        };
        self.confirm(&row, outcome.version).await?;
        figures.insert(
            key,
            Figure::Resolved(UuidVersion {
                aggregate_id: row.aggregate_id,
                version: outcome.version,
            }),
        );
        Ok(outcome.appended)
    }

    /// Drive one outfit's constituent pieces into the season fundus:
    /// `CreatePiece` → optional `SetPieceCategory` → optional
    /// `UpdatePieceNotes`, confirming the mapping row after every step.
    ///
    /// Pieces are separate aggregates with their own streams, so each gets its
    /// own `piece` mapping row (addressed by the row's `draft_ref` and the
    /// ROW-FLAT piece position). `Err` is reserved for an unavailable
    /// dependency, which must fail the whole apply; a step the domain refused
    /// is reported as [`ChainStep::Refused`] so the other outfits still apply.
    async fn apply_outfit_pieces(
        &self,
        actor: UserId,
        dispatch: OutfitPieceDispatch<'_>,
    ) -> Result<ChainStep<PieceChainOutcome>, DomainError> {
        let OutfitPieceDispatch {
            preview_id,
            season_id,
            project_id,
            row,
            outfit,
        } = dispatch;
        let mut created = 0;
        let mut piece_ids = Vec::with_capacity(outfit.pieces.len());
        for piece in &outfit.pieces {
            match self
                .apply_piece(
                    actor.clone(),
                    PieceDispatch {
                        preview_id,
                        season_id,
                        project_id,
                        row,
                        piece,
                    },
                )
                .await?
            {
                ChainStep::Done((piece_id, appended)) => {
                    if appended {
                        created += 1;
                    }
                    piece_ids.push(piece_id);
                }
                ChainStep::Refused(reason, detail) => {
                    return Ok(ChainStep::Refused(reason, detail));
                }
            }
        }
        Ok(ChainStep::Done(PieceChainOutcome { created, piece_ids }))
    }

    /// Drive one `Piece` through its version chain
    /// (`CreatePiece` → optional `SetPieceCategory` → optional
    /// `UpdatePieceNotes`), confirming the mapping row after every step.
    ///
    /// Returns the piece id and whether this call created it.
    async fn apply_piece(
        &self,
        actor: UserId,
        dispatch: PieceDispatch<'_>,
    ) -> Result<ChainStep<(Uuid, bool)>, DomainError> {
        let PieceDispatch {
            preview_id,
            season_id,
            project_id,
            row,
            piece,
        } = dispatch;
        let ordinal = ordinal_of(piece.ordinal)?;
        let phases = PiecePhases {
            has_category: piece.category_id.is_some(),
        };
        let stored = self
            .mappings
            .find(preview_id, &row.draft_ref, mapping_kind::PIECE, ordinal) // ast-grep-ignore: cqrs-boundary
            .await?;
        let mapping = match stored {
            Some(row) => row,
            None => {
                self.mappings
                    .reserve(AiImportMapping::reservation(
                        preview_id,
                        row.draft_ref.clone(),
                        mapping_kind::PIECE.to_owned(),
                        ordinal,
                        derive_id(preview_id, &row.draft_ref, mapping_kind::PIECE, ordinal),
                    ))
                    .await?
            }
        };
        let id = mapping.aggregate_id;
        let mut version = mapping.aggregate_version;
        let mut created = false;

        if version < PiecePhases::CREATED {
            let attempt = PieceCommands::create(
                &*self.wardrobe_commands,
                actor.clone(),
                CreatePiece {
                    id,
                    name: piece_name(piece),
                    // The category is set in its own step so a crashed apply
                    // converges on the same stream: `CreatePiece` seeds the
                    // repertoire, `SetPieceCategory` classifies.
                    category_id: None,
                    season_id: Some(season_id),
                    project_id,
                },
            )
            .await;
            let outcome = match created_now(attempt) {
                Ok(outcome) => outcome,
                Err(error) if is_infra_outage(&error) => return Err(error),
                Err(error) => {
                    return Ok(ChainStep::Refused(
                        UnappliedOutfitReason::PieceRejected,
                        error.to_string(),
                    ));
                }
            };
            version = outcome.version;
            created = outcome.appended;
            self.confirm(&mapping, version).await?;
        }

        if let Some(category_id) = piece.category_id
            && version < PiecePhases::CATEGORIZED
        {
            let attempt = PieceCommands::set_category(
                &*self.wardrobe_commands,
                actor.clone(),
                SetPieceCategory {
                    id,
                    category_id: Some(category_id),
                    project_id,
                    version,
                },
            )
            .await;
            match attempt {
                Ok(next) => {
                    version = next;
                    self.confirm(&mapping, version).await?;
                }
                Err(error) if is_infra_outage(&error) => return Err(error),
                Err(error) => {
                    // A category is metadata, not the garment: the piece
                    // exists and the look can still be assembled, so the
                    // refusal is logged and the chain continues.
                    tracing::warn!(
                        piece = %id,
                        error = %error,
                        "AI apply could not set the category of a piece"
                    );
                    version = recover_version(Err(error)).unwrap_or(version);
                }
            }
        }

        if let Some(notes) = piece.notes.as_deref()
            && version < phases.notes_version()
        {
            let attempt = PieceCommands::update_notes(
                &*self.wardrobe_commands,
                actor.clone(),
                UpdatePieceNotes {
                    id,
                    notes: notes.to_owned(),
                    project_id,
                    version,
                },
            )
            .await;
            version = match recover_version(attempt) {
                Ok(version) => version,
                Err(error) if is_infra_outage(&error) => return Err(error),
                Err(error) => {
                    return Ok(ChainStep::Refused(
                        UnappliedOutfitReason::NotesRejected,
                        error.to_string(),
                    ));
                }
            };
            self.confirm(&mapping, version).await?;
        }

        Ok(ChainStep::Done((id, created)))
    }

    /// Drive one `Outfit` through `CreateOutfit` (with its pieces) plus optional
    /// `UpdateOutfitNotes`, confirming the mapping row after every step.
    ///
    /// The archived-season precondition (CR-002/D2, issue #533) is checked here
    /// because the domain refuses the create: resolving it as a dispatch
    /// precondition keeps the reviewer's report honest instead of surfacing it as
    /// an aggregate validation error.
    async fn apply_outfit(
        &self,
        actor: UserId,
        dispatch: OutfitDispatch<'_>,
    ) -> Result<ChainStep<OutfitChainOutcome>, DomainError> {
        let OutfitDispatch {
            preview_id,
            season_id,
            project_id,
            row,
            outfit,
            character_id,
            piece_ids,
        } = dispatch;
        let ordinal = ordinal_of(outfit.ordinal)?;
        // A selected gap row carries its own kind: its ordinal is the figure's
        // draft position, so sharing the extracted rows' namespace could collide.
        let kind = if outfit.from_continuity_selection {
            mapping_kind::OUTFIT_CONTINUITY
        } else {
            mapping_kind::OUTFIT
        };
        let stored = self
            .mappings
            .find(preview_id, &row.draft_ref, kind, ordinal) // ast-grep-ignore: cqrs-boundary
            .await?;
        let mapping = match stored {
            Some(row) => row,
            None => {
                self.mappings
                    .reserve(AiImportMapping::reservation(
                        preview_id,
                        row.draft_ref.clone(),
                        kind.to_owned(),
                        ordinal,
                        derive_id(preview_id, &row.draft_ref, kind, ordinal),
                    ))
                    .await?
            }
        };
        let id = mapping.aggregate_id;
        let mut version = mapping.aggregate_version;
        let mut created = false;
        // Whether the notes phase is still owed, judged from the mapping BEFORE
        // the recovery loop below can push the stream past `OUTFIT_NOTED` by
        // re-adding missing pieces. Reading the live `version` after the loop
        // would conclude "notes already written" and drop them silently.
        let notes_pending = version < OUTFIT_NOTED;

        if version < OUTFIT_CREATED {
            let season = self
                .season_repo
                .find_by_id(season_id.0) // ast-grep-ignore: cqrs-boundary
                .await;
            match season {
                Ok(season) if season.archived => {
                    tracing::info!(
                        season = %season_id.0,
                        "AI apply refused the outfit step: the target season is archived"
                    );
                    return Ok(ChainStep::Refused(
                        UnappliedOutfitReason::BindingRejected,
                        DomainError::conflict("target season is archived").to_string(),
                    ));
                }
                Ok(_) => {}
                Err(error) if is_infra_outage(&error) => return Err(error),
                Err(error) => {
                    tracing::warn!(
                        %error,
                        season = %season_id.0,
                        "AI apply could not resolve the target season; refusing the outfit step"
                    );
                    return Ok(ChainStep::Refused(
                        UnappliedOutfitReason::BindingRejected,
                        DomainError::conflict("target season could not be resolved").to_string(),
                    ));
                }
            }
            let attempt = OutfitCommands::create(
                &*self.wardrobe_commands,
                actor.clone(),
                CreateOutfit {
                    id,
                    character_id,
                    name: outfit_name(outfit),
                    piece_ids: piece_ids.clone(),
                    project_id,
                },
            )
            .await;
            match attempt {
                Ok((_, next)) => {
                    version = next;
                    created = true;
                }
                // A crash between the create and its confirm — or a retry that
                // lost its mapping write — lands here: the stream exists, so
                // re-add any piece it is missing instead of creating it again.
                Err(DomainError::VersionConflict { current, .. })
                    if current != AggregateVersion(0) =>
                {
                    tracing::info!(
                        current = current.0,
                        "recovered an AI apply outfit from its own reserved stream"
                    );
                    // Each successful `AddPieceToOutfit` appends an event and
                    // advances the stream, so the NEXT call must use the version
                    // the previous one reached — dispatching them all at
                    // `current` made every call after the first a version
                    // conflict that was logged and swallowed: those pieces were
                    // never added, and the mapping then confirmed a stale version
                    // that also lost the notes below.
                    let mut reached = current;
                    for piece_id in &piece_ids {
                        let added = OutfitCommands::add_piece(
                            &*self.wardrobe_commands,
                            actor.clone(),
                            AddPieceToOutfit {
                                id,
                                piece_id: *piece_id,
                                project_id,
                                version: reached,
                            },
                        )
                        .await;
                        match recover_version(added) {
                            // An already-contained piece is a state-based no-op
                            // at the aggregate (`Ok(vec![])`), so it also lands
                            // here; `max` keeps the reached version exact.
                            Ok(next) => reached = reached.max(next),
                            Err(error) if is_infra_outage(&error) => return Err(error),
                            // A genuine refusal is reported, never silent.
                            Err(error) => {
                                tracing::warn!(
                                    outfit = %id,
                                    error = %error,
                                    "AI apply could not add a recovered piece to the outfit"
                                );
                            }
                        }
                    }
                    version = reached;
                }
                Err(error) if is_infra_outage(&error) => return Err(error),
                Err(error) => {
                    return Ok(ChainStep::Refused(
                        UnappliedOutfitReason::CreateRejected,
                        error.to_string(),
                    ));
                }
            }
            self.confirm(&mapping, version).await?;
        }

        if let Some(notes) = outfit.notes.as_deref()
            && notes_pending
        {
            let attempt = OutfitCommands::update_notes(
                &*self.wardrobe_commands,
                actor.clone(),
                UpdateOutfitNotes {
                    id,
                    notes: notes.to_owned(),
                    project_id,
                    version,
                },
            )
            .await;
            version = match recover_version(attempt) {
                Ok(version) => version,
                Err(error) if is_infra_outage(&error) => return Err(error),
                Err(error) => {
                    return Ok(ChainStep::Refused(
                        UnappliedOutfitReason::NotesRejected,
                        error.to_string(),
                    ));
                }
            };
            self.confirm(&mapping, version).await?;
        }

        Ok(ChainStep::Done(OutfitChainOutcome {
            created,
            outfit_id: id,
        }))
    }

    /// Assign one figure of the row to the row's scene (issue #546 §5.8),
    /// advancing the shared scene-stream version.
    ///
    /// Recovery, not failure: a `CharacterAlreadyAssigned` conflict means an
    /// earlier attempt — or an earlier row naming the same figure — assigned
    /// it already; the goal state holds and no event is appended. A stale
    /// expected version folds into the version the stream reached via
    /// [`recover_version`]: for a create-row the scene id came from this
    /// apply's reservation, so the conflict proves our own earlier append.
    /// For an update-row the fold may ride a concurrent manual edit; the beat
    /// dispatch below still verifies every command against the aggregate, so
    /// the fold can never invent a beat — it can only proceed at the stream's
    /// real version or be refused per costume as `BeatRejected`.
    async fn assign_figure_to_scene(
        &self,
        actor: UserId,
        project_id: Option<ProjectId>,
        scene_id: Uuid,
        character_id: Uuid,
        version: AggregateVersion,
    ) -> Result<AggregateVersion, DomainError> {
        let attempt = self
            .scene_commands
            .assign_character(
                actor,
                AssignCharacter {
                    id: scene_id,
                    character_id,
                    project_id,
                    version,
                },
            )
            .await;
        match recover_version(attempt) {
            Ok(reached) => Ok(reached),
            Err(DomainError::Conflict { code, .. })
                if *code == SCENE_CHARACTER_ALREADY_ASSIGNED =>
            {
                Ok(version)
            }
            Err(error) => Err(error),
        }
    }

    /// Add one costume beat for a fully applied costume (issue #546 §5.8),
    /// running the mapping-row phase protocol of [`CostumePhases`] against
    /// the SCENE stream.
    ///
    /// The `scene_outfit_beat` row is addressed by the figure's mapping
    /// reference plus the outfit's per-figure position and carries the
    /// SCENE aggregate id. **Shared-stream collision:** the row's `scene`
    /// mapping row and every `scene_costume_beat` row of the same draft hold
    /// versions of the same scene stream — never read one of them alone;
    /// recover the stream version as the max across all of the row's rows
    /// (`apply_script` does) and rely on confirms being only-moves-forward.
    async fn apply_outfit_beat(
        &self,
        dispatch: BeatDispatch<'_>,
    ) -> Result<BeatAttempt, DomainError> {
        let BeatDispatch {
            actor,
            preview_id,
            project_id,
            scene_id,
            character_id,
            beat,
            outfit_id,
            scene_version,
        } = dispatch;
        let ordinal = ordinal_of(beat.ordinal)?;
        // `BeatAddress` already carries the final mapping key, so the recovery
        // loop and this dispatch can never disagree on it.
        let lane_ref = beat.draft_ref.as_ref();
        let stored = self
            .mappings
            .find(preview_id, lane_ref, beat.kind, ordinal) // ast-grep-ignore: cqrs-boundary
            .await?;
        let mapping = match stored {
            Some(row) => row,
            None => {
                self.mappings
                    .reserve(AiImportMapping::reservation(
                        preview_id,
                        lane_ref.to_owned(),
                        beat.kind.to_owned(),
                        ordinal,
                        // The beat row pins the SCENE id — the aggregate it
                        // mutates — not a derived id: the scene already exists
                        // by the time a beat is dispatched.
                        scene_id,
                    ))
                    .await?
            }
        };
        // A confirmed row means the beat already exists: re-applying the
        // preview adds no second beat (idempotency over the mapping rows).
        if !mapping.is_reserved() {
            *scene_version = (*scene_version).max(mapping.aggregate_version);
            return Ok(BeatAttempt::Settled);
        }
        let beat = |version: AggregateVersion| {
            AddOutfitBeat {
                id: scene_id,
                character_id,
                outfit_id,
                // The extracted wording lives on the outfit's notes; a beat
                // note is a crew cue the extraction does not produce.
                note: None,
                project_id,
                version,
            }
        };
        let mut version = *scene_version;
        let attempt = self
            .scene_commands
            .add_outfit_beat(actor.clone(), beat(version))
            .await;
        match attempt {
            Ok(next) => {
                *scene_version = next;
                self.confirm(&mapping, next).await?;
                return Ok(BeatAttempt::Appended);
            }
            Err(DomainError::VersionConflict { current, .. }) if current != AggregateVersion(0) => {
                // A crash between the beat append and its confirm — or a
                // concurrent writer — moved the stream. Re-dispatch ONCE at
                // the reached version below; the aggregate's guards then
                // decide (identical-last settles, append lands, refusal
                // reports), so a foreign move can never settle an absent
                // beat silently.
                tracing::info!(
                    current = current.0,
                    "recovered an AI apply scene beat from a moved scene stream"
                );
                version = current;
            }
            // The identical-last guard is the only `scene.validation`
            // refusal `AddOutfitBeat` can produce (pinned in
            // `add_costume_beat_refuses_identical_last_as_the_only_validation_error`):
            // the beat already exists as the character's last beat at
            // exactly this version — settle the row, append nothing.
            Err(DomainError::Validation { code, .. }) if *code == SCENE_VALIDATION => {
                *scene_version = (*scene_version).max(version);
                self.confirm(&mapping, version).await?;
                return Ok(BeatAttempt::Settled);
            }
            Err(error) if is_infra_outage(&error) => return Err(error),
            Err(error) => return Ok(BeatAttempt::Refused(error)),
        }
        let attempt = self
            .scene_commands
            .add_outfit_beat(actor, beat(version))
            .await;
        match attempt {
            Ok(next) => {
                *scene_version = next;
                self.confirm(&mapping, next).await?;
                Ok(BeatAttempt::Appended)
            }
            Err(DomainError::Validation { code, .. }) if *code == SCENE_VALIDATION => {
                *scene_version = (*scene_version).max(version);
                self.confirm(&mapping, version).await?;
                Ok(BeatAttempt::Settled)
            }
            Err(error) if is_infra_outage(&error) => Err(error),
            Err(error) => Ok(BeatAttempt::Refused(error)),
        }
    }

    /// Advance a mapping row to the version the aggregate just reached. The
    /// repository only moves forward, so a late duplicate can never roll a
    /// confirmed phase back onto a reservation.
    async fn confirm(
        &self,
        mapping: &AiImportMapping,
        version: AggregateVersion,
    ) -> Result<(), DomainError> {
        self.mappings
            .insert(AiImportMapping {
                preview_id: mapping.preview_id,
                draft_ref: mapping.draft_ref.clone(),
                aggregate_kind: mapping.aggregate_kind.clone(),
                ordinal: mapping.ordinal,
                aggregate_id: mapping.aggregate_id,
                aggregate_version: version,
            })
            .await
    }

    /// Reserve the aggregate id for `(preview_id, episode_ref, 'episode', 0)`
    /// and create the episode one draft episode group maps to (issue #581,
    /// mirroring [`Self::create_scene_reserved`]).
    ///
    /// The mapping row is keyed by the GROUP ref, not a draft row ref, so
    /// every row of the group converges on ONE episode. A reservation means a
    /// previous attempt already claimed the aggregate id: the reservation
    /// wins, the create is re-driven through `created_now` (our own earlier
    /// append), and the confirm finishes the interrupted attempt. Returns the
    /// episode id and whether THIS call appended the `EpisodeCreated` (not
    /// counted again on a retry).
    async fn create_episode_reserved(
        &self,
        actor: UserId,
        draft: ReservedEpisodeDraft,
    ) -> Result<(EpisodeId, bool), DomainError> {
        let ReservedEpisodeDraft {
            preview_id,
            episode_ref,
            block_id,
            project_id,
            number,
            name,
        } = draft;
        let stored = self
            .mappings
            .find(
                preview_id,
                &episode_ref,
                mapping_kind::EPISODE,
                PRIMARY_ORDINAL,
            )
            .await?;
        let candidate_id = match stored {
            Some(mapping) => mapping.aggregate_id,
            None => {
                // Derived, never generated fresh: the id must be re-derivable
                // after a crash so a retry converges on the same stream
                // (issue #182, mirroring the scene reservation).
                derive_id(
                    preview_id,
                    &episode_ref,
                    mapping_kind::EPISODE,
                    PRIMARY_ORDINAL,
                )
            }
        };
        let reservation = self
            .mappings
            .reserve(AiImportMapping::reservation(
                preview_id,
                episode_ref,
                mapping_kind::EPISODE.to_owned(),
                PRIMARY_ORDINAL,
                candidate_id,
            ))
            .await?;
        let id = reservation.aggregate_id;
        let outcome = created_now(
            self.episode_commands
                .create(
                    actor,
                    CreateEpisode {
                        id,
                        block_id,
                        project_id,
                        number,
                        name,
                    },
                )
                .await,
        )?;
        self.mappings
            .insert(AiImportMapping {
                preview_id: reservation.preview_id,
                draft_ref: reservation.draft_ref,
                aggregate_kind: reservation.aggregate_kind,
                ordinal: reservation.ordinal,
                aggregate_id: id,
                aggregate_version: outcome.version,
            })
            .await?;
        Ok((EpisodeId::from_uuid(id), outcome.appended))
    }

    /// Reserve `candidate_id` for `(preview_id, draft_ref, 'scene', 0)` *before*
    /// dispatching `CreateScene`, then confirm the mapping — mirroring the
    /// schedule apply path (issue #338).
    ///
    /// The reservation is insert-if-absent: concurrent duplicates (or a retry
    /// after a crashed confirm) converge on the winning row's id, and the
    /// command runs against that id. A `VersionConflict` on the reserved
    /// stream proves our own earlier append, so `recover_version` treats it
    /// as success instead of duplicating the scene.
    /// Create the scene under its reserved id, reporting whether THIS call
    /// appended the `SceneCreated` event.
    ///
    /// `false` means the reserved stream already held our append — a crash
    /// retry, or a concurrent duplicate that won the `ExpectedVersion::Empty`
    /// race and was recovered through `created_now` (issue #763 review). The
    /// applied-episode summary must not count such a row again: the scene sits
    /// where the winning attempt put it, which is not necessarily this request's
    /// episode target.
    async fn create_scene_reserved(
        &self,
        actor: UserId,
        draft: ReservedSceneDraft,
    ) -> Result<(Uuid, AggregateVersion, bool), DomainError> {
        let ReservedSceneDraft {
            preview_id,
            draft_ref,
            candidate_id,
            episode_id,
            project_id,
            details,
        } = draft;
        let reservation = self
            .mappings
            .reserve(AiImportMapping::reservation(
                preview_id,
                draft_ref,
                mapping_kind::SCENE.to_owned(),
                PRIMARY_ORDINAL,
                candidate_id,
            ))
            .await?;
        let id = reservation.aggregate_id;
        let outcome = created_now(
            self.scene_commands
                .create(
                    actor,
                    CreateScene {
                        id,
                        episode_id,
                        project_id,
                        details,
                        // AI-provenance for the script import (issue #517):
                        // the document id is the import job id, the draft_ref
                        // the external_ref. Confidence is `None` — the preview
                        // pipeline carries no model confidence, so we record no
                        // invented value.
                        source: SceneSource::AiExtracted {
                            document_id: preview_id.as_uuid(),
                            external_ref: Some(reservation.draft_ref.clone()),
                            confidence: None,
                        },
                    },
                )
                .await,
        )?;
        let version = outcome.version;
        self.mappings
            .insert(AiImportMapping {
                preview_id: reservation.preview_id,
                draft_ref: reservation.draft_ref,
                aggregate_kind: reservation.aggregate_kind,
                ordinal: reservation.ordinal,
                aggregate_id: id,
                aggregate_version: version,
            })
            .await?;
        Ok((id, version, outcome.appended))
    }

    /// The schedule-apply machinery driving one row's day resolution and
    /// scene link (issue #706) — the same reservation protocol the schedule
    /// path runs, built from this worker's own ports.
    fn day_linker(&self) -> ScheduleApplyWorker<C, SD, SS, M> {
        ScheduleApplyWorker {
            scene_commands: Arc::clone(&self.scene_commands),
            shooting_day_commands: Arc::clone(&self.shooting_day_commands),
            scene_shoot_commands: Arc::clone(&self.scene_shoot_commands),
            mappings: Arc::clone(&self.mappings),
        }
    }

    /// Link one applied scene row to its accepted day group's shooting day
    /// (issue #706): dispatch `ScheduleSceneOnShootingDay` with the same
    /// recover-once pattern the costume beats run, then plan the `scene_shoot`
    /// pair through the schedule path's reservation protocol (reserve →
    /// command → confirm). Returns whether this call planned a pair.
    ///
    /// Only a *confirmed* pair mapping ends the work (mirrors the schedule
    /// path): a reservation means a previous attempt died between the command
    /// and the confirm, so the row must be re-driven onto the reserved id.
    async fn schedule_row_on_day(
        &self,
        actor: UserId,
        link: RowDayLink<'_>,
    ) -> Result<bool, DomainError> {
        let RowDayLink {
            preview_id,
            project_id,
            scene_id,
            day,
            scene_version,
            fallback_order,
        } = link;
        let day_linker = self.day_linker();
        let pair_key = format!("scene-shoot:{}:{}", scene_id, day.0);
        // Consume the fallback order BEFORE the confirmed-pair early return:
        // every planned row advances the counter on every attempt, so a
        // partial-run retry cannot reallocate a confirmed row's order to a
        // later row of the same day (CodeRabbit review, issue #706). The
        // allocation is computed before any command dispatch — it can fail
        // and must not leave the scene already scheduled.
        *fallback_order = fallback_order.checked_add(1).ok_or_else(|| {
            DomainError::validation("cannot allocate a unique fallback planned order")
        })?;
        let planned_order = LexicalSortKey::new(format!("{:08}", *fallback_order))
            .map_err(|error| DomainError::validation(error.to_string()))?;
        // Read the idempotency projection (non-audit): the spec requires the
        // mapping lookup so a retried apply re-drives an unfinished pair
        // instead of planning a second scene shoot. Not audit-context
        // resolution — project_id comes from the request. (Suppression
        // directive on the find line below.)
        if self
            .mappings
            .find(
                preview_id,
                &pair_key,
                mapping_kind::SCENE_SHOOT,
                PRIMARY_ORDINAL,
            ) // ast-grep-ignore: cqrs-boundary
            .await?
            .is_some_and(|mapping| !mapping.is_reserved())
        {
            return Ok(false);
        }

        // Step 1 (reserve): make the SceneShootId durable before the command
        // so a crash between append and confirm retries onto the same
        // aggregate. The id is derived deterministically from (preview_id,
        // pair_key) so a retry re-derives the SAME id (issue #182).
        let scene_shoot_id = SceneShootId::from_uuid(derive_id(
            preview_id,
            &pair_key,
            mapping_kind::SCENE_SHOOT,
            PRIMARY_ORDINAL,
        ));
        let reservation = self
            .mappings
            .reserve(AiImportMapping::reservation(
                preview_id,
                pair_key,
                mapping_kind::SCENE_SHOOT.to_owned(),
                PRIMARY_ORDINAL,
                scene_shoot_id.0,
            ))
            .await?;
        let scene_shoot_id = SceneShootId::from_uuid(reservation.aggregate_id);

        // Step 2a (scene link): state-idempotent; a stale version — a crash
        // between the link append and the pair confirm — recovers once at the
        // reached version (same pattern as the costume beats above).
        let mut version = *scene_version;
        version = match day_linker
            .schedule_scene(actor.clone(), scene_id, day, project_id, version)
            .await
        {
            Ok(next) => next,
            Err(DomainError::VersionConflict { current, .. }) if current != AggregateVersion(0) => {
                tracing::info!(
                    current = current.0,
                    "recovered an AI apply scene-day link from a moved scene stream"
                );
                current
            }
            Err(error) => return Err(error),
        };
        *scene_version = (*scene_version).max(version);

        // Step 2b (scene_shoot pair): dispatch onto the reserved stream — a
        // retry re-drives it, the adapter's ExpectedVersion::Empty then
        // reports the current version (recovery). The planned order was
        // allocated above, before the confirmed-pair early return.

        // Step 2c (command): a retry re-dispatches onto the reserved stream,
        // which already carries the SceneShootPlanned event — the adapter's
        // ExpectedVersion::Empty then reports the current version (recovery).
        let version = recover_version(
            self.scene_shoot_commands
                .plan(
                    actor,
                    PlanSceneShoot {
                        id: scene_shoot_id,
                        scene_id,
                        shooting_day_id: day,
                        project_id,
                        planned_order,
                    },
                )
                .await
                .map(|(_, version)| version),
        )?;

        // Step 3 (confirm).
        self.mappings
            .insert(AiImportMapping {
                preview_id: reservation.preview_id,
                draft_ref: reservation.draft_ref,
                aggregate_kind: reservation.aggregate_kind,
                ordinal: reservation.ordinal,
                aggregate_id: scene_shoot_id.0,
                aggregate_version: version,
            })
            .await?;
        Ok(true)
    }
}

/// Where one costume row's commands point. Bundled so `apply_costume` stays
/// under the `too_many_arguments` lint (an `#[allow]` would violate AGENTS.md §3,
/// cf. `ReservedSceneDraft`).
struct OutfitPieceDispatch<'a> {
    preview_id: AiImportJobId,
    /// Resolved by the API edge; the write side never looks a season up (CQRS
    /// boundary). A `Piece`'s repertoire is seeded from it.
    season_id: SeasonId,
    project_id: Option<ProjectId>,
    row: &'a SceneApplyPlan,
    outfit: &'a OutfitApplyPlan,
}

/// Where ONE piece's commands point. Bundled so `apply_piece` stays under the
/// `too_many_arguments` lint (an `#[allow]` would violate AGENTS.md §3).
struct PieceDispatch<'a> {
    preview_id: AiImportJobId,
    season_id: SeasonId,
    project_id: Option<ProjectId>,
    row: &'a SceneApplyPlan,
    piece: &'a PieceApplyPlan,
}

/// Where ONE outfit's commands point. Bundled for the same reason.
struct OutfitDispatch<'a> {
    preview_id: AiImportJobId,
    season_id: SeasonId,
    project_id: Option<ProjectId>,
    row: &'a SceneApplyPlan,
    outfit: &'a OutfitApplyPlan,
    /// The figure this row's outfit belongs to, created or resolved above.
    character_id: Uuid,
    /// The ids of the outfit's pieces, created in the step before.
    piece_ids: Vec<Uuid>,
}

/// The per-row day-link context of the script apply (issue #706). Bundled so
/// `ApplyWorker::schedule_row_on_day` stays under the `too_many_arguments`
/// lint (an `#[allow]` would violate AGENTS.md §3, cf. `ReservedSceneDraft`).
struct RowDayLink<'a> {
    preview_id: AiImportJobId,
    project_id: Option<ProjectId>,
    scene_id: Uuid,
    day: ShootingDayId,
    /// The row's running scene-stream version, advanced in place.
    scene_version: &'a mut AggregateVersion,
    /// Monotonic fallback planned-order counter, advanced in place.
    fallback_order: &'a mut u32,
}

/// A costume row that did not become a `Costume`, shaped for the reviewer.
fn unapplied(
    row: &SceneApplyPlan,
    outfit: &OutfitApplyPlan,
    reason: UnappliedOutfitReason,
    detail: Option<String>,
) -> UnappliedOutfit {
    UnappliedOutfit {
        draft_ref: row.draft_ref.clone(),
        ordinal: outfit.ordinal,
        character_name: outfit.character_name.clone(),
        name: outfit.name.clone(),
        reason,
        detail,
    }
}

pub fn validate_chunk_count(chunk_count: usize, max_chunks: u32) -> Result<(), DomainError> {
    if chunk_count > max_chunks as usize {
        return Err(DomainError::validation(format!(
            "script contains {chunk_count} chunks, exceeding max_chunks_per_script {max_chunks}"
        )));
    }
    Ok(())
}

/// Retry a transient LLM provider failure at most `max_retries` times with
/// backoff, then return the last error. The shared saga retry helper loops
/// forever on transient errors; a provider outage must not retry without bound
/// (unbounded cost, and the concurrency permit is held for the whole outage).
async fn retry_bounded<F, Fut, T>(mut op: F, max_retries: usize) -> Result<T, AnyhowError>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T, AnyhowError>>,
{
    let mut attempt: usize = 0;
    loop {
        match op().await {
            Ok(value) => return Ok(value),
            Err(error) if is_transient(&error) && attempt < max_retries => {
                attempt += 1;
                tokio::time::sleep(supervisor::compute_backoff(
                    attempt,
                    std::time::Duration::from_secs(30),
                ))
                .await;
            }
            Err(error) => return Err(error),
        }
    }
}

async fn retry_chat<C>(
    client: &C,
    request: LlmChatRequest,
    max_retries: usize,
) -> Result<(ScriptContext, LlmCallUsage), DomainError>
where
    C: LlmClient + ?Sized,
{
    let outcome = retry_bounded(
        || async {
            client
                .chat_constrained(request.clone())
                .await
                .map_err(AnyhowError::new)
        },
        max_retries,
    )
    .await;
    match outcome {
        Ok(value) => Ok((value.output, value.usage)),
        Err(error) => match error.downcast::<DomainError>() {
            Ok(domain_error) => Err(domain_error),
            Err(other) => Err(DomainError::validation(other.to_string())),
        },
    }
}

async fn retry_schedule<C>(
    client: &C,
    request: LlmChatRequest,
    max_retries: usize,
) -> Result<(ShootingSchedule, LlmCallUsage), DomainError>
where
    C: LlmClient + ?Sized,
{
    let outcome = retry_bounded(
        || async {
            client
                .extract_schedule(request.clone())
                .await
                .map_err(AnyhowError::new)
        },
        max_retries,
    )
    .await;
    match outcome {
        Ok(value) => Ok((value.output, value.usage)),
        Err(error) => match error.downcast::<DomainError>() {
            Ok(domain_error) => Err(domain_error),
            Err(other) => Err(DomainError::validation(other.to_string())),
        },
    }
}
