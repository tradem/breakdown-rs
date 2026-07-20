// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

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
    BlockCommandsImpl, CharacterCommandsImpl, CostumeCommandsImpl, EpisodeCommandsImpl,
    MembershipCommandsImpl, SceneCommandsImpl, SeasonCommandsImpl,
};
use infra::queries::{
    AuditRepositoryImpl, BlockRepositoryImpl, CharacterRepositoryImpl, CostumeRepositoryImpl,
    EpisodeRepositoryImpl, MembershipRepositoryImpl, SceneRepositoryImpl, SeasonRepositoryImpl,
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

    let pool = PgPoolOptions::new()
        .max_connections(20)
        .connect(&database_url)
        .await?;

    sqlx::migrate!("../infra/migrations").run(&pool).await?;
    info!("projection migrations applied");

    let redis_client: Arc<RedisClient> = Arc::new(RedisClient::open(sierradb_url)?);
    let sierra_conn = redis_client.get_multiplexed_tokio_connection().await?;
    let cmd_service = CommandService::new(sierra_conn);

    // Start one PostgresProcessor per aggregate, each with its own checkpoint stream.
    let _season_projector =
        infra::projectors::spawn_season_projector(pool.clone(), Arc::clone(&redis_client)).await?;
    let _block_projector =
        infra::projectors::spawn_block_projector(pool.clone(), Arc::clone(&redis_client)).await?;
    let _episode_projector =
        infra::projectors::spawn_episode_projector(pool.clone(), Arc::clone(&redis_client)).await?;
    let _scene_projector =
        infra::projectors::spawn_scene_projector(pool.clone(), Arc::clone(&redis_client)).await?;
    let _character_projector =
        infra::projectors::spawn_character_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;
    let _costume_projector =
        infra::projectors::spawn_costume_projector(pool.clone(), Arc::clone(&redis_client)).await?;
    let _membership_projector =
        infra::projectors::spawn_membership_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;
    let _audit_projector =
        infra::projectors::spawn_audit_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;
    info!("projectors spawned");

    let ports = ProductionPorts::new(
        SceneCommandsImpl::new(cmd_service.clone()),
        SceneRepositoryImpl::new(pool.clone()),
        CharacterCommandsImpl::new(cmd_service.clone()),
        CharacterRepositoryImpl::new(pool.clone()),
        CostumeCommandsImpl::new(cmd_service.clone()),
        CostumeRepositoryImpl::new(pool.clone()),
        SeasonCommandsImpl::new(cmd_service.clone()),
        SeasonRepositoryImpl::new(pool.clone()),
        BlockCommandsImpl::new(cmd_service.clone()),
        BlockRepositoryImpl::new(pool.clone()),
        EpisodeCommandsImpl::new(cmd_service.clone()),
        EpisodeRepositoryImpl::new(pool.clone()),
        MembershipCommandsImpl::new(cmd_service.clone()),
        MembershipRepositoryImpl::new(pool.clone()),
        AuditRepositoryImpl::new(pool.clone()),
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
