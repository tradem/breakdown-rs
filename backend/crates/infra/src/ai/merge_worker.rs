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
            let error = DomainError::ValidationError(
                "schedule job has no preview handle for merge".to_owned(),
            );
            self.fail(job.id, &error, false).await?;
            return Err(error);
        };
        let Some(payload) = self.previews.get(preview_handle).await? else {
            let error = DomainError::NotFound(format!("schedule preview {preview_handle}"));
            self.fail(job.id, &error, true).await?;
            return Err(error);
        };
        let input: MergeInput = match from_slice(&payload) {
            Ok(input) => input,
            Err(error) => {
                let error = DomainError::ValidationError(format!("invalid merge input: {error}"));
                self.fail(job.id, &error, false).await?;
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
                let retryable = !matches!(error, DomainError::Conflict(_));
                self.fail(job.id, &error, retryable).await?;
                return Err(error);
            }
        };
        let payload = to_vec(&merged).map_err(|error| {
            DomainError::ValidationError(format!("could not serialize merged preview: {error}"))
        })?;
        let handle = self.previews.put(job.id, payload).await?;
        self.queue
            .record_telemetry(
                job.id,
                Telemetry {
                    doc_kind: Some(DocumentKind::Schedule),
                    latency_total: started.elapsed().as_millis().min(u128::from(u64::MAX)) as u64,
                    apply_state: TelemetryApplyState::NotApplied,
                    ..Telemetry::default()
                },
            )
            .await?;
        self.queue.mark_succeeded(job.id, &handle).await?;
        Ok(true)
    }

    async fn fail(
        &self,
        id: AiImportJobId,
        error: &DomainError,
        retryable: bool,
    ) -> Result<(), DomainError> {
        self.queue
            .mark_failed(id, &error.to_string(), retryable)
            .await
    }
}

/// Pure merge helper retained for callers that already loaded the projections.
pub fn merge_loaded_schedule(
    schedule: &breakdown_core::ai::ShootingSchedule,
    scenes: &[breakdown_core::scene::views::SceneView],
) -> Result<MergedPreview, DomainError> {
    if scenes.is_empty() {
        return Err(DomainError::Conflict(
            "merge pending: block has no applied scenes yet".to_owned(),
        ));
    }
    Ok(breakdown_core::ai::merge_schedule_to_scenes(
        schedule, scenes,
    ))
}
