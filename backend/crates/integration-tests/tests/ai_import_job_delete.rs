// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! Database-backed contract for the terminal-job delete affordance (issue
//! #671).
//!
//! `DELETE /v1/ai-import/jobs/{id}` frees the `(user_id, dedup_key)` unique
//! slot with the row, so a stuck import stops permanently blocking re-upload
//! of the same document. Two Postgres-level properties carry that contract,
//! and neither is observable against an in-memory fake:
//!
//! 1. `delete_terminal` removes **only** a terminal row (`succeeded`,
//!    `dead_letter`, `payload_unavailable`) — the authoritative backstop
//!    behind the handler's registered 409 pre-check. `pending`/`running`/
//!    `failed` rows must survive untouched: they are leased, queued or
//!    backed off, and deleting one would corrupt the claim/permit machinery.
//! 2. A deleted `succeeded` job leaves **no dangling mapping rows** in
//!    `ai_import.projection_ai_import_mapping` — that table has no foreign
//!    key to the job row, so the adapter must remove the mappings in the same
//!    transaction.
//!
//! The write path uses only public core/infra APIs (`enqueue` for seeding,
//! `delete_terminal` under test). The only raw SQL is the read-back
//! assertion, mirroring the repo's established adapter-test pattern
//! (`ai_import_queue_telemetry.rs`).

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
    AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJobId, AiImportQueue, DocumentKind,
    SourceFormat,
};
use breakdown_core::shared::UserId;
use infra::ai::PgAiImportQueue;
use sqlx::PgPool;

/// Seed a job row through the public `enqueue` API and return its id.
async fn seed_job(queue: &PgAiImportQueue, user: &str, dedup: &str) -> AiImportJobId {
    let id = AiImportJobId::new();
    let result = queue
        .enqueue(AiImportEnqueueRequest {
            id,
            user_id: UserId::from_sub(user),
            document_kind: DocumentKind::Script,
            source_format: SourceFormat::Pdf,
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

/// Force a job into the given status. Raw SQL is the only way to reach the
/// states the workers would normally produce (there is no public
/// "dead-letter this job" API callable without a claim).
async fn force_status(pool: &PgPool, id: AiImportJobId, status: &str) {
    sqlx::query("UPDATE ai_import.ai_import_job SET status = $2 WHERE id = $1")
        .bind(id.as_uuid())
        .bind(status)
        .execute(pool)
        .await
        .unwrap();
}

/// Whether the job row still exists.
async fn row_exists(pool: &PgPool, id: AiImportJobId) -> bool {
    sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM ai_import.ai_import_job WHERE id = $1")
        .bind(id.as_uuid())
        .fetch_one(pool)
        .await
        .unwrap()
        > 0
}

#[tokio::test]
async fn delete_terminal_removes_a_dead_letter_row_and_frees_the_dedup_key() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = seed_job(&queue, "delete-user", "delete-dedup").await;
    force_status(&pool, id, "dead_letter").await;

    let deleted = queue.delete_terminal(id).await.unwrap();
    assert!(deleted, "a dead-letter row must be deletable");
    assert!(!row_exists(&pool, id).await, "the row must be gone");

    // The unique `(user_id, dedup_key)` slot is freed: re-enqueueing the same
    // dedup key enqueues a fresh job (202) instead of returning the old id.
    let reupload = queue
        .enqueue(AiImportEnqueueRequest {
            id: AiImportJobId::new(),
            user_id: UserId::from_sub("delete-user"),
            document_kind: DocumentKind::Script,
            source_format: SourceFormat::Pdf,
            block_id: None,
            dedup_key: "delete-dedup".to_owned(),
            document_digest: "digest".to_owned(),
            source_handle: "handle".to_owned(),
        })
        .await
        .unwrap();
    assert!(
        matches!(reupload, AiImportEnqueueResult::Enqueued(fresh) if fresh != id),
        "the same document must enqueue a fresh job after the delete"
    );
    Ok(())
}

#[tokio::test]
async fn delete_terminal_refuses_non_terminal_rows() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    for status in ["pending", "running", "failed"] {
        let id = seed_job(
            &queue,
            "non-terminal-user",
            &format!("non-terminal-{status}"),
        )
        .await;
        force_status(&pool, id, status).await;

        let deleted = queue.delete_terminal(id).await.unwrap();
        assert!(
            !deleted,
            "a {status} row must not be deletable (claim/permit corruption)"
        );
        assert!(row_exists(&pool, id).await, "the {status} row must stay");
    }
    Ok(())
}

#[tokio::test]
async fn delete_terminal_succeeds_for_every_terminal_state() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    for (n, status) in ["succeeded", "payload_unavailable"].iter().enumerate() {
        let id = seed_job(&queue, "terminal-user", &format!("terminal-{n}")).await;
        force_status(&pool, id, status).await;

        let deleted = queue.delete_terminal(id).await.unwrap();
        assert!(deleted, "a {status} row is terminal and must be deletable");
        assert!(!row_exists(&pool, id).await);
    }
    Ok(())
}

#[tokio::test]
async fn delete_terminal_of_a_succeeded_job_removes_its_mapping_rows() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = seed_job(&queue, "mapping-user", "mapping-dedup").await;
    force_status(&pool, id, "succeeded").await;

    // Seed a mapping row the way the apply path would (raw SQL: the mapping
    // repository's `reserve`/`insert` is out of scope for this contract — the
    // delete must be observable against any pre-existing rows).
    sqlx::query(
        r#"
        INSERT INTO ai_import.projection_ai_import_mapping
            (preview_id, draft_ref, aggregate_kind, aggregate_id, aggregate_version)
        VALUES ($1, 'scene-0', 'scene', $2, 3)
        "#,
    )
    .bind(id.as_uuid())
    .bind(uuid::Uuid::now_v7())
    .execute(&pool)
    .await
    .unwrap();

    let deleted = queue.delete_terminal(id).await.unwrap();
    assert!(deleted);
    let dangling: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM ai_import.projection_ai_import_mapping WHERE preview_id = $1",
    )
    .bind(id.as_uuid())
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        dangling, 0,
        "a deleted succeeded job must leave no dangling mapping rows"
    );
    Ok(())
}

#[tokio::test]
async fn delete_terminal_of_an_unknown_row_reports_not_deleted() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);
    let missing = AiImportJobId::new();

    let deleted = queue.delete_terminal(missing).await.unwrap();
    assert!(
        !deleted,
        "an unknown id must report 'not deleted' so the handler answers 404"
    );
    Ok(())
}
