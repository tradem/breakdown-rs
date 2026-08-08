// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0-free (opencode)

//! Worker-lease recovery contract for the AI import queue (issue #177).
//!
//! `claim_next`/`claim_next_kind` must record the claiming worker and a lease
//! deadline, must not hand a leased job to a second worker, and must let a
//! third worker reclaim the job once the lease has expired — otherwise a
//! crashed worker strands its job in `running` forever.
//!
//! The tests are timing-safe: an "expired lease" is produced by claiming with
//! a zero-length lease window (`with_lease(Duration::ZERO)`), never by
//! sleeping. All writes go through the public `AiImportQueue` API; the only
//! raw SQL is the read-back of the two claim-metadata columns, which are
//! deliberately not part of the `AiImportJob` view (same rationale as
//! `ai_import_queue_telemetry.rs`).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
mod fixtures;

use std::time::Duration;

use anyhow::Result;
use breakdown_core::ai::{
    AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJobId, AiImportQueue, DocumentKind,
    JobStatus,
};
use breakdown_core::shared::UserId;
use chrono::{DateTime, Utc};
use infra::ai::PgAiImportQueue;
use sqlx::PgPool;

/// Seed a job row through the public `enqueue` API and return its id.
async fn seed_job(
    queue: &PgAiImportQueue,
    user: &str,
    dedup: &str,
    kind: DocumentKind,
) -> AiImportJobId {
    let id = AiImportJobId::new();
    let result = queue
        .enqueue(AiImportEnqueueRequest {
            id,
            user_id: UserId::from_sub(user),
            document_kind: kind,
            block_id: None,
            dedup_key: dedup.to_owned(),
            document_digest: "digest".to_owned(),
            source_handle: "handle".to_owned(),
        })
        .await
        .unwrap();
    match result {
        AiImportEnqueueResult::Enqueued(id) | AiImportEnqueueResult::Existing(id) => id,
    }
}

/// Read back the claim metadata. Kept as raw SQL on purpose: `worker_id` and
/// `lease_expires_at` are operational claim bookkeeping and are not exposed on
/// the `AiImportJob` view.
async fn read_claim(pool: &PgPool, id: AiImportJobId) -> (Option<String>, Option<DateTime<Utc>>) {
    sqlx::query_as(
        r#"
        SELECT worker_id, lease_expires_at
        FROM ai_import.ai_import_job
        WHERE id = $1
        "#,
    )
    .bind(id.as_uuid())
    .fetch_one(pool)
    .await
    .unwrap()
}

#[tokio::test]
async fn claim_records_worker_id_and_lease_expiry() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone()).with_lease(Duration::from_secs(900));
    let id = seed_job(&queue, "lease-user", "lease-claim", DocumentKind::Script).await;

    let claimed = queue.claim_next("worker-a").await?.expect("job claimable");
    assert_eq!(claimed.id, id);
    assert_eq!(claimed.status, JobStatus::Running);

    let (worker_id, lease_expires_at) = read_claim(&pool, id).await;
    assert_eq!(
        worker_id.as_deref(),
        Some("worker-a"),
        "a claim must record its owner"
    );
    let lease = lease_expires_at.expect("a claim must set a lease deadline");
    assert!(
        lease > Utc::now(),
        "a fresh 900s lease must not already be expired"
    );
    Ok(())
}

#[tokio::test]
async fn unexpired_lease_blocks_a_second_worker() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone()).with_lease(Duration::from_secs(900));
    let id = seed_job(&queue, "lease-user", "lease-block", DocumentKind::Script).await;

    let first = queue.claim_next("worker-a").await?.expect("job claimable");
    assert_eq!(first.id, id);

    assert!(
        queue.claim_next("worker-b").await?.is_none(),
        "a running job with a live lease must never be handed to a second worker"
    );

    let (worker_id, _) = read_claim(&pool, id).await;
    assert_eq!(
        worker_id.as_deref(),
        Some("worker-a"),
        "the losing worker must not overwrite the owner"
    );
    Ok(())
}

#[tokio::test]
async fn expired_lease_is_reclaimed_by_another_worker() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    // A zero-length lease is already expired when the claim commits — this is
    // the deterministic stand-in for "worker-a crashed", with no sleeping.
    let crashing = PgAiImportQueue::new(pool.clone()).with_lease(Duration::ZERO);
    let recovering = PgAiImportQueue::new(pool.clone()).with_lease(Duration::from_secs(900));
    let id = seed_job(
        &crashing,
        "lease-user",
        "lease-reclaim",
        DocumentKind::Script,
    )
    .await;

    let first = crashing.claim_next("worker-a").await?.expect("claimable");
    assert_eq!(first.id, id);

    let reclaimed = recovering
        .claim_next("worker-b")
        .await?
        .expect("an expired lease must make the job claimable again");
    assert_eq!(reclaimed.id, id, "recovery must reclaim the same job");

    let (worker_id, lease_expires_at) = read_claim(&pool, id).await;
    assert_eq!(
        worker_id.as_deref(),
        Some("worker-b"),
        "reclaim must transfer ownership"
    );
    assert!(
        lease_expires_at.expect("reclaim renews the lease") > Utc::now(),
        "reclaim must install a fresh, unexpired lease"
    );
    Ok(())
}

#[tokio::test]
async fn claim_next_kind_applies_the_same_lease_semantics() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let crashing = PgAiImportQueue::new(pool.clone()).with_lease(Duration::ZERO);
    let live = PgAiImportQueue::new(pool.clone()).with_lease(Duration::from_secs(900));
    let id = seed_job(&crashing, "kind-user", "kind-lease", DocumentKind::Schedule).await;

    let first = crashing
        .claim_next_kind("worker-a", DocumentKind::Schedule)
        .await?
        .expect("claimable");
    assert_eq!(first.id, id);

    assert!(
        live.claim_next_kind("worker-b", DocumentKind::Script)
            .await?
            .is_none(),
        "the kind filter must still apply to expired-lease recovery"
    );

    let reclaimed = live
        .claim_next_kind("worker-b", DocumentKind::Schedule)
        .await?
        .expect("expired lease must be reclaimable by the matching kind");
    assert_eq!(reclaimed.id, id);

    assert!(
        live.claim_next_kind("worker-c", DocumentKind::Schedule)
            .await?
            .is_none(),
        "the renewed lease must block the next worker"
    );
    Ok(())
}

#[tokio::test]
async fn pending_and_retryable_failed_jobs_remain_claimable() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone()).with_lease(Duration::from_secs(900));
    let id = seed_job(&queue, "retry-user", "retry-lease", DocumentKind::Script).await;

    // Pending is claimable (baseline preserved by the new predicate).
    assert_eq!(
        queue.claim_next("worker-a").await?.map(|job| job.id),
        Some(id)
    );

    // A retryable failure releases the claim and schedules a backoff.
    queue.mark_failed(id, "transient upstream", true).await?;
    let (worker_id, lease_expires_at) = read_claim(&pool, id).await;
    assert_eq!(worker_id, None, "a failed job must hold no claim");
    assert_eq!(
        lease_expires_at, None,
        "a failed job must hold no lease, so reclaim cannot resurrect it early"
    );

    // Backoff not yet due → not claimable.
    assert!(
        queue.claim_next("worker-b").await?.is_none(),
        "a backing-off failed job must not be claimable before next_attempt_at"
    );

    // Make the backoff due through the public schema contract, then re-claim.
    sqlx::query(
        r#"
        UPDATE ai_import.ai_import_job
        SET next_attempt_at = now() - interval '1 minute'
        WHERE id = $1
        "#,
    )
    .bind(id.as_uuid())
    .execute(&pool)
    .await?;

    let retried = queue
        .claim_next("worker-b")
        .await?
        .expect("a due retryable failure must be claimable");
    assert_eq!(retried.id, id);
    assert_eq!(retried.retries, 1);
    Ok(())
}

#[tokio::test]
async fn success_releases_the_claim() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone()).with_lease(Duration::ZERO);
    let id = seed_job(&queue, "done-user", "done-lease", DocumentKind::Script).await;

    queue.claim_next("worker-a").await?.expect("claimable");
    queue.mark_succeeded(id, "preview-handle").await?;

    let (worker_id, lease_expires_at) = read_claim(&pool, id).await;
    assert_eq!(worker_id, None, "a succeeded job must hold no claim");
    assert_eq!(lease_expires_at, None, "a succeeded job must hold no lease");

    assert!(
        queue.claim_next("worker-b").await?.is_none(),
        "a succeeded job must never be reclaimed, even with a zero lease window"
    );
    Ok(())
}
