// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! # Breakdown RS – API-Server
//!
//! Composition-Root: Hier werden alle Abhängigkeiten per Hand injiziert
//! (Poor Man's Dependency Injection gemäß hexagonaler Architektur).

use std::env;
use std::sync::Arc;

use anyhow::Result;
use api::auth::authorization::MembershipAuthorizationPolicy;
use api::auth::{AuthState, AuthorizationState};
use api::routes::app_router;
use api::state::{AppState, Ports, ProductionPorts};
use breakdown_core::membership::policy::AuthorizationPolicy;
use infra::event_store::{
    BlockCommandsImpl, CharacterCommandsImpl, CostumeCategoryCommandsImpl, CostumeCommandsImpl,
    EpisodeCommandsImpl, MembershipCommandsImpl, PhotoCommandsImpl, SceneCommandsImpl,
    SceneShootCommandsImpl, SeasonCommandsImpl, ShootingDayCommandsImpl,
};
use infra::photo::{
    gc::spawn_gc_scheduler, repository::PhotoRepositoryImpl, storage::OpenDalPhotoStorage,
};
use infra::queries::{
    AuditRepositoryImpl, BlockRepositoryImpl, CharacterRepositoryImpl,
    CostumeCategoryRepositoryImpl, CostumeRepositoryImpl, EpisodeRepositoryImpl,
    MembershipRepositoryImpl, SceneRepositoryImpl, SceneShootReportRepositoryImpl,
    SceneShootRepositoryImpl, SeasonRepositoryImpl, ShootingDayRepositoryImpl,
};
use infra::reporting::{
    BackupWorkerConfig, MemoryReportArchiveStorage, OpenDalReportArchiveStorage,
    PgReportArchivalQueue, SceneShootReportDataLoader, ScheduleConfig, TypstReportRenderer,
    spawn_backup_worker, spawn_schedule_ticker, spawn_wrap_archival_saga,
};
use kameo_es::command_service::CommandService;
use opentelemetry::trace::TracerProvider as _;
use opentelemetry_otlp::WithExportConfig;
use redis::Client as RedisClient;
use sqlx::postgres::PgPoolOptions;
use tower_http::trace::TraceLayer;
use tracing::{info, warn};
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;

/// Initialise an OpenTelemetry tracer when `OTEL_EXPORTER_OTLP_ENDPOINT` is set.
///
/// Returns `None` when the endpoint is not configured, keeping local dev
/// free of OTLP connection attempts. When configured, builds an OTLP exporter
/// respecting `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_PROTOCOL`, and
/// `OTEL_TRACES_EXPORTER`.
fn init_otel_tracer() -> Option<opentelemetry_sdk::trace::SdkTracer> {
    let endpoint = env::var("OTEL_EXPORTER_OTLP_ENDPOINT").unwrap_or_default();
    if endpoint.is_empty() {
        info!("OTEL_EXPORTER_OTLP_ENDPOINT not set; OTLP tracing disabled");
        return None;
    }

    let service_name = env::var("OTEL_SERVICE_NAME").unwrap_or_else(|_| "breakdown-rs".to_string());

    let protocol = env::var("OTEL_EXPORTER_OTLP_PROTOCOL").unwrap_or_else(|_| "grpc".to_string());

    // Build the exporter based on the configured protocol.
    let exporter = match protocol.as_str() {
        "http/protobuf" => opentelemetry_otlp::SpanExporter::builder()
            .with_http()
            .with_endpoint(&endpoint)
            .build()
            .expect("failed to build OTLP HTTP exporter"),
        _ => {
            // Default to gRPC (tonic) when protocol is unset or "grpc".
            opentelemetry_otlp::SpanExporter::builder()
                .with_tonic()
                .with_endpoint(&endpoint)
                .build()
                .expect("failed to build OTLP gRPC exporter")
        }
    };

    let tracer_provider = opentelemetry_sdk::trace::SdkTracerProvider::builder()
        .with_batch_exporter(exporter)
        .with_resource(
            opentelemetry_sdk::Resource::builder()
                .with_attribute(opentelemetry::KeyValue::new("service.name", service_name))
                .build(),
        )
        .build();

    // NOTE: The SDK logs batch export errors internally via `otel_error!` / `tracing::error!`
    // under the "BatchSpanProcessor" target when the collector is unreachable.
    // No custom error handler wiring is required for v1.

    let tracer = tracer_provider.tracer("breakdown-rs");
    opentelemetry::global::set_tracer_provider(tracer_provider);

    Some(tracer)
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialise the tracing subscriber with a composable registry:
    // the `fmt` layer is always active, and the OTLP layer is added
    // conditionally when an OTLP endpoint is configured.
    let fmt_layer = tracing_subscriber::fmt::layer();
    let subscriber = tracing_subscriber::registry().with(fmt_layer);

    if let Some(tracer) = init_otel_tracer() {
        let otel_layer = tracing_opentelemetry::OpenTelemetryLayer::new(tracer);
        subscriber.with(otel_layer).init();
        info!("OTLP tracing enabled");
    } else {
        subscriber.init();
    }

    let database_url = env::var("DATABASE_URL").unwrap_or_else(|_| {
        warn!("DATABASE_URL not set; using local dev default");
        "postgres://postgres:postgres@localhost:5432/breakdown".into()
    });
    // SierraDB speaks RESP3 (ADR-015 / ADR-016). The dev compose exposes it on
    // port 9090; connect with a RESP3-capable `redis::Client`. The URL is
    // environment-driven (gitleaks-clean) — never hardcoded beyond the dev default.
    let sierradb_url = env::var("SIERRADB_URL").unwrap_or_else(|_| {
        warn!("SIERRADB_URL not set; using local dev default (RESP3, port 9090)");
        "redis://127.0.0.1:9090/?protocol=resp3".into()
    });

    // --- Two-pool Postgres connection (DDL migrator + DML app) ---
    //
    // MIGRATOR_DATABASE_URL is used only during boot to apply DDL (migrations),
    // then dropped. Falls back to DATABASE_URL for dev convenience (single-role
    // mode). In production, MIGRATOR_DATABASE_URL connects as breakdown_migrator
    // (schema owner), and DATABASE_URL connects as breakdown_app (DML only).
    let migrator_database_url = env::var("MIGRATOR_DATABASE_URL")
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| {
            warn!("MIGRATOR_DATABASE_URL not set; falling back to DATABASE_URL");
            database_url.clone()
        });

    // Short-lived migrator pool (1 connection, DDL rights).
    let migrator_pool = PgPoolOptions::new()
        .max_connections(1)
        .connect(&migrator_database_url)
        .await?;

    // Run migrations as the migrator role (schema owner).
    sqlx::migrate!("../infra/migrations")
        .run(&migrator_pool)
        .await?;
    info!("projection migrations applied");

    // Post-migration: enforce INSERT-only audit logging.
    // The bootstrap script sets DML default privileges for breakdown_app, so
    // projection_audit automatically gets SELECT, INSERT, UPDATE, DELETE.
    // We revoke UPDATE/DELETE here to make the audit log append-only.
    // Best-effort: in dev mode without role separation the REVOKE may fail
    // harmlessly (role or table does not exist).
    if migrator_database_url != database_url {
        match sqlx::query("REVOKE UPDATE, DELETE ON projection_audit FROM breakdown_app")
            .execute(&migrator_pool)
            .await
        {
            Ok(_) => info!("audit table set to INSERT-only for breakdown_app"),
            Err(e) => {
                warn!("could not revoke UPDATE/DELETE on audit table (roles not separated?): {e}")
            }
        }
    }

    // Release the DDL pool; all subsequent queries use the app pool.
    drop(migrator_pool);

    // Long-lived app pool (DML only, up to 20 connections).
    let pool = PgPoolOptions::new()
        .max_connections(20)
        .connect(&database_url)
        .await?;
    info!("app database pool connected");

    let redis_client: Arc<RedisClient> = Arc::new(RedisClient::open(sierradb_url)?);
    let sierra_conn = redis_client.get_multiplexed_async_connection().await?;
    let cmd_service = CommandService::new(sierra_conn);

    // Start one PostgresProcessor per aggregate, each with its own checkpoint stream.
    let _season_projector = infra::projectors::spawn_season_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::default(),
    )
    .await?;
    let _block_projector = infra::projectors::spawn_block_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::default(),
    )
    .await?;
    let _episode_projector = infra::projectors::spawn_episode_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::default(),
    )
    .await?;
    let _scene_projector = infra::projectors::spawn_scene_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::default(),
    )
    .await?;
    let _character_projector = infra::projectors::spawn_character_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::default(),
    )
    .await?;
    let _costume_projector = infra::projectors::spawn_costume_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::default(),
    )
    .await?;
    let _membership_projector = infra::projectors::spawn_membership_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::default(),
    )
    .await?;
    // Spawn all 11 category audit projectors and keep their supervisor handles
    // alive for the process lifetime. The handles' Drop aborts the projectors,
    // so they MUST be held here (not dropped at end of function).
    let _audit_handles = infra::projectors::spawn_all_audit_projectors(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::default(),
    )
    .await?;
    let _shooting_day_projector = infra::projectors::spawn_shooting_day_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::default(),
    )
    .await?;
    let _costume_category_projector = infra::projectors::spawn_costume_category_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::default(),
    )
    .await?;
    let _scene_shoot_projector = infra::projectors::spawn_scene_shoot_projector(
        pool.clone(),
        Arc::clone(&redis_client),
        infra::projectors::ProjectorFlushConfig::default(),
    )
    .await?;
    // Event-reactor saga: seeds default costume categories on SeasonCreated.
    infra::sagas::spawn_season_seeding_saga(
        pool.clone(),
        Arc::clone(&redis_client),
        cmd_service.clone(),
    )
    .await?;
    info!("projectors spawned");

    // --- Photo storage (Garage / S3) ---
    let photo_storage = OpenDalPhotoStorage::from_env().map_err(|e| {
        anyhow::anyhow!("Failed to initialise OpenDalPhotoStorage: {e}. Set S3_ENDPOINT, S3_ACCESS_KEY, S3_SECRET_KEY")
    })?;

    // Create repositories first (commands depend on them for series_id resolution)
    let photo_repo = PhotoRepositoryImpl::new(pool.clone());
    let costume_repo = CostumeRepositoryImpl::new(pool.clone());
    let character_repo = CharacterRepositoryImpl::new(pool.clone());
    let season_repo = SeasonRepositoryImpl::new(pool.clone());
    let scene_shoot_repo = SceneShootRepositoryImpl::new(pool.clone());
    let scene_repo = SceneRepositoryImpl::new(pool.clone());
    let episode_repo = EpisodeRepositoryImpl::new(pool.clone());
    let shooting_day_repo = ShootingDayRepositoryImpl::new(pool.clone());
    let costume_category_repo = CostumeCategoryRepositoryImpl::new(pool.clone());
    let block_repo = BlockRepositoryImpl::new(pool.clone());
    let membership_repo_impl = MembershipRepositoryImpl::new(pool.clone());
    let audit_repo = AuditRepositoryImpl::new(pool.clone());

    // Create command adapters with repository dependencies
    let photo_commands = PhotoCommandsImpl::new(
        cmd_service.clone(),
        photo_repo.clone(),
        costume_repo.clone(),
        character_repo.clone(),
        season_repo.clone(),
        scene_shoot_repo.clone(),
        scene_repo.clone(),
        episode_repo.clone(),
    );
    let scene_shoot_commands = SceneShootCommandsImpl::new(
        cmd_service.clone(),
        scene_shoot_repo.clone(),
        scene_repo.clone(),
        episode_repo.clone(),
    );
    let scene_shoot_report_repo = SceneShootReportRepositoryImpl::new(pool.clone());

    // --- Spawn photo sagas (thumbnail, deletion, bytes-cleanup) ---
    infra::photo::sagas::spawn_photo_thumbnail_saga(
        cmd_service.clone(),
        photo_storage.clone(),
        photo_repo.clone(),
        costume_repo.clone(),
        character_repo.clone(),
        season_repo.clone(),
        scene_shoot_repo.clone(),
        scene_repo.clone(),
        episode_repo.clone(),
        Arc::clone(&redis_client),
    )
    .await?;
    infra::photo::sagas::spawn_photo_deletion_saga(
        cmd_service.clone(),
        photo_repo.clone(),
        costume_repo.clone(),
        character_repo.clone(),
        season_repo.clone(),
        scene_shoot_repo.clone(),
        scene_repo.clone(),
        episode_repo.clone(),
        Arc::clone(&redis_client),
    )
    .await?;
    infra::photo::sagas::spawn_photo_bytes_cleanup_saga(
        photo_storage.clone(),
        Arc::clone(&redis_client),
    )
    .await?;
    infra::photo::sagas::spawn_continuity_deletion_saga(
        cmd_service.clone(),
        photo_repo.clone(),
        costume_repo.clone(),
        character_repo.clone(),
        season_repo.clone(),
        scene_shoot_repo.clone(),
        scene_repo.clone(),
        episode_repo.clone(),
        pool.clone(),
        Arc::clone(&redis_client),
    )
    .await?;
    info!("photo sagas spawned");

    // --- Spawn the orphan GC scheduler ---
    spawn_gc_scheduler(pool.clone(), photo_storage.clone(), photo_repo.clone());
    info!("photo GC scheduler spawned");

    // --- Report archival (staging + external + worker + triggers) ---
    let report_archival_queue = PgReportArchivalQueue::new(pool.clone());
    let report_staging: std::sync::Arc<dyn breakdown_core::reporting::ReportArchiveStorage> =
        match OpenDalReportArchiveStorage::staging_from_env() {
            Ok(s) => std::sync::Arc::new(s),
            Err(e) => {
                warn!(
                    error = %e,
                    "report staging storage unavailable — using in-memory staging (dev only)"
                );
                std::sync::Arc::new(MemoryReportArchiveStorage::new())
            }
        };
    let report_external: std::sync::Arc<dyn breakdown_core::reporting::ReportArchiveStorage> =
        match OpenDalReportArchiveStorage::external_from_env() {
            Ok(s) => std::sync::Arc::new(s),
            Err(e) => {
                warn!(
                    error = %e,
                    "report external storage unavailable — using in-memory external (dev only)"
                );
                std::sync::Arc::new(MemoryReportArchiveStorage::new())
            }
        };
    // Shared renderer (process-wide semaphore budget for HTTP + backup).
    let report_renderer: std::sync::Arc<dyn breakdown_core::reporting::ReportRenderer> =
        std::sync::Arc::new(TypstReportRenderer::with_defaults().unwrap_or_else(|e| {
            warn!(error = %e, "TypstReportRenderer defaults failed — empty renderer");
            use std::collections::HashMap;
            TypstReportRenderer::new(HashMap::new(), vec![])
        }));
    let report_loader = std::sync::Arc::new(SceneShootReportDataLoader::new(
        scene_shoot_report_repo.clone(),
    ));
    let backup_worker = std::sync::Arc::new(infra::reporting::ReportBackupWorker::new(
        report_archival_queue.clone(),
        report_staging,
        report_external,
        report_renderer.clone(),
        report_loader,
        BackupWorkerConfig::default(),
    ));
    spawn_backup_worker(backup_worker);
    spawn_schedule_ticker(
        pool.clone(),
        report_archival_queue.clone(),
        ScheduleConfig::from_env(),
    );
    if let Err(e) =
        spawn_wrap_archival_saga(report_archival_queue.clone(), Arc::clone(&redis_client)).await
    {
        warn!(error = %e, "failed to spawn wrap archival saga");
    } else {
        info!("report archival worker + triggers spawned");
    }

    let ports = ProductionPorts::new(
        SceneCommandsImpl::new(
            cmd_service.clone(),
            scene_repo.clone(),
            episode_repo.clone(),
            shooting_day_repo.clone(),
        ),
        scene_repo,
        ShootingDayCommandsImpl::new(
            cmd_service.clone(),
            shooting_day_repo.clone(),
            episode_repo.clone(),
        ),
        shooting_day_repo,
        CharacterCommandsImpl::new(
            cmd_service.clone(),
            character_repo.clone(),
            season_repo.clone(),
        ),
        character_repo.clone(),
        CostumeCommandsImpl::new(
            cmd_service.clone(),
            costume_repo.clone(),
            character_repo.clone(),
            season_repo.clone(),
        ),
        costume_repo,
        CostumeCategoryCommandsImpl::new(
            cmd_service.clone(),
            costume_category_repo.clone(),
            season_repo.clone(),
        ),
        costume_category_repo,
        SeasonCommandsImpl::new(cmd_service.clone(), season_repo.clone()),
        season_repo,
        BlockCommandsImpl::new(cmd_service.clone(), block_repo.clone()),
        block_repo.clone(),
        EpisodeCommandsImpl::new(cmd_service.clone(), episode_repo.clone()),
        episode_repo,
        MembershipCommandsImpl::new(cmd_service.clone(), block_repo.clone()),
        membership_repo_impl.clone(),
        audit_repo.clone(),
        photo_storage,
        photo_commands,
        photo_repo,
        scene_shoot_commands,
        scene_shoot_repo,
        scene_shoot_report_repo,
        report_archival_queue,
        report_renderer,
    );
    let app_state = AppState::new(ports);

    // --- OIDC authentication + authorization wiring ---
    let auth = Arc::new(
        AuthState::from_env_or_dev().map_err(|e| anyhow::anyhow!("auth configuration: {e}"))?,
    );

    let membership_repo: Arc<MembershipRepositoryImpl> =
        Arc::new(app_state.ports.membership_repo().clone());
    let policy: Arc<dyn AuthorizationPolicy> =
        Arc::new(MembershipAuthorizationPolicy::new(membership_repo));
    let authz = Arc::new(AuthorizationState::from_env_or_dev(policy));

    info!(
        "authz enforce={} dev_auth={}",
        authz.enforce(),
        auth.is_dev()
    );

    let app = app_router(auth, authz)
        .with_state(app_state)
        .layer(TraceLayer::new_for_http());

    let bind_addr = env::var("BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:3000".into());
    let listener = tokio::net::TcpListener::bind(&bind_addr).await?;
    info!("🚀 Breakdown RS listening on {}", bind_addr);
    axum::serve(listener, app).await?;

    Ok(())
}
