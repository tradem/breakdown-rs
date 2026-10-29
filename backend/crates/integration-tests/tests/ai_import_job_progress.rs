// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

//! Postgres integration tests for the owner-fenced job progress writes
//! (issue #664): persistence + decode, `episodes_seen` accumulation,
//! displaced-worker conflict rejection, and the retry progress reset.

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

mod fixtures;

use anyhow::Result;
use breakdown_core::ai::JobStatus;
use breakdown_core::ai::{
    AiImportEnqueueRequest, AiImportJobId, AiImportProgress, AiImportQueue, AiImportStage,
    DocumentKind,
};
use infra::ai::queue::PgAiImportQueue;
use uuid::Uuid;

fn make_enqueue_request(user_id: &str) -> AiImportEnqueueRequest {
    AiImportEnqueueRequest {
        id: AiImportJobId::new(),
        user_id: breakdown_core::shared::UserId::from_sub(user_id),
        document_kind: DocumentKind::Script,
        source_format: breakdown_core::ai::SourceFormat::Pdf,
        block_id: None,
        dedup_key: format!("dedup-{user_id}-{}", Uuid::now_v7()),
        document_digest: format!("digest-{}", Uuid::now_v7()),
        source_handle: format!("handle-{}", Uuid::now_v7()),
        source_file_name: None,
    }
}

fn progress(stage: AiImportStage, chunk: u32, episodes: &[&str]) -> AiImportProgress {
    AiImportProgress {
        stage,
        chunk: Some(chunk),
        chunks_total: Some(12),
        episodes_seen: episodes.iter().map(|label| (*label).to_owned()).collect(),
    }
}

#[tokio::test]
async fn mark_progress_persists_and_round_trips() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-progress");
    let id = request.id;
    queue.enqueue(request).await?;

    let claimed = queue.claim_next("worker-1").await?.expect("claimable");
    assert_eq!(claimed.progress, None, "fresh claim has no progress");

    // Two throttled frames, accumulating episode labels first-seen.
    queue
        .mark_progress(
            id,
            "worker-1",
            &progress(AiImportStage::Extracting, 1, &["Ep. 3"]),
        )
        .await?;
    queue
        .mark_progress(
            id,
            "worker-1",
            &progress(AiImportStage::Extracting, 4, &["Ep. 3", "Ep. 4"]),
        )
        .await?;

    let job = queue.get(id).await?.expect("job exists");
    let progress = job.progress.expect("progress persisted");
    assert_eq!(progress.stage, AiImportStage::Extracting);
    assert_eq!(progress.chunk, Some(4));
    assert_eq!(progress.chunks_total, Some(12));
    assert_eq!(progress.episodes_seen, vec!["Ep. 3", "Ep. 4"]);
    Ok(())
}

#[tokio::test]
async fn displaced_worker_cannot_overwrite_progress() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-progress-fence");
    let id = request.id;
    queue.enqueue(request).await?;

    let _claimed = queue.claim_next("worker-1").await?.expect("claimable");
    queue
        .mark_progress(
            id,
            "worker-1",
            &progress(AiImportStage::Extracting, 1, &["Ep. 3"]),
        )
        .await?;

    // The lease of worker-1 never expires, so a plain re-claim finds nothing;
    // simulate the displaced worker by publishing under a foreign id: the
    // owner fence (status = 'running' AND worker_id = worker) must reject it.
    let outcome = queue
        .mark_progress(id, "worker-2", &progress(AiImportStage::Extracting, 2, &[]))
        .await;
    assert!(
        matches!(
            &outcome,
            Err(breakdown_core::error::DomainError::Conflict { .. })
        ),
        "displaced worker must get Conflict, got {outcome:?}"
    );

    // The original owner's progress is intact.
    let job = queue.get(id).await?.expect("job exists");
    assert_eq!(
        job.progress.expect("progress intact").chunk,
        Some(1),
        "the displaced write must not touch the new owner's progress"
    );
    Ok(())
}

#[tokio::test]
async fn retry_claim_resets_stale_progress() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());

    let request = make_enqueue_request("user-progress-reset");
    let id = request.id;
    queue.enqueue(request).await?;

    let _claimed = queue.claim_next("worker-1").await?.expect("claimable");
    queue
        .mark_progress(
            id,
            "worker-1",
            &progress(AiImportStage::StoringPreview, 12, &["Ep. 3"]),
        )
        .await?;

    // Retryable failure: attempt 1 leaves stale progress behind.
    queue
        .mark_failed(id, "worker-1", "boom", Some("dependency.test"), true)
        .await?;
    let failed = queue.get(id).await?.expect("job exists");
    assert_eq!(failed.status, JobStatus::Failed);
    assert!(
        failed.progress.is_some(),
        "attempt 1's progress is still served while the job backs off"
    );

    // Fast-forward the exponential backoff (1 min after the first retry) so
    // the reclaim predicate is due; the reset under test happens in the
    // claim statement itself.
    sqlx::query(
        "UPDATE ai_import.ai_import_job SET next_attempt_at = now() - interval '1 second' WHERE id = $1",
    )
    .bind(id.as_uuid())
    .execute(&pool)
    .await?;

    // Attempt 2: the reclaim resets progress to NULL before processing.
    let reclaimed = queue.claim_next("worker-2").await?.expect("reclaimable");
    assert_eq!(reclaimed.id, id);
    assert_eq!(
        reclaimed.progress, None,
        "stale progress from attempt 1 must be reset by the claim"
    );
    Ok(())
}

#[tokio::test]
async fn mark_progress_on_a_non_running_job_is_rejected() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-progress-terminal");
    let id = request.id;
    queue.enqueue(request).await?;

    // The job is still `pending`: even the (never-issued) claiming worker id
    // is rejected because the fence requires status = 'running'.
    let outcome = queue
        .mark_progress(id, "worker-1", &progress(AiImportStage::Extracting, 1, &[]))
        .await;
    assert!(
        matches!(
            &outcome,
            Err(breakdown_core::error::DomainError::Conflict { .. })
        ),
        "non-running job must reject progress writes, got {outcome:?}"
    );
    Ok(())
}

/// Issue #763: `succeeded` is terminal, so the job must not keep advertising the
/// stage it finished at. The last frame a worker publishes is
/// `storing_preview`, which every consumer then rendered forever — the stale
/// "Vorschau wird gespeichert …" line this issue removes.
#[tokio::test]
async fn mark_succeeded_clears_progress() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-progress-succeeded");
    let id = request.id;
    queue.enqueue(request).await?;

    let _claimed = queue.claim_next("worker-1").await?.expect("claimable");
    queue
        .mark_progress(
            id,
            "worker-1",
            &progress(AiImportStage::StoringPreview, 12, &["Ep. 3"]),
        )
        .await?;
    queue
        .mark_succeeded(id, "worker-1", "ai-preview/handle")
        .await?;

    let job = queue.get(id).await?.expect("job exists");
    assert_eq!(job.status, JobStatus::Succeeded);
    assert_eq!(
        job.progress, None,
        "a terminal job must not carry the stage it finished at"
    );
    Ok(())
}

/// Issue #763: the same holds for a dead-lettered job — `mark_failed` lands it
/// terminal, so the stage is cleared in that same statement.
#[tokio::test]
async fn dead_lettering_mark_failed_clears_progress() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-progress-dead-letter");
    let id = request.id;
    queue.enqueue(request).await?;

    let _claimed = queue.claim_next("worker-1").await?.expect("claimable");
    queue
        .mark_progress(
            id,
            "worker-1",
            &progress(AiImportStage::Extracting, 3, &["Ep. 3"]),
        )
        .await?;
    // A non-retryable failure is terminal by construction: no waiting for the
    // retry budget to run out.
    queue
        .mark_failed(id, "worker-1", "hopeless", Some("dependency.test"), false)
        .await?;

    let job = queue.get(id).await?.expect("job exists");
    assert_eq!(job.status, JobStatus::DeadLetter);
    assert_eq!(job.progress, None, "a dead letter has no live stage");
    Ok(())
}

/// Issue #763: a job whose payload is gone is terminal too.
#[tokio::test]
async fn mark_payload_unavailable_clears_progress() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-progress-payload-gone");
    let id = request.id;
    queue.enqueue(request).await?;

    let _claimed = queue.claim_next("worker-1").await?.expect("claimable");
    queue
        .mark_progress(
            id,
            "worker-1",
            &progress(AiImportStage::ExtractingText, 0, &[]),
        )
        .await?;
    queue
        .mark_payload_unavailable(
            id,
            "worker-1",
            "payload gone",
            Some("ai-import.payload-missing"),
        )
        .await?;

    let job = queue.get(id).await?.expect("job exists");
    assert_eq!(job.status, JobStatus::PayloadUnavailable);
    assert_eq!(job.progress, None, "a payload-less job has no live stage");
    Ok(())
}

/// Issue #763: the retryable branch is deliberately excluded — a job that backs
/// off still has a future, so its last progress stays readable until the next
/// claim replaces it.
#[tokio::test]
async fn retryable_mark_failed_keeps_progress() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-progress-retryable");
    let id = request.id;
    queue.enqueue(request).await?;

    let _claimed = queue.claim_next("worker-1").await?.expect("claimable");
    queue
        .mark_progress(
            id,
            "worker-1",
            &progress(AiImportStage::Merging, 12, &["Ep. 3"]),
        )
        .await?;
    queue
        .mark_failed(id, "worker-1", "transient", Some("dependency.test"), true)
        .await?;

    let job = queue.get(id).await?.expect("job exists");
    assert_eq!(job.status, JobStatus::Failed);
    assert_eq!(
        job.progress.map(|progress| progress.stage),
        Some(AiImportStage::Merging),
        "a backing-off job keeps its progress until the next claim"
    );
    Ok(())
}
