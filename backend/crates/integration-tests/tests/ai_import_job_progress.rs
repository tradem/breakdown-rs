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
    ApplyProgress, ApplyRunId, ApplyStage, DocumentKind,
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
        target: None,
    }
}

fn progress(stage: AiImportStage, chunk: u32, episodes: &[&str]) -> AiImportProgress {
    AiImportProgress {
        stage,
        chunk: Some(chunk),
        chunks_total: Some(12),
        episodes_seen: episodes.iter().map(|label| (*label).to_owned()).collect(),
        started_at: None,
        done_bytes: None,
        total_bytes: None,
        written_at: None,
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

/// An apply payload owned by `run_id` (issues #762, #800).
fn apply_run_frame(run_id: ApplyRunId, applied: u32, total: u32) -> ApplyProgress {
    let now = chrono::Utc::now();
    ApplyProgress {
        stage: ApplyStage::Applying,
        applied,
        total,
        started_at: now,
        updated_at: now,
        run_id,
    }
}

/// A `succeeded` job ready for an apply (issues #762, #800).
async fn succeeded_job(queue: &PgAiImportQueue, user: &str) -> Result<AiImportJobId> {
    let request = make_enqueue_request(user);
    let id = request.id;
    queue.enqueue(request).await?;
    let _claimed = queue.claim_next("worker-1").await?.expect("claimable");
    queue
        .mark_succeeded(id, "worker-1", "ai-preview/handle")
        .await?;
    Ok(id)
}

/// Issue #762 + #800: the apply-run progress round-trips through the JSONB
/// column, and the run counter proves the run happened even after it cleared.
#[tokio::test]
async fn apply_progress_round_trips_on_a_succeeded_job() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);
    let id = succeeded_job(&queue, "user-apply-progress").await?;

    let run_id = ApplyRunId::new();
    assert!(
        queue.claim_apply_run(id, run_id).await?,
        "a free slot is claimable"
    );
    let run = apply_run_frame(run_id, 3, 57);
    queue.mark_apply_progress(id, run_id, Some(&run)).await?;

    let job = queue.get(id).await?.expect("job exists");
    assert_eq!(
        job.apply_progress,
        Some(run.clone()),
        "the run's own numbers survive the round trip, anchor and run id included"
    );

    // The slot now answers "who owns it, and how many runs have started".
    let state = queue
        .apply_run_state(id)
        .await?
        .expect("a stored job has a run slot");
    assert_eq!(state.owner, Some(run_id), "the claim is visible");
    assert_eq!(state.seq, 1, "the claim bumped the run counter once");
    assert_eq!(
        state.progress,
        Some(run.clone()),
        "and it carries the payload"
    );

    // Clearing is the end signal the apply stream closes on.
    queue.mark_apply_progress(id, run_id, None).await?;
    let job = queue.get(id).await?.expect("job exists");
    assert_eq!(job.apply_progress, None, "the run is gone once it ended");
    let state = queue
        .apply_run_state(id)
        .await?
        .expect("a stored job has a run slot");
    assert_eq!(state.owner, None, "the ended run released the slot");
    assert_eq!(
        state.seq, 1,
        "but the counter stays — that is what proves the run to the stream"
    );
    Ok(())
}

/// Issue #800: two applies cannot interleave. The second claim is refused while
/// the first run is live, and its writes cannot touch the owner's payload.
#[tokio::test]
async fn a_second_apply_claim_is_refused_and_cannot_write() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);
    let id = succeeded_job(&queue, "user-apply-single-flight").await?;

    let live = ApplyRunId::new();
    assert!(queue.claim_apply_run(id, live).await?);
    queue
        .mark_apply_progress(id, live, Some(&apply_run_frame(live, 3, 57)))
        .await?;

    let intruder = ApplyRunId::new();
    assert!(
        !queue.claim_apply_run(id, intruder).await?,
        "a live run keeps the slot"
    );
    // … and without the slot its writes are no-ops, for the payload AND the
    // clear (that is what keeps a superseded run from ending the stream).
    queue
        .mark_apply_progress(id, intruder, Some(&apply_run_frame(intruder, 40, 57)))
        .await?;
    queue.mark_apply_progress(id, intruder, None).await?;

    let state = queue.apply_run_state(id).await?.expect("run slot");
    assert_eq!(state.owner, Some(live), "ownership is unchanged");
    assert_eq!(
        state.progress.as_ref().map(|frame| frame.applied),
        Some(3),
        "the live run's counters are untouched"
    );
    assert_eq!(state.seq, 1, "the refused claim did not bump the counter");
    Ok(())
}

/// Issue #800: a claim whose process died is stolen, not locked forever. The
/// staleness cutoff comes from `ApplyProgress::STALE_AFTER`, so the test moves
/// the *payload* into the past instead of sleeping (AGENTS.md §4).
#[tokio::test]
async fn a_stale_claim_is_stolen_by_the_next_apply() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);
    let id = succeeded_job(&queue, "user-apply-stale-steal").await?;

    let dead = ApplyRunId::new();
    assert!(queue.claim_apply_run(id, dead).await?);
    let mut stale = apply_run_frame(dead, 3, 57);
    stale.updated_at =
        chrono::Utc::now() - ApplyProgress::STALE_AFTER - chrono::Duration::seconds(1);
    queue.mark_apply_progress(id, dead, Some(&stale)).await?;

    let next = ApplyRunId::new();
    assert!(
        queue.claim_apply_run(id, next).await?,
        "a claim older than the staleness window is dead and must be stealable"
    );
    let state = queue.apply_run_state(id).await?.expect("run slot");
    assert_eq!(state.owner, Some(next), "the stealer owns the slot");
    assert_eq!(state.seq, 2, "and the run counter recorded the new run");
    Ok(())
}

/// Issue #800: `AiImportJob.applied` is the persisted "already imported" fact,
/// derived from the apply telemetry the apply path records.
#[tokio::test]
async fn applied_tracks_the_recorded_apply_telemetry() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);
    let id = succeeded_job(&queue, "user-apply-applied-flag").await?;

    let before = queue.get(id).await?.expect("job exists");
    assert!(!before.applied, "a preview nobody applied is not imported");

    queue
        .record_telemetry(
            id,
            breakdown_core::ai::Telemetry {
                apply_state: breakdown_core::ai::TelemetryApplyState::Applied {
                    accept_as_is: true,
                    edit_distance: 0,
                },
                ..breakdown_core::ai::Telemetry::default()
            },
        )
        .await?;

    let after = queue.get(id).await?.expect("job exists");
    assert!(
        after.applied,
        "the recorded apply makes the job an applied one"
    );
    Ok(())
}

/// Issue #762: an apply can only ever run against a `succeeded` job, so the
/// adapter must refuse the payload for any other state — and it must not touch
/// the claim/lease columns while it does (an apply is not a worker transition).
#[tokio::test]
async fn apply_progress_is_refused_for_a_running_job_and_leaves_the_lease_alone() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());

    let request = make_enqueue_request("user-apply-progress-running");
    let id = request.id;
    queue.enqueue(request).await?;
    let claimed = queue.claim_next("worker-1").await?.expect("claimable");
    let lease_before: Option<chrono::DateTime<chrono::Utc>> =
        sqlx::query_scalar("SELECT lease_expires_at FROM ai_import.ai_import_job WHERE id = $1")
            .bind(id.as_uuid())
            .fetch_one(&pool)
            .await?;

    // Issue #800: the claim is the gate, and a non-`succeeded` job has no slot
    // at all — so there is nothing an apply could write to.
    let run_id = ApplyRunId::new();
    assert!(
        !queue.claim_apply_run(id, run_id).await?,
        "a running job has no apply slot"
    );
    queue
        .mark_apply_progress(id, run_id, Some(&apply_run_frame(run_id, 1, 2)))
        .await?;

    let job = queue.get(id).await?.expect("job exists");
    assert_eq!(
        job.apply_progress, None,
        "a running job never carries apply progress"
    );
    assert_eq!(job.status, JobStatus::Running, "the status is untouched");
    let (lease_after, worker_id): (Option<chrono::DateTime<chrono::Utc>>, Option<String>) =
        sqlx::query_as(
            "SELECT lease_expires_at, worker_id FROM ai_import.ai_import_job WHERE id = $1",
        )
        .bind(id.as_uuid())
        .fetch_one(&pool)
        .await?;
    assert_eq!(lease_after, lease_before, "the lease is not disturbed");
    assert_eq!(
        worker_id.as_deref(),
        Some("worker-1"),
        "the claim owner is not disturbed"
    );
    assert_eq!(claimed.id, id);
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

/// Issue #763 (CodeRabbit review): a *retryable* failure that exhausts the
/// budget lands `dead_letter` through the same statement, so that path must
/// clear the stage too — the branch the non-retryable test above cannot reach.
#[tokio::test]
async fn budget_exhaustion_clears_progress() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());

    let request = make_enqueue_request("user-progress-budget");
    let id = request.id;
    queue.enqueue(request).await?;
    let job = queue.get(id).await?.expect("job exists");
    let max_retries = job.max_retries;

    // Drive retryable failures until the budget is spent. Each round resets the
    // exponential backoff so the reclaim predicate is due — the wait itself is
    // never the thing under test.
    let mut status = JobStatus::Pending;
    for attempt in 1..=max_retries {
        let _claimed = queue
            .claim_next("worker-1")
            .await?
            .expect("a claimable attempt");
        queue
            .mark_progress(
                id,
                "worker-1",
                &progress(AiImportStage::Extracting, attempt, &["Ep. 3"]),
            )
            .await?;
        queue
            .mark_failed(id, "worker-1", "transient", Some("dependency.test"), true)
            .await?;
        status = queue.get(id).await?.expect("job exists").status;
        if status == JobStatus::Failed {
            assert!(
                queue.get(id).await?.expect("job exists").progress.is_some(),
                "a backing-off attempt keeps its progress (attempt {attempt})"
            );
        }
        sqlx::query(
            "UPDATE ai_import.ai_import_job SET next_attempt_at = now() - interval '1 second' WHERE id = $1",
        )
        .bind(id.as_uuid())
        .execute(&pool)
        .await?;
    }

    assert_eq!(
        status,
        JobStatus::DeadLetter,
        "the last permitted retryable failure must dead-letter the job"
    );
    assert_eq!(
        queue.get(id).await?.expect("job exists").progress,
        None,
        "the dead-lettering statement must clear the stage"
    );
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
