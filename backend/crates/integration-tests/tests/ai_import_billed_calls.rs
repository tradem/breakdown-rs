// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Billed-call ledger contract for the AI import queue (issue #970, CodeRabbit
//! review PR #967 round 13).
//!
//! What these tests guard:
//!
//! 1. the ledger is **append-only and per request** — two paid requests are two
//!    entries, never one summed entry (the #794 energy cap is applied per
//!    request, so the boundaries must survive the round trip);
//! 2. an append is **idempotent per key** — a retry after a lost
//!    acknowledgement adds nothing a second time;
//! 3. the read is empty for a fresh job and returns the entries in billing
//!    order;
//! 4. the ledger is **independent of the completion counters**: a
//!    `record_worker_telemetry` write stores the totals and leaves the ledger
//!    untouched — that separation is what stops a crashed attempt's completion
//!    total from being counted again by the re-drive;
//! 5. the write is **owner-fenced** and only applies to a `running` claim.
//!
//! Every assertion goes through the public `AiImportQueue` API; the raw SQL is
//! read-back only, because the counters are deliberately write-only and not part
//! of the `AiImportJob` view (the established adapter-test pattern of this crate
//! — see `ai_import_queue_telemetry.rs`).

#![allow(clippy::unwrap_used, clippy::expect_used)]

mod fixtures;

use anyhow::Result;
use breakdown_core::ai::ports::{
    AiImportEnqueueRequest, AiImportEnqueueResult, AiImportQueue, LlmCallUsage,
};
use breakdown_core::ai::{
    AiImportJobId, DocumentKind, LlmProvider, SourceFormat, Telemetry, TelemetryApplyState,
};
use breakdown_core::shared::UserId;
use infra::ai::queue::PgAiImportQueue;
use sqlx::PgPool;
use uuid::Uuid;

const PROVIDER: LlmProvider = LlmProvider::OpenCodeGo;
const MODEL: &str = "some-model";

/// Seed a job and claim it, so the ledger writes' claim fence and `running`
/// status predicate are satisfied.
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

fn call(tokens_in: u64, energy_millijoules: u64) -> LlmCallUsage {
    LlmCallUsage {
        tokens_in,
        tokens_out: 1,
        cached_tokens_in: 0,
        energy_millijoules,
    }
}

/// The completion counters on the row — NOT the ledger.
async fn read_completion_counters(pool: &PgPool, id: AiImportJobId) -> (i64, i64) {
    sqlx::query_as(
        r#"
        SELECT COALESCE(tokens_in, 0), COALESCE(energy_millijoules, 0)
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
async fn the_ledger_keeps_one_entry_per_paid_request() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = claimed_job(&queue, "d1", "w1").await;

    assert_eq!(
        queue.recorded_billed_calls(id).await?,
        Vec::new(),
        "a first attempt seeds from an empty ledger"
    );

    // Two paid requests, appended separately — exactly how the worker records a
    // chunk and a page: as soon as each call returned.
    queue
        .append_billed_calls(id, "w1", &[call(1_000, 100)], Uuid::now_v7())
        .await?;
    queue
        .append_billed_calls(id, "w1", &[call(10, 5_000)], Uuid::now_v7())
        .await?;

    assert_eq!(
        queue.recorded_billed_calls(id).await?,
        vec![call(1_000, 100), call(10, 5_000)],
        "the request boundaries survive: never one summed entry (#794)"
    );
    Ok(())
}

#[tokio::test]
async fn an_append_is_idempotent_per_key() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = claimed_job(&queue, "d2", "w1").await;

    let key = Uuid::now_v7();
    queue
        .append_billed_calls(id, "w1", &[call(500, 7)], key)
        .await?;
    // The retry after a lost acknowledgement re-uses the key verbatim.
    queue
        .append_billed_calls(id, "w1", &[call(500, 7)], key)
        .await?;

    assert_eq!(
        queue.recorded_billed_calls(id).await?,
        vec![call(500, 7)],
        "the same key appends once, however often the write is retried"
    );

    // A fresh key is a fresh request.
    queue
        .append_billed_calls(id, "w1", &[call(500, 7)], Uuid::now_v7())
        .await?;
    assert_eq!(queue.recorded_billed_calls(id).await?.len(), 2);
    Ok(())
}

#[tokio::test]
async fn the_completion_telemetry_does_not_touch_the_ledger() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = claimed_job(&queue, "d3", "w1").await;

    queue
        .append_billed_calls(id, "w1", &[call(120, 9)], Uuid::now_v7())
        .await?;
    // The crashed-attempt shape: a completion-time telemetry write landed, the
    // following `mark_succeeded` did not. The counters now cover the whole job.
    queue
        .record_worker_telemetry(
            id,
            "w1",
            Telemetry {
                provider: Some(PROVIDER),
                model: Some(MODEL.to_owned()),
                tokens_in: 120,
                energy_millijoules: 9,
                ..Telemetry::default()
            },
        )
        .await?;
    assert_eq!(
        read_completion_counters(&pool, id).await,
        (120, 9),
        "the completion counters are the job total"
    );
    assert_eq!(
        queue.recorded_billed_calls(id).await?,
        vec![call(120, 9)],
        "the ledger is a separate column and stays the per-request record"
    );
    Ok(())
}

#[tokio::test]
async fn the_append_is_fenced_and_only_applies_to_a_running_claim() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = claimed_job(&queue, "d4", "w1").await;

    // The owning worker's append lands …
    queue
        .append_billed_calls(id, "w1", &[call(1, 1)], Uuid::now_v7())
        .await?;
    assert_eq!(queue.recorded_billed_calls(id).await?, vec![call(1, 1)]);

    // … and a displaced worker must not append to a row it no longer owns.
    let displaced = queue
        .append_billed_calls(id, "w2", &[call(9, 9)], Uuid::now_v7())
        .await;
    assert!(
        displaced.is_err(),
        "a lost claim is refused, not silently accepted: {displaced:?}"
    );
    assert_eq!(
        queue.recorded_billed_calls(id).await?,
        vec![call(1, 1)],
        "the displaced write added nothing"
    );

    // After the terminal transition the row is no longer `running`, so even the
    // owner's append is refused (the accounting of a finished job is fixed).
    queue
        .mark_failed(id, "w1", "dead-lettered by the test", None, false, None)
        .await?;
    let after_terminal = queue
        .append_billed_calls(id, "w1", &[call(9, 9)], Uuid::now_v7())
        .await;
    assert!(
        after_terminal.is_err(),
        "a terminal job's ledger is closed: {after_terminal:?}"
    );
    assert_eq!(
        queue.recorded_billed_calls(id).await?,
        vec![call(1, 1)],
        "the terminal write added nothing"
    );
    Ok(())
}

#[tokio::test]
async fn an_applied_telemetry_write_leaves_the_ledger_alone() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = claimed_job(&queue, "d5", "w1").await;
    queue
        .append_billed_calls(id, "w1", &[call(42, 3)], Uuid::now_v7())
        .await?;
    queue
        .record_telemetry(
            id,
            Telemetry {
                provider: Some(PROVIDER),
                model: Some(MODEL.to_owned()),
                tokens_in: 42,
                apply_state: TelemetryApplyState::NotApplied,
                ..Telemetry::default()
            },
        )
        .await?;
    assert_eq!(
        queue.recorded_billed_calls(id).await?,
        vec![call(42, 3)],
        "no telemetry path rewrites the ledger"
    );
    Ok(())
}
