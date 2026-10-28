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
//! The job is created the way production creates one — `enqueue`, a worker
//! claim, `mark_succeeded` — through the ordinary `AiImportQueue` /
//! `AiPreviewStore` ports, so the fixture exercises the same lifecycle writes
//! the worker does and no port grows a test-only method.
//!
//! # Seeding is claimed once, then retried with a FRESH job
//!
//! The handler claims its own job immediately after enqueueing it. On a dev
//! backend with `AI_IMPORT_ENABLED` set (the Gherkin harness needs it: the job
//! status screen renders from the SSE stream, which only exists for an enabled
//! import) a *running* AI worker polls the same queue and may win that claim.
//! Losing it is recoverable: the fixture never re-claims (the queue is
//! oldest-first, so a second attempt could only touch foreign work) — it
//! enqueues a FRESH job instead, up to [`SEED_ATTEMPTS`] times. The chance that
//! a polling worker steals every attempt is negligible, and a stolen row only
//! ever costs one dead-lettered extraction of a placeholder document.
//!
//! When every attempt loses (the queue holds foreign pending script work, e.g.
//! a hand-queued import on the same dev database), each foreign job is released
//! back to `pending` untouched and the route answers `503` with an actionable
//! message. It never leaves a row claimed, and it never silently seeds a
//! preview the scenario does not control.

use axum::body::Bytes;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::post;
use axum::{Json, Router};
use serde::Serialize;
use uuid::Uuid;

use breakdown_core::ai::{
    AiImportEnqueueRequest, AiImportEnqueueResult, AiImportJobId, AiImportQueue as _, DocumentKind,
    ScriptContext, SourceFormat,
};
// The payload-store traits live in `infra` and are imported for method
// resolution on the generic `P::AiDocumentStore` / `P::AiPreviewStore` ports
// (same seam `handlers` uses).
use infra::ai::{AiDocumentStore as _, AiPreviewStore as _};

use crate::auth::CurrentUser;
use crate::problems::ApiError;
use crate::state::AppState;

/// The synthetic worker id the fixture claims its own job under. Distinct from
/// every real worker id so a leaked `running` row (a crashed fixture) is
/// identifiable in the queue.
const FIXTURE_WORKER: &str = "test-support-ai-import-fixture";

/// The placeholder source document stored for the fixture job. The job never
/// runs (the fixture completes it immediately), so the bytes are inert — they
/// exist so `delete_ai_import_job` and the payload GC have a real handle to
/// clean up.
const FIXTURE_SOURCE: &[u8] = b"breakdown-rs test-support AI import fixture source";

/// How many times a lost claim is retried with a FRESH job. A polling worker
/// that steals one claim cannot steal them all; a genuinely busy queue fails
/// after the budget instead of looping.
const SEED_ATTEMPTS: usize = 3;

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
    for _ in 0..SEED_ATTEMPTS {
        if let Some(job_id) = seed_once(&state, &current_user, &body).await? {
            tracing::info!(
                job_id = %job_id.as_uuid(),
                "seeded a stored AI-import preview fixture (test-support build)"
            );
            return Ok((
                StatusCode::CREATED,
                Json(SeededAiImportPreview {
                    job_id: job_id.as_uuid(),
                }),
            )
                .into_response());
        }
    }
    Err(ApiError::ServiceUnavailable(
        "AI-import fixture could not claim its own job: foreign pending script work is ahead of \
         it in the queue. Drain the dev queue (or run the harness against an empty one) and \
         retry the seeding step.",
    ))
}

/// One seeding attempt.
///
/// `Ok(Some(id))` — the stored preview is ready; `Ok(None)` — the claim went to
/// another job (released again) and the caller should retry with a fresh one.
async fn seed_once<P: crate::state::Ports>(
    state: &AppState<P>,
    current_user: &CurrentUser,
    body: &[u8],
) -> Result<Option<AiImportJobId>, ApiError> {
    // Validate BEFORE any state is written: a fixture payload the production
    // preview parser would reject must fail here, with the fixture's own
    // failure, not as a 422 on the screen under test. The bytes stored are the
    // caller's own (the preview handler parses them again).
    serde_json::from_slice::<ScriptContext>(body).map_err(|error| {
        tracing::warn!(error = %error, "rejected AI-import preview fixture payload");
        ApiError::Validation("invalid AI preview fixture payload")
    })?;

    let job_id = AiImportJobId::from_uuid(Uuid::now_v7());
    // Blobs first, then the row: a claimed job must never point at a payload
    // that is still being written (the crash-window the real worker avoids the
    // same way, by storing the preview before `mark_succeeded`).
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

    let enqueued = state
        .ports
        .ai_import_queue()
        .enqueue(AiImportEnqueueRequest {
            id: job_id,
            user_id: current_user.sub.clone(),
            document_kind: DocumentKind::Script,
            // Any declarable format: the fixture never extracts anything. The
            // format only steers the worker's extraction path, which this job
            // never reaches.
            source_format: SourceFormat::Csv,
            // Owner-only visibility (`authorize_ai_job` gates on the season
            // only when the job names a block), so the fixture needs no
            // seeded season and cannot leak into another member's list.
            block_id: None,
            // Unique per call: the dedup index would otherwise answer
            // `Existing(<earlier job>)` and the scenario would open a preview
            // from a previous run.
            dedup_key: format!("test-support-fixture|{}", job_id.as_uuid()),
            document_digest: format!("test-support-fixture-digest|{}", job_id.as_uuid()),
            source_handle,
        })
        .await?;

    let AiImportEnqueueResult::Enqueued(job_id) = enqueued else {
        // Unreachable by construction (the dedup key carries a fresh uuid);
        // reported rather than panicked, per the no-panics hard rule.
        tracing::error!("AI-import preview fixture hit a dedup collision");
        return Err(ApiError::ServiceUnavailable(
            "AI-import fixture dedup collision; retry the seeding step",
        ));
    };

    // Claim exactly one job. The queue hands out the OLDEST runnable script
    // job, so a second attempt could only claim (and disturb) more foreign
    // work — a retry loop would not converge on ours.
    let claimed = state
        .ports
        .ai_import_queue()
        .claim_next_kind(FIXTURE_WORKER, DocumentKind::Script)
        .await?;
    match claimed {
        Some(job) if job.id == job_id => {}
        Some(foreign) => {
            // Leave the queue exactly as it was: `release_claim` returns the
            // job to `pending` without charging an attempt. The caller retries
            // with a FRESH job rather than re-claiming this one.
            state
                .ports
                .ai_import_queue()
                .release_claim(foreign.id, FIXTURE_WORKER)
                .await?;
            tracing::warn!(
                fixture_job = %job_id.as_uuid(),
                foreign_job = %foreign.id.as_uuid(),
                "AI-import fixture lost its claim; retrying with a fresh job"
            );
            return Ok(None);
        }
        None => {
            tracing::warn!(
                fixture_job = %job_id.as_uuid(),
                "AI-import fixture enqueued a job that was not claimable; retrying"
            );
            return Ok(None);
        }
    }

    state
        .ports
        .ai_import_queue()
        .mark_succeeded(job_id, FIXTURE_WORKER, &preview_handle)
        .await?;

    Ok(Some(job_id))
}
