// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Database-backed contract for the set-once target attach (issue #829).
//!
//! `PUT /v1/ai-import/jobs/{id}/target` fills in the write target of a
//! block-less job, and the whole guarantee lives in ONE SQL statement:
//!
//! ```sql
//! UPDATE ai_import.ai_import_job
//! SET block_id = $2, target_block_number = $3, updated_at = now()
//! WHERE id = $1 AND block_id IS NULL AND accept_as_is IS NULL
//! ```
//!
//! Neither property is observable against an in-memory fake — the handler tests
//! drive `FakeAiImportQueue`, which re-implements the rule in Rust, so the real
//! predicate can be dropped without a single red test:
//!
//! 1. `block_id IS NULL` makes it attach-ONLY: a job that already has a target
//!    keeps it, and the reported outcome names the block that won.
//! 2. `accept_as_is IS NULL` freezes the target of a job whose apply already
//!    recorded rows (`AiImportJob::applied` is derived from that column). Those
//!    rows are bound to the old block, so moving the target afterwards would
//!    orphan them.
//!
//! The same block repeated stays an idempotent success in every state, which is
//! the third property pinned here: a retry must never report a conflict for a
//! request that is already satisfied.
//!
//! The write path uses only public core/infra APIs (`enqueue` for seeding,
//! `set_target_once` under test). The only raw SQL is the read-back assertion
//! and the state forcing, mirroring the repo's established adapter-test pattern
//! (`ai_import_job_delete.rs`, `ai_import_queue_telemetry.rs`).

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
mod fixtures;

use anyhow::Result;
use breakdown_core::ai::{
    AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJobId, AiImportQueue, AiImportTarget,
    DocumentKind, SourceFormat, TargetAttachOutcome,
};
use breakdown_core::shared::{BlockId, SeasonId, UserId};
use infra::ai::PgAiImportQueue;
use sqlx::PgPool;

/// Seed a block-less job (season-only target) and return its id.
async fn seed_blockless_job(
    queue: &PgAiImportQueue,
    user: &str,
    dedup: &str,
    season_id: SeasonId,
) -> AiImportJobId {
    let id = AiImportJobId::new();
    let result = queue
        .enqueue(AiImportEnqueueRequest {
            // Issue #871: no breaker snapshot in this fixture — the job is
            // never breaker-filtered, which is the honest degradation.
            provider: None,
            model: None,
            id,
            user_id: UserId::from_sub(user),
            document_kind: DocumentKind::Script,
            source_format: SourceFormat::Pdf,
            block_id: None,
            dedup_key: dedup.to_owned(),
            document_digest: "digest".to_owned(),
            source_handle: "handle".to_owned(),
            source_file_name: None,
            target: Some(AiImportTarget {
                season_id,
                season_number: 7,
                block_number: None,
            }),
        })
        .await
        .unwrap();
    match result {
        AiImportEnqueueResult::Enqueued(id) | AiImportEnqueueResult::Existing(id) => id,
    }
}

/// Mark the job as applied. `accept_as_is` is the persisted "an apply landed"
/// fact the adapter's freeze predicate reads; raw SQL is the only way to reach
/// it without running a full apply.
async fn mark_applied(pool: &PgPool, id: AiImportJobId) {
    sqlx::query("UPDATE ai_import.ai_import_job SET accept_as_is = true WHERE id = $1")
        .bind(id.as_uuid())
        .execute(pool)
        .await
        .unwrap();
}

/// The persisted `(block_id, target_block_number)` pair — read back so the test
/// pins the ROW, not just the outcome enum.
async fn stored_target(pool: &PgPool, id: AiImportJobId) -> (Option<uuid::Uuid>, Option<i32>) {
    sqlx::query_as::<_, (Option<uuid::Uuid>, Option<i32>)>(
        "SELECT block_id, target_block_number FROM ai_import.ai_import_job WHERE id = $1",
    )
    .bind(id.as_uuid())
    .fetch_one(pool)
    .await
    .unwrap()
}

#[tokio::test]
async fn set_target_once_attaches_the_block_and_its_number_in_one_write() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let season_id = SeasonId::new();
    let id = seed_blockless_job(&queue, "attach-user", "attach-dedup", season_id).await;
    let block_id = BlockId::new();

    let outcome = queue
        .set_target_once(id, block_id, 2)
        .await
        .expect("attach succeeds");
    assert_eq!(outcome, TargetAttachOutcome::Attached);

    let (stored_block, stored_number) = stored_target(&pool, id).await;
    assert_eq!(
        stored_block,
        Some(block_id.0),
        "the guard value must be persisted"
    );
    assert_eq!(
        stored_number,
        Some(2),
        "the number the card renders is written by the same statement, so the \
         visible target and the guard value cannot drift"
    );
    Ok(())
}

#[tokio::test]
async fn set_target_once_refuses_a_second_block_and_names_the_winner() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let season_id = SeasonId::new();
    let id = seed_blockless_job(&queue, "attach-user", "attach-dedup", season_id).await;
    let winning = BlockId::new();
    let other = BlockId::new();

    assert_eq!(
        queue.set_target_once(id, winning, 2).await.unwrap(),
        TargetAttachOutcome::Attached
    );
    // The `block_id IS NULL` predicate is what makes the target set-once: without
    // it this second call would move the job (and its future rows) into `other`.
    assert_eq!(
        queue.set_target_once(id, other, 3).await.unwrap(),
        TargetAttachOutcome::AlreadySet {
            existing_block_id: winning,
        },
        "a different block must be refused and name the block that won"
    );

    let (stored_block, stored_number) = stored_target(&pool, id).await;
    assert_eq!(stored_block, Some(winning.0), "the first attach must win");
    assert_eq!(
        stored_number,
        Some(2),
        "the loser must not write the number"
    );
    Ok(())
}

#[tokio::test]
async fn set_target_once_freezes_the_target_of_an_applied_job() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let season_id = SeasonId::new();
    let id = seed_blockless_job(&queue, "attach-user", "attach-dedup", season_id).await;
    let block_id = BlockId::new();

    assert_eq!(
        queue.set_target_once(id, block_id, 2).await.unwrap(),
        TargetAttachOutcome::Attached
    );
    mark_applied(&pool, id).await;

    // `accept_as_is IS NULL` is what freezes the target: the apply's rows are
    // bound to `block_id`, so a later attach must not move them.
    assert_eq!(
        queue.set_target_once(id, BlockId::new(), 3).await.unwrap(),
        TargetAttachOutcome::AlreadyApplied,
        "an applied job's target must be frozen"
    );
    let (stored_block, _) = stored_target(&pool, id).await;
    assert_eq!(
        stored_block,
        Some(block_id.0),
        "the applied job keeps the block its rows were written into"
    );
    Ok(())
}

#[tokio::test]
async fn set_target_once_stays_idempotent_for_the_same_block_after_an_apply() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let season_id = SeasonId::new();
    let id = seed_blockless_job(&queue, "attach-user", "attach-dedup", season_id).await;
    let block_id = BlockId::new();

    assert_eq!(
        queue.set_target_once(id, block_id, 2).await.unwrap(),
        TargetAttachOutcome::Attached
    );
    mark_applied(&pool, id).await;

    // A retry after the rows landed asks for nothing that is not already true.
    // Reporting `AlreadyApplied` here would turn a satisfied retry into a 409
    // the client renders as "target frozen".
    assert_eq!(
        queue.set_target_once(id, block_id, 2).await.unwrap(),
        TargetAttachOutcome::Unchanged,
        "the same block repeated is an idempotent success in every state"
    );
    Ok(())
}

#[tokio::test]
async fn set_target_once_reports_not_found_for_an_unknown_job() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());

    assert_eq!(
        queue
            .set_target_once(AiImportJobId::new(), BlockId::new(), 2)
            .await
            .unwrap(),
        TargetAttachOutcome::NotFound
    );
    Ok(())
}

#[tokio::test]
async fn set_target_once_refuses_a_job_without_a_target_snapshot() -> Result<()> {
    let (pool, _container) = fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = AiImportJobId::new();
    queue
        .enqueue(AiImportEnqueueRequest {
            // Issue #871: no breaker snapshot in this fixture — the job is
            // never breaker-filtered, which is the honest degradation.
            provider: None,
            model: None,
            id,
            user_id: UserId::from_sub("attach-user"),
            document_kind: DocumentKind::Script,
            source_format: SourceFormat::Pdf,
            block_id: None,
            dedup_key: "no-target".to_owned(),
            document_digest: "digest".to_owned(),
            source_handle: "handle".to_owned(),
            source_file_name: None,
            target: None,
        })
        .await
        .unwrap();

    // A block number without its season pair would leave a target that no
    // longer decodes (`target_season_id` NULL, `target_block_number` set), so
    // the statement refuses the row outright — and says so instead of borrowing
    // another outcome's name.
    assert_eq!(
        queue.set_target_once(id, BlockId::new(), 2).await.unwrap(),
        TargetAttachOutcome::NoTargetSeason,
        "a job without a target season cannot receive a block"
    );
    let (stored_block, stored_number) = stored_target(&pool, id).await;
    assert!(
        stored_block.is_none() && stored_number.is_none(),
        "a job without a target season must not gain a bare block number"
    );
    Ok(())
}
