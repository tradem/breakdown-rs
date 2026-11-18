// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Both HTTP surfaces of one apply run, composed through PostgreSQL (issue #912).
//!
//! The apply-outcome **identity** chain has three seams, and before this case
//! each one was proved on its own:
//!
//! | seam | proof |
//! |---|---|
//! | what PostgreSQL holds | `crates/integration-tests/tests/ai_import_job_progress.rs::a_finished_run_keeps_its_identity_and_frees_the_slot` |
//! | what the frame reports | `handler_ai_import_apply_sse.rs::the_frame_reports_the_owner_then_the_outcomes_run` (`handlers::apply_frame_run_id`, pure) |
//! | what the client compares | `frontend-flutter/test/unit/ai_import_repositories_test.dart` |
//!
//! What no test drove was the **join between them**: the real `GET
//! /v1/ai-import/jobs/{id}` handler and the real `apply-events` stream handler,
//! reading a row that a real `PgAiImportQueue` wrote. Both readers compose the
//! same rule (`live owner first, otherwise the run recorded next to the
//! persisted outcome`) in two places — `infra::ai::decode_run_identity` for the
//! DTO and `handlers::apply_frame_run_id` for the frame — and either could stop
//! surfacing the field without any existing test failing.
//!
//! This case closes that join for one job across two consecutive runs: run A
//! finishes (ownership released, attribution kept), both surfaces must report
//! A; then run B takes the slot and finishes, and both must report B. A handler
//! that drops `apply_run_id` / the frame's `run_id` fails here.
//!
//! **Container gating.** The case needs Docker (PostgreSQL via
//! `testcontainers`), so it only runs when `AI_IMPORT_PG_TESTS=1`. Without the
//! variable it returns immediately and prints why — `cargo test -p api` stays
//! container-free, and the "Testcontainers integration tests" CI job sets the
//! variable (see `.github/workflows/integration-tests.yml`).
//!
//! **Why the ports are a forwarder and not a new adapter.** `crates/api` may
//! not depend on `crates/integration-tests` (AGENTS.md §4), so the PostgreSQL
//! fixture lives here. The case needs exactly one real port (the AI import
//! queue) and no logic from the other 39: a whole port set built on real
//! infrastructure would prove nothing extra, so [`PgQueuePorts`] forwards
//! everything else to the existing `FakePorts` and overrides only the queue.
//! The compiler enforces completeness — a new port on `Ports` does not compile
//! here until it is forwarded.

// Test code: the workspace denies `clippy::expect_used`/`panic`; assertions use
// `.expect()` with explicit messages so a broken seam names itself. The skip
// announcement is printed because a silently skipped case is indistinguishable
// from a passing one.
#![allow(
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::unwrap_used
)]

use std::env;
use std::time::Duration;

use axum::body::{Body, to_bytes};
use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use http_body_util::BodyExt;

use api::auth::CurrentUser;
use api::handlers::{get_ai_import_job, stream_ai_import_apply_events};
use api::problems::Path;
use api::state::{AppState, Ports};
use breakdown_core::ai::{
    AiImportEnqueueRequest, AiImportJobId, AiImportQueue, ApplyRunId, ApplyRunRequest,
    DocumentKind, DraftScene, ScriptApplyRunRequest, ScriptContext, SourceFormat,
};
use breakdown_core::shared::UserId;
use infra::ai::AiPreviewStore as _;
use infra::ai::PgAiImportQueue;
use sqlx::PgPool;
use testcontainers::runners::AsyncRunner;
use testcontainers::{ContainerAsync, ImageExt};
use testcontainers_modules::postgres::Postgres as PostgresImage;

use crate::common::FakePorts;

/// The env gate: set by the container CI job, never by the fast unit job.
const PG_TEST_GATE: &str = "AI_IMPORT_PG_TESTS";

/// The job's submitting user; `authorize_ai_job` compares it against the
/// caller, and a `block_id`-less job resolves no season, so no costume-role
/// gate applies (the same shape the stored-preview fixture seeds).
const TEST_SUB: &str = "ai-import-pg-composition-user";

fn user() -> CurrentUser {
    CurrentUser::dummy(TEST_SUB)
}

fn state(ports: PgQueuePorts) -> AppState<PgQueuePorts> {
    AppState::with_ai_import(ports, true, 4096, Vec::new())
}

// ---------------------------------------------------------------------------
// The port set: `FakePorts` everywhere, the AI import queue in PostgreSQL.
// ---------------------------------------------------------------------------

/// A `Ports` set whose **AI import queue** is the production PostgreSQL adapter
/// and whose other 39 ports are the shared fakes.
///
/// This is the smallest composition that can drive the real handlers against a
/// real row: the two handlers under test read the queue (the job DTO, the run
/// slot and the wake-up hub) and the authorization policy. The apply *worker*
/// reaches only its own command ports, which stay fakes — its dispatch
/// behaviour is covered by the fake harness, so repeating it against
/// infrastructure would add cost, not signal.
#[derive(Clone)]
struct PgQueuePorts {
    inner: FakePorts,
    queue: PgAiImportQueue,
}

impl Ports for PgQueuePorts {
    type SceneCommands = <FakePorts as Ports>::SceneCommands;
    type SceneRepo = <FakePorts as Ports>::SceneRepo;
    type CharacterCommands = <FakePorts as Ports>::CharacterCommands;
    type CharacterRepo = <FakePorts as Ports>::CharacterRepo;
    type WardrobeCommands = <FakePorts as Ports>::WardrobeCommands;
    type PieceRepo = <FakePorts as Ports>::PieceRepo;
    type OutfitRepo = <FakePorts as Ports>::OutfitRepo;
    type CostumeCategoryCommands = <FakePorts as Ports>::CostumeCategoryCommands;
    type CostumeCategoryRepo = <FakePorts as Ports>::CostumeCategoryRepo;
    type SeasonCommands = <FakePorts as Ports>::SeasonCommands;
    type SeasonRepo = <FakePorts as Ports>::SeasonRepo;
    type BlockCommands = <FakePorts as Ports>::BlockCommands;
    type BlockRepo = <FakePorts as Ports>::BlockRepo;
    type EpisodeCommands = <FakePorts as Ports>::EpisodeCommands;
    type EpisodeRepo = <FakePorts as Ports>::EpisodeRepo;
    type MembershipCommands = <FakePorts as Ports>::MembershipCommands;
    type MembershipRepo = <FakePorts as Ports>::MembershipRepo;
    type SettingsCommands = <FakePorts as Ports>::SettingsCommands;
    type SettingsRepo = <FakePorts as Ports>::SettingsRepo;
    type CredentialVault = <FakePorts as Ports>::CredentialVault;
    type AuditRepo = <FakePorts as Ports>::AuditRepo;
    type ShootingDayCommands = <FakePorts as Ports>::ShootingDayCommands;
    type ShootingDayRepo = <FakePorts as Ports>::ShootingDayRepo;
    type PhotoStorage = <FakePorts as Ports>::PhotoStorage;
    type PhotoCommands = <FakePorts as Ports>::PhotoCommands;
    type PhotoRepo = <FakePorts as Ports>::PhotoRepo;
    type SceneShootCommands = <FakePorts as Ports>::SceneShootCommands;
    type SceneShootRepo = <FakePorts as Ports>::SceneShootRepo;
    type SceneShootReportRepo = <FakePorts as Ports>::SceneShootReportRepo;
    type ReportArchivalQueue = <FakePorts as Ports>::ReportArchivalQueue;
    type ReportRenderer = <FakePorts as Ports>::ReportRenderer;
    type AiConfigCommands = <FakePorts as Ports>::AiConfigCommands;
    type AiConfigRepo = <FakePorts as Ports>::AiConfigRepo;
    // The one port this composition replaces.
    type AiImportQueue = PgAiImportQueue;
    type AiImportMappingRepo = <FakePorts as Ports>::AiImportMappingRepo;
    type AiModelPricingRepo = <FakePorts as Ports>::AiModelPricingRepo;
    type AiPreviewStore = <FakePorts as Ports>::AiPreviewStore;
    type AiDocumentStore = <FakePorts as Ports>::AiDocumentStore;
    type AiDocumentSource = <FakePorts as Ports>::AiDocumentSource;
    type ProjectorHealthRepo = <FakePorts as Ports>::ProjectorHealthRepo;

    fn scene_commands(&self) -> &Self::SceneCommands {
        self.inner.scene_commands()
    }
    fn scene_repo(&self) -> &Self::SceneRepo {
        self.inner.scene_repo()
    }
    fn shooting_day_commands(&self) -> &Self::ShootingDayCommands {
        self.inner.shooting_day_commands()
    }
    fn shooting_day_repo(&self) -> &Self::ShootingDayRepo {
        self.inner.shooting_day_repo()
    }
    fn scene_shoot_commands(&self) -> &Self::SceneShootCommands {
        self.inner.scene_shoot_commands()
    }
    fn scene_shoot_repo(&self) -> &Self::SceneShootRepo {
        self.inner.scene_shoot_repo()
    }
    fn scene_shoot_report_repo(&self) -> &Self::SceneShootReportRepo {
        self.inner.scene_shoot_report_repo()
    }
    fn character_commands(&self) -> &Self::CharacterCommands {
        self.inner.character_commands()
    }
    fn character_repo(&self) -> &Self::CharacterRepo {
        self.inner.character_repo()
    }
    fn wardrobe_commands(&self) -> &Self::WardrobeCommands {
        self.inner.wardrobe_commands()
    }
    fn piece_repo(&self) -> &Self::PieceRepo {
        self.inner.piece_repo()
    }
    fn outfit_repo(&self) -> &Self::OutfitRepo {
        self.inner.outfit_repo()
    }
    fn costume_category_commands(&self) -> &Self::CostumeCategoryCommands {
        self.inner.costume_category_commands()
    }
    fn costume_category_repo(&self) -> &Self::CostumeCategoryRepo {
        self.inner.costume_category_repo()
    }
    fn season_commands(&self) -> &Self::SeasonCommands {
        self.inner.season_commands()
    }
    fn season_repo(&self) -> &Self::SeasonRepo {
        self.inner.season_repo()
    }
    fn block_commands(&self) -> &Self::BlockCommands {
        self.inner.block_commands()
    }
    fn block_repo(&self) -> &Self::BlockRepo {
        self.inner.block_repo()
    }
    fn episode_commands(&self) -> &Self::EpisodeCommands {
        self.inner.episode_commands()
    }
    fn episode_repo(&self) -> &Self::EpisodeRepo {
        self.inner.episode_repo()
    }
    fn membership_commands(&self) -> &Self::MembershipCommands {
        self.inner.membership_commands()
    }
    fn membership_repo(&self) -> &Self::MembershipRepo {
        self.inner.membership_repo()
    }
    fn settings_commands(&self) -> &Self::SettingsCommands {
        self.inner.settings_commands()
    }
    fn settings_repo(&self) -> &Self::SettingsRepo {
        self.inner.settings_repo()
    }
    fn credential_vault(&self) -> &Self::CredentialVault {
        self.inner.credential_vault()
    }
    fn audit_repo(&self) -> &Self::AuditRepo {
        self.inner.audit_repo()
    }
    fn photo_storage(&self) -> &Self::PhotoStorage {
        self.inner.photo_storage()
    }
    fn photo_commands(&self) -> &Self::PhotoCommands {
        self.inner.photo_commands()
    }
    fn photo_repo(&self) -> &Self::PhotoRepo {
        self.inner.photo_repo()
    }
    fn report_archival_queue(&self) -> &Self::ReportArchivalQueue {
        self.inner.report_archival_queue()
    }
    fn report_renderer(&self) -> &Self::ReportRenderer {
        self.inner.report_renderer()
    }
    fn report_renderer_ref(&self) -> &dyn breakdown_core::reporting::ReportRenderer {
        self.inner.report_renderer_ref()
    }
    fn ai_config_commands(&self) -> &Self::AiConfigCommands {
        self.inner.ai_config_commands()
    }
    fn ai_config_repo(&self) -> &Self::AiConfigRepo {
        self.inner.ai_config_repo()
    }
    fn ai_import_queue(&self) -> &Self::AiImportQueue {
        &self.queue
    }
    fn ai_import_mapping(&self) -> &Self::AiImportMappingRepo {
        self.inner.ai_import_mapping()
    }
    fn ai_model_pricing_repo(&self) -> &Self::AiModelPricingRepo {
        self.inner.ai_model_pricing_repo()
    }
    fn ai_preview_store(&self) -> &Self::AiPreviewStore {
        self.inner.ai_preview_store()
    }
    fn ai_document_store(&self) -> &Self::AiDocumentStore {
        self.inner.ai_document_store()
    }
    fn ai_document_source(&self) -> &Self::AiDocumentSource {
        self.inner.ai_document_source()
    }
    fn projector_health_repo(&self) -> &Self::ProjectorHealthRepo {
        self.inner.projector_health_repo()
    }
}

// ---------------------------------------------------------------------------
// The PostgreSQL fixture (crates/api may not use crates/integration-tests).
// ---------------------------------------------------------------------------

/// Start an ephemeral PostgreSQL, run the real migrations and hand back the
/// pool. The container is returned so the caller keeps it alive for the whole
/// case (dropping it stops the database).
///
/// Honours `POSTGRES_IMAGE` exactly like the integration-tests fixture: the CI
/// workflow pre-pulls that image, so the test pull is a cache hit instead of a
/// live Docker Hub dependency. The repo prefix is normalized away — only the
/// tag is overridden.
async fn spawn_postgres() -> (PgPool, ContainerAsync<PostgresImage>) {
    let tag = env::var("POSTGRES_IMAGE").ok().and_then(|image| {
        let image = image.trim();
        let tag = image.rsplit(':').next()?;
        (!tag.is_empty() && !tag.contains('/') && image.contains(':')).then(|| tag.to_owned())
    });
    let request = match tag {
        Some(tag) => PostgresImage::default().with_tag(tag),
        None => PostgresImage::default().into(),
    };
    let request = request
        .with_cmd(["-c", "fsync=off"])
        .with_startup_timeout(Duration::from_secs(120));
    let container = request.start().await.expect("PostgreSQL container starts");

    let host = container
        .get_host()
        .await
        .expect("container host is resolvable");
    let port = container
        .get_host_port_ipv4(5432)
        .await
        .expect("container publishes 5432");
    let url = format!("postgres://postgres:postgres@{host}:{port}/postgres");
    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(5)
        .connect(&url)
        .await
        .expect("pool connects to the container");
    sqlx::query("SELECT 1")
        .fetch_one(&pool)
        .await
        .expect("the container answers a probe query");
    sqlx::migrate!("../infra/migrations")
        .run(&pool)
        .await
        .expect("the migrations apply to a fresh container");
    (pool, container)
}

// ---------------------------------------------------------------------------
// Seeding and driving one run.
// ---------------------------------------------------------------------------

/// A `succeeded` job whose stored preview holds no draft rows.
///
/// No rows means the plan is empty: this case is about the *outcome identity*,
/// not about what an apply dispatches (the fake harness owns that), so the run
/// has nothing to write and no decision to resolve.
fn enqueue_request(id: AiImportJobId) -> AiImportEnqueueRequest {
    AiImportEnqueueRequest {
        // Issue #871: no breaker snapshot — the job is never breaker-filtered.
        provider: None,
        model: None,
        id,
        user_id: UserId::from_sub(TEST_SUB),
        document_kind: DocumentKind::Script,
        source_format: SourceFormat::Csv,
        // `None` on purpose: `authorize_ai_job` then resolves no season and the
        // handlers are gated by ownership alone, which keeps this case about the
        // identity chain instead of the costume-role policy.
        block_id: None,
        dedup_key: format!("pg-composition|{}", id.as_uuid()),
        document_digest: format!("pg-composition-digest|{}", id.as_uuid()),
        source_handle: format!("ai-source/{}", id.as_uuid()),
        source_file_name: None,
        target: None,
    }
}

fn script_preview() -> ScriptContext {
    ScriptContext {
        block_number: None,
        title: Some("composition test script".to_owned()),
        // Deliberately empty: nothing to apply, so the run's outcome is a
        // persisted `succeeded` summary with zero rows.
        scenes: Vec::<DraftScene>::new(),
        uncertainties: Vec::new(),
        scenes_detected: 0,
        scenes_extracted: 0,
        scenes_synthesized: 0,
    }
}

fn apply_request() -> ApplyRunRequest {
    ApplyRunRequest::Script(Box::new(ScriptApplyRunRequest {
        actor: UserId::from_sub(TEST_SUB),
        episode_id: breakdown_core::shared::EpisodeId::new(),
        season_id: breakdown_core::shared::SeasonId::new(),
        project_id: None,
        block_id: breakdown_core::shared::BlockId::new(),
        decisions: Vec::new(),
        episode_groups: Vec::new(),
        known_episodes: Vec::new(),
        shooting_days: Vec::new(),
        acknowledged_uncertainties: Vec::new(),
        categories: Vec::new(),
        continuity_selections: Vec::new(),
        telemetry: None,
    }))
}

/// Seed the terminal job in PostgreSQL, with its preview payload in the
/// in-memory preview store the same port set serves.
async fn seed_succeeded_job(ports: &PgQueuePorts) -> AiImportJobId {
    let id = AiImportJobId::new();
    let handle = ports
        .ai_preview_store()
        .put(
            id,
            serde_json::to_vec(&script_preview()).expect("the preview serializes"),
        )
        .await
        .expect("the preview store accepts the payload");
    ports
        .ai_import_queue()
        .seed_succeeded(enqueue_request(id), &handle)
        .await
        .expect("the terminal fixture job is inserted");
    id
}

/// Dispatch and run one apply through the same pair the `POST /apply` handler
/// uses (`request_apply_run` → `begin_apply_run`) and the same runner
/// production uses (`ApplyRunner::run_claimed`), then assert it succeeded.
///
/// The run's terminal write (`complete_apply_run`) is what releases ownership
/// and stamps the attribution — the transition this case is about.
async fn run_apply(ports: &PgQueuePorts, id: AiImportJobId) -> ApplyRunId {
    let queue = ports.ai_import_queue();
    let run_id = ApplyRunId::new();
    assert!(
        queue
            .request_apply_run(id, run_id, &apply_request())
            .await
            .expect("the dispatch write succeeds"),
        "the slot is free, so the dispatch claims it"
    );
    let claimed = queue
        .begin_apply_run(id, ApplyRunId::new())
        .await
        .expect("the requested run is adoptable")
        .expect("the run is in `requested`, so it is adoptable");
    assert_eq!(
        claimed.run_id, run_id,
        "adoption keeps the id the dispatch minted"
    );
    let outcome = api::apply_runner::ApplyRunner::new(state(ports.clone()))
        .run_claimed(claimed)
        .await
        .expect("the run reports an outcome");
    match outcome {
        breakdown_core::ai::ApplyRunOutcome::Succeeded(_) => run_id,
        breakdown_core::ai::ApplyRunOutcome::Failed { code } => {
            panic!("the composition run failed with code {code}")
        }
    }
}

/// `GET /v1/ai-import/jobs/{id}` through the real handler, as the wire JSON.
async fn job_json(ports: &PgQueuePorts, id: AiImportJobId) -> serde_json::Value {
    let response = get_ai_import_job::<PgQueuePorts>(State(state(ports.clone())), user(), Path(id))
        .await
        .expect("the authorized job read answers");
    assert_eq!(response.status(), StatusCode::OK);
    let body = to_bytes(response.into_body(), 1024 * 1024)
        .await
        .expect("the job body reads");
    serde_json::from_slice(&body).expect("the job body is JSON")
}

/// The **terminal** frame of the real `apply-events` stream, read until the
/// stream closes.
///
/// The stream is snapshot-first, so the terminal frame arrives as the first
/// frame and the stream then ends — a bounded read that finishes without any
/// timer.
async fn terminal_frame(ports: &PgQueuePorts, id: AiImportJobId) -> serde_json::Value {
    let response = stream_ai_import_apply_events::<PgQueuePorts>(
        State(state(ports.clone())),
        user(),
        Path(id),
        HeaderMap::new(),
    )
    .await
    .expect("the authorized stream call answers before the stream");
    assert_eq!(response.status(), StatusCode::OK);
    let mut body: Body = response.into_body();
    let mut terminal: Option<serde_json::Value> = None;
    while let Some(frame) = body.frame().await {
        let Ok(frame) = frame else { break };
        let Some(data) = frame.data_ref() else {
            continue;
        };
        let text = String::from_utf8_lossy(data);
        for line in text.lines() {
            let Some(payload) = line.strip_prefix("data: ") else {
                continue;
            };
            let value: serde_json::Value =
                serde_json::from_str(payload).expect("the frame data is JSON");
            let state = value
                .get("apply_state")
                .and_then(|state| state.as_str())
                .unwrap_or_default();
            if state == "done" || state == "failed" {
                terminal = Some(value);
            }
        }
        if terminal.is_some() {
            break;
        }
    }
    terminal.expect("the terminal run emits exactly one closing frame")
}

fn wire_run_id(value: &serde_json::Value) -> Option<&str> {
    value.get("run_id").and_then(|id| id.as_str())
}

// ---------------------------------------------------------------------------
// The case.
// ---------------------------------------------------------------------------

/// Both HTTP surfaces name the run that produced the outcome — through two
/// consecutive runs, against PostgreSQL (issue #912).
///
/// Run A finishes: ownership is released (the slot frees immediately) but the
/// attribution survives, so the job read and the terminal frame both report A.
/// Run B then takes the slot and finishes, and both surfaces switch to B — which
/// is how run A's late client detects that the outcome it is looking at belongs
/// to someone else.
#[tokio::test]
async fn both_surfaces_report_the_run_that_produced_the_outcome() {
    if env::var(PG_TEST_GATE).as_deref() != Ok("1") {
        println!(
            "skipped: set {PG_TEST_GATE}=1 (and have Docker) to run the PostgreSQL composition case"
        );
        return;
    }

    let (pool, _container) = spawn_postgres().await;
    let ports = PgQueuePorts {
        inner: FakePorts::default(),
        queue: PgAiImportQueue::new(pool),
    };
    let id = seed_succeeded_job(&ports).await;

    let run_a = run_apply(&ports, id).await;
    let run_a_wire = run_a.as_uuid().to_string();

    // Run A is over: the slot released ownership, the row kept attribution.
    let slot = ports
        .ai_import_queue()
        .apply_run_state(id)
        .await
        .expect("the slot read succeeds")
        .expect("the job exists");
    assert_eq!(
        slot.owner, None,
        "a finished run frees the single-flight slot"
    );
    assert_eq!(
        slot.result_run_id,
        Some(run_a),
        "…while the persisted attribution names the run that produced it"
    );

    let job = job_json(&ports, id).await;
    assert_eq!(
        job["job"]["apply_run_id"], run_a_wire,
        "GET /jobs/{{id}} reports run A: a handler that drops the field fails here"
    );
    assert_eq!(
        job["job"]["apply_state"], "done",
        "the job read reports the terminal state the outcome belongs to"
    );
    assert!(
        !job["job"]["apply_result"].is_null(),
        "…and the outcome the identity is attributed to is on the same read"
    );

    let frame = terminal_frame(&ports, id).await;
    assert_eq!(
        wire_run_id(&frame),
        Some(run_a_wire.as_str()),
        "the terminal frame reports run A: a handler that drops the frame's run_id fails here"
    );

    // Run B takes the freed slot and finishes.
    let run_b = run_apply(&ports, id).await;
    let run_b_wire = run_b.as_uuid().to_string();
    assert_ne!(run_a, run_b, "each dispatch mints its own run id");

    let job = job_json(&ports, id).await;
    assert_eq!(
        job["job"]["apply_run_id"], run_b_wire,
        "both readers now name run B — which is how run A's client detects it"
    );
    let frame = terminal_frame(&ports, id).await;
    assert_eq!(
        wire_run_id(&frame),
        Some(run_b_wire.as_str()),
        "the terminal frame follows the slot to run B"
    );
}
