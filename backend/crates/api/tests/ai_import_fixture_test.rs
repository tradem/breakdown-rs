// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Issue #748 — the stored AI-import preview fixture
//! (`POST /v1/__fixtures/ai-import-preview`, `test-support` builds only).
//!
//! The Gherkin harness cannot make the AI worker produce a Pass-2 preview on
//! demand, so the harness seeds one instead. These cases pin the fixture's
//! contract: a well-formed payload yields a **succeeded** job whose stored
//! preview is exactly the bytes the runner sent (readable through the same
//! `AiPreviewStore` the preview handler reads), a malformed payload is
//! rejected before any row is written, and a busy queue fails the seeding step
//! loudly while leaving the foreign job untouched.
//!
//! The whole file is test-support-gated like the route it exercises; the
//! harness root declares the shared `common` module (see `tests/README.md`).

#![cfg(feature = "test-support")]
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)] // tests

use std::sync::Arc;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;
use uuid::Uuid;

use api::ai_import_fixture::ai_import_fixture_routes;
use api::routes::apply_api_middleware;
use api::state::AppState;
use api::versioning::DeprecationRegistry;

use breakdown_core::ai::{
    AiImportJob, AiImportJobId, AiImportQueue, DocumentKind, JobStatus, ScriptContext, SourceFormat,
};
use infra::ai::AiPreviewStore as _;

// `Ports` is imported for method resolution on `AppState::ports`.
use api::state::Ports as _;

use crate::common::FakePorts;

const DEV_SUB: &str = "dev-e2e";
const FIXTURE_PATH: &str = "/__fixtures/ai-import-preview";

/// A stored `ScriptContext` in the shape the frontend preview screen parses.
fn script_payload() -> String {
    r#"{
        "title": "Fixture-Pilot",
        "scenes": [
            {
                "draft_ref": "row-1",
                "scene_number": 1,
                "characters": ["BEN"],
                "outfits": [
                    {"character_name": "BEN", "name": "Zivil-Look", "source_quote": "trägt Zivil"}
                ]
            }
        ],
        "uncertainties": []
    }"#
    .to_owned()
}

/// Mount the real middleware stack (dev auth + the cfg-gated fixture route) over
/// `FakePorts` — mirroring `app_router`'s `/v1` composition.
fn test_app(state: AppState<FakePorts>) -> axum::Router {
    let auth = Arc::new(api::auth::AuthState::dev(api::auth::CurrentUser::dummy(
        DEV_SUB,
    )));
    let authz = Arc::new(api::auth::authorization::AuthorizationState::new(
        Arc::new(
            api::auth::authorization::MembershipAuthorizationPolicy::new(
                state.ports.membership_repo.clone().into(),
            ),
        ),
        /* enforce = */ true,
    ));
    apply_api_middleware(
        axum::Router::new().nest("/v1", ai_import_fixture_routes()),
        auth,
        authz,
        DeprecationRegistry::new(),
    )
    .with_state(state)
}

async fn post_fixture(app: &axum::Router, payload: &str) -> (StatusCode, String) {
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1{FIXTURE_PATH}"))
                .header("content-type", "application/json")
                .body(Body::from(payload.to_owned()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    (status, String::from_utf8_lossy(&bytes).into_owned())
}

/// A foreign `pending` script job, older than anything the fixture enqueues —
/// the queue hands out jobs oldest-first.
fn foreign_pending_job() -> AiImportJob {
    AiImportJob {
        id: AiImportJobId::from_uuid(Uuid::now_v7()),
        user_id: breakdown_core::shared::UserId::from_sub(DEV_SUB),
        document_kind: DocumentKind::Script,
        source_format: SourceFormat::Csv,
        block_id: None,
        dedup_key: "foreign".into(),
        document_digest: "foreign-digest".into(),
        source_handle: "foreign-source".into(),
        status: JobStatus::Pending,
        preview_handle: None,
        last_error: None,
        retries: 0,
        progress: None,
        next_attempt_at: None,
        attempts: Vec::new(),
        max_retries: 5,
        created_at: chrono::Utc::now() - chrono::Duration::hours(1),
        updated_at: chrono::Utc::now() - chrono::Duration::hours(1),
        telemetry: None,
        cost: None,
        source_file_name: None,
        applied_episodes: Vec::new(),
    }
}

#[tokio::test]
async fn seeds_a_succeeded_job_whose_stored_preview_is_the_payload() {
    let state = AppState::new(FakePorts::default());
    let app = test_app(state.clone());

    let (status, body) = post_fixture(&app, &script_payload()).await;
    assert_eq!(status, StatusCode::CREATED, "body: {body}");

    let job_id: Uuid = serde_json::from_str::<serde_json::Value>(&body)
        .unwrap()
        .get("job_id")
        .and_then(serde_json::Value::as_str)
        .unwrap()
        .parse()
        .unwrap();
    let job_id = AiImportJobId::from_uuid(job_id);

    let job = state
        .ports
        .ai_import_queue()
        .get(job_id)
        .await
        .unwrap()
        .expect("the fixture must leave a readable job row");
    assert_eq!(job.status, JobStatus::Succeeded);
    assert_eq!(
        job.user_id,
        breakdown_core::shared::UserId::from_sub(DEV_SUB)
    );
    assert_eq!(job.document_kind, DocumentKind::Script);
    // Owner-only visibility: no season/block on the job, so `authorize_ai_job`
    // cannot 403 on a season role the harness never seeded.
    assert!(job.block_id.is_none());

    let handle = job.preview_handle.expect("succeeded job carries a handle");
    let stored = state
        .ports
        .ai_preview_store()
        .get(&handle)
        .await
        .unwrap()
        .expect("the preview blob must be stored under the job's handle");
    // The stored bytes are the caller's own payload — the production preview
    // parser reads exactly this shape.
    let parsed: ScriptContext = serde_json::from_slice(&stored).unwrap();
    assert_eq!(parsed.title.as_deref(), Some("Fixture-Pilot"));
    assert_eq!(parsed.scenes.len(), 1);
    assert_eq!(parsed.scenes[0].outfits.len(), 1);
}

#[tokio::test]
async fn rejects_a_malformed_payload_without_writing_any_row() {
    let state = AppState::new(FakePorts::default());
    let app = test_app(state.clone());

    let (status, body) = post_fixture(&app, r#"{"title": "no scenes here"}"#).await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "body: {body}");
    assert!(
        body.contains("domain.validation"),
        "a malformed fixture is a registered problem document, got: {body}"
    );
    assert!(
        state.ports.ai_import_queue.jobs.lock().await.is_empty(),
        "validation runs before the enqueue, so no job row may exist"
    );
}

#[tokio::test]
async fn seeds_beside_pending_work_without_claiming_it_or_leaking_a_job() {
    let state = AppState::new(FakePorts::default());
    // A foreign job sits in the runnable pool. The fixture inserts a TERMINAL
    // row, so it must neither compete for the claim nor disturb this job —
    // the failure modes of the enqueue→claim design CodeRabbit flagged on
    // PR #749 (a lost claim, and a leftover `pending` fixture row per retry).
    let foreign = foreign_pending_job();
    let foreign_id = foreign.id;
    state.ports.ai_import_queue.seed(foreign).await;
    let app = test_app(state.clone());

    let (status, body) = post_fixture(&app, &script_payload()).await;

    assert_eq!(status, StatusCode::CREATED, "body: {body}");
    let job_id = serde_json::from_str::<serde_json::Value>(&body)
        .unwrap()
        .get("job_id")
        .and_then(serde_json::Value::as_str)
        .unwrap()
        .parse::<Uuid>()
        .unwrap();

    // The foreign job is untouched: still pending, no attempt charged.
    let reloaded = state
        .ports
        .ai_import_queue()
        .get(foreign_id)
        .await
        .unwrap()
        .expect("the foreign job must survive");
    assert_eq!(reloaded.status, JobStatus::Pending);
    assert_eq!(reloaded.retries, 0);

    // Exactly one fixture row exists — terminal, so nothing is left runnable.
    let jobs = state.ports.ai_import_queue.jobs.lock().await;
    assert_eq!(
        jobs.len(),
        2,
        "only the foreign job and the fixture job exist"
    );
    let fixture = jobs.get(&job_id).expect("the fixture job must be stored");
    assert_eq!(fixture.status, JobStatus::Succeeded);
}
