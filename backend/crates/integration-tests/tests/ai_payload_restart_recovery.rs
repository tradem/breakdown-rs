// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0-free (opencode)

//! Restart-recovery and payload-retention contract for AI import jobs
//! (issue #181).
//!
//! Two invariants are asserted against a real Postgres:
//!
//! 1. **Non-resumable termination.** A worker that finds a job's durable
//!    payload absent moves it to `payload_unavailable`. That state is
//!    terminal: no claim predicate may hand the job out again, and the write
//!    is owner-fenced like every other worker transition.
//! 2. **Retention respects the retry state.** Payload GC must sweep terminal
//!    jobs only. `failed` is *not* terminal — it is the backoff state of a job
//!    that is still within its retry budget — so sweeping it would delete the
//!    source document of a job that is still scheduled to run, manufacturing
//!    the very missing-payload case invariant 1 handles.
//!
//! The tests are timing-safe. No test sleeps, and no assertion compares a
//! database timestamp against the test process' clock: ages are produced by
//! backdating `updated_at` **in SQL** by 30 days against a 1-day retention
//! window, so the margin dwarfs any host/container clock skew by ~4 orders of
//! magnitude.
//!
//! Raw SQL appears in exactly two places, both deliberate:
//!   * backdating `updated_at`, which no public API exposes (the alternative
//!     would be sleeping out a retention window, which the deterministic-test
//!     rule forbids);
//!   * reading back the raw `status` string, which is the persistence contract
//!     the migration's CHECK constraint guards.
//!
//! Every state transition under test goes through the public `AiImportQueue`.

#![allow(
    // A violated contract must abort the test rather than be threaded through
    // a Result: these tests assert invariants, not happy paths.
    clippy::unwrap_used,
    clippy::expect_used
)]
mod fixtures;

use anyhow::Result;
use breakdown_core::ai::{
    AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJobId, AiImportQueue, DocumentKind,
    JobStatus,
};
use breakdown_core::error::DomainError;
use breakdown_core::shared::UserId;
use infra::ai::payload_cleanup::{AiPayloadGcConfig, run_gc_sweep};
use infra::ai::{OpenDalAiPayloadStorage, PgAiImportQueue};
use sqlx::{PgPool, Row};

/// Seed a job through the public `enqueue` API and return its id.
async fn seed_job(queue: &PgAiImportQueue, dedup: &str, kind: DocumentKind) -> AiImportJobId {
    let id = AiImportJobId::new();
    let result = queue
        .enqueue(AiImportEnqueueRequest {
            id,
            user_id: UserId::from_sub("payload-recovery-user"),
            document_kind: kind,
            block_id: None,
            dedup_key: dedup.to_owned(),
            document_digest: "digest".to_owned(),
            source_handle: format!("ai-import/{}/source", id.as_uuid()),
        })
        .await
        .unwrap();
    match result {
        AiImportEnqueueResult::Enqueued(id) | AiImportEnqueueResult::Existing(id) => id,
    }
}

/// Read the raw persisted status string.
///
/// Deliberately raw SQL: the string (not the enum) is what the migration's
/// CHECK constraint accepts, and a drift between the two would only surface
/// here.
async fn read_status(pool: &PgPool, id: AiImportJobId) -> String {
    sqlx::query_scalar("SELECT status FROM ai_import.ai_import_job WHERE id = $1")
        .bind(id.as_uuid())
        .fetch_one(pool)
        .await
        .unwrap()
}

/// Read the operational claim/backoff bookkeeping that the `AiImportJob` view
/// does not expose.
async fn read_claim_state(
    pool: &PgPool,
    id: AiImportJobId,
) -> (Option<String>, Option<chrono::DateTime<chrono::Utc>>) {
    let row = sqlx::query(
        r#"
        SELECT worker_id, lease_expires_at
        FROM ai_import.ai_import_job
        WHERE id = $1
        "#,
    )
    .bind(id.as_uuid())
    .fetch_one(pool)
    .await
    .unwrap();
    (
        row.try_get("worker_id").unwrap(),
        row.try_get("lease_expires_at").unwrap(),
    )
}

/// Backdate a job by 30 days so it is unambiguously older than the 1-day
/// retention window used by these tests, independent of clock skew.
///
/// Deliberately raw SQL: `updated_at` is maintained by the queue adapter and
/// no public API can move it. The alternative — sleeping out the retention
/// window — is forbidden by the deterministic-test rule.
async fn backdate(pool: &PgPool, id: AiImportJobId) {
    sqlx::query(
        r#"
        UPDATE ai_import.ai_import_job
        SET updated_at = now() - interval '30 days'
        WHERE id = $1
        "#,
    )
    .bind(id.as_uuid())
    .execute(pool)
    .await
    .unwrap();
}

/// Make a retryable job's exponential backoff due.
///
/// Deliberately raw SQL: `next_attempt_at` is computed in SQL
/// (`now() + interval ...`) and no public API exposes it. The alternative —
/// sleeping out the one-minute first backoff — is forbidden by the
/// deterministic-test rule. (Same rationale as `ai_import_queue_lease.rs`.)
async fn make_backoff_due(pool: &PgPool, id: AiImportJobId) {
    sqlx::query(
        r#"
        UPDATE ai_import.ai_import_job
        SET next_attempt_at = now() - interval '1 minute'
        WHERE id = $1
        "#,
    )
    .bind(id.as_uuid())
    .execute(pool)
    .await
    .unwrap();
}

/// GC config with a 1-day retention window, in dry-run mode.
///
/// Dry-run is what makes this a Postgres-only test: `run_gc_sweep` performs no
/// storage call on that branch, it only *selects* the jobs it would sweep and
/// records the count. Selection is exactly the retention policy under test, so
/// the storage adapter below is never dialled and its endpoint is irrelevant.
fn dry_run_config() -> AiPayloadGcConfig {
    AiPayloadGcConfig {
        enabled: true,
        interval_secs: 3600,
        max_age_secs: 86_400,
        batch_size: 1000,
        dry_run: true,
    }
}

/// Storage handle for the dry-run sweep; never contacted (see
/// [`dry_run_config`]).
fn unused_storage() -> OpenDalAiPayloadStorage {
    OpenDalAiPayloadStorage::new(
        "http://127.0.0.1:1".to_owned(),
        "unused".to_owned(),
        "unused".to_owned(),
        "unused".to_owned(),
        None,
    )
}

/// Number of jobs the most recent sweep selected.
async fn last_sweep_scanned(pool: &PgPool) -> i64 {
    sqlx::query_scalar(
        r#"
        SELECT scanned
        FROM ai_import.projection_ai_payload_gc_run
        ORDER BY started_at DESC
        LIMIT 1
        "#,
    )
    .fetch_one(pool)
    .await
    .unwrap()
}

#[tokio::test]
async fn payload_unavailable_is_persisted_and_terminal() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = seed_job(&queue, "pu-terminal", DocumentKind::Script).await;

    let claimed = queue.claim_next("worker-a").await?.expect("job claimable");
    assert_eq!(claimed.id, id);

    queue
        .mark_payload_unavailable(id, "worker-a", "AI document source is gone")
        .await?;

    // The persisted string must be the one the CHECK constraint accepts.
    assert_eq!(read_status(&pool, id).await, "payload_unavailable");

    let job = queue.get(id).await?.expect("job row still exists");
    assert_eq!(job.status, JobStatus::PayloadUnavailable);
    assert!(job.status.is_terminal());
    assert!(job.status.is_non_resumable());
    assert_eq!(
        job.retries, 0,
        "a lost payload is not a failed attempt, so no retry may be charged"
    );
    assert!(
        job.last_error.is_some(),
        "the reason must be recorded for the operator"
    );

    // A terminal job holds no claim: leaving a lease behind would let the
    // reclaim predicate resurrect it once the lease lapsed.
    let (worker_id, lease_expires_at) = read_claim_state(&pool, id).await;
    assert_eq!(worker_id, None);
    assert_eq!(lease_expires_at, None);

    assert!(
        queue.claim_next("worker-b").await?.is_none(),
        "a payload_unavailable job must never be handed to a worker again"
    );
    Ok(())
}

#[tokio::test]
async fn payload_unavailable_is_owner_fenced() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = seed_job(&queue, "pu-fenced", DocumentKind::Script).await;

    queue.claim_next("worker-a").await?.expect("job claimable");

    // A worker that lost its claim must not stamp a terminal state over the
    // result of the worker that now owns the job.
    let result = queue
        .mark_payload_unavailable(id, "worker-b", "stale worker")
        .await;
    assert!(
        matches!(result, Err(DomainError::Conflict(_))),
        "expected Conflict, got {result:?}"
    );
    assert_eq!(
        read_status(&pool, id).await,
        "running",
        "the rightful owner's state must be untouched"
    );
    Ok(())
}

#[tokio::test]
async fn gc_spares_a_retryable_failed_job_and_sweeps_terminal_ones() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());

    // (1) Retryable `failed`: within its retry budget, so it will be claimed
    // again once the backoff is due. Its payloads must survive.
    let retryable = seed_job(&queue, "gc-retryable", DocumentKind::Script).await;
    queue.claim_next("worker-a").await?.expect("claimable");
    queue
        .mark_failed(retryable, "worker-a", "transient provider 503", true)
        .await?;
    assert_eq!(read_status(&pool, retryable).await, "failed");

    // (2) Succeeded: terminal.
    let succeeded = seed_job(&queue, "gc-succeeded", DocumentKind::Script).await;
    queue.claim_next("worker-b").await?.expect("claimable");
    queue
        .mark_succeeded(succeeded, "worker-b", "ai-import/x/preview")
        .await?;

    // (3) Payload unavailable: terminal, and has nothing left to protect.
    let unavailable = seed_job(&queue, "gc-unavailable", DocumentKind::Schedule).await;
    queue
        .claim_next_kind("worker-c", DocumentKind::Schedule)
        .await?
        .expect("claimable");
    queue
        .mark_payload_unavailable(unavailable, "worker-c", "source document is gone")
        .await?;

    // (4) Pending: never ran, must never be swept.
    let pending = seed_job(&queue, "gc-pending", DocumentKind::Script).await;

    for id in [retryable, succeeded, unavailable, pending] {
        backdate(&pool, id).await;
    }

    run_gc_sweep(&pool, &unused_storage(), &dry_run_config()).await?;

    assert_eq!(
        last_sweep_scanned(&pool).await,
        2,
        "only the succeeded and payload_unavailable jobs are terminal; a \
         retryable `failed` job and a `pending` job must keep their payloads"
    );

    // The spared job is still runnable — which is exactly why its source
    // document had to survive. Its backoff is made due first; until then the
    // queue correctly prefers the untouched `pending` job.
    make_backoff_due(&pool, retryable).await;
    let reclaimed = queue.claim_next("worker-d").await?;
    assert_eq!(
        reclaimed.map(|job| job.id),
        Some(retryable),
        "the retryable job must still be claimable after the sweep \
         (it is the oldest runnable row once its backoff is due)"
    );
    Ok(())
}

#[tokio::test]
async fn gc_sweeps_a_dead_lettered_job() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = seed_job(&queue, "gc-dead-letter", DocumentKind::Script).await;

    queue.claim_next("worker-a").await?.expect("claimable");
    // A non-retryable failure dead-letters immediately, regardless of the
    // remaining budget.
    queue
        .mark_failed(id, "worker-a", "malformed document", false)
        .await?;
    assert_eq!(read_status(&pool, id).await, "dead_letter");

    backdate(&pool, id).await;
    run_gc_sweep(&pool, &unused_storage(), &dry_run_config()).await?;

    assert_eq!(
        last_sweep_scanned(&pool).await,
        1,
        "a dead-lettered job is terminal and its payloads are sweepable"
    );
    Ok(())
}

#[tokio::test]
async fn gc_respects_the_retention_window() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = seed_job(&queue, "gc-fresh", DocumentKind::Script).await;

    queue.claim_next("worker-a").await?.expect("claimable");
    queue
        .mark_succeeded(id, "worker-a", "ai-import/y/preview")
        .await?;

    // Deliberately *not* backdated: a job that just reached a terminal state
    // is inside the retention window, so its preview must stay readable for
    // the user who is about to apply it.
    run_gc_sweep(&pool, &unused_storage(), &dry_run_config()).await?;

    assert_eq!(
        last_sweep_scanned(&pool).await,
        0,
        "a freshly terminal job must survive its retention window"
    );
    Ok(())
}
