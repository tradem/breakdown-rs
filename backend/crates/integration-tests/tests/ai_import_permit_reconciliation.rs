// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (pi)
// Co-authored-by: longcat-2.0-free (pi)
// Co-authored-by: longcat-2.0-free (opencode)

//! Permit reconciliation contract for the AI import queue (issue #180).
//!
//! Issues #177 and #178 delivered the two leases this design rests on: a
//! job-scoped worker lease on `ai_import_job`, and a permit-scoped lease on
//! `ai_import.concurrency_permit`. What they did *not* close is the gap
//! between them.
//!
//! When a worker dies mid-job, its **job** lease expires first, and another
//! worker reclaims the job. But the dead worker's **permit** row survives
//! until its own lease lapses — up to `AI_IMPORT_LEASE_SECS` (900s by default)
//! of capacity consumed by a job that is already running somewhere else. The
//! global and per-user ceilings are inflated for the whole window.
//!
//! `claim_next_reconciling` closes that gap: the reclaiming worker reads the
//! orphaned `permit_id` recorded on the job and deletes that permit row
//! **inside the same statement** that flips the job to itself. Reconciliation
//! is exactly-once because only the worker that wins the `FOR UPDATE SKIP
//! LOCKED` race ever observes a non-null orphan id, and the DELETE is by
//! primary key.
//!
//! ## The claim-then-acquire order
//!
//! Capacity is acquired *after* the claim, not before, and linked back with
//! `attach_permit`. Two properties depend on that order and are asserted here:
//!
//! * the permit is charged to `job.user_id` — the user whose work it is — so
//!   the per-user ceiling actually binds. Acquiring first would mean acquiring
//!   before the owning user is known;
//! * the orphan is freed *before* the acquisition, so a reclaiming worker is
//!   not refused the very slot the dead worker is still holding. At a
//!   saturated ceiling the reverse order deadlocks the job permanently.
//!
//! ## Why these tests do not expire the *permit* lease
//!
//! `PgAiConcurrencyLimiter::try_acquire_as` sweeps expired permits before it
//! counts. Expiring the orphan's permit would let the *sweep* free it, and the
//! reclaim would find nothing to release — the tests would pass while
//! asserting nothing about the code under test. These tests expire only the
//! **job** lease and keep the orphaned permit live, which is precisely the
//! production failure mode: capacity held by a dead worker inside its lease
//! window.
//!
//! The tests are timing-safe: lease expiry is written into the past, never
//! slept out.

// Test-only lint suppressions: an unmet expectation must abort the test rather
// than be threaded through a Result.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

mod fixtures;

use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use anyhow::Result;
use async_trait::async_trait;
use breakdown_core::ai::{
    AiImportBounds, AiImportQueue, LlmChatRequest, LlmClient, LlmProvider, ScriptContext,
};
use breakdown_core::error::DomainError;
use infra::ai::{
    AiDocumentSource, MemoryAiPreviewStore, PgAiConcurrencyLimiter, PgAiImportQueue,
    ScheduleImportWorker,
};
use sqlx::PgPool;
use tokio::sync::Notify;
use uuid::Uuid;

/// Force a job's worker lease into the past, simulating a worker that died
/// without completing or releasing the job. The worker's *permit* is left live
/// on purpose — see the module docs.
async fn expire_job_lease(pool: &PgPool, job_id: Uuid) {
    sqlx::query(
        "UPDATE ai_import.ai_import_job \
         SET lease_expires_at = now() - interval '1 second' WHERE id = $1",
    )
    .bind(job_id)
    .execute(pool)
    .await
    .unwrap();
}

/// Seed one runnable job owned by `user_id`. The schema already exists:
/// `spawn_postgres` runs the full migration set.
async fn seed_pending_job(pool: &PgPool, user_id: &str) -> Result<Uuid> {
    seed_pending_job_of_kind(pool, user_id, "script").await
}

async fn seed_pending_job_of_kind(pool: &PgPool, user_id: &str, kind: &str) -> Result<Uuid> {
    let id = Uuid::now_v7();
    sqlx::query(
        r#"
        INSERT INTO ai_import.ai_import_job
            (id, user_id, document_kind, dedup_key, document_digest, source_handle,
             status, retries, max_retries, created_at, updated_at)
        VALUES ($1, $2, $3, $4, 'test-digest', 'test-source',
                'pending', 0, 5, now(), now())
        "#,
    )
    .bind(id)
    .bind(user_id)
    .bind(kind)
    .bind(id.to_string())
    .execute(pool)
    .await?;
    Ok(id)
}

/// A source that counts fetches, so a test can prove the document was never
/// loaded when capacity was refused.
#[derive(Default)]
struct CountingSource {
    loads: AtomicUsize,
}

impl CountingSource {
    fn loads(&self) -> usize {
        self.loads.load(Ordering::Acquire)
    }
}

#[async_trait]
impl AiDocumentSource for CountingSource {
    async fn load(&self, _handle: &str) -> Result<Vec<u8>, DomainError> {
        self.loads.fetch_add(1, Ordering::AcqRel);
        Ok(b"scene_number,shooting_day_label\n1,T1\n".to_vec())
    }
}

/// A source that blocks inside `load` until the test releases it, so the test
/// can observe database state *while* the worker is mid-run.
///
/// Deterministic by construction: the test waits on `entered` for the worker
/// to arrive, and the worker waits on `release` for the test to finish
/// observing. Neither side sleeps, so there is no wall-clock budget to bust on
/// a slow runner.
struct GatedSource {
    entered: Arc<Notify>,
    release: Arc<Notify>,
}

#[async_trait]
impl AiDocumentSource for GatedSource {
    async fn load(&self, _handle: &str) -> Result<Vec<u8>, DomainError> {
        self.entered.notify_one();
        self.release.notified().await;
        Ok(b"scene_number,shooting_day_label\n1,T1\n".to_vec())
    }
}

/// An LLM client that must never be called: the schedule worker runs in
/// `native_csv` mode, which parses in-process.
struct UnusedLlmClient;

#[async_trait]
impl LlmClient for UnusedLlmClient {
    async fn chat_constrained(
        &self,
        _request: LlmChatRequest,
    ) -> Result<ScriptContext, DomainError> {
        Err(DomainError::ValidationError(
            "the LLM must not be reached in native_csv mode".to_owned(),
        ))
    }
}

/// A schedule worker in native-CSV mode: no subprocess (`pdftotext`) and no
/// LLM call, so the test stays hermetic and deterministic.
fn schedule_worker(
    queue: Arc<PgAiImportQueue>,
) -> ScheduleImportWorker<PgAiImportQueue, UnusedLlmClient, MemoryAiPreviewStore> {
    ScheduleImportWorker {
        queue,
        client: Arc::new(UnusedLlmClient),
        previews: Arc::new(MemoryAiPreviewStore::default()),
        provider: LlmProvider::Neuralwatt,
        model: "unused".to_owned(),
        prompt: "unused".to_owned(),
        bounds: AiImportBounds::default(),
    }
}

/// Live permits, i.e. the global counter the ceiling is checked against.
async fn permit_count(pool: &PgPool) -> i64 {
    sqlx::query_scalar("SELECT COUNT(*) FROM ai_import.concurrency_permit")
        .fetch_one(pool)
        .await
        .unwrap()
}

/// Live permits for one user, i.e. the per-user counter.
async fn permit_count_for_user(pool: &PgPool, user_id: &str) -> i64 {
    sqlx::query_scalar("SELECT COUNT(*) FROM ai_import.concurrency_permit WHERE user_id = $1")
        .bind(user_id)
        .fetch_one(pool)
        .await
        .unwrap()
}

/// The `user_id` a permit is charged to.
async fn permit_owner(pool: &PgPool, permit_id: Uuid) -> Option<String> {
    sqlx::query_scalar("SELECT user_id FROM ai_import.concurrency_permit WHERE id = $1")
        .bind(permit_id)
        .fetch_optional(pool)
        .await
        .unwrap()
}

/// The permit currently recorded as owning a job's claim.
async fn job_permit_id(pool: &PgPool, job_id: Uuid) -> Option<Uuid> {
    sqlx::query_scalar("SELECT permit_id FROM ai_import.ai_import_job WHERE id = $1")
        .bind(job_id)
        .fetch_one(pool)
        .await
        .unwrap()
}

/// `(status, retries)` — used to prove a returned claim is not charged a retry.
async fn job_state(pool: &PgPool, job_id: Uuid) -> (String, i32) {
    sqlx::query_as("SELECT status, retries FROM ai_import.ai_import_job WHERE id = $1")
        .bind(job_id)
        .fetch_one(pool)
        .await
        .unwrap()
}

/// Issue #180 AC: "Recovery decrements the applicable global and per-user
/// counters exactly once."
///
/// Worker A claims a job and dies inside its permit lease. Worker B reclaims
/// the job; the global counter must fall back to one live permit (B's), not
/// stay at two until A's lease lapses.
#[tokio::test]
async fn reclaim_releases_the_orphaned_permit_exactly_once() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;
    let limiter = PgAiConcurrencyLimiter::new(pool.clone(), 2, 2)?;
    let queue = PgAiImportQueue::new(pool.clone());

    let job_id = seed_pending_job(&pool, "test-user").await?;
    assert_eq!(permit_count(&pool).await, 0, "clean slate: no permits");

    // Worker A: claim, then acquire capacity for the job's own user.
    let (job, released_a) = queue
        .claim_next_reconciling("worker-a")
        .await?
        .expect("seeded job is claimable");
    assert_eq!(job.id.as_uuid(), job_id, "claimed the seeded job");
    assert_eq!(released_a, None, "fresh claim has no orphan to release");

    let permit_a = limiter
        .try_acquire_as(job.user_id.as_str(), "worker-a")
        .await?
        .expect("slot available for worker-a");
    queue
        .attach_permit(job.id, "worker-a", permit_a.id())
        .await?;
    assert_eq!(
        job_permit_id(&pool, job_id).await,
        Some(permit_a.id()),
        "the permit is linked to the claim"
    );
    assert_eq!(permit_count(&pool).await, 1);

    // Worker A dies. Its job lease is expired; its permit is still live and
    // still consuming a slot — the leak this change exists to close.
    expire_job_lease(&pool, job_id).await;
    assert_eq!(
        permit_count(&pool).await,
        1,
        "the dead worker's permit is still counted before the reclaim"
    );

    // Worker B reclaims. The orphan is released by the claim itself.
    let (job_b, released_b) = queue
        .claim_next_reconciling("worker-b")
        .await?
        .expect("the expired job is reclaimable");
    assert_eq!(job_b.id.as_uuid(), job_id, "reclaimed the same job");
    assert_eq!(
        released_b,
        Some(permit_a.id()),
        "the reclaim reports the orphan it released"
    );
    assert_eq!(
        permit_count(&pool).await,
        0,
        "the orphan is gone; capacity is free before worker-b acquires"
    );
    assert_eq!(
        job_permit_id(&pool, job_id).await,
        None,
        "the stale permit link is cleared by the same statement"
    );

    let permit_b = limiter
        .try_acquire_as(job_b.user_id.as_str(), "worker-b")
        .await?
        .expect("capacity freed by the reclaim");
    assert_ne!(permit_a.id(), permit_b.id(), "distinct permit ids");
    queue
        .attach_permit(job_b.id, "worker-b", permit_b.id())
        .await?;
    assert_eq!(
        permit_count(&pool).await,
        1,
        "exactly one live permit after recovery, not two"
    );

    Ok(())
}

/// Issue #180 AC: "Expired `running` jobs become retryable without duplicate
/// recovery."
///
/// A reclaim whose recorded orphan was already freed by the other recovery
/// path (the permit lease sweep) must be a no-op on the counter — never a
/// second decrement charged to an unrelated permit.
#[tokio::test]
async fn reclaim_of_an_already_freed_orphan_does_not_double_decrement() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;
    let limiter = PgAiConcurrencyLimiter::new(pool.clone(), 2, 2)?;
    let queue = PgAiImportQueue::new(pool.clone());

    let job_id = seed_pending_job(&pool, "test-user").await?;

    let (job, _) = queue
        .claim_next_reconciling("worker-a")
        .await?
        .expect("job claimable");
    let permit_a = limiter
        .try_acquire_as(job.user_id.as_str(), "worker-a")
        .await?
        .expect("slot available");
    queue
        .attach_permit(job.id, "worker-a", permit_a.id())
        .await?;
    expire_job_lease(&pool, job_id).await;

    // Worker A's permit is freed by the *other* recovery path before anyone
    // reclaims the job — what the lease sweep in `try_acquire_as` does once
    // the permit lease lapses.
    sqlx::query("DELETE FROM ai_import.concurrency_permit WHERE id = $1")
        .bind(permit_a.id())
        .execute(&pool)
        .await?;
    assert_eq!(permit_count(&pool).await, 0, "the orphan is already gone");

    // Worker B reclaims. The job still records worker-a's permit id, but that
    // row no longer exists, so the DELETE must match nothing.
    let (_, released_b) = queue
        .claim_next_reconciling("worker-b")
        .await?
        .expect("job reclaimable");
    assert_eq!(
        released_b, None,
        "nothing to release: the orphan was already freed"
    );
    assert_eq!(
        permit_count(&pool).await,
        0,
        "no extra row was deleted by the redundant reclaim"
    );

    Ok(())
}

/// Issue #180 AC: the reconciliation is charged to the *owning* user, so the
/// per-user ceiling recovers too — not just the global one.
///
/// This is the property that claim-then-acquire buys: the permit carries the
/// job's `user_id`, not the worker's identity.
#[tokio::test]
async fn reclaim_reconciles_the_owning_users_counter() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;
    // Per-user ceiling of 1 makes the assertion sharp: user-a can only acquire
    // again if their orphan was genuinely released.
    let limiter = PgAiConcurrencyLimiter::new(pool.clone(), 4, 1)?;
    let queue = PgAiImportQueue::new(pool.clone());

    let job_id = seed_pending_job(&pool, "user-a").await?;

    // A worker claims user-a's job. The permit must be charged to user-a even
    // though the worker is called "worker-a".
    let (job, _) = queue
        .claim_next_reconciling("worker-a")
        .await?
        .expect("job claimable");
    let permit_a = limiter
        .try_acquire_as(job.user_id.as_str(), "worker-a")
        .await?
        .expect("slot available");
    queue
        .attach_permit(job.id, "worker-a", permit_a.id())
        .await?;
    assert_eq!(
        permit_owner(&pool, permit_a.id()).await.as_deref(),
        Some("user-a"),
        "the permit is charged to the job's user, not the worker identity"
    );
    assert_eq!(permit_count_for_user(&pool, "user-a").await, 1);

    // user-a is at their ceiling: no second job of theirs can start.
    assert!(
        limiter
            .try_acquire_as("user-a", "worker-x")
            .await?
            .is_none(),
        "user-a's per-user ceiling binds while their permit is live"
    );

    // The worker dies; another one takes the job over.
    expire_job_lease(&pool, job_id).await;
    let (job_b, released_b) = queue
        .claim_next_reconciling("worker-b")
        .await?
        .expect("job reclaimable");
    assert_eq!(released_b, Some(permit_a.id()), "user-a's orphan released");
    assert_eq!(
        permit_count_for_user(&pool, "user-a").await,
        0,
        "user-a's per-user counter is back to zero"
    );

    // The recovered slot is genuinely usable again, not merely uncounted, and
    // the new permit is charged to user-a as well.
    let permit_b = limiter
        .try_acquire_as(job_b.user_id.as_str(), "worker-b")
        .await?
        .expect("user-a's capacity is usable again right after the reclaim");
    assert_eq!(
        permit_owner(&pool, permit_b.id()).await.as_deref(),
        Some("user-a"),
        "the reclaiming worker also charges the job's user"
    );
    assert_eq!(permit_count_for_user(&pool, "user-a").await, 1);

    Ok(())
}

/// Issue #180 AC: "Counter updates and job transitions are transactional."
///
/// For a job that is not claimable, nothing at all happens: no job is
/// returned and no permit is released.
#[tokio::test]
async fn no_claimable_job_means_no_permit_is_released() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;
    let limiter = PgAiConcurrencyLimiter::new(pool.clone(), 2, 2)?;
    let queue = PgAiImportQueue::new(pool.clone());

    let job_id = seed_pending_job(&pool, "test-user").await?;

    // Worker A claims the job and keeps a *live* lease: nothing is reclaimable.
    let (job, _) = queue
        .claim_next_reconciling("worker-a")
        .await?
        .expect("job claimable");
    let permit_a = limiter
        .try_acquire_as(job.user_id.as_str(), "worker-a")
        .await?
        .expect("slot available");
    queue
        .attach_permit(job.id, "worker-a", permit_a.id())
        .await?;

    assert!(
        queue.claim_next_reconciling("worker-b").await?.is_none(),
        "a live lease is not reclaimable, so no job is returned"
    );
    assert_eq!(
        job_permit_id(&pool, job_id).await,
        Some(permit_a.id()),
        "the healthy worker still owns the job"
    );
    assert_eq!(
        permit_count(&pool).await,
        1,
        "no permit was released by the failed claim attempt"
    );

    Ok(())
}

/// A worker that cannot get capacity must hand the claim back unrun: the job
/// is immediately runnable again, is **not** charged a retry, and the source
/// document is never even fetched.
///
/// This drives the real `run_once_with_permit` entry point against a limiter
/// whose only slot is already taken, rather than calling `release_claim`
/// directly — the point is that the *worker* takes this path, not merely that
/// the queue method works.
#[tokio::test]
async fn a_saturated_ceiling_returns_the_claim_unrun_and_uncharged() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;
    // One slot per user, and it is about to be occupied.
    let limiter = PgAiConcurrencyLimiter::new(pool.clone(), 4, 1)?;
    let queue = Arc::new(PgAiImportQueue::new(pool.clone()));

    let job_id = seed_pending_job_of_kind(&pool, "user-a", "schedule").await?;

    // Occupy user-a's only slot with an unrelated holder.
    let blocker = limiter
        .try_acquire_as("user-a", "other-worker")
        .await?
        .expect("the single per-user slot is free to begin with");

    let source = CountingSource::default();
    let worker = schedule_worker(Arc::clone(&queue));
    let ran = worker
        .run_once_with_permit("worker-a", &source, true, &limiter)
        .await?;

    assert!(!ran, "no job runs when the ceiling is saturated");
    assert_eq!(
        source.loads(),
        0,
        "the source document is never fetched without capacity"
    );

    let (status, retries) = job_state(&pool, job_id).await;
    assert_eq!(status, "pending", "the claim was handed back, not held");
    assert_eq!(retries, 0, "an unrun claim is not charged an attempt");
    assert_eq!(
        job_permit_id(&pool, job_id).await,
        None,
        "no permit is left linked to a returned claim"
    );
    assert_eq!(
        permit_count(&pool).await,
        1,
        "only the blocker's permit exists; the worker acquired none"
    );

    // With capacity free again the same job runs — it was never penalised.
    blocker.release().await?;
    let ran = worker
        .run_once_with_permit("worker-a", &source, true, &limiter)
        .await?;
    assert!(ran, "the returned job runs once capacity is available");
    assert_eq!(source.loads(), 1, "now the source is actually fetched");
    assert_eq!(
        permit_count(&pool).await,
        0,
        "the worker released its permit on completion"
    );
    let (status, _) = job_state(&pool, job_id).await;
    assert_eq!(status, "succeeded", "the job ran to completion");

    Ok(())
}

/// The happy path links the permit to the claim **while the job is running**,
/// so a crash of this worker would be recoverable by the next reclaim.
///
/// Asserting only the end state would prove nothing: the worker releases its
/// permit on completion, so `permit_count == 0` afterwards is equally
/// consistent with `attach_permit` never having written anything. The test
/// therefore stops the worker inside `source.load` — after acquisition and
/// attachment, before completion — and observes the link directly.
#[tokio::test]
async fn a_running_worker_links_its_permit_to_the_claim() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;
    let limiter = PgAiConcurrencyLimiter::new(pool.clone(), 4, 4)?;
    let queue = Arc::new(PgAiImportQueue::new(pool.clone()));

    let job_id = seed_pending_job_of_kind(&pool, "user-a", "schedule").await?;

    let entered = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    // Signalled when the worker returns, however it returns. Without it, an
    // early exit — a failed claim, a refused acquisition, a rejected
    // `attach_permit` — would never reach `source.load`, `entered` would never
    // fire, and the observer would wait forever: the test would hang instead
    // of reporting the failure.
    let finished = Arc::new(Notify::new());
    let source = GatedSource {
        entered: Arc::clone(&entered),
        release: Arc::clone(&release),
    };
    let worker = schedule_worker(Arc::clone(&queue));

    let observer_pool = pool.clone();
    let run = async {
        let outcome = worker
            .run_once_with_permit("worker-a", &source, true, &limiter)
            .await;
        finished.notify_one();
        outcome
    };
    let observe = async {
        // Whichever comes first: the worker reaching the gated load (the
        // expected path — by then it has claimed, acquired and attached), or
        // the worker returning early without ever getting there.
        tokio::select! {
            () = entered.notified() => {}
            () = finished.notified() => return None,
        }

        let linked = job_permit_id(&observer_pool, job_id).await;
        let live: Option<Uuid> = sqlx::query_scalar("SELECT id FROM ai_import.concurrency_permit")
            .fetch_optional(&observer_pool)
            .await
            .unwrap();
        let owner = permit_count_for_user(&observer_pool, "user-a").await;
        let (status, _) = job_state(&observer_pool, job_id).await;

        release.notify_one();
        Some((linked, live, owner, status))
    };
    let (ran, observed) = tokio::join!(run, observe);

    // Surface the worker's own error first: it explains an early exit far
    // better than "the observer saw nothing" would.
    assert!(ran?, "the seeded job runs");
    let (linked, live, owner, status) =
        observed.expect("the worker reached the gated load rather than exiting early");
    assert_eq!(status, "running", "observed while the job was in flight");
    assert!(
        linked.is_some(),
        "attach_permit linked a permit to the claim during the run"
    );
    assert_eq!(
        linked, live,
        "the link points at the permit the worker actually holds"
    );
    assert_eq!(
        owner, 1,
        "the in-flight permit is charged to the job's user, not the worker id"
    );

    // And it is all cleaned up on completion.
    assert_eq!(permit_count(&pool).await, 0, "the permit was released");
    assert_eq!(
        job_permit_id(&pool, job_id).await,
        None,
        "the terminal write clears the permit link"
    );
    let (status, retries) = job_state(&pool, job_id).await;
    assert_eq!(status, "succeeded");
    assert_eq!(retries, 0);

    Ok(())
}

/// `attach_permit` and `release_claim` are owner-fenced: a worker that lost
/// its claim must not be able to overwrite the new owner's permit link or
/// yank the job out from under them.
#[tokio::test]
async fn lifecycle_writes_are_owner_fenced() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;
    let limiter = PgAiConcurrencyLimiter::new(pool.clone(), 4, 4)?;
    let queue = PgAiImportQueue::new(pool.clone());

    let job_id = seed_pending_job(&pool, "user-a").await?;

    // Worker A claims and is then displaced by worker B.
    let (job, _) = queue
        .claim_next_reconciling("worker-a")
        .await?
        .expect("job claimable");
    expire_job_lease(&pool, job_id).await;
    let (job_b, _) = queue
        .claim_next_reconciling("worker-b")
        .await?
        .expect("job reclaimable");

    let permit_b = limiter
        .try_acquire_as(job_b.user_id.as_str(), "worker-b")
        .await?
        .expect("slot available");
    queue
        .attach_permit(job_b.id, "worker-b", permit_b.id())
        .await?;

    // The displaced worker must not overwrite the new owner's link: doing so
    // would make a later reclaim delete a *live* permit.
    let stale_permit = limiter
        .try_acquire_as("user-a", "worker-a")
        .await?
        .expect("slot available");
    assert!(
        queue
            .attach_permit(job.id, "worker-a", stale_permit.id())
            .await
            .is_err(),
        "a displaced worker cannot relink the permit"
    );
    assert_eq!(
        job_permit_id(&pool, job_id).await,
        Some(permit_b.id()),
        "the new owner's link survives the stale write"
    );

    // Nor can it hand back a claim it no longer holds.
    assert!(
        queue.release_claim(job.id, "worker-a").await.is_err(),
        "a displaced worker cannot release the new owner's claim"
    );
    let (status, _) = job_state(&pool, job_id).await;
    assert_eq!(status, "running", "the new owner still holds the job");

    stale_permit.release().await?;
    Ok(())
}
