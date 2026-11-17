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
use jiff::SignedDuration;
use jiff::Timestamp;
use tower::ServiceExt;
use uuid::Uuid;

use api::ai_import_fixture::ai_import_fixture_routes;
use api::routes::apply_api_middleware;
use api::state::AppState;
use api::versioning::DeprecationRegistry;

use breakdown_core::ai::{
    AiImportJob, AiImportJobId, AiImportQueue, DocumentKind, JobStatus, ScriptContext,
    SourceFormat, category_conflict_uncertainties, ensure_script_applyable, episode_group_refs,
};
use breakdown_core::character::CharacterCategory;
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
    post_fixture_with_query(app, payload, "").await
}

/// Same POST, with a query string appended (the optional target parameters).
async fn post_fixture_with_query(
    app: &axum::Router,
    payload: &str,
    query: &str,
) -> (StatusCode, String) {
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1{FIXTURE_PATH}{query}"))
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
        // Issue #871: pre-#871 row — no provider snapshot, no hold.
        provider: None,
        model: None,
        provider_hold: None,
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
        created_at: Timestamp::now() - SignedDuration::from_hours(1),
        updated_at: Timestamp::now() - SignedDuration::from_hours(1),
        telemetry: None,
        cost: None,
        source_file_name: None,
        target: None,
        applied_episodes: Vec::new(),
        // No Decision Model outcome recorded by a test fixture (issue #767).
        decision_telemetry: None,
        apply_progress: None,
        applied: false,
        // Issue #899: this literal never ran a durable apply run.
        apply_state: breakdown_core::ai::ApplyState::Idle,
        apply_run_id: None,
        apply_result: None,
    }
}

/// A resolved block for the block-scoped seed: the fixture reads the block
/// projection and authorizes against ITS season, so the row has to exist (the
/// fake's unknown-id fallback mints a random season and would refuse every
/// target).
async fn seed_block(
    state: &AppState<FakePorts>,
    block: breakdown_core::shared::BlockId,
    season: breakdown_core::shared::SeasonId,
) {
    state.ports.block_repo.blocks.lock().await.insert(
        block.0,
        breakdown_core::block::views::BlockView {
            id: block.0,
            season_id: season,
            project_id: breakdown_core::shared::ProjectId::new(),
            number: 1,
            start_date: None,
            end_date: None,
            version: breakdown_core::shared::AggregateVersion::INITIAL,
            updated_at: Timestamp::now(),
        },
    );
}

/// Grant the dev caller a costume-dept role in `season` (the predicate
/// `authorize_season_result` resolves through `effective_costume_role_in_season`).
async fn allow_costume_role(state: &AppState<FakePorts>, season: breakdown_core::shared::SeasonId) {
    state
        .ports
        .membership_repo
        .piece_role_by_season
        .lock()
        .await
        .insert(season.0, Ok(true));
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

/// The optional target parameters (issue #900's attribution benchmark): a caller
/// that wants to APPLY the seeded preview names the block, so the job carries the
/// block id and the season snapshot `POST /apply` gates on. Without them the job
/// stays target-less, which every preview-screen scenario relies on.
#[tokio::test]
async fn the_optional_target_parameters_seed_a_block_scoped_job() {
    use breakdown_core::shared::{BlockId, SeasonId};

    let state = AppState::new(FakePorts::default());
    let app = test_app(state.clone());
    let season = SeasonId::new();
    let block = BlockId::new();
    seed_block(&state, block, season).await;
    // A block-scoped seed is authorized against the block's season, so the
    // caller must hold a costume role there (the upload path's gate).
    allow_costume_role(&state, season).await;

    let query = format!(
        "?season_id={}&season_number=3&block_id={}&block_number=7",
        season.0, block.0
    );
    let (status, body) = post_fixture_with_query(&app, &script_payload(), &query).await;
    assert_eq!(status, StatusCode::CREATED, "body: {body}");

    let job_id: Uuid = serde_json::from_str::<serde_json::Value>(&body)
        .unwrap()
        .get("job_id")
        .and_then(serde_json::Value::as_str)
        .unwrap()
        .parse()
        .unwrap();
    let job = state
        .ports
        .ai_import_queue()
        .get(AiImportJobId::from_uuid(job_id))
        .await
        .unwrap()
        .expect("the fixture must leave a readable job row");

    assert_eq!(job.block_id, Some(block));
    let target = job.target.expect("a named target must be snapshotted");
    assert_eq!(target.season_id, season);
    assert_eq!(target.season_number, 3);
    assert_eq!(target.block_number, Some(7));
}

/// A block-scoped fixture seed is authorized against the **block's** season, not
/// against the `season_id` the caller typed — otherwise a caller holding a role
/// in season A could name A as the target and B's block as the write target, and
/// `POST /apply` then writes scenes into block B.
#[tokio::test]
async fn a_target_whose_block_belongs_to_another_season_is_refused() {
    use breakdown_core::shared::{BlockId, SeasonId};

    let state = AppState::new(FakePorts::default());
    let app = test_app(state.clone());
    let claimed = SeasonId::new();
    let real = SeasonId::new();
    let block = BlockId::new();
    seed_block(&state, block, real).await;
    // The caller DOES hold a role in the season it claims — the fixture must
    // still refuse, because the block says otherwise.
    allow_costume_role(&state, claimed).await;

    let query = format!(
        "?season_id={}&season_number=1&block_id={}&block_number=1",
        claimed.0, block.0
    );
    let (status, body) = post_fixture_with_query(&app, &script_payload(), &query).await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "body: {body}");
    assert!(
        body.contains("domain.validation"),
        "a contradictory target is a registered problem document, got: {body}"
    );
    assert!(
        state.ports.ai_import_queue.jobs.lock().await.is_empty(),
        "the target is checked before the blobs, so no job row may exist"
    );
}

/// The block's season is the authorization scope: a caller with no costume role
/// there gets the AI-import 403, and nothing is written.
#[tokio::test]
async fn a_block_scoped_target_without_a_costume_role_is_forbidden() {
    use breakdown_core::shared::{BlockId, SeasonId};

    let state = AppState::new(FakePorts::default());
    let app = test_app(state.clone());
    let season = SeasonId::new();
    let block = BlockId::new();
    seed_block(&state, block, season).await;

    let query = format!(
        "?season_id={}&season_number=1&block_id={}&block_number=1",
        season.0, block.0
    );
    let (status, body) = post_fixture_with_query(&app, &script_payload(), &query).await;

    assert_eq!(status, StatusCode::FORBIDDEN, "body: {body}");
    assert!(
        body.contains("ai-import.forbidden"),
        "the block gate reuses the scoped AI-import forbiddance, got: {body}"
    );
    assert!(
        state.ports.ai_import_queue.jobs.lock().await.is_empty(),
        "authorization precedes the blobs, so no job row may exist"
    );
}

/// A query string the extractor cannot deserialize is a registered problem
/// document (`http.bad-query-param`), not axum's plain-text rejection — the
/// fixture route sits behind the same middleware stack as every real route.
#[tokio::test]
async fn a_malformed_query_parameter_answers_a_problem_document() {
    let state = AppState::new(FakePorts::default());
    let app = test_app(state.clone());

    let (status, body) =
        post_fixture_with_query(&app, &script_payload(), "?season_id=not-a-uuid").await;

    assert_eq!(status, StatusCode::BAD_REQUEST, "body: {body}");
    assert!(
        body.contains("http.bad-query-param"),
        "a malformed query parameter must be the registered problem code, got: {body}"
    );
}

/// A half-specified target cannot seed a job whose apply could resolve its
/// block, so it is refused before anything is written (no blob, no row).
#[tokio::test]
async fn a_half_specified_target_is_refused_before_any_write() {
    use breakdown_core::shared::BlockId;

    let state = AppState::new(FakePorts::default());
    let app = test_app(state.clone());

    let query = format!("?block_id={}", BlockId::new().0);
    let (status, body) = post_fixture_with_query(&app, &script_payload(), &query).await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "body: {body}");
    assert!(
        body.contains("domain.validation"),
        "a half-specified target is a registered problem document, got: {body}"
    );
    assert!(
        state.ports.ai_import_queue.jobs.lock().await.is_empty(),
        "the target is resolved before the blobs, so no job row may exist"
    );
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

/// The recorded preview the issue #826 prompt revision is supposed to produce
/// for the two marker shapes that used to become blocking `field_ambiguity`
/// entries (the live job: 28 entries on 8 `(scene_index, field)` pairs).
///
/// An `(OT)` cast list is `extra` on every row, and the page headers read
/// `Ep.: 292/15` / `Ep.: 292/16` — ONE episode 292, the suffix a page index
/// inside it. The prompt now states both rules (pinned by the embedded-wording
/// tests in `infra::ai::catalog_misc_tests`); this case pins their **contract**:
/// the shape a model following those rules emits survives the stored-preview
/// pipeline with zero blocking uncertainties, so the #663 gate needs no tick and
/// the #821 acknowledgement has nothing to aggregate.
///
/// A recorded preview, not a live model call: CI has no LLM, and the issue
/// explicitly accepts a fixture in place of one.
fn recorded_ot_and_episode_suffix_preview() -> String {
    r#"{
        "title": "Klinik am See",
        "scenes": [
            {
                "draft_ref": "1   A/T - BAUERNHOF",
                "scene_number": 1,
                "location": "BAUERNHOF",
                "mood": "A/T",
                "characters": [
                    {"name": "LEYLA", "category": "main_cast"},
                    {"name": "OP-PERSONAL", "category": "extra"},
                    {"name": "BESUCHER", "category": "extra"}
                ],
                "outfits": [],
                "episode": {"number": 292, "title": null}
            },
            {
                "draft_ref": "2   I/T - KUECHE",
                "scene_number": 2,
                "location": "KUECHE",
                "mood": "I/T",
                "characters": [
                    {"name": "LEYLA", "category": "main_cast"},
                    {"name": "OP-PERSONAL", "category": "extra"},
                    {"name": "BESUCHER", "category": "extra"}
                ],
                "outfits": [],
                "episode": {"number": 292, "title": null}
            }
        ],
        "uncertainties": []
    }"#
    .to_owned()
}

#[tokio::test]
async fn a_recorded_ot_cast_list_and_episode_suffix_preview_carries_no_blocking_uncertainty() {
    let state = AppState::new(FakePorts::default());
    let app = test_app(state.clone());

    let (status, body) = post_fixture(&app, &recorded_ot_and_episode_suffix_preview()).await;
    assert_eq!(status, StatusCode::CREATED, "body: {body}");

    let job_id = AiImportJobId::from_uuid(
        serde_json::from_str::<serde_json::Value>(&body)
            .unwrap()
            .get("job_id")
            .and_then(serde_json::Value::as_str)
            .unwrap()
            .parse::<Uuid>()
            .unwrap(),
    );
    let job = state
        .ports
        .ai_import_queue()
        .get(job_id)
        .await
        .unwrap()
        .expect("the fixture must leave a readable job row");
    let handle = job.preview_handle.expect("succeeded job carries a handle");
    let stored = state
        .ports
        .ai_preview_store()
        .get(&handle)
        .await
        .unwrap()
        .expect("the preview blob must be stored under the job's handle");
    let preview: ScriptContext = serde_json::from_slice(&stored).unwrap();

    assert_eq!(preview.scenes.len(), 2);
    for scene in &preview.scenes {
        // `(OT)` is a stated classification signal: `extra`, no uncertainty.
        let ot_figures: Vec<_> = scene
            .characters
            .iter()
            .filter(|character| character.name != "LEYLA")
            .collect();
        assert_eq!(ot_figures.len(), 2, "both OT figures are listed");
        for figure in ot_figures {
            assert_eq!(
                figure.category,
                CharacterCategory::Extra,
                "an (OT) figure is a background performer, not an ambiguity"
            );
        }
    }

    // Zero blocking entries: nothing for the #663 gate to tick, and the #695
    // server-side conflict scan adds none either (the classification agrees
    // across rows).
    assert!(
        preview.uncertainties.is_empty(),
        "the recorded preview carries no uncertainty: {}",
        preview.uncertainties.len()
    );
    assert!(
        category_conflict_uncertainties(&preview).is_empty(),
        "agreeing `extra` classifications are not a conflict"
    );
    assert!(
        ensure_script_applyable(&preview, &[]).is_ok(),
        "the apply gate must pass without an acknowledgement"
    );

    // `Ep.: 292/15` and `Ep.: 292/16` are one episode, not two candidates.
    assert_eq!(
        episode_group_refs(&preview),
        vec!["ep:292".to_owned()],
        "the page-header suffix is a page index, not a second episode"
    );
}
