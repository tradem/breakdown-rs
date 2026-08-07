// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Database-backed telemetry persistence contract for the AI import queue
//! (issue #171, CodeRabbit review).
//!
//! Exercises `PgAiImportQueue::record_telemetry` against a real Postgres:
//! a `NotApplied` job must persist `accept_as_is = NULL` and
//! `edit_distance = NULL`, while an applied zero-edit outcome must persist
//! `edit_distance = 0` — the two states must never be conflated.

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
    AiImportJobId, AiImportQueue, DocumentKind, Telemetry, TelemetryApplyState,
};
use infra::ai::PgAiImportQueue;
use sqlx::PgPool;

/// Seed a minimal job row (only the NOT NULL columns) and return its id.
async fn seed_job(pool: &PgPool, user: &str, dedup: &str) -> AiImportJobId {
    let id = AiImportJobId::new();
    sqlx::query(
        r#"
        INSERT INTO ai_import.ai_import_job
            (id, user_id, document_kind, dedup_key, document_digest, source_handle)
        VALUES ($1, $2, 'script', $3, 'digest', 'handle')
        "#,
    )
    .bind(id.as_uuid())
    .bind(user)
    .bind(dedup)
    .execute(pool)
    .await
    .unwrap();
    id
}

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
    let id = seed_job(&pool, "not-applied-user", "not-applied").await;

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
    let id = seed_job(&pool, "applied-user", "applied-zero").await;

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
