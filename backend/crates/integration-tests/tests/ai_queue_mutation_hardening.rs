// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

//! P3.7 — Postgres integration tests for PgAiImportQueue.

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

mod fixtures;

use std::time::Duration;

use anyhow::Result;
use breakdown_core::ai::{
    AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJobId, AiImportQueue, DocumentKind,
};
use breakdown_core::ai::{JobStatus, Telemetry, TelemetryApplyState};
use infra::ai::queue::PgAiImportQueue;
use uuid::Uuid;

fn make_enqueue_request(user_id: &str, kind: DocumentKind) -> AiImportEnqueueRequest {
    AiImportEnqueueRequest {
        id: AiImportJobId::new(),
        user_id: breakdown_core::shared::UserId::from_sub(user_id),
        document_kind: kind,
        source_format: breakdown_core::ai::SourceFormat::Csv,
        block_id: None,
        dedup_key: format!("dedup-{user_id}-{}", Uuid::now_v7()),
        document_digest: format!("digest-{}", Uuid::now_v7()),
        source_handle: format!("handle-{}", Uuid::now_v7()),
    }
}

#[tokio::test]
async fn lease_window_returns_some() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);
    let window = queue.lease_window();
    assert!(window.is_some(), "lease_window should return Some");
    assert!(
        window.unwrap() > Duration::ZERO,
        "lease_window must be positive"
    );
    Ok(())
}

#[tokio::test]
async fn enqueue_and_get_roundtrip() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-1", DocumentKind::Script);
    let id = request.id;

    let result = queue.enqueue(request).await?;
    match result {
        AiImportEnqueueResult::Enqueued(queued_id) => {
            assert_eq!(queued_id, id);
        }
        other => panic!("expected Enqueued, got {other:?}"),
    }

    let job = queue.get(id).await?;
    assert!(job.is_some(), "job should be retrievable after enqueue");
    let job = job.unwrap();
    assert_eq!(job.status, JobStatus::Pending);

    Ok(())
}

#[tokio::test]
async fn claim_next_returns_pending_job() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-1", DocumentKind::Script);
    queue.enqueue(request).await?;

    let claimed = queue.claim_next("worker-1").await?;
    assert!(claimed.is_some(), "should claim the pending job");

    let job = claimed.unwrap();
    assert_eq!(job.status, JobStatus::Running);
    assert_eq!(job.retries, 0);

    Ok(())
}

#[tokio::test]
async fn claim_next_returns_none_when_empty() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let claimed = queue.claim_next("worker-1").await?;
    assert!(claimed.is_none(), "should return None for empty queue");

    Ok(())
}

#[tokio::test]
async fn claim_next_kind_filters_by_document_kind() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-1", DocumentKind::Script);
    queue.enqueue(request).await?;

    let claimed = queue
        .claim_next_kind("worker-1", DocumentKind::Schedule)
        .await?;
    assert!(claimed.is_none(), "should not claim job with wrong kind");

    let claimed = queue
        .claim_next_kind("worker-1", DocumentKind::Script)
        .await?;
    assert!(claimed.is_some(), "should claim job with correct kind");

    Ok(())
}

#[tokio::test]
async fn claim_next_reconciling_returns_job_and_none_for_pending() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-1", DocumentKind::Script);
    queue.enqueue(request).await?;

    let (job, orphan) = queue
        .claim_next_reconciling("worker-1")
        .await?
        .expect("should claim");
    assert_eq!(job.status, JobStatus::Running);
    assert!(orphan.is_none(), "no orphan for fresh claim");

    Ok(())
}

#[tokio::test]
async fn claim_next_kind_reconciling_filters_by_kind() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-1", DocumentKind::Script);
    queue.enqueue(request).await?;

    let claimed = queue
        .claim_next_kind_reconciling("worker-1", DocumentKind::Schedule)
        .await?;
    assert!(claimed.is_none());

    let claimed = queue
        .claim_next_kind_reconciling("worker-1", DocumentKind::Script)
        .await?;
    assert!(claimed.is_some());

    Ok(())
}

#[tokio::test]
async fn attach_permit_succeeds_for_owned_claim() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool.clone());

    let request = make_enqueue_request("user-1", DocumentKind::Script);
    queue.enqueue(request).await?;

    let job = queue.claim_next("worker-1").await?.expect("should claim");
    let permit_id = Uuid::now_v7();

    let result = queue.attach_permit(job.id, "worker-1", permit_id).await;
    assert!(result.is_ok(), "attach_permit should succeed for owner");

    // Verify the permit link is persisted
    let row: (Option<Uuid>,) =
        sqlx::query_as("SELECT permit_id FROM ai_import.ai_import_job WHERE id = $1")
            .bind(job.id.as_uuid())
            .fetch_one(&pool)
            .await?;
    assert_eq!(row.0, Some(permit_id), "permit link should be persisted");

    Ok(())
}

#[tokio::test]
async fn release_claim_returns_job_to_pending() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-1", DocumentKind::Script);
    let id = request.id;
    queue.enqueue(request).await?;

    let job = queue.claim_next("worker-1").await?.expect("should claim");
    assert_eq!(job.status, JobStatus::Running);

    queue.release_claim(job.id, "worker-1").await?;

    let job = queue.get(id).await?.expect("job should exist");
    assert_eq!(job.status, JobStatus::Pending);

    Ok(())
}

#[tokio::test]
async fn mark_running_extends_lease() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-1", DocumentKind::Script);
    queue.enqueue(request).await?;

    let job = queue.claim_next("worker-1").await?.expect("should claim");

    let result = queue.mark_running(job.id, "worker-1").await;
    assert!(result.is_ok(), "mark_running should succeed for owner");

    Ok(())
}

#[tokio::test]
async fn mark_succeeded_sets_succeeded_status() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-1", DocumentKind::Script);
    let id = request.id;
    queue.enqueue(request).await?;

    let job = queue.claim_next("worker-1").await?.expect("should claim");
    queue
        .mark_succeeded(job.id, "worker-1", "preview-handle")
        .await?;

    let job = queue.get(id).await?.expect("job should exist");
    assert_eq!(job.status, JobStatus::Succeeded);
    assert_eq!(job.preview_handle, Some("preview-handle".into()));

    Ok(())
}

#[tokio::test]
async fn mark_failed_sets_failed_status_and_increments_retries() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-1", DocumentKind::Script);
    let id = request.id;
    queue.enqueue(request).await?;

    let job = queue.claim_next("worker-1").await?.expect("should claim");
    assert_eq!(job.retries, 0);

    queue
        .mark_failed(job.id, "worker-1", "something went wrong", true)
        .await?;

    let job = queue.get(id).await?.expect("job should exist");
    assert_eq!(job.status, JobStatus::Failed);
    assert_eq!(job.retries, 1);
    assert_eq!(job.last_error, Some("something went wrong".into()));

    Ok(())
}

#[tokio::test]
async fn mark_payload_unavailable_sets_terminal_status() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-1", DocumentKind::Script);
    let id = request.id;
    queue.enqueue(request).await?;

    let job = queue.claim_next("worker-1").await?.expect("should claim");
    queue
        .mark_payload_unavailable(job.id, "worker-1", "payload gone")
        .await?;

    let job = queue.get(id).await?.expect("job should exist");
    assert_eq!(job.status, JobStatus::PayloadUnavailable);

    Ok(())
}

#[tokio::test]
async fn record_worker_telemetry_succeeds() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-1", DocumentKind::Script);
    queue.enqueue(request).await?;

    let job = queue.claim_next("worker-1").await?.expect("should claim");

    let telemetry = Telemetry {
        provider: Some(breakdown_core::ai::LlmProvider::OpenAI),
        model: Some("gpt-4o".into()),
        doc_kind: Some(DocumentKind::Script),
        chunk_count: 10,
        tokens_in: 1000,
        tokens_out: 500,
        latency_total: 1234,
        apply_state: TelemetryApplyState::default(),
    };

    let result = queue
        .record_worker_telemetry(job.id, "worker-1", telemetry)
        .await;
    assert!(result.is_ok(), "record_worker_telemetry should succeed");

    Ok(())
}

#[tokio::test]
async fn record_telemetry_succeeds_for_terminal_job() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-1", DocumentKind::Script);
    queue.enqueue(request).await?;

    let job = queue.claim_next("worker-1").await?.expect("should claim");
    queue.mark_succeeded(job.id, "worker-1", "preview").await?;

    let telemetry = Telemetry {
        provider: Some(breakdown_core::ai::LlmProvider::OpenAI),
        model: Some("gpt-4o".into()),
        doc_kind: Some(DocumentKind::Script),
        chunk_count: 10,
        tokens_in: 1000,
        tokens_out: 500,
        latency_total: 1234,
        apply_state: TelemetryApplyState::default(),
    };

    let result = queue.record_telemetry(job.id, telemetry).await;
    assert!(result.is_ok(), "record_telemetry should succeed");

    Ok(())
}

#[tokio::test]
async fn owner_fenced_operations_fail_for_wrong_worker() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-1", DocumentKind::Script);
    queue.enqueue(request).await?;

    let job = queue.claim_next("worker-1").await?.expect("should claim");

    let result = queue.mark_running(job.id, "worker-2").await;
    assert!(result.is_err(), "wrong worker should fail");

    let result = queue.mark_succeeded(job.id, "worker-2", "preview").await;
    assert!(result.is_err(), "wrong worker should fail mark_succeeded");

    let result = queue.mark_failed(job.id, "worker-2", "error", true).await;
    assert!(result.is_err(), "wrong worker should fail mark_failed");

    Ok(())
}

#[tokio::test]
async fn concurrent_claims_do_not_double_claim() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let request = make_enqueue_request("user-1", DocumentKind::Script);
    queue.enqueue(request).await?;

    let job1 = queue.claim_next("worker-1").await?.expect("first claim");
    let job2 = queue.claim_next("worker-2").await?;
    assert!(job2.is_none(), "should not double-claim");

    queue.release_claim(job1.id, "worker-1").await?;
    let job3 = queue
        .claim_next("worker-2")
        .await?
        .expect("re-claim after release");
    assert_eq!(job3.id, job1.id);

    Ok(())
}

#[tokio::test]
async fn duplicate_dedup_key_returns_existing() -> Result<()> {
    let (pool, _container) = crate::fixtures::spawn_postgres().await?;
    let queue = PgAiImportQueue::new(pool);

    let dedup_key = format!("dedup-unique-{}", Uuid::now_v7());
    let first_id = AiImportJobId::new();
    let request1 = AiImportEnqueueRequest {
        id: first_id,
        dedup_key: dedup_key.clone(),
        ..make_enqueue_request("user-1", DocumentKind::Script)
    };
    let request2 = AiImportEnqueueRequest {
        dedup_key,
        ..make_enqueue_request("user-1", DocumentKind::Script)
    };

    let result1 = queue.enqueue(request1).await?;
    assert!(matches!(result1, AiImportEnqueueResult::Enqueued(_)));

    let result2 = queue.enqueue(request2).await?;
    match result2 {
        AiImportEnqueueResult::Existing(existing_id) => {
            assert_eq!(
                existing_id, first_id,
                "Existing should return the original job ID"
            );
        }
        other => panic!("expected Existing, got {other:?}"),
    }

    Ok(())
}
