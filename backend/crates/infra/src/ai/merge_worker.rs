// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use std::sync::Arc;
use std::time::Instant;

use breakdown_core::ai::{
    AiImportJobId, AiImportQueue, DocumentKind, MergedPreview, ShootingSchedule, Telemetry,
    merge_schedule_to_scenes,
};
use breakdown_core::episode::ports::EpisodeRepository;
use breakdown_core::error::DomainError;
use breakdown_core::scene::ports::SceneRepository;
use breakdown_core::shared::EpisodeId;
use serde_json::{from_slice, to_vec};

use super::preview_store::AiPreviewStore;

const MAX_EPISODES_PER_BLOCK: i64 = 10_000;
const MAX_SCENES_PER_EPISODE: i64 = 10_000;

/// Queue-backed deterministic schedule merge worker.
///
/// A schedule job is claimed only after its preview exists. The merge reads
/// applied Scene projections, never a script draft, and stores the derived
/// merged preview under the same operational job handle.
pub struct QueueMergeWorker<Q, E, S, P> {
    pub queue: Arc<Q>,
    pub episodes: Arc<E>,
    pub scenes: Arc<S>,
    pub previews: Arc<P>,
}

impl<Q, E, S, P> QueueMergeWorker<Q, E, S, P>
where
    Q: AiImportQueue + 'static,
    E: EpisodeRepository + 'static,
    S: SceneRepository + 'static,
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
        let schedule: ShootingSchedule = match from_slice(&payload) {
            Ok(schedule) => schedule,
            Err(error) => {
                // A malformed payload must not leave the job stuck in `running`
                // (the queue has no running-job reclaim path).
                let error =
                    DomainError::ValidationError(format!("invalid schedule preview: {error}"));
                self.fail(job.id, &error, false).await?;
                return Err(error);
            }
        };
        let Some(block_id) = schedule.block_id else {
            let error =
                DomainError::ValidationError("schedule preview has no target block".to_owned());
            self.fail(job.id, &error, false).await?;
            return Err(error);
        };
        // Request one extra row per page so a truncated projection can be
        // detected: marking a partial merge as succeeded would silently drop
        // scenes beyond the page limit.
        let episodes = match self
            .episodes
            .list_by_block(block_id, MAX_EPISODES_PER_BLOCK + 1, 0)
            .await
        {
            Ok(episodes) => episodes,
            Err(error) => {
                // A transient projection error must not strand the claimed job
                // in `running`; mark it failed+retryable first.
                self.fail(job.id, &error, true).await?;
                return Err(error);
            }
        };
        if episodes.len() > MAX_EPISODES_PER_BLOCK as usize {
            let error = DomainError::ValidationError(format!(
                "block contains more than {MAX_EPISODES_PER_BLOCK} episodes; \
                 refusing a partial merge"
            ));
            self.fail(job.id, &error, false).await?;
            return Err(error);
        }
        let mut scenes = Vec::new();
        for episode in episodes {
            let episode_scenes = match self
                .scenes
                .list_by_episode(
                    EpisodeId::from_uuid(episode.id),
                    MAX_SCENES_PER_EPISODE + 1,
                    0,
                )
                .await
            {
                Ok(episode_scenes) => episode_scenes,
                Err(error) => {
                    self.fail(job.id, &error, true).await?;
                    return Err(error);
                }
            };
            if episode_scenes.len() > MAX_SCENES_PER_EPISODE as usize {
                let error = DomainError::ValidationError(format!(
                    "episode contains more than {MAX_SCENES_PER_EPISODE} scenes; \
                     refusing a partial merge"
                ));
                self.fail(job.id, &error, false).await?;
                return Err(error);
            }
            scenes.extend(episode_scenes);
        }
        if scenes.is_empty() {
            let error =
                DomainError::Conflict("merge pending: block has no applied scenes yet".to_owned());
            self.fail(job.id, &error, true).await?;
            return Ok(false);
        }

        let merged = merge_schedule_to_scenes(&schedule, &scenes);
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
    schedule: &ShootingSchedule,
    scenes: &[breakdown_core::scene::views::SceneView],
) -> Result<MergedPreview, DomainError> {
    if scenes.is_empty() {
        return Err(DomainError::Conflict(
            "merge pending: block has no applied scenes yet".to_owned(),
        ));
    }
    Ok(merge_schedule_to_scenes(schedule, scenes))
}
