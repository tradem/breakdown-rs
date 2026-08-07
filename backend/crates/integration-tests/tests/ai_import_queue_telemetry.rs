// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Database-backed telemetry persistence contract for the AI import queue
//! (issue #171, CodeRabbit review).
//!
//! Exercises the public `AiImportQueue` adapter API against a real Postgres:
//! a `NotApplied` job must persist `accept_as_is = NULL` and
//! `edit_distance = NULL`, while an applied zero-edit outcome must persist
//! `edit_distance = 0` — the two states must never be conflated.
//!
//! The write path uses only public core/infra APIs (`enqueue` for seeding,
//! `record_telemetry` under test). The only raw SQL is the read-back
//! assertion, because the telemetry columns are deliberately write-only and
//! are not exposed on the `AiImportJob` view — this mirrors the repo's
//! established adapter-test pattern (`command_adapter_tests.rs`). Moving the
//! whole test into the `infra` crate is not possible: `ci.yml` runs
//! `cargo test --workspace` without Docker, and the ephemeral-Postgres
//! harness lives in this crate.

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
    Telemetry, TelemetryApplyState,
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

/// Read back the persisted telemetry columns. Kept as raw SQL on purpose:
/// `Telemetry` is write-only by design and not part of the `AiImportJob`
/// view, so there is no public read API to assert against.
async fn read_telemetry_row(pool: &PgPool, id: AiImportJobId) -> (Option<bool>, Option<i32>) {
    sqlx::query_as(
        r#"
        SELECT accept_as_is, edit_distance
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
async fn record_telemetry_not_applied_persists_null_metrics() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = seed_job(&queue, "not-applied-user", "not-applied").await;

    queue
        .record_telemetry(
            id,
            Telemetry {
                doc_kind: Some(DocumentKind::Script),
                apply_state: TelemetryApplyState::NotApplied,
                ..Telemetry::default()
            },
        )
        .await?;

    let (accept_as_is, edit_distance) = read_telemetry_row(&pool, id).await;
    assert_eq!(
        accept_as_is, None,
        "NotApplied must persist accept_as_is = NULL"
    );
    assert_eq!(
        edit_distance, None,
        "NotApplied must persist edit_distance = NULL"
    );
    Ok(())
}

#[tokio::test]
async fn record_telemetry_applied_zero_edits_persists_zero() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());
    let id = seed_job(&queue, "applied-user", "applied-zero").await;

    queue
        .record_telemetry(
            id,
            Telemetry {
                doc_kind: Some(DocumentKind::Script),
                apply_state: TelemetryApplyState::Applied {
                    accept_as_is: true,
                    edit_distance: 0,
                },
                ..Telemetry::default()
            },
        )
        .await?;

    let (accept_as_is, edit_distance) = read_telemetry_row(&pool, id).await;
    assert_eq!(accept_as_is, Some(true));
    assert_eq!(
        edit_distance,
        Some(0),
        "applied zero-edit must persist edit_distance = 0"
    );
    Ok(())
}
