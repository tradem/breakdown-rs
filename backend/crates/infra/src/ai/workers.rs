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
    AiImportProgress, AiImportQueue, AiImportStage, AiModelPricingRepository, ApplyGateError,
    ApplyMapping, ApplyMappingDecision, CharacterApplyPlan, CostBreakdown, CostumeApplyPlan,
    DecisionClient, DocumentKind, EpisodeGroupPlan, LlmCallUsage, LlmChatRequest, LlmClient,
    MergedPreview, PRIMARY_ORDINAL, PlannedEpisode, PlannedShootingDay, ReviewerDecisions,
    SceneApplyCommand, SceneApplyPlan, ScriptContext, ShootingDayPlan, ShootingSchedule,
    SourceFormat, Telemetry, TelemetryApplyState, UnappliedCostume, UnappliedCostumeReason,
    Uncertainty, UncertaintyAcknowledgement, UncertaintyKind, category_conflict_uncertainties,
    character_mapping_ref, draft_row_ref, ensure_merge_applyable, extract_scenes, mapping_kind,
    merge_schedule_to_scenes, parse_script_day, plan_scene_apply, sanitize_meta_summary,
    scene_beat_lanes, stable_draft_ref, verify_draft_costumes,
};
use breakdown_core::character::commands::CreateCharacter;
use breakdown_core::character::ports::CharacterCommands;
use breakdown_core::episode::commands::CreateEpisode;
use breakdown_core::episode::ports::EpisodeCommands;
use breakdown_core::error::DomainError;
use breakdown_core::error_registry::{
    AI_IMPORT_APPLY_MISSING_EPISODE_GROUP, AI_IMPORT_APPLY_MISSING_MAPPING,
    AI_IMPORT_APPLY_MISSING_SHOOTING_DAY_GROUP,
};
use breakdown_core::error_registry::{SCENE_CHARACTER_ALREADY_ASSIGNED, SCENE_VALIDATION};
use breakdown_core::outfit::commands::{AddPieceToOutfit, CreateOutfit};
use breakdown_core::outfit::ports::OutfitCommands;
use breakdown_core::piece::commands::{CreatePiece, UpdatePieceNotes};
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
    pub decision: Option<Arc<DecisionPass>>,
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
                        // prompt forbids inventing a costume, but a prompt is an
                        // instruction, not a guarantee. Everything the check drops
                        // is recorded as a non-blocking `DroppedRow` uncertainty,
                        // so a hallucinated costume cannot reach the reviewer and
                        // a missing one is still visible as missing — without
                        // making the whole preview unappliable (design D9).
                        // Issue #722: count the drops of THIS scene — a
                        // grounding penalty input for the scene score.
                        let mut scene_dropped = 0usize;
                        for rejected in verify_draft_costumes(&mut scene, &source_text) {
                            scene_dropped += 1;
                            context.uncertainties.push(Uncertainty {
                                // 0-based index of the row pushed just below.
                                // `scene_ordinal` is a 1-based GLOBAL counter, so
                                // using it here attached every drop to the NEXT
                                // preview row — and pointed past the end of the
                                // list for the last scene, so the reviewer would
                                // see the missing costume on the wrong scene.
                                scene_index: context.scenes.len(),
                                field: "costumes".to_owned(),
                                note: format!(
                                    "{}: costume of {:?} ({:?}) was dropped; row {}",
                                    rejected.reason,
                                    rejected.character_name,
                                    rejected.description,
                                    scene.draft_ref,
                                ),
                                suggested_value: Some(rejected.description),
                                kind: UncertaintyKind::DroppedRow,
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
                    if let Some(decision) = self.decision.as_ref() {
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
                        super::decision_scoring::score_script_chunk(
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
    /// See [`ScriptImportWorker::decision`] (issue #722).
    pub decision: Option<Arc<DecisionPass>>,
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
        if let Some(decision) = self.decision.as_ref()
            && !native_csv
        {
            super::decision_scoring::score_schedule_rows(
                decision,
                &mut schedule.rows,
                &mut total_usage,
            )
            .await;
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
    pub costume_commands: Arc<CO>,
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
    pub created_costumes: u32,
    /// Costume beats this apply appended to the row scenes' streams (issue
    /// #546 §5.8). A settled beat (already present from an earlier apply) is
    /// not counted again. Infra-internal reporting: the wire response carries
    /// the per-costume refusals (`unapplied_costumes`), from which the applied
    /// beats are exactly the accepted costumes absent from that list.
    pub created_costume_beats: u32,
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
    /// Costumes that did not become a `Costume`, each with its reason. Reported,
    /// never dropped: a silently missing costume is the failure mode this change
    /// exists to remove (design D5).
    pub unapplied_costumes: Vec<UnappliedCostume>,
}

/// A figure as far as this apply is concerned.
#[derive(Debug, Clone)]
enum Figure {
    Resolved(UuidVersion),
    /// `CreateCharacter` was refused; the detail is what the reviewer sees
    /// alongside the costumes that could therefore not be bound.
    Unavailable(String),
}

/// What one costume row produced — including when it stopped half way.
///
/// A row can create the costume and then fail to bind it. Collapsing that into a
/// plain error would report a `Costume` that exists as never having been
/// created, which is exactly the silent-divergence class this change removes.
struct CostumeAttempt {
    /// This call appended a `CostumeCreated`.
    created: bool,
    /// The costume's aggregate id — the beat step binds it into the row's
    /// scene stream (issue #546 §5.8).
    costume_id: Uuid,
    /// `Some` when the row did not reach a bound costume, with the reason the
    /// reviewer sees.
    failure: Option<(UnappliedCostumeReason, String)>,
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

/// The version chain one AI costume leaves behind.
///
/// `projection_ai_import_mapping` stores the aggregate version after every step,
/// which makes the **version the phase record** of a crashed apply: a retry
/// re-drives only the steps above the stored version and can never append the
/// same event twice. The arithmetic is pinned by
/// `test_ai_apply_chain_advances_exactly_one_version_per_step`.
#[derive(Debug, Clone, Copy)]
struct CostumePhases {
    /// The extracted description carries the row's actual data, so it is written
    /// as the costume's notes (design D8) — but an empty description must not
    /// dispatch a command the aggregate would reject as "notes unchanged".
    has_notes: bool,
}

impl CostumePhases {
    /// Version reached after `UpdatePieceNotes` appended.
    const NOTED: AggregateVersion = AggregateVersion(2);
    /// `CreatePiece` appends exactly one event, landing on `INITIAL`.
    const CREATED: AggregateVersion = AggregateVersion::INITIAL;

    /// The piece stream is complete (created, optional notes written) once this
    /// version is reached; the outfit step is then driven on the OUTFIT stream,
    /// which is idempotent by deterministic id, so no version phase is needed
    /// for it.
    fn piece_complete(&self) -> AggregateVersion {
        if self.has_notes {
            Self::NOTED
        } else {
            AggregateVersion(1)
        }
    }
}

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

/// The fundus piece's name, derived from the extracted garment description.
///
/// The extraction gives free-form prose, not a label: the first clause is the
/// closest thing to a garment name the script offers. An empty description
/// falls back to a neutral generic name — the aggregate requires a non-blank
/// name, and the notes carry the full description anyway.
fn piece_name(costume: &CostumeApplyPlan) -> String {
    let first_line = costume
        .description
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .unwrap_or("");
    let clause = first_line
        .split(['.', ';', ','])
        .map(str::trim)
        .find(|part| !part.is_empty())
        .unwrap_or("");
    if clause.is_empty() {
        "Kleidungsstück".to_string()
    } else {
        clause.chars().take(120).collect()
    }
}

/// The look name for the figure's outfit: the figure the extraction named.
fn outfit_name(costume: &CostumeApplyPlan) -> String {
    let name = costume.character_name.trim();
    if name.is_empty() {
        "Outfit".to_string()
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
    /// Per-day decisions keyed by the preview's day-group refs (issue #706).
    /// An accepted group's rows are scheduled onto a NEW episode-scoped day;
    /// a rejected group's rows apply unscheduled.
    pub shooting_days: Vec<ShootingDayPlan>,
    /// Reviewer acknowledgements of blocking uncertainties (issue #663).
    /// Request-carried: the stored preview is immutable, so the resolution
    /// travels with the other reviewer decisions and the apply gate counts
    /// only unacknowledged blockers.
    pub acknowledged_uncertainties: Vec<UncertaintyAcknowledgement>,
    pub telemetry: Option<Telemetry>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UuidVersion {
    pub aggregate_id: uuid::Uuid,
    pub version: breakdown_core::shared::AggregateVersion,
}

/// Where one costume beat's command points. Bundled so `apply_costume_beat`
/// stays under the `too_many_arguments` lint (an `#[allow]` would violate
/// AGENTS.md §3, cf. `CostumeDispatch`).
struct BeatDispatch<'a> {
    actor: UserId,
    preview_id: AiImportJobId,
    project_id: Option<ProjectId>,
    /// The scene aggregate the beat mutates — the stream whose version the
    /// row's mapping rows jointly track.
    scene_id: Uuid,
    character_id: Uuid,
    costume: &'a CostumeApplyPlan,
    per_figure_order: usize,
    costume_id: Uuid,
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
            shooting_days,
            acknowledged_uncertainties,
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
            other => DomainError::conflict(other.to_string()),
        })?;
        // Fully specified (no `..Default` spread) so a deleted field is a
        // compile error instead of a silent default (mutation hardening,
        // issue #585; same pattern as PR #358).
        let mut result = ScriptApplyResult {
            applied: Vec::with_capacity(plan.scenes.len()),
            created_characters: 0,
            created_costumes: 0,
            created_costume_beats: 0,
            created_episodes: 0,
            created_days: 0,
            planned_scene_shoots: 0,
            unapplied_costumes: plan.unapplied_costumes,
        };
        // Figures named by several draft rows are created once. This is a cache
        // of what *this* request resolved, not a projection read: everything that
        // crosses a request boundary goes through the mapping (CQRS boundary).
        let mut figures: HashMap<String, Figure> = HashMap::new();
        // Episodes a NEW group already resolved in *this* request (issue #581).
        // Same rationale as `figures`: the mapping is the durable record, the
        // map only avoids re-driving it per row of the same group.
        let mut resolved_episodes: HashMap<String, EpisodeId> = HashMap::new();
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
            let row_episode_id = match &row.episode {
                PlannedEpisode::Existing(episode_id) => *episode_id,
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
                    match resolved_episodes.get(episode_ref) {
                        Some(episode_id) => *episode_id,
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
                            resolved_episodes.insert(episode_ref.clone(), episode_id);
                            episode_id
                        }
                    }
                }
            };
            let scene = self
                .apply_scene_row(actor.clone(), preview_id, row_episode_id, project_id, row)
                .await?;
            result.applied.push(scene);

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
                let lane_ref = character_mapping_ref(&lane.character.identity);
                for slot in &lane.beats {
                    let stored = self
                        .mappings
                        .find(
                            preview_id,
                            &lane_ref,
                            mapping_kind::SCENE_COSTUME_BEAT,
                            ordinal_of(slot.per_figure_order)?, // ast-grep-ignore: cqrs-boundary
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
                            result.unapplied_costumes.push(unapplied(
                                row,
                                slot.costume,
                                UnappliedCostumeReason::CharacterUnavailable,
                                Some(detail.clone()),
                            ));
                        }
                        continue;
                    }
                    None => {
                        // Unreachable through the planner, which only pairs a
                        // costume with a figure of the same row; reported rather
                        // than assumed, because an ownerless costume is exactly
                        // what must never be created.
                        for slot in &lane.beats {
                            result.unapplied_costumes.push(unapplied(
                                row,
                                slot.costume,
                                UnappliedCostumeReason::CharacterNotPlanned,
                                None,
                            ));
                        }
                        continue;
                    }
                };
                for slot in &lane.beats {
                    let costume = slot.costume;
                    let CostumeAttempt {
                        created,
                        costume_id,
                        failure,
                    } = self
                        .apply_costume(
                            actor.clone(),
                            CostumeDispatch {
                                preview_id,
                                season_id,
                                project_id,
                                row,
                                costume,
                                character_id,
                            },
                        )
                        .await?;
                    if created {
                        result.created_costumes += 1;
                    }
                    if let Some((reason, detail)) = failure {
                        tracing::warn!(
                            draft_ref = %row.draft_ref,
                            costume_ordinal = costume.ordinal,
                            reason = ?reason,
                            error = %detail,
                            "AI apply could not finish one costume row"
                        );
                        result.unapplied_costumes.push(unapplied(
                            row,
                            costume,
                            reason,
                            Some(detail),
                        ));
                        continue;
                    }
                    // The costume chain fully succeeded — persist the scene
                    // relation as its beat (issue #546 §5.8).
                    match self
                        .apply_costume_beat(BeatDispatch {
                            actor: actor.clone(),
                            preview_id,
                            project_id,
                            scene_id: scene.aggregate_id,
                            character_id,
                            costume,
                            per_figure_order: slot.per_figure_order,
                            costume_id,
                            scene_version: &mut scene_version,
                        })
                        .await?
                    {
                        BeatAttempt::Appended => result.created_costume_beats += 1,
                        BeatAttempt::Settled => {}
                        BeatAttempt::Refused(error) => {
                            tracing::warn!(
                                draft_ref = %row.draft_ref,
                                costume_ordinal = costume.ordinal,
                                error = %error,
                                "AI apply could not add one costume beat"
                            );
                            result.unapplied_costumes.push(unapplied(
                                row,
                                costume,
                                UnappliedCostumeReason::BeatRejected,
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
                let day_key = format!("{}:{day_ref}", row_episode_id.0);
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
                                    episode_id: row_episode_id,
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
                    costume_decisions: Vec::new(),
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
    ) -> Result<UuidVersion, DomainError> {
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
            return Ok(UuidVersion {
                aggregate_id: confirmed.aggregate_id,
                version: confirmed.aggregate_version,
            });
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
        let (aggregate_id, version) = if let Some(candidate_id) = reserved_id {
            self.create_scene_reserved(
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
            .await?
        } else {
            match &row.scene {
                SceneApplyCommand::Create(_) => {
                    self.create_scene_reserved(
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
                    .await?
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
        Ok(UuidVersion {
            aggregate_id,
            version,
        })
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

    /// Drive one costume through `CreateCostume` (unassigned, design D3) +
    /// `UpdateCostumeNotes` (the extracted description, design D8) +
    /// `AssignCostumeToCharacter`, confirming the mapping after every step.
    ///
    /// `Err` is reserved for an unavailable dependency, which must fail the whole
    /// apply; a row the domain refused is reported through
    /// [`CostumeAttempt::failure`] so the other rows still apply.
    async fn apply_costume(
        &self,
        actor: UserId,
        dispatch: CostumeDispatch<'_>,
    ) -> Result<CostumeAttempt, DomainError> {
        let CostumeDispatch {
            preview_id,
            season_id,
            project_id,
            row,
            costume,
            character_id,
        } = dispatch;
        let ordinal = ordinal_of(costume.ordinal)?;
        let phases = CostumePhases {
            has_notes: !costume.description.trim().is_empty(),
        };
        let stored = self
            .mappings
            .find(preview_id, &row.draft_ref, mapping_kind::COSTUME, ordinal) // ast-grep-ignore: cqrs-boundary
            .await?;
        let mapping = match stored {
            Some(row) => row,
            None => {
                self.mappings
                    .reserve(AiImportMapping::reservation(
                        preview_id,
                        row.draft_ref.clone(),
                        mapping_kind::COSTUME.to_owned(),
                        ordinal,
                        derive_id(preview_id, &row.draft_ref, mapping_kind::COSTUME, ordinal),
                    ))
                    .await?
            }
        };
        let id = mapping.aggregate_id;
        let mut version = mapping.aggregate_version;
        let mut created = false;
        // A step the domain refused ends this row, but never hides a creation
        // that already happened: `created` travels with the failure.
        macro_rules! refused {
            ($reason:expr, $error:expr) => {{
                return Ok(CostumeAttempt {
                    created,
                    costume_id: id,
                    failure: Some(($reason, $error.to_string())),
                });
            }};
        }

        // Step 1: create the **piece** in the fundus. A version below `INITIAL`
        // is the reservation sentinel, i.e. no step has appended yet. The piece
        // carries no character binding any more — the character is expressed by
        // the outfit created in step 3.
        if version < CostumePhases::CREATED {
            // The garment gets a name from the extraction: the description's
            // first clause is the closest thing to a label the script gives.
            let name = piece_name(costume);
            let attempt = PieceCommands::create(
                &*self.costume_commands,
                actor.clone(),
                CreatePiece {
                    id,
                    name,
                    category_id: None,
                    // The repertoire season the API edge resolved for this
                    // import; without it the piece would be invisible in
                    // every wardrobe list.
                    season_id: Some(season_id),
                    project_id,
                },
            )
            .await;
            let outcome = match created_now(attempt) {
                Ok(outcome) => outcome,
                Err(error) if is_infra_outage(&error) => return Err(error),
                Err(error) => refused!(UnappliedCostumeReason::CreateRejected, error),
            };
            version = outcome.version;
            created = outcome.appended;
            self.confirm(&mapping, version).await?;
        }

        // Step 2: the extracted description, so the garment the script named
        // survives the apply instead of dying in the reviewer's preview.
        if phases.has_notes && version < CostumePhases::NOTED {
            let notes = PieceCommands::update_notes(
                &*self.costume_commands,
                actor.clone(),
                UpdatePieceNotes {
                    id,
                    notes: costume.description.clone(),
                    project_id,
                    version,
                },
            )
            .await;
            // A crash between the notes append and its `confirm` leaves the
            // mapping at version 1 while the stream is already at 2. The retry
            // then re-dispatches `UpdatePieceNotes { version: 1 }` and is
            // refused with `VersionConflict` — which without recovery ends the
            // row on EVERY retry, so the piece is never put into an outfit. The
            // id came from this apply's reservation, so that conflict proves our
            // own earlier append; `recover_version` folds it into the version the
            // stream reached.
            version = match recover_version(notes) {
                Ok(version) => version,
                Err(error) if is_infra_outage(&error) => return Err(error),
                Err(error) => refused!(UnappliedCostumeReason::NotesRejected, error),
            };
            self.confirm(&mapping, version).await?;
        }

        // Step 3: put the piece into the figure's outfit. One outfit per figure
        // and draft row, addressed by a deterministic id: a retry that lands on
        // the existing outfit folds the conflict into `AddPieceToOutfit` at the
        // reached version instead of creating a second look. A refusal leaves the
        // piece in the fundus — visible and correctable — and the retry reuses
        // this mapping row instead of creating a second piece.
        if version >= phases.piece_complete() {
            // CR-002/D2: an outfit mutation inside an archived season is refused
            // by every manual route with 409 `season.archived` (issue #533 makes
            // the archive terminal), and the AI apply owes the same invariant.
            // The refusal must land HERE and not earlier: steps 1 and 2 already
            // appended a valid `Piece`, which stays in the fundus — visible and
            // correctable — exactly as the spec requires.
            //
            // This read is a *dispatch precondition*, not audit-context
            // resolution (AGENTS.md §1): the worker is not deriving a
            // `project_id` for `EventMetadata`, it asks whether the target season
            // still accepts mutations at all. No command field can carry the
            // answer, because it has to be true at the moment of the outfit
            // append; the same reasoning the mapping-reservation reads above rely
            // on.
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
                    refused!(
                        UnappliedCostumeReason::BindingRejected,
                        DomainError::conflict("target season is archived")
                    );
                }
                Ok(_) => {}
                // A dependency outage is not a refusal: fail the apply so the
                // retry re-drives the unfinished rows from their reservations.
                Err(error) if is_infra_outage(&error) => return Err(error),
                // A projection miss is permanent for this attempt. Refusing the
                // outfit step fails *closed* (nothing is created in a season we
                // cannot prove mutable) while the piece stays correctable.
                Err(error) => {
                    tracing::warn!(
                        %error,
                        season = %season_id.0,
                        "AI apply could not resolve the target season; refusing the outfit step"
                    );
                    refused!(
                        UnappliedCostumeReason::BindingRejected,
                        DomainError::conflict("target season could not be resolved")
                    );
                }
            }
            let outfit_id = derive_id(
                preview_id,
                &character_mapping_ref(&costume.character_identity),
                "outfit",
                PRIMARY_ORDINAL,
            );
            let outfit = OutfitCommands::create(
                &*self.costume_commands,
                actor.clone(),
                CreateOutfit {
                    id: outfit_id,
                    character_id,
                    name: outfit_name(costume),
                    piece_ids: vec![id],
                    project_id,
                },
            )
            .await;
            match outfit {
                Ok(_) => {}
                // The outfit already exists (second piece of the same figure, or
                // a replayed step): join the existing look at its current
                // version. `AddPieceToOutfit` is a state-based no-op when the
                // piece is already there.
                Err(DomainError::VersionConflict { current, .. }) => {
                    let added = OutfitCommands::add_piece(
                        &*self.costume_commands,
                        actor,
                        AddPieceToOutfit {
                            id: outfit_id,
                            piece_id: id,
                            project_id,
                            version: current,
                        },
                    )
                    .await;
                    match added {
                        Ok(_) => {}
                        Err(error) if is_infra_outage(&error) => return Err(error),
                        Err(error) => refused!(UnappliedCostumeReason::BindingRejected, error),
                    }
                }
                Err(error) if is_infra_outage(&error) => return Err(error),
                Err(error) => refused!(UnappliedCostumeReason::BindingRejected, error),
            }
            // The beat step references the outfit, not the bare piece: a scene
            // casts the composed look.
            return Ok(CostumeAttempt {
                created,
                costume_id: outfit_id,
                failure: None,
            });
        }

        Ok(CostumeAttempt {
            created,
            costume_id: id,
            failure: None,
        })
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
    /// The `scene_costume_beat` row is addressed by the figure's mapping
    /// reference plus the costume's per-figure position and carries the
    /// SCENE aggregate id. **Shared-stream collision:** the row's `scene`
    /// mapping row and every `scene_costume_beat` row of the same draft hold
    /// versions of the same scene stream — never read one of them alone;
    /// recover the stream version as the max across all of the row's rows
    /// (`apply_script` does) and rely on confirms being only-moves-forward.
    async fn apply_costume_beat(
        &self,
        dispatch: BeatDispatch<'_>,
    ) -> Result<BeatAttempt, DomainError> {
        let BeatDispatch {
            actor,
            preview_id,
            project_id,
            scene_id,
            character_id,
            costume,
            per_figure_order,
            costume_id,
            scene_version,
        } = dispatch;
        let ordinal = ordinal_of(per_figure_order)?;
        let lane_ref = character_mapping_ref(&costume.character_identity);
        let stored = self
            .mappings
            .find(
                preview_id,
                &lane_ref,
                mapping_kind::SCENE_COSTUME_BEAT,
                ordinal,
            ) // ast-grep-ignore: cqrs-boundary
            .await?;
        let mapping = match stored {
            Some(row) => row,
            None => {
                self.mappings
                    .reserve(AiImportMapping::reservation(
                        preview_id,
                        lane_ref.clone(),
                        mapping_kind::SCENE_COSTUME_BEAT.to_owned(),
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
                outfit_id: costume_id,
                // The extracted description lives on the costume's notes;
                // a beat note is a crew cue the extraction does not produce.
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
            // refusal `AddCostumeBeat` can produce (pinned in
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
    async fn create_scene_reserved(
        &self,
        actor: UserId,
        draft: ReservedSceneDraft,
    ) -> Result<(Uuid, AggregateVersion), DomainError> {
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
        let version = recover_version(
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
                .await
                .map(|(_, version)| version),
        )?;
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
        Ok((id, version))
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
struct CostumeDispatch<'a> {
    preview_id: AiImportJobId,
    /// Resolved by the API edge; the write side never looks a season up (CQRS
    /// boundary) and a `Costume` carries no scope of its own.
    season_id: SeasonId,
    project_id: Option<ProjectId>,
    row: &'a SceneApplyPlan,
    costume: &'a CostumeApplyPlan,
    /// The figure this row's costume binds to, created or resolved above.
    character_id: Uuid,
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
    costume: &CostumeApplyPlan,
    reason: UnappliedCostumeReason,
    detail: Option<String>,
) -> UnappliedCostume {
    UnappliedCostume {
        draft_ref: row.draft_ref.clone(),
        ordinal: costume.ordinal,
        character_name: costume.character_name.clone(),
        description: costume.description.clone(),
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
