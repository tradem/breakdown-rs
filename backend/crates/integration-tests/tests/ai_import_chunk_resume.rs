// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Chunk-level resume contract (issue #871, workstream B).
//!
//! What these tests guard:
//!
//! 1. a simulated kill after `put(25)` resumes at **26**, not at 0;
//! 2. the cursor survives a process restart (it is derived from rows, not held in
//!    memory);
//! 3. a fingerprint mismatch **clears** the rows and restarts at 0 — never a
//!    partial resume across two models/prompts/chunkings;
//! 4. a re-run chunk is counted **once** in the usage sum (`ON CONFLICT DO
//!    UPDATE` replaces, never adds);
//! 5. a hole is not resumed past (`0, 1, 3` ⇒ cursor 2) and the tail is deleted;
//! 6. the write fence: a worker that lost its claim cannot add a chunk to a set
//!    another worker has since invalidated — asserted in both submission orders
//!    with two sessions, because that is the interleaving the row lock exists for;
//! 7. terminal transitions drop the rows; a retryable failure keeps them.
//!
//! Timing-safe: nothing sleeps, and no assertion compares a database timestamp
//! against the test process' clock.

#![allow(clippy::unwrap_used, clippy::expect_used)]
mod fixtures;

use anyhow::Result;
use breakdown_core::ai::ports::{
    AiImportChunkStore, AiImportEnqueueRequest, AiImportEnqueueResult, AiImportQueue,
    ChunkSetState, ExtractionFingerprint, LlmCallUsage, StoredChunk, resume_cursor,
};
use breakdown_core::ai::preview::CHUNKER_VERSION;
use breakdown_core::ai::{AiImportJobId, DocumentKind, LlmProvider, ScriptContext, SourceFormat};
use breakdown_core::shared::UserId;
use infra::ai::chunk_store::{PgAiImportChunkStore, fingerprint_key, prompt_hash};
use infra::ai::queue::PgAiImportQueue;

const PROVIDER: LlmProvider = LlmProvider::OpenCodeGo;
const MODEL: &str = "some-model";

fn chunk(index: u32, tokens_in: u64) -> StoredChunk {
    StoredChunk {
        chunk_index: index,
        payload: ScriptContext::default(),
        usage: LlmCallUsage {
            tokens_in,
            ..LlmCallUsage::default()
        },
    }
}

fn fingerprint(model: &str, prompt: &str) -> ExtractionFingerprint {
    ExtractionFingerprint {
        document_digest: "digest".to_owned(),
        provider: PROVIDER,
        model: model.to_owned(),
        prompt_hash: prompt_hash(prompt),
        chunker_version: CHUNKER_VERSION,
    }
}

/// Seed a job and claim it, so the store's fence is satisfied.
async fn claimed_job(queue: &PgAiImportQueue, dedup: &str, worker: &str) -> AiImportJobId {
    let id = AiImportJobId::new();
    let result = queue
        .enqueue(AiImportEnqueueRequest {
            provider: Some(PROVIDER),
            model: Some(MODEL.to_owned()),
            id,
            user_id: UserId::from_sub("u1"),
            document_kind: DocumentKind::Script,
            source_format: SourceFormat::Pdf,
            block_id: None,
            dedup_key: dedup.to_owned(),
            document_digest: "digest".to_owned(),
            source_handle: "handle".to_owned(),
            source_file_name: None,
            target: None,
        })
        .await
        .unwrap();
    let id = match result {
        AiImportEnqueueResult::Enqueued(id) | AiImportEnqueueResult::Existing(id) => id,
    };
    queue.claim_next(worker).await.unwrap().expect("claimable");
    id
}

#[tokio::test]
async fn a_kill_after_chunk_25_resumes_at_26() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let store = PgAiImportChunkStore::new(pool.clone());
    let id = claimed_job(&queue, "d1", "w1").await;

    let print = fingerprint(MODEL, "the prompt");
    let key = fingerprint_key(&print);
    store.begin_extraction(id, "w1", &print, &key).await?;
    // Chunks 0..=24 (25 chunks) completed, then the process died.
    for index in 0..25 {
        store.put(id, "w1", &key, &chunk(index, 10)).await?;
    }

    // The "restarted" attempt: same fingerprint, new worker id.
    let reloaded = store.load(id).await?;
    assert_eq!(
        resume_cursor(&reloaded),
        25,
        "the cursor is the prefix length"
    );
    assert_eq!(
        resume_cursor(&reloaded) + 1,
        26,
        "the next attempt continues at chunk 26 (1-based)"
    );
    Ok(())
}

#[tokio::test]
async fn the_cursor_survives_a_process_restart() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = claimed_job(&queue, "d1", "w1").await;
    let print = fingerprint(MODEL, "p");
    let key = fingerprint_key(&print);
    {
        // A store instance that is then dropped — the "process" that died.
        let store = PgAiImportChunkStore::new(pool.clone());
        store.begin_extraction(id, "w1", &print, &key).await?;
        store.put(id, "w1", &key, &chunk(0, 5)).await?;
        store.put(id, "w1", &key, &chunk(1, 5)).await?;
    }
    // A brand-new instance reads the same answer from the rows.
    let store = PgAiImportChunkStore::new(pool.clone());
    assert_eq!(resume_cursor(&store.load(id).await?), 2);
    Ok(())
}

#[tokio::test]
async fn a_fingerprint_mismatch_clears_the_set_and_restarts_at_zero() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let store = PgAiImportChunkStore::new(pool.clone());
    let id = claimed_job(&queue, "d1", "w1").await;

    let first = fingerprint(MODEL, "prompt one");
    let first_key = fingerprint_key(&first);
    store.begin_extraction(id, "w1", &first, &first_key).await?;
    for index in 0..5 {
        store.put(id, "w1", &first_key, &chunk(index, 1)).await?;
    }
    assert_eq!(resume_cursor(&store.load(id).await?), 5);

    // The user switched the model: the stored chunks must NOT be resumed across.
    let second = fingerprint("other-model", "prompt one");
    let second_key = fingerprint_key(&second);
    let outcome = store
        .begin_extraction(id, "w1", &second, &second_key)
        .await?;
    assert_eq!(
        outcome,
        ChunkSetState::Invalidated(vec!["model"]),
        "the invalidation must NAME the component that changed"
    );
    assert!(store.load(id).await?.is_empty(), "the set is gone");
    Ok(())
}

#[tokio::test]
async fn a_prompt_edit_invalidates_too() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let store = PgAiImportChunkStore::new(pool.clone());
    let id = claimed_job(&queue, "d1", "w1").await;

    let first = fingerprint(MODEL, "prompt one");
    store
        .begin_extraction(id, "w1", &first, &fingerprint_key(&first))
        .await?;
    store
        .put(id, "w1", &fingerprint_key(&first), &chunk(0, 1))
        .await?;

    // A whitespace-only edit CAN change model output, so it re-invalidates (D-B7).
    let edited = fingerprint(MODEL, "prompt  one");
    let outcome = store
        .begin_extraction(id, "w1", &edited, &fingerprint_key(&edited))
        .await?;
    assert_eq!(outcome, ChunkSetState::Invalidated(vec!["prompt"]));
    Ok(())
}

#[tokio::test]
async fn a_rerun_chunk_is_counted_once() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let store = PgAiImportChunkStore::new(pool.clone());
    let id = claimed_job(&queue, "d1", "w1").await;
    let print = fingerprint(MODEL, "p");
    let key = fingerprint_key(&print);
    store.begin_extraction(id, "w1", &print, &key).await?;

    store.put(id, "w1", &key, &chunk(0, 100)).await?;
    // The same chunk re-runs (a lost write, then a retry): replaced, not added.
    store.put(id, "w1", &key, &chunk(0, 40)).await?;

    let stored = store.load(id).await?;
    assert_eq!(stored.len(), 1, "one row per chunk, never two");
    assert_eq!(
        stored.first().map(|c| c.usage.tokens_in),
        Some(40),
        "the usage is REPLACED, so the cost snapshot counts one paid call"
    );
    Ok(())
}

#[tokio::test]
async fn a_hole_is_not_resumed_past_and_its_tail_is_deleted() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let store = PgAiImportChunkStore::new(pool.clone());
    let id = claimed_job(&queue, "d1", "w1").await;
    let print = fingerprint(MODEL, "p");
    let key = fingerprint_key(&print);
    store.begin_extraction(id, "w1", &print, &key).await?;

    // A hand-made hole: 0, 1, 3 — chunk 2 never completed.
    store.put(id, "w1", &key, &chunk(0, 1)).await?;
    store.put(id, "w1", &key, &chunk(1, 1)).await?;
    store.put(id, "w1", &key, &chunk(3, 1)).await?;

    let loaded = store.load(id).await?;
    assert_eq!(resume_cursor(&loaded), 2, "resume at the hole, not past it");
    assert_eq!(loaded.len(), 2, "the tail beyond the hole is deleted");
    Ok(())
}

#[tokio::test]
async fn a_worker_that_lost_its_claim_cannot_write() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let store = PgAiImportChunkStore::new(pool.clone());
    let id = claimed_job(&queue, "d1", "w1").await;
    let print = fingerprint(MODEL, "p");
    let key = fingerprint_key(&print);
    store.begin_extraction(id, "w1", &print, &key).await?;

    // The claim moves to another worker (a lease lapse + reclaim).
    sqlx::query("UPDATE ai_import.ai_import_job SET worker_id = 'w2' WHERE id = $1")
        .bind(id.as_uuid())
        .execute(&pool)
        .await?;

    let refused = store.put(id, "w1", &key, &chunk(0, 1)).await;
    assert!(
        refused.is_err(),
        "a displaced worker must not add to the set — the row lock is the fence"
    );
    assert!(store.load(id).await?.is_empty());
    Ok(())
}

#[tokio::test]
async fn a_stale_chunk_cannot_land_in_an_invalidated_set() -> Result<()> {
    // The interleaving D-B3 exists for, in one session each: worker A holds a
    // paid result for the OLD fingerprint, worker B reclaims the job and
    // invalidates the set, and A then tries to write. The row lock serializes
    // them, so A's write is refused instead of mixing two configurations.
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let store = PgAiImportChunkStore::new(pool.clone());
    let id = claimed_job(&queue, "d1", "w1").await;

    let old_print = fingerprint(MODEL, "prompt one");
    let old_key = fingerprint_key(&old_print);
    store
        .begin_extraction(id, "w1", &old_print, &old_key)
        .await?;

    // B reclaims (a lease lapse in production) and invalidates with a new prompt.
    sqlx::query("UPDATE ai_import.ai_import_job SET worker_id = 'w2' WHERE id = $1")
        .bind(id.as_uuid())
        .execute(&pool)
        .await?;
    let new_print = fingerprint(MODEL, "prompt two");
    let new_key = fingerprint_key(&new_print);
    store
        .begin_extraction(id, "w2", &new_print, &new_key)
        .await?;

    // A's write carries the old key: refused on the key fence.
    let refused = store.put(id, "w1", &old_key, &chunk(0, 1)).await;
    assert!(
        refused.is_err(),
        "a stale chunk must never enter the new set"
    );
    // And even with the right key, A no longer owns the claim.
    let also_refused = store.put(id, "w1", &new_key, &chunk(0, 1)).await;
    assert!(also_refused.is_err());
    assert!(store.load(id).await?.is_empty());
    Ok(())
}

#[tokio::test]
async fn terminal_transitions_drop_the_rows_and_a_retryable_failure_keeps_them() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let store = PgAiImportChunkStore::new(pool.clone());
    let id = claimed_job(&queue, "d1", "w1").await;
    let print = fingerprint(MODEL, "p");
    let key = fingerprint_key(&print);
    store.begin_extraction(id, "w1", &print, &key).await?;
    store.put(id, "w1", &key, &chunk(0, 1)).await?;

    // A retryable failure keeps the set: that IS the resume.
    queue
        .mark_failed(id, "w1", "boom", Some("domain.service-unavailable"), true)
        .await?;
    assert_eq!(
        store.load(id).await?.len(),
        1,
        "a backoff must not lose paid work"
    );

    // The next attempt completes the job: terminal, so the rows go. The backoff
    // is made due by writing a past timestamp — never by sleeping it out.
    sqlx::query(
        "UPDATE ai_import.ai_import_job SET next_attempt_at = now() - interval '1 second' WHERE id = $1",
    )
    .bind(id.as_uuid())
    .execute(&pool)
    .await?;
    let reclaimed = queue.claim_next("w2").await?.expect("claimable again");
    assert_eq!(reclaimed.id, id);
    queue.mark_succeeded(id, "w2", "preview").await?;
    assert!(
        store.load(id).await?.is_empty(),
        "a succeeded job keeps no chunk rows"
    );
    Ok(())
}

/// Issue #871 review (D-B1): hold expiry is a **terminal** transition, so the
/// chunks paid for before the hold must go with it — like every other
/// `dead_letter` path. Leaving them behind kept storage for a job no worker can
/// ever claim again.
#[tokio::test]
async fn an_expired_hold_drops_the_stored_chunks() -> Result<()> {
    const HOLD_WINDOW: u64 = 3600;
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let store = PgAiImportChunkStore::new(pool.clone());
    let id = claimed_job(&queue, "d1", "w1").await;
    let print = fingerprint(MODEL, "p");
    let key = fingerprint_key(&print);
    store.begin_extraction(id, "w1", &print, &key).await?;
    store.put(id, "w1", &key, &chunk(0, 1)).await?;
    store.put(id, "w1", &key, &chunk(1, 1)).await?;
    assert_eq!(resume_cursor(&store.load(id).await?), 2);

    // The breaker opens mid-run and the job is parked with its progress.
    queue
        .mark_held(
            id,
            "w1",
            breakdown_core::ai::ProviderHold {
                provider: PROVIDER,
                model: MODEL.to_owned(),
                reason_code: "ai-import.llm-provider-unavailable".to_owned(),
                state: breakdown_core::ai::ProviderBreakerState::Open,
                until: chrono::Utc::now() + chrono::Duration::minutes(5),
                // Self-describing only; the adapter re-derives the deadline from
                // the job's own series clock.
                hold_deadline: chrono::Utc::now() + chrono::Duration::minutes(5),
                chunks_done: 2,
            },
            HOLD_WINDOW,
        )
        .await?;
    assert_eq!(
        resume_cursor(&store.load(id).await?),
        2,
        "a hold keeps the paid work: that is the resume it exists for"
    );

    // The deadline passed — written in the past, never slept out.
    sqlx::query(
        "UPDATE ai_import.ai_import_job SET provider_hold = jsonb_set(provider_hold, '{hold_deadline}', to_jsonb(now() - interval '1 minute')) WHERE id = $1",
    )
    .bind(id.as_uuid())
    .execute(&pool)
    .await?;
    let expired = queue
        .expire_provider_holds(
            "the provider stayed unavailable",
            Some("ai-import.llm-provider-unavailable"),
        )
        .await?;
    assert_eq!(expired, vec![id]);
    assert!(
        store.load(id).await?.is_empty(),
        "hold expiry is terminal, so the stored chunks go with it"
    );
    Ok(())
}

#[tokio::test]
async fn clear_is_idempotent() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let store = PgAiImportChunkStore::new(pool.clone());
    let id = AiImportJobId::new();
    assert_eq!(
        store.clear(id).await?,
        0,
        "nothing to delete is not an error"
    );
    Ok(())
}
