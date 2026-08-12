// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0-free (opencode)
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Per-payload cleanup-state contract for the AI payload GC sweep (issue
//! #206).
//!
//! The retention policy itself — which statuses are terminal, and how the age
//! window is applied — is covered by `ai_payload_restart_recovery.rs`. This
//! file asserts the orthogonal property that makes the sweep *make progress*:
//!
//! 1. **A cleaned payload is not cleaned again.** Before the completion marks,
//!    every run re-selected the oldest `batch_size` terminal jobs. Deletions
//!    are idempotent, so nothing was corrupted and no test failed — the damage
//!    was that the run-history counters re-counted the same deletions and any
//!    job behind the `LIMIT` could outlive its retention window forever.
//! 2. **Only what actually got deleted is marked.** A failed deletion, and
//!    every payload in a dry run, must leave no mark: a mark is what hides a
//!    payload from all future sweeps, so recording one for an object still
//!    sitting in Garage converts a transient error (or an observation run)
//!    into a permanent leak.
//! 3. **The two payloads are tracked independently.** A sweep that deleted the
//!    source but failed on the preview must come back for the preview alone.
//!
//! Two container tiers are used deliberately:
//!
//! * Tests that need a *successful* deletion run against real Garage, because
//!   the mark is written from the storage result and a fake would assert the
//!   test's own assumption.
//! * Tests of the *selection* predicate are Postgres-only: they seed a mark
//!   and assert what the next sweep declines to select, which involves no
//!   storage call at all. This keeps the fast tier fast.
//!
//! Timing-safe throughout: ages come from backdating `updated_at` in SQL by 30
//! days against a 1-day window, never from sleeping.

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
    SourceFormat,
};
use breakdown_core::error::DomainError;
use fixtures::{GarageCredentials, spawn_garage, spawn_postgres};
use infra::ai::payload_cleanup::{AiPayloadGcConfig, run_gc_sweep};
use infra::ai::{AiDocumentStore, AiPreviewStore, OpenDalAiPayloadStorage, PgAiImportQueue};
use sqlx::{PgPool, Row};

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// Seed a job through the public `enqueue` API and return its id.
async fn seed_job(queue: &PgAiImportQueue, dedup: &str) -> AiImportJobId {
    let id = AiImportJobId::new();
    let result = queue
        .enqueue(AiImportEnqueueRequest {
            id,
            user_id: breakdown_core::shared::UserId::from_sub("payload-gc-user"),
            document_kind: DocumentKind::Script,
            source_format: SourceFormat::Pdf,
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

/// Drive a freshly enqueued job to `succeeded`, the terminal state that owns
/// *both* a source and a preview payload.
async fn succeed(queue: &PgAiImportQueue, worker: &str, id: AiImportJobId) -> String {
    let preview_handle = format!("ai-import/{}/preview", id.as_uuid());
    queue.claim_next(worker).await.unwrap().expect("claimable");
    queue
        .mark_succeeded(id, worker, &preview_handle)
        .await
        .unwrap();
    preview_handle
}

/// Order two already-backdated jobs so `first` is swept before `second`.
///
/// The sweep orders by `updated_at`, and two jobs backdated by the same
/// interval can tie. Deliberately raw SQL for the same reason as [`backdate`]:
/// no public API moves `updated_at`, and the alternative (sleeping between the
/// two writes) is both slow and forbidden by the deterministic-test rule.
async fn order_before(pool: &PgPool, first: AiImportJobId, second: AiImportJobId) {
    sqlx::query(
        r#"
        UPDATE ai_import.ai_import_job
        SET updated_at = CASE WHEN id = $1
                              THEN now() - interval '31 days'
                              ELSE now() - interval '30 days'
                         END
        WHERE id IN ($1, $2)
        "#,
    )
    .bind(first.as_uuid())
    .bind(second.as_uuid())
    .execute(pool)
    .await
    .unwrap();
}

/// Backdate a job past the retention window used here (1 day) by a margin that
/// dwarfs any container clock skew.
///
/// Deliberately raw SQL: `updated_at` is maintained by the queue adapter and no
/// public API can move it. Sleeping out the window is forbidden by the
/// deterministic-test rule.
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

/// GC config with a 1-day retention window that actually deletes.
fn deleting_config() -> AiPayloadGcConfig {
    AiPayloadGcConfig {
        enabled: true,
        interval_secs: 3600,
        max_age_secs: 86_400,
        batch_size: 1000,
        dry_run: false,
    }
}

/// The same window in dry-run mode.
fn dry_run_config() -> AiPayloadGcConfig {
    AiPayloadGcConfig {
        dry_run: true,
        ..deleting_config()
    }
}

/// Storage handle pointed at an unroutable endpoint.
///
/// Used by two kinds of test: dry runs (which never touch storage) and the
/// failed-deletion case, where an unreachable endpoint is the simplest honest
/// way to make every delete fail.
fn unreachable_storage() -> OpenDalAiPayloadStorage {
    OpenDalAiPayloadStorage::new(
        "http://127.0.0.1:1".to_owned(),
        "unused".to_owned(),
        "unused".to_owned(),
        "unused".to_owned(),
        None,
    )
}

fn garage_storage(creds: &GarageCredentials) -> OpenDalAiPayloadStorage {
    OpenDalAiPayloadStorage::new(
        creds.endpoint.clone(),
        creds.access_key.clone(),
        creds.secret_key.clone(),
        creds.bucket.clone(),
        None,
    )
}

/// Counters of the most recent sweep.
struct SweepHistory {
    scanned: i64,
    source_deleted: i64,
    preview_deleted: i64,
    errors: i64,
}

async fn last_sweep(pool: &PgPool) -> SweepHistory {
    let row = sqlx::query(
        r#"
        SELECT scanned, source_deleted, preview_deleted, errors
        FROM ai_import.projection_ai_payload_gc_run
        ORDER BY started_at DESC
        LIMIT 1
        "#,
    )
    .fetch_one(pool)
    .await
    .unwrap();
    SweepHistory {
        scanned: row.try_get("scanned").unwrap(),
        source_deleted: row.try_get("source_deleted").unwrap(),
        preview_deleted: row.try_get("preview_deleted").unwrap(),
        errors: row.try_get("errors").unwrap(),
    }
}

/// Completion marks for a job as `(payload_kind, handle)`, ordered by kind.
///
/// Deliberately raw SQL: the marks are adapter-internal retention bookkeeping
/// consumed by an anti-join, with no public read API.
async fn cleanup_marks(pool: &PgPool, id: AiImportJobId) -> Vec<(String, String)> {
    sqlx::query(
        r#"
        SELECT payload_kind, handle
        FROM ai_import.ai_payload_cleanup
        WHERE job_id = $1
        ORDER BY payload_kind
        "#,
    )
    .bind(id.as_uuid())
    .fetch_all(pool)
    .await
    .unwrap()
    .into_iter()
    .map(|row| {
        (
            row.try_get("payload_kind").unwrap(),
            row.try_get("handle").unwrap(),
        )
    })
    .collect()
}

/// Record a completion mark directly, standing in for an earlier successful
/// sweep.
///
/// Deliberately raw SQL, and deliberately *not* a real prior sweep: the
/// Postgres-only tests below have no object store, so a real deleting sweep
/// could not succeed there. Seeding the mark isolates the selection predicate
/// — the contract under test — from the storage round-trip, which the Garage
/// tests cover separately.
async fn seed_cleanup_mark(pool: &PgPool, id: AiImportJobId, kind: &str, handle: &str) {
    sqlx::query(
        r#"
        INSERT INTO ai_import.ai_payload_cleanup (job_id, payload_kind, handle, run_id)
        VALUES ($1, $2, $3, $4)
        "#,
    )
    .bind(id.as_uuid())
    .bind(kind)
    .bind(handle)
    .bind(uuid::Uuid::now_v7())
    .execute(pool)
    .await
    .unwrap();
}

// ---------------------------------------------------------------------------
// Selection predicate (Postgres-only)
// ---------------------------------------------------------------------------

/// The headline regression: a fully cleaned job disappears from the candidate
/// set instead of being re-selected on every sweep forever.
#[tokio::test]
async fn a_fully_cleaned_job_is_never_selected_again() -> Result<()> {
    let (pool, _pg) = spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());

    let id = seed_job(&queue, "gc-cleaned").await;
    let preview = succeed(&queue, "worker-a", id).await;
    let source = format!("ai-import/{}/source", id.as_uuid());
    backdate(&pool, id).await;

    seed_cleanup_mark(&pool, id, "source", &source).await;
    seed_cleanup_mark(&pool, id, "preview", &preview).await;

    // Dry run: selection is the whole contract here, and it happens before any
    // storage call.
    run_gc_sweep(&pool, &unreachable_storage(), &dry_run_config()).await?;

    assert_eq!(
        last_sweep(&pool).await.scanned,
        0,
        "a job whose payloads are both marked cleaned must not be re-selected \
         — re-selection is what made the counters inflate and starved jobs \
         behind the batch limit"
    );
    Ok(())
}

/// A partially cleaned job is still owed its other payload, and the sweep must
/// come back for exactly that one.
#[tokio::test]
async fn a_partially_cleaned_job_is_reselected_for_the_missing_payload_only() -> Result<()> {
    let (pool, _pg) = spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());

    let id = seed_job(&queue, "gc-partial").await;
    let _preview = succeed(&queue, "worker-a", id).await;
    let source = format!("ai-import/{}/source", id.as_uuid());
    backdate(&pool, id).await;

    // The source went; the preview deletion failed last time.
    seed_cleanup_mark(&pool, id, "source", &source).await;

    run_gc_sweep(&pool, &unreachable_storage(), &dry_run_config()).await?;

    let history = last_sweep(&pool).await;
    assert_eq!(
        history.scanned, 1,
        "a job still owing one payload must be re-selected"
    );
    assert_eq!(
        history.source_deleted, 0,
        "the already-cleaned source must not be re-deleted — re-counting it \
         is exactly the counter inflation issue #206 removes"
    );
    assert_eq!(
        history.preview_deleted, 1,
        "the outstanding preview must be the one payload acted on"
    );
    Ok(())
}

/// A job that never produced a preview owes only its source, and is done once
/// that is marked. `preview_handle` is written solely by `mark_succeeded`,
/// which needs a `running` claim no terminal status can return to — so the
/// NULL can never later become a handle.
#[tokio::test]
async fn a_job_without_a_preview_is_complete_once_its_source_is_marked() -> Result<()> {
    let (pool, _pg) = spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());

    let id = seed_job(&queue, "gc-no-preview").await;
    queue.claim_next("worker-a").await?.expect("claimable");
    // Non-retryable: dead-letters immediately, so no preview was ever stored.
    queue
        .mark_failed(id, "worker-a", "malformed document", false)
        .await?;
    backdate(&pool, id).await;

    let source = format!("ai-import/{}/source", id.as_uuid());
    seed_cleanup_mark(&pool, id, "source", &source).await;

    run_gc_sweep(&pool, &unreachable_storage(), &dry_run_config()).await?;

    assert_eq!(
        last_sweep(&pool).await.scanned,
        0,
        "a NULL preview_handle is not an outstanding payload; requiring a \
         preview mark would park this job in the candidate set forever"
    );
    Ok(())
}

/// A dry run must not mark anything. A mark hides the payload from every
/// future real sweep, so marking in observation mode would leak precisely the
/// objects the operator was trying to preview.
#[tokio::test]
async fn a_dry_run_records_no_marks() -> Result<()> {
    let (pool, _pg) = spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());

    let id = seed_job(&queue, "gc-dry-run").await;
    succeed(&queue, "worker-a", id).await;
    backdate(&pool, id).await;

    run_gc_sweep(&pool, &unreachable_storage(), &dry_run_config()).await?;

    let history = last_sweep(&pool).await;
    assert_eq!(history.scanned, 1, "the job is eligible");
    assert_eq!(
        history.source_deleted + history.preview_deleted,
        2,
        "a dry run still reports what it would have deleted"
    );
    assert!(
        cleanup_marks(&pool, id).await.is_empty(),
        "a dry run deletes nothing, so it must mark nothing — otherwise the \
         payload is hidden from every future real sweep while still in Garage"
    );

    // The proof that it is not hidden: a second sweep still sees it.
    run_gc_sweep(&pool, &unreachable_storage(), &dry_run_config()).await?;
    assert_eq!(last_sweep(&pool).await.scanned, 1);
    Ok(())
}

/// A failed deletion must leave no mark, so the payload is retried on the next
/// sweep. Marking on failure would strand the object permanently.
#[tokio::test]
async fn a_failed_deletion_records_no_mark_and_is_retried() -> Result<()> {
    let (pool, _pg) = spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());

    let id = seed_job(&queue, "gc-delete-fails").await;
    succeed(&queue, "worker-a", id).await;
    backdate(&pool, id).await;

    // Storage is unroutable: every delete fails.
    let result = run_gc_sweep(&pool, &unreachable_storage(), &deleting_config()).await;
    assert!(
        result.is_err(),
        "the sweep must surface the deletion failure to its scheduler"
    );

    let history = last_sweep(&pool).await;
    assert_eq!(history.scanned, 1);
    assert_eq!(history.source_deleted, 0);
    assert_eq!(history.preview_deleted, 0);
    assert_eq!(history.errors, 2, "both payloads failed");
    assert!(
        cleanup_marks(&pool, id).await.is_empty(),
        "nothing was deleted, so nothing may be marked"
    );

    // Still a candidate — which is the point of not marking it.
    run_gc_sweep(&pool, &unreachable_storage(), &dry_run_config()).await?;
    assert_eq!(
        last_sweep(&pool).await.scanned,
        1,
        "a payload whose deletion failed must be retried by the next sweep"
    );
    Ok(())
}

// ---------------------------------------------------------------------------
// Deletion + marking round-trip (Garage)
// ---------------------------------------------------------------------------

/// The positive path end to end: real bytes in Garage, a real deleting sweep,
/// marks written from the storage result, and a second sweep that finds
/// nothing left to do.
#[tokio::test]
async fn a_successful_sweep_marks_both_payloads_and_does_not_repeat_itself() -> Result<()> {
    let (pool, _pg) = spawn_postgres().await?;
    let (creds, _garage) = spawn_garage().await?;
    let storage = garage_storage(&creds);
    let queue = PgAiImportQueue::new(pool.clone());

    let id = seed_job(&queue, "gc-round-trip").await;
    let source = storage.put_source(id, b"PDF bytes".to_vec()).await?;
    let stored_preview = storage.put(id, b"{\"scenes\":[]}".to_vec()).await?;

    let preview = succeed(&queue, "worker-a", id).await;
    assert_eq!(
        preview, stored_preview,
        "the queue's handle must be the one storage wrote, or the sweep would \
         delete a different object than the job owns"
    );
    backdate(&pool, id).await;

    run_gc_sweep(&pool, &storage, &deleting_config()).await?;

    let history = last_sweep(&pool).await;
    assert_eq!(history.scanned, 1);
    assert_eq!(history.source_deleted, 1);
    assert_eq!(history.preview_deleted, 1);
    assert_eq!(history.errors, 0);

    assert!(
        storage.get_source(&source).await?.is_none(),
        "the source bytes must be gone"
    );
    assert!(
        storage.get(&preview).await?.is_none(),
        "the preview bytes must be gone"
    );

    assert_eq!(
        cleanup_marks(&pool, id).await,
        vec![
            ("preview".to_owned(), preview),
            ("source".to_owned(), source),
        ],
        "both payloads must be marked, each naming the handle actually deleted"
    );

    // The regression itself: the second sweep must be a no-op.
    run_gc_sweep(&pool, &storage, &deleting_config()).await?;
    let second = last_sweep(&pool).await;
    assert_eq!(
        second.scanned, 0,
        "the swept job must not be re-selected — before the marks this was 1 \
         on every run, forever"
    );
    assert_eq!(
        second.source_deleted + second.preview_deleted,
        0,
        "history counters must reflect new deletions only"
    );
    Ok(())
}

/// A missing object is a *successful* outcome and must be marked. The goal
/// state (the object is gone) holds, and a terminal job can never be re-claimed
/// to recreate it — so without a mark the sweep would re-probe an object that
/// will never exist again, on every run.
#[tokio::test]
async fn a_not_found_payload_counts_as_cleaned_and_is_marked() -> Result<()> {
    let (pool, _pg) = spawn_postgres().await?;
    let (creds, _garage) = spawn_garage().await?;
    let storage = garage_storage(&creds);
    let queue = PgAiImportQueue::new(pool.clone());

    // Nothing is ever written to storage: both handles dangle from the start,
    // which is the state left behind by an out-of-band deletion.
    let id = seed_job(&queue, "gc-not-found").await;
    let preview = succeed(&queue, "worker-a", id).await;
    backdate(&pool, id).await;

    run_gc_sweep(&pool, &storage, &deleting_config()).await?;

    let history = last_sweep(&pool).await;
    assert_eq!(
        history.errors, 0,
        "an absent object is the goal state, not a failure"
    );
    assert_eq!(history.source_deleted, 1);
    assert_eq!(history.preview_deleted, 1);

    let marks = cleanup_marks(&pool, id).await;
    assert_eq!(
        marks.len(),
        2,
        "a not-found deletion must be marked like any other success, or the \
         job is re-probed on every sweep for the rest of its retention life"
    );
    assert!(
        marks
            .iter()
            .any(|(kind, handle)| kind == "preview" && handle == &preview)
    );

    run_gc_sweep(&pool, &storage, &deleting_config()).await?;
    assert_eq!(last_sweep(&pool).await.scanned, 0);
    Ok(())
}

/// A storage decorator that fails deletions for one nominated handle.
///
/// Needed because Garage cannot be provoked into a per-object deletion error:
/// it accepts every key shape (empty, oversized, control characters) and
/// answers a delete of a nonexistent object with success — and a *missing*
/// object is classified as cleaned by design (see
/// `a_not_found_payload_counts_as_cleaned_and_is_marked`). Pointing the whole
/// sweep at an unreachable endpoint fails every job in the batch, which
/// destroys the mixed batch this test exists to produce. A decorator over the
/// real adapter keeps every other operation genuine.
struct FailingHandle {
    inner: OpenDalAiPayloadStorage,
    handle: String,
}

impl FailingHandle {
    fn guard(&self, handle: &str) -> Result<(), DomainError> {
        if handle == self.handle {
            return Err(DomainError::service_unavailable(
                "injected deletion failure",
            ));
        }
        Ok(())
    }
}

#[async_trait::async_trait]
impl AiDocumentStore for FailingHandle {
    async fn put_source(
        &self,
        job_id: AiImportJobId,
        payload: Vec<u8>,
    ) -> Result<String, DomainError> {
        self.inner.put_source(job_id, payload).await
    }

    async fn get_source(&self, handle: &str) -> Result<Option<Vec<u8>>, DomainError> {
        self.inner.get_source(handle).await
    }

    async fn delete_source(&self, handle: &str) -> Result<(), DomainError> {
        self.guard(handle)?;
        self.inner.delete_source(handle).await
    }
}

#[async_trait::async_trait]
impl AiPreviewStore for FailingHandle {
    async fn put(&self, job_id: AiImportJobId, payload: Vec<u8>) -> Result<String, DomainError> {
        self.inner.put(job_id, payload).await
    }

    async fn get(&self, handle: &str) -> Result<Option<Vec<u8>>, DomainError> {
        self.inner.get(handle).await
    }

    async fn delete(&self, handle: &str) -> Result<(), DomainError> {
        self.guard(handle)?;
        self.inner.delete(handle).await
    }
}

/// Marks must survive a partial batch: one job's deletion failing may not cost
/// a sibling job the marks it earned.
///
/// This is the ordering the implementation encodes by flushing the marks
/// *before* the early return on the first error. Flushing after would mean a
/// single 503 anywhere in a 1000-job batch discarded every mark in it, and the
/// next sweep would re-delete all of them — the original bug, merely rarer.
#[tokio::test]
async fn a_partial_batch_still_persists_the_marks_it_earned() -> Result<()> {
    let (pool, _pg) = spawn_postgres().await?;
    let (creds, _garage) = spawn_garage().await?;
    let storage = garage_storage(&creds);
    let queue = PgAiImportQueue::new(pool.clone());

    // Succeeds: real objects under handles the job actually owns.
    let good = seed_job(&queue, "gc-partial-good").await;
    let good_source = storage.put_source(good, b"good".to_vec()).await?;
    storage.put(good, b"good-preview".to_vec()).await?;
    let good_preview = succeed(&queue, "worker-a", good).await;

    // Fails: one nominated handle in the same batch. `bad` is enqueued second,
    // so its `updated_at` is later and the sweep reaches `good` first —
    // ensuring the failure happens *after* a mark has been earned, which is
    // the ordering under test.
    let bad = seed_job(&queue, "gc-partial-bad").await;
    succeed(&queue, "worker-b", bad).await;
    let bad_source = format!("ai-import/{}/source", bad.as_uuid());

    for id in [good, bad] {
        backdate(&pool, id).await;
    }
    // Order the two within the backdated window so `good` is swept first.
    order_before(&pool, good, bad).await;

    let faulty = FailingHandle {
        inner: storage.clone(),
        handle: bad_source,
    };
    let result = run_gc_sweep(&pool, &faulty, &deleting_config()).await;
    assert!(
        result.is_err(),
        "the batch contained a failing deletion, which must reach the scheduler"
    );

    assert_eq!(
        cleanup_marks(&pool, good).await,
        vec![
            ("preview".to_owned(), good_preview),
            ("source".to_owned(), good_source),
        ],
        "the completed job's marks must be persisted even though the run \
         ended in an error — otherwise one failure re-costs the whole batch"
    );

    let bad_marks = cleanup_marks(&pool, bad).await;
    assert!(
        bad_marks.iter().all(|(kind, _)| kind != "source"),
        "the source that could not be deleted must stay unmarked so it is retried"
    );

    // And the consequence: only the failing job comes back.
    run_gc_sweep(&pool, &faulty, &dry_run_config()).await?;
    assert_eq!(
        last_sweep(&pool).await.scanned,
        1,
        "only the job with an outstanding payload may be re-selected"
    );
    Ok(())
}
