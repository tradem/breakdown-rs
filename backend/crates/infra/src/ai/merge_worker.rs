// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

use std::sync::Arc;
use std::time::Instant;

use breakdown_core::ai::{
    AiImportJobId, AiImportQueue, DocumentKind, MergeInput, MergedPreview, Telemetry,
    TelemetryApplyState, merge_from_input,
};
use breakdown_core::error::DomainError;
use serde_json::{from_slice, to_vec};

use super::preview_store::AiPreviewStore;

/// Queue-backed deterministic schedule merge worker.
///
/// The merge input (schedule + pre-loaded scenes) is prepared at the
/// API/query boundary — an authorized read-model query — and stored as an
/// immutable blob before the job is claimed. This worker performs only a
/// deterministic join, never querying a read-model projection (CQRS
/// boundary, AGENTS.md §1).
pub struct QueueMergeWorker<Q, P> {
    pub queue: Arc<Q>,
    pub previews: Arc<P>,
}

impl<Q, P> QueueMergeWorker<Q, P>
where
    Q: AiImportQueue + 'static,
    P: AiPreviewStore + 'static,
{
    pub async fn run_once(&self, worker_id: &str) -> Result<bool, DomainError> {
        let Some(job) = self
            .queue
            .claim_next_kind(worker_id, DocumentKind::Schedule)
            .await?
        else {
            return Ok(false);
        };
        let started = Instant::now();
        let Some(preview_handle) = job.preview_handle.as_deref() else {
            let error = DomainError::validation("schedule job has no preview handle for merge");
            self.fail(job.id, worker_id, &error, false).await?;
            return Err(error);
        };
        // Two distinct outcomes, deliberately not collapsed (issue #181):
        //
        //   `Err`  — the store itself failed. Nothing is known about whether
        //            the blob exists, so the job must not be dead-ended.
        //            `fail_payload_load` keeps a `ServiceUnavailable` retryable
        //            and dead-letters anything else through the budget.
        //            Propagating with `?` (as this did before) skipped the
        //            terminal write entirely and left the job `running` until
        //            its lease lapsed — recovery delayed by a full lease
        //            window, with no backoff recorded.
        //   `None` — *absence*. The preview blob is written once by the
        //            schedule worker and never rewritten, so this is permanent:
        //            retrying could only re-discover it while consuming a claim
        //            and a permit each time. Terminated as non-resumable; it
        //            was retryable before, which burned the whole retry budget
        //            on a payload that was gone.
        let stored = match self.previews.get(preview_handle).await {
            Ok(stored) => stored,
            Err(error) => {
                super::workers::fail_payload_load(&*self.queue, job.id, worker_id, &error).await?;
                return Err(error);
            }
        };
        let Some(payload) = stored else {
            let error = DomainError::not_found("schedule-preview");
            self.queue
                .mark_payload_unavailable(job.id, worker_id, &error.to_string())
                .await?;
            return Err(error);
        };
        let input: MergeInput = match from_slice(&payload) {
            Ok(input) => input,
            Err(error) => {
                let error = DomainError::validation(format!("invalid merge input: {error}"));
                self.fail(job.id, worker_id, &error, false).await?;
                return Err(error);
            }
        };

        let merged = match merge_from_input(&input) {
            Ok(merged) => merged,
            Err(error) => {
                // A Conflict (empty scenes) is non-retryable: the MergeInput is
                // immutable and the worker cannot observe later applied scenes.
                // The caller must re-prepare a fresh MergeInput at the API boundary
                // after scenes are applied (CQRS boundary, AGENTS.md §1).
                let retryable = !matches!(error, DomainError::Conflict { .. });
                self.fail(job.id, worker_id, &error, retryable).await?;
                return Err(error);
            }
        };
        let payload = to_vec(&merged).map_err(|error| {
            DomainError::validation(format!("could not serialize merged preview: {error}"))
        })?;
        let handle = self.previews.put(job.id, payload).await?;
        // The merge is a pure in-process transform (no LLM call), so it cannot
        // outlive the lease and needs no heartbeat. The telemetry write is
        // still owner-fenced.
        self.queue
            .record_worker_telemetry(
                job.id,
                worker_id,
                Telemetry {
                    // Fully specified (no `..Default` spread) so a deleted
                    // field is a compile error, not a surviving mutant
                    // (issue #307): the pure merge records no provider/model.
                    provider: None,
                    model: None,
                    doc_kind: Some(DocumentKind::Schedule),
                    chunk_count: 0,
                    tokens_in: 0,
                    tokens_out: 0,
                    latency_total: started.elapsed().as_millis().min(u128::from(u64::MAX)) as u64,
                    apply_state: TelemetryApplyState::NotApplied,
                },
            )
            .await?;
        self.queue
            .mark_succeeded(job.id, worker_id, &handle)
            .await?;
        Ok(true)
    }

    async fn fail(
        &self,
        id: AiImportJobId,
        worker_id: &str,
        error: &DomainError,
        retryable: bool,
    ) -> Result<(), DomainError> {
        self.queue
            .mark_failed(id, worker_id, &error.to_string(), retryable)
            .await
    }
}

/// Pure merge helper retained for callers that already loaded the projections.
pub fn merge_loaded_schedule(
    schedule: &breakdown_core::ai::ShootingSchedule,
    scenes: &[breakdown_core::scene::views::SceneView],
) -> Result<MergedPreview, DomainError> {
    if scenes.is_empty() {
        return Err(DomainError::conflict(
            "merge pending: block has no applied scenes yet",
        ));
    }
    Ok(breakdown_core::ai::merge_schedule_to_scenes(
        schedule, scenes,
    ))
}
