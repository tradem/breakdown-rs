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
use breakdown_core::ai::{
    AiImportEnqueueRequest, AiImportJobId, AiImportQueue as _, AiImportTarget, DocumentKind,
    ScriptContext, SourceFormat,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
// `BlockRepository` is imported for method resolution on the generic
// `P::BlockRepo` port (same seam `handlers` uses).
use breakdown_core::block::ports::BlockRepository as _;
use breakdown_core::membership::policy::{Action, PolicyDecision, SeasonAuthContext};
use breakdown_core::shared::{BlockId, SeasonId};
// The payload-store traits live in `infra` and are imported for method
// resolution on the generic `P::AiDocumentStore` / `P::AiPreviewStore` ports
// (same seam `handlers` uses).
use infra::ai::{AiDocumentStore as _, AiPreviewStore as _};

use crate::auth::CurrentUser;
// `problems::Query` rather than the raw axum extractor: a rejected query string
// must be an RFC 9457 problem document (`http.bad-query-param`), not axum's
// plain-text `400` (ADR-031).
use crate::problems::{ApiError, Query};

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

/// Optional query parameters that give the seeded job a **target block**.
///
/// The body stays exactly the stored preview (the Gherkin arrange steps send a
/// `ScriptContext` and nothing else), so the parameters are additive and
/// optional. A preview-only job is enough for every screen scenario, but not
/// for one that *executes* the preview: `POST /apply` refuses a job without a
/// block (`ai-import.target-missing`) and the target attach needs the season the
/// job was authorized for, which a body-less fixture job has no way to name. The
/// #900 apply-attribution benchmark is that caller — it applies a seeded 49-scene
/// preview and reads the row-phase numbers, dev data untouched.
#[derive(Debug, Default, Deserialize)]
pub struct FixtureTargetQuery {
    /// The season `block_id` is claimed to belong to. Checked against the block
    /// projection (and refused on a mismatch); the block's own season is what
    /// the seed is authorized against.
    season_id: Option<Uuid>,
    /// That season's production-global number (`AiImportTarget::season_number`).
    season_number: Option<i32>,
    /// The block the preview will apply into.
    block_id: Option<Uuid>,
    /// The block's production-global number, when the caller knows it (display
    /// metadata only, exactly as on the real upload path).
    block_number: Option<i32>,
}

impl FixtureTargetQuery {
    /// The target the seeded job carries, or `None` for a target-less fixture.
    ///
    /// All identifying parts or none: a half-specified target would seed a job
    /// whose apply can never resolve its block — the state the real upload path
    /// refuses up front.
    fn target(&self) -> Result<Option<AiImportTarget>, ApiError> {
        match (self.season_id, self.season_number, self.block_id) {
            (None, None, None) => Ok(None),
            (Some(season_id), Some(season_number), Some(_)) => Ok(Some(AiImportTarget {
                season_id: SeasonId::from_uuid(season_id),
                season_number,
                block_number: self.block_number,
            })),
            _ => Err(ApiError::Validation(
                "a fixture target needs season_id, season_number and block_id together",
            )),
        }
    }

    /// The block id the job's apply is pinned to (`None` for a target-less job).
    fn block_id(&self) -> Option<BlockId> {
        self.block_id.map(BlockId::from_uuid)
    }
}

/// The block-scoped half of the fixture's `AUTHZ-GATE`.
///
/// A **block-scoped** seed (`block_id` + `target`, the #900 benchmark's shape)
/// is different from a target-less one: it seeds the state `POST /apply`
/// subsequently writes scenes into, so it is authorized exactly like the upload
/// path's `X-Active-Block` arm. Without this, a caller holding a role in season A
/// could name A as the target and B's block as the write target, and the apply
/// would then accept an episode in block B.
///
/// Two invariants, both resolved at the API edge (the handler is the only
/// legitimate read-model consumer, AGENTS.md §1):
///
/// * the block projection decides **which** season is written into — the
///   caller's `season_id` parameter only has to AGREE with it (a contradiction
///   would hand `/apply` a job whose two halves name two different seasons,
///   CWE-639);
/// * the caller must hold an active costume-dept role in that season — the same
///   `effective_costume_role_in_season` predicate the upload path evaluates,
///   fail-closed, with a read-model failure surfacing as a mapped error rather
///   than a silent 403.
async fn authorize_fixture_target<P: crate::state::Ports>(
    state: &AppState<P>,
    current_user: &CurrentUser,
    target: &AiImportTarget,
    block_id: BlockId,
) -> Result<(), ApiError> {
    let block = state.ports.block_repo().find_by_id(block_id.0).await?;
    if block.season_id != target.season_id {
        return Err(ApiError::Validation(
            "fixture block does not belong to the target season",
        ));
    }
    // AUTHZ-GATE: the block's season is the authorization scope of a
    // block-scoped fixture seed.
    let decision = state
        .authorization_policy
        .authorize_season_result(&SeasonAuthContext {
            actor: current_user.sub.clone(),
            season_id: block.season_id,
            action: Action::Write,
        })
        .await?;
    if decision != PolicyDecision::Allow {
        return Err(ApiError::AiImportForbidden(
            "not authorized for this AI import job",
        ));
    }
    Ok(())
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
    Query(target_query): Query<FixtureTargetQuery>,
    body: Bytes,
) -> Result<Response, ApiError> {
    // AUTHZ-GATE: this fixture's base authorization story is OWNERSHIP, not a
    // season/block policy — deliberately, because a target-less seeded job
    // belongs to no tenant resource:
    //   * the row is written with `user_id = current_user.sub`, so it is
    //     invisible to every other member (`authorize_ai_job` gates the
    //     resulting status/preview/apply reads on the owner);
    //   * a target-less job names no season/block at all, so there is nothing
    //     to call a policy predicate with — `authorize_ai_block` (the upload
    //     path's gate) derives its scope from `X-Active-Block`, which this
    //     route does not carry;
    //   * the privilege is bounded by construction: the caller can only create
    //     their OWN job from bytes they sent, never read or mutate anyone
    //     else's;
    //   * and the whole module is compile-time absent in release builds, so no
    //     production caller can reach this write at all.
    // A **block-scoped** fixture (`block_id` + `target`, the #900 benchmark's
    // shape) is a different story: it seeds the state `POST /apply` then writes
    // scenes into, so it carries the block's season and is authorized exactly
    // like the upload path's block arm — otherwise a caller holding a role in
    // season A could name A as the target and B's block as the write target.
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
    // Resolve the optional target BEFORE any state is written, for the same
    // reason the payload is validated first: a rejected request must not leave
    // blobs behind.
    let target = target_query.target()?;
    let block_id = target_query.block_id();
    match (target.as_ref(), block_id) {
        (Some(target), Some(block_id)) => {
            authorize_fixture_target(&state, &current_user, target, block_id).await?;
        }
        (None, None) => {}
        // `FixtureTargetQuery::target` already refuses a half-specified
        // target; this arm keeps the pairing closed if that ever regresses.
        _ => {
            return Err(ApiError::Validation(
                "a fixture target needs season_id, season_number and block_id together",
            ));
        }
    }
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
                // Issue #871: no breaker snapshot in this fixture — the job is
                // never breaker-filtered, which is the honest degradation.
                provider: None,
                model: None,
                id: job_id,
                user_id: current_user.sub.clone(),
                document_kind: DocumentKind::Script,
                // Any declarable format: the fixture never extracts anything.
                // The format only steers the worker's extraction path, which a
                // terminal row never reaches.
                source_format: SourceFormat::Csv,
                block_id,
                // Unique per call: the dedup index would otherwise collide with
                // a previous run's fixture row.
                dedup_key: format!("test-support-fixture|{}", job_id.as_uuid()),
                document_digest: format!("test-support-fixture-digest|{}", job_id.as_uuid()),
                source_handle,
                source_file_name: None,
                // Target-less unless the caller named one (see
                // [`FixtureTargetQuery`]): the Gherkin arrange steps seed a
                // preview to LOOK at, the #900 benchmark seeds one to APPLY.
                target,
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
