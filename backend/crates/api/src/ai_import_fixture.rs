// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Stored AI-import preview fixtures for the on-device Gherkin harness
//! (issue #748).
//!
//! **Entirely compiled out of production builds:** like
//! [`crate::fault_injection`], every item here lives behind
//! `#[cfg(feature = "test-support")]` at the `pub mod` site in `lib.rs` — a
//! release binary does not contain this code at all. The E2E/Gherkin backend
//! is booted with `cargo run --bin api --features api/test-support`.
//!
//! # Why this exists
//!
//! `features-spec/ai_import_continuity_gap.feature` drives the AI-import
//! preview's Pass-2 outfit provenance badges and the wardrobe-gap candidate
//! picker (OpenSpec `ai-import-decision-outfit-continuity`, issues #745 + #748).
//! The preview screen reads `GET /v1/ai-import/jobs/{id}/preview`, which needs
//! **two** durable pieces of state: a job row owned by the caller whose status
//! is `succeeded`, and the stored payload its `preview_handle` names. A real
//! preview is produced by the AI worker from a paid LLM extraction, so no
//! seeding call can create one — hence this fixture route. It is deliberately
//! NOT part of the utoipa derive: it must never appear in
//! `backend/openapi.yaml` (`openapi_drift` fails if a mounted route leaks into
//! the documented spec), so it stays out of `handlers::routes()` and the
//! `#[openapi]` `paths`.
//!
//! # Contract
//!
//! `POST /v1/__fixtures/ai-import-preview` with a stored `ScriptContext`
//! payload as the JSON body (exactly the bytes a script job stores; it is
//! deserialized here so a malformed fixture fails at seed time instead of
//! surfacing as a `422` on the preview screen). Answers
//! `201 {"job_id": "<uuid>"}`.
//!
//! # Why a direct insert instead of the worker lifecycle
//!
//! The job is created through the ordinary `AiPreviewStore` /
//! `AiDocumentStore` ports and `AiImportQueue::seed_succeeded`, which lands the
//! row **already terminal** (`succeeded`) and pointing at the stored preview in
//! one INSERT. The usual path (`enqueue` → `claim_next_kind` →
//! `mark_succeeded`) is deliberately not used: a claim is not addressable by
//! id — it hands out the oldest runnable job — so on a busy or worker-polled
//! dev queue the fixture would either lose its own job to the worker that won
//! the race, or leave its `pending` row and both blobs behind on every refusal.
//! A terminal row can never be claimed, never competes with real imports, and
//! leaves nothing to clean up: the seeding step either stores a complete,
//! readable preview or fails without touching the queue.
//!
//! Boot requirements for the harness itself (durable payload storage,
//! `AI_IMPORT_ENABLED=1` for the job status screen's SSE stream) are documented
//! in `frontend-flutter/tool/run_gherkin.sh`.

use axum::body::Bytes;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::post;
use axum::{Json, Router};
use serde::Serialize;
use uuid::Uuid;

use breakdown_core::ai::{
    AiImportEnqueueRequest, AiImportJobId, AiImportQueue as _, DocumentKind, ScriptContext,
    SourceFormat,
};
// The payload-store traits live in `infra` and are imported for method
// resolution on the generic `P::AiDocumentStore` / `P::AiPreviewStore` ports
// (same seam `handlers` uses).
use infra::ai::{AiDocumentStore as _, AiPreviewStore as _};

use crate::auth::CurrentUser;
use crate::problems::ApiError;
use crate::state::AppState;

/// The placeholder source document stored for the fixture job. The job never
/// runs (the fixture completes it immediately), so the bytes are inert — they
/// exist so `delete_ai_import_job` and the payload GC have a real handle to
/// clean up.
const FIXTURE_SOURCE: &[u8] = b"breakdown-rs test-support AI import fixture source";

/// `POST /v1/__fixtures/ai-import-preview` (test-support builds only).
#[derive(Debug, Serialize)]
pub struct SeededAiImportPreview {
    /// The real job id the scenario's steps address (`AppWorld.seedIds`).
    pub job_id: Uuid,
}

/// The cfg-gated fixture routes the host-side Gherkin arrange steps call.
///
/// Generic over the state's `Ports` so integration tests can mount the routes
/// over `FakePorts` the same way `app_router` mounts them over
/// `ProductionPorts`.
pub fn ai_import_fixture_routes<P: crate::state::Ports>() -> Router<AppState<P>> {
    Router::new().route(
        "/__fixtures/ai-import-preview",
        post(seed_ai_import_preview::<P>),
    )
}

async fn seed_ai_import_preview<P: crate::state::Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    body: Bytes,
) -> Result<Response, ApiError> {
    // AUTHZ-GATE: this is the fixture's whole authorization story, and it is
    // OWNERSHIP, not a season/block policy — deliberately, because the seeded
    // job belongs to no tenant resource:
    //   * the row is written with `user_id = current_user.sub` and no
    //     `block_id`, so it is invisible to every other member (`authorize_ai_job`
    //     gates the resulting status/preview/apply reads on the owner and
    //     consults the season policy only when a job names a block);
    //   * there is therefore no season/block to call a policy predicate with —
    //     `authorize_ai_block` (the upload path's gate) derives its scope from
    //     `X-Active-Block`, which this route deliberately does not carry;
    //   * the privilege is bounded by construction: the caller can only create
    //     their OWN job from bytes they sent, never read or mutate anyone
    //     else's;
    //   * and the whole module is compile-time absent in release builds, so no
    //     production caller can reach this write at all.
    // A future fixture that seeds block-scoped state MUST add the matching
    // `authorize_season_result` call here.
    //
    // Validate BEFORE any state is written: a payload the production preview
    // parser would reject must fail here, with the fixture's own failure, not
    // as a 422 on the screen under test. The bytes stored are the caller's own
    // (the preview handler parses them again).
    serde_json::from_slice::<ScriptContext>(&body).map_err(|error| {
        tracing::warn!(error = %error, "rejected AI-import preview fixture payload");
        ApiError::Validation("invalid AI preview fixture payload")
    })?;

    let job_id = AiImportJobId::from_uuid(Uuid::now_v7());
    // Blobs first, then the row: the job must never point at a payload that is
    // still being written (the same ordering the real worker uses, where the
    // preview is stored before `mark_succeeded`).
    let source_handle = state
        .ports
        .ai_document_store()
        .put_source(job_id, FIXTURE_SOURCE.to_vec())
        .await?;
    let preview_handle = state
        .ports
        .ai_preview_store()
        .put(job_id, body.to_vec())
        .await?;

    state
        .ports
        .ai_import_queue()
        .seed_succeeded(
            AiImportEnqueueRequest {
                id: job_id,
                user_id: current_user.sub.clone(),
                document_kind: DocumentKind::Script,
                // Any declarable format: the fixture never extracts anything.
                // The format only steers the worker's extraction path, which a
                // terminal row never reaches.
                source_format: SourceFormat::Csv,
                block_id: None,
                // Unique per call: the dedup index would otherwise collide with
                // a previous run's fixture row.
                dedup_key: format!("test-support-fixture|{}", job_id.as_uuid()),
                document_digest: format!("test-support-fixture-digest|{}", job_id.as_uuid()),
                source_handle,
                source_file_name: None,
                // The fixture seeds a preview only; it names no target.
                target: None,
            },
            &preview_handle,
        )
        .await?;

    tracing::info!(
        job_id = %job_id.as_uuid(),
        "seeded a stored AI-import preview fixture (test-support build)"
    );
    Ok((
        StatusCode::CREATED,
        Json(SeededAiImportPreview {
            job_id: job_id.as_uuid(),
        }),
    )
        .into_response())
}
