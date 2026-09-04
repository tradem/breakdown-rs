// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: longcat-2.0-free (opencode)

use std::sync::Arc;
use std::time::Instant;

use anyhow::Error as AnyhowError;
use breakdown_core::ai::{
    AiImportBounds, AiImportJob, AiImportJobId, AiImportMapping, AiImportMappingRepository,
    AiImportQueue, ApplyMapping, ApplyMappingDecision, DocumentKind, LlmChatRequest, LlmClient,
    MergedPreview, ScriptContext, ShootingSchedule, SourceFormat, Telemetry, TelemetryApplyState,
    ensure_merge_applyable, ensure_script_applyable, extract_scenes, merge_schedule_to_scenes,
};
use breakdown_core::error::DomainError;
use breakdown_core::scene::commands::{CreateScene, UpdateSceneDetails};
use breakdown_core::scene::events::SceneDetails;
use breakdown_core::scene::ports::SceneCommands;
use breakdown_core::shared::{AggregateVersion, EpisodeId, SeriesId, UserId};

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
        for chunk in chunks {
            let request = LlmChatRequest {
                provider: self.provider,
                model: self.model.clone(),
                prompt: self.prompt.clone(),
                source_text: format!("{}\n{}", chunk.heading, chunk.text),
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
                    context.scenes.extend(partial.scenes);
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
                    latency_total: started.elapsed().as_millis().min(u128::from(u64::MAX)) as u64,
                    // The job only reached preview; the apply outcome (if any)
                    // is recorded by the apply path as `Applied`.
                    apply_state: TelemetryApplyState::NotApplied,
                    ..Telemetry::default()
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
                    latency_total: started.elapsed().as_millis().min(u128::from(u64::MAX)) as u64,
                    // The job only reached preview; the apply outcome (if any)
                    // is recorded by the apply path as `Applied`.
                    apply_state: TelemetryApplyState::NotApplied,
                    ..Telemetry::default()
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

/// Apply worker for reviewed script rows. Each row checks the persisted mapping
/// before dispatching, so a crash/retry cannot create a duplicate Scene.
pub struct ApplyWorker<C, M, Q> {
    pub scene_commands: Arc<C>,
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

impl<C, M, Q> ApplyWorker<C, M, Q>
where
    C: SceneCommands + 'static,
    M: AiImportMappingRepository + 'static,
    Q: AiImportQueue + 'static,
{
    pub async fn apply_script(
        &self,
        request: ApplyScriptRequest<'_>,
    ) -> Result<Vec<UuidVersion>, DomainError> {
        let ApplyScriptRequest {
            actor,
            preview_id,
            preview,
            decisions,
            episode_id,
            series_id,
            telemetry,
        } = request;
        ensure_script_applyable(preview)
            .map_err(|error| DomainError::conflict(error.to_string()))?;
        let mut applied = Vec::with_capacity(preview.scenes.len());
        for (index, draft) in preview.scenes.iter().enumerate() {
            let draft_ref = if draft.draft_ref.is_empty() {
                format!("scene-{index}")
            } else {
                draft.draft_ref.clone()
            };
            let stored = self
                .mappings
                .find(preview_id, &draft_ref) // ast-grep-ignore: cqrs-boundary
                .await?;
            // A confirmed mapping means this row already applied: a retry —
            // or a concurrent duplicate that confirmed first — is a no-op
            // returning the stored id/version instead of re-dispatching
            // (issue #338). Re-dispatching an `Update` here would also fail
            // in production: identical details are rejected as unchanged.
            if let Some(confirmed) = stored.as_ref().filter(|mapping| !mapping.is_reserved()) {
                applied.push(UuidVersion {
                    aggregate_id: confirmed.aggregate_id,
                    version: confirmed.aggregate_version,
                });
                continue;
            }
            // A reservation means a previous attempt already claimed an
            // aggregate id for this draft. The reservation wins over the
            // client-supplied decision: the reserved stream may already hold
            // our append (crash after create, before confirm), so switching
            // targets would orphan it. Reusing the reserved id also converges
            // concurrent duplicates onto one stream, whose
            // `ExpectedVersion::Empty` guard turns the loser into a
            // `recover_version` success — mirroring the schedule apply path.
            let reserved_id = stored
                .filter(|mapping| mapping.is_reserved())
                .map(|mapping| mapping.aggregate_id);
            let details = draft.scene_details();
            let (aggregate_id, version) = if let Some(candidate_id) = reserved_id {
                self.create_scene_reserved(
                    actor.clone(),
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
                let decision = decisions
                    .iter()
                    .find(|decision| decision.draft_ref == draft_ref)
                    .map(|decision| decision.decision.clone())
                    .ok_or_else(|| {
                        DomainError::validation(format!("missing mapping for {draft_ref}"))
                    })?;
                match decision {
                    ApplyMappingDecision::Create => {
                        let candidate_id = super::schedule_apply::derive_id(preview_id, &draft_ref);
                        self.create_scene_reserved(
                            actor.clone(),
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
                    }
                    ApplyMappingDecision::Update {
                        aggregate_id,
                        version,
                    } => {
                        let new_version = self
                            .scene_commands
                            .update_details(
                                actor.clone(),
                                UpdateSceneDetails {
                                    id: aggregate_id,
                                    details,
                                    series_id,
                                    version,
                                },
                            )
                            .await?;
                        self.mappings
                            .insert(AiImportMapping {
                                preview_id,
                                draft_ref,
                                aggregate_kind: "scene".to_owned(),
                                aggregate_id,
                                aggregate_version: new_version,
                            })
                            .await?;
                        (aggregate_id, new_version)
                    }
                }
            };
            applied.push(UuidVersion {
                aggregate_id,
                version,
            });
        }
        if let Some(telemetry) = telemetry {
            self.queue.record_telemetry(preview_id, telemetry).await?;
        }
        Ok(applied)
    }

    /// Reserve `candidate_id` for `(preview_id, draft_ref)` *before*
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
                "scene".to_owned(),
                candidate_id,
            ))
            .await?;
        let id = reservation.aggregate_id;
        let version = super::schedule_apply::recover_version(
            self.scene_commands
                .create(
                    actor,
                    CreateScene {
                        id,
                        episode_id,
                        series_id,
                        details,
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
                aggregate_id: id,
                aggregate_version: version,
            })
            .await?;
        Ok((id, version))
    }
}

pub struct ApplyScriptRequest<'a> {
    pub actor: UserId,
    pub preview_id: AiImportJobId,
    pub preview: &'a ScriptContext,
    pub decisions: &'a [ApplyMapping],
    pub episode_id: EpisodeId,
    pub series_id: Option<SeriesId>,
    pub telemetry: Option<Telemetry>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UuidVersion {
    pub aggregate_id: uuid::Uuid,
    pub version: breakdown_core::shared::AggregateVersion,
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
