// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: longcat-2.0-free (opencode)
// Co-authored-by: qwen3.8-flash (opencode-go)

use std::sync::Arc;
use std::time::Instant;

use anyhow::Error as AnyhowError;
use std::collections::HashMap;

use breakdown_core::ai::{
    AiImportBounds, AiImportJob, AiImportJobId, AiImportMapping, AiImportMappingRepository,
    AiImportQueue, ApplyMapping, ApplyMappingDecision, CharacterApplyPlan, CostumeApplyPlan,
    DocumentKind, LlmChatRequest, LlmClient, MergedPreview, PRIMARY_ORDINAL, SceneApplyCommand,
    SceneApplyPlan, ScriptContext, ShootingSchedule, SourceFormat, Telemetry, TelemetryApplyState,
    UnappliedCostume, UnappliedCostumeReason, Uncertainty, UncertaintyKind, character_mapping_ref,
    draft_row_ref, ensure_merge_applyable, extract_scenes, mapping_kind, merge_schedule_to_scenes,
    plan_scene_apply, stable_draft_ref, verify_draft_costumes,
};
use breakdown_core::character::category::CharacterCategory;
use breakdown_core::character::commands::CreateCharacter;
use breakdown_core::character::ports::CharacterCommands;
use breakdown_core::costume::commands::{
    AssignCostumeToCharacter, CreateCostume, UpdateCostumeNotes,
};
use breakdown_core::costume::ports::CostumeCommands;
use breakdown_core::error::DomainError;
use breakdown_core::scene::commands::CreateScene;
use breakdown_core::scene::events::{SceneDetails, SceneSource};
use breakdown_core::scene::ports::SceneCommands;
use breakdown_core::shared::{AggregateVersion, EpisodeId, SeasonId, SeriesId, UserId};

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
use super::schedule_apply::{derive_id, recover_version};
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
            .mark_payload_unavailable(id, worker_id, &error.to_string())
            .await;
    }
    queue
        .mark_failed(
            id,
            worker_id,
            &error.to_string(),
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
        // Globally unique scene counter across all chunks — the tail of
        // `stable_draft_ref`, which needs a stable identity per preview row
        // that survives the model's own (hallucinated) `draft_ref`.
        let mut scene_ordinal = 0usize;
        for chunk in chunks {
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
                Ok(partial) => {
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
                        // Server-side truth beats the prompt too (design D5): a
                        // prompt forbids inventing a costume, but a prompt is an
                        // instruction, not a guarantee. Everything the check drops
                        // is recorded as a non-blocking `DroppedRow` uncertainty,
                        // so a hallucinated costume cannot reach the reviewer and
                        // a missing one is still visible as missing — without
                        // making the whole preview unappliable (design D8).
                        for rejected in verify_draft_costumes(&mut scene, &source_text) {
                            context.uncertainties.push(Uncertainty {
                                scene_index: scene_ordinal,
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
                        context.scenes.push(scene);
                    }
                    context.uncertainties.extend(partial.uncertainties);
                }
                Err(error) => {
                    self.fail(job.id, worker_id, &error).await?;
                    return Err(error);
                }
            }
        }
        let payload = to_vec(&context).map_err(|error| {
            DomainError::validation(format!("could not serialize script preview: {error}"))
        })?;
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
                    // (issue #307): token counts are 0 until measured.
                    tokens_in: 0,
                    tokens_out: 0,
                    latency_total: started.elapsed().as_millis().min(u128::from(u64::MAX)) as u64,
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
                matches!(error, DomainError::ServiceUnavailable { .. }),
            )
            .await
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
            retry_schedule(
                self.client.as_ref(),
                request,
                self.bounds.max_retries as usize,
            )
            .await?
        };
        if schedule.block_id.is_none() {
            schedule.block_id = job.block_id;
        }
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
                    // (issue #307).
                    chunk_count: 0,
                    tokens_in: 0,
                    tokens_out: 0,
                    latency_total: started.elapsed().as_millis().min(u128::from(u64::MAX)) as u64,
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
    ) -> Result<MergedPreview, DomainError> {
        if scenes.is_empty() {
            return Err(DomainError::conflict(
                "merge is pending until the block has applied scenes",
            ));
        }
        Ok(merge_schedule_to_scenes(schedule, scenes))
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
pub struct ApplyWorker<C, CH, CO, M, Q> {
    pub scene_commands: Arc<C>,
    pub character_commands: Arc<CH>,
    pub costume_commands: Arc<CO>,
    pub mappings: Arc<M>,
    pub queue: Arc<Q>,
}

/// Parameters for one reserved scene create in the script apply path.
/// Bundled so `create_scene_reserved` stays under the `too_many_arguments`
/// lint (an `#[allow]` would violate AGENTS.md §3).
struct ReservedSceneDraft {
    preview_id: AiImportJobId,
    draft_ref: String,
    candidate_id: Uuid,
    episode_id: EpisodeId,
    series_id: Option<SeriesId>,
    details: SceneDetails,
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
    /// `Some` when the row did not reach a bound costume, with the reason the
    /// reviewer sees.
    failure: Option<(UnappliedCostumeReason, String)>,
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
    /// as the costume's notes (design D7) — but an empty description must not
    /// dispatch a command the aggregate would reject as "notes unchanged".
    has_notes: bool,
}

impl CostumePhases {
    /// Version reached after `UpdateCostumeNotes` appended.
    const NOTED: AggregateVersion = AggregateVersion(2);
    /// `CreateCostume` appends exactly one event, landing on `INITIAL`.
    const CREATED: AggregateVersion = AggregateVersion::INITIAL;

    /// Version reached once the costume is bound to its figure.
    fn bound(&self) -> AggregateVersion {
        if self.has_notes {
            AggregateVersion(3)
        } else {
            Self::NOTED
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

/// Reviewed script apply request. `episode_id`, `season_id` and `series_id` are
/// resolved by the API edge from the target episode and are never looked up by
/// this write-side worker (CQRS boundary, AGENTS.md §1). Figures and costumes are
/// season-scoped aggregates, so the season cannot be derived here.
pub struct ApplyScriptRequest<'a> {
    pub actor: UserId,
    pub preview_id: AiImportJobId,
    pub preview: &'a ScriptContext,
    pub decisions: &'a [ApplyMapping],
    pub episode_id: EpisodeId,
    pub season_id: SeasonId,
    pub series_id: Option<SeriesId>,
    pub telemetry: Option<Telemetry>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UuidVersion {
    pub aggregate_id: uuid::Uuid,
    pub version: breakdown_core::shared::AggregateVersion,
}

impl<C, CH, CO, M, Q> ApplyWorker<C, CH, CO, M, Q>
where
    C: SceneCommands + 'static,
    CH: CharacterCommands + 'static,
    CO: CostumeCommands + 'static,
    M: AiImportMappingRepository + 'static,
    Q: AiImportQueue + 'static,
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
            series_id,
            telemetry,
        } = request;
        // The planner is the single source of what an apply dispatches; the
        // worker never re-derives the reviewer's decisions itself, so plan and
        // dispatch cannot drift apart.
        let decisions = self
            .resolved_decisions(preview_id, preview, decisions)
            .await?;
        let plan = plan_scene_apply(preview, &decisions, episode_id, series_id, preview_id)
            .map_err(|error| DomainError::conflict(error.to_string()))?;
        let mut result = ScriptApplyResult {
            applied: Vec::with_capacity(plan.scenes.len()),
            unapplied_costumes: plan.unapplied_costumes,
            ..ScriptApplyResult::default()
        };
        // Figures named by several draft rows are created once. This is a cache
        // of what *this* request resolved, not a projection read: everything that
        // crosses a request boundary goes through the mapping (CQRS boundary).
        let mut figures: HashMap<String, Figure> = HashMap::new();

        for row in &plan.scenes {
            let scene = self
                .apply_scene_row(actor.clone(), preview_id, episode_id, series_id, row)
                .await?;
            result.applied.push(scene);

            for character in &row.characters {
                if self
                    .resolve_figure(
                        actor.clone(),
                        preview_id,
                        season_id,
                        series_id,
                        character,
                        &mut figures,
                    )
                    .await?
                {
                    result.created_characters += 1;
                }
            }

            for costume in &row.costumes {
                let key = character_mapping_ref(&costume.character_identity);
                let character_id = match figures.get(&key) {
                    Some(Figure::Resolved(resolved)) => resolved.aggregate_id,
                    Some(Figure::Unavailable(detail)) => {
                        result.unapplied_costumes.push(unapplied(
                            row,
                            costume,
                            UnappliedCostumeReason::CharacterUnavailable,
                            Some(detail.clone()),
                        ));
                        continue;
                    }
                    None => {
                        // Unreachable through the planner, which only pairs a
                        // costume with a figure of the same row; reported rather
                        // than assumed, because an ownerless costume is exactly
                        // what must never be created.
                        result.unapplied_costumes.push(unapplied(
                            row,
                            costume,
                            UnappliedCostumeReason::CharacterNotPlanned,
                            None,
                        ));
                        continue;
                    }
                };
                let CostumeAttempt { created, failure } = self
                    .apply_costume(
                        actor.clone(),
                        CostumeDispatch {
                            preview_id,
                            season_id,
                            series_id,
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
                    result
                        .unapplied_costumes
                        .push(unapplied(row, costume, reason, Some(detail)));
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
        // (`series_id`, `season_id`) comes from the API-edge request, never here.
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
        series_id: Option<SeriesId>,
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
                    series_id,
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
                            series_id,
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
        series_id: Option<SeriesId>,
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
                    series_id,
                    // Verbatim: the script's own wording is the figure's name.
                    // `character_identity` is a matching key, never a value.
                    name: character.name.clone(),
                    // The extraction carries no role type, so the figure enters
                    // as the category default and the reviewer refines it. An
                    // invented guess at Main/Guest/Extra would be data the script
                    // never stated.
                    category: CharacterCategory::MainCast,
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
    /// `UpdateCostumeNotes` (the extracted description, design D7) +
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
            series_id,
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
                    failure: Some(($reason, $error.to_string())),
                });
            }};
        }

        // Step 1: create the costume **without** a character. A version below
        // `INITIAL` is the reservation sentinel, i.e. no step has appended yet.
        if version < CostumePhases::CREATED {
            let attempt = self
                .costume_commands
                .create(
                    actor.clone(),
                    CreateCostume {
                        id,
                        // The repertoire season the API edge resolved for this
                        // import. Without it a costume whose binding failed would
                        // be invisible in every list, and "visible as unassigned"
                        // (spec `costume-character-binding`) requires it to appear
                        // in the season's wardrobe overview.
                        season_id: Some(season_id),
                        series_id,
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
            let notes = self
                .costume_commands
                .update_notes(
                    actor.clone(),
                    UpdateCostumeNotes {
                        id,
                        notes: costume.description.clone(),
                        series_id,
                        version,
                    },
                )
                .await;
            version = match notes {
                Ok(version) => version,
                Err(error) if is_infra_outage(&error) => return Err(error),
                Err(error) => refused!(UnappliedCostumeReason::NotesRejected, error),
            };
            self.confirm(&mapping, version).await?;
        }

        // Step 3: bind it to the figure of this row. A refusal leaves the costume
        // created and unassigned — visible and correctable — and the retry reuses
        // this mapping row instead of creating a second costume (spec
        // `costume-character-binding`). `recover_version` folds a replayed bind
        // into the version the stream already reached.
        if version < phases.bound() {
            let bound = recover_version(
                self.costume_commands
                    .assign_to_character(
                        actor,
                        AssignCostumeToCharacter {
                            id,
                            character_id,
                            series_id,
                            version,
                        },
                    )
                    .await,
            );
            version = match bound {
                Ok(version) => version,
                Err(error) if is_infra_outage(&error) => return Err(error),
                Err(error) => refused!(UnappliedCostumeReason::BindingRejected, error),
            };
            self.confirm(&mapping, version).await?;
        }
        Ok(CostumeAttempt {
            created,
            failure: None,
        })
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
            series_id,
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
                        series_id,
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
}

/// Where one costume row's commands point. Bundled so `apply_costume` stays
/// under the `too_many_arguments` lint (an `#[allow]` would violate AGENTS.md §3,
/// cf. `ReservedSceneDraft`).
struct CostumeDispatch<'a> {
    preview_id: AiImportJobId,
    /// Resolved by the API edge; the write side never looks a season up (CQRS
    /// boundary) and a `Costume` carries no scope of its own.
    season_id: SeasonId,
    series_id: Option<SeriesId>,
    row: &'a SceneApplyPlan,
    costume: &'a CostumeApplyPlan,
    /// The figure this row's costume binds to, created or resolved above.
    character_id: Uuid,
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
) -> Result<ScriptContext, DomainError>
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
        Ok(value) => Ok(value),
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
) -> Result<ShootingSchedule, DomainError>
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
        Ok(value) => Ok(value),
        Err(error) => match error.downcast::<DomainError>() {
            Ok(domain_error) => Err(domain_error),
            Err(other) => Err(DomainError::validation(other.to_string())),
        },
    }
}
