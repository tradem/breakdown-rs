// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! # Breakdown RS – API-Server
//!
//! Composition-Root: Hier werden alle Abhängigkeiten per Hand injiziert
//! (Poor Man's Dependency Injection gemäß hexagonaler Architektur).

use std::env;
use std::sync::Arc;

use anyhow::Result;
use api::routes::app_router;
use api::state::{AppState, ProductionPorts};
use infra::event_store::{
    CalculationCommandsImpl, CharacterCommandsImpl, CostumeCommandsImpl, SceneCommandsImpl,
};
use infra::queries::{
    CalculationRepositoryImpl, CharacterRepositoryImpl, CostumeRepositoryImpl, SceneRepositoryImpl,
};
use kameo_es::command_service::CommandService;
use redis::Client as RedisClient;
use sqlx::postgres::PgPoolOptions;
use tracing::{info, warn};

#[tokio::main]
async fn main() -> Result<()> {
    // Logging initialisieren
    tracing_subscriber::fmt::init();

    let database_url = env::var("DATABASE_URL").unwrap_or_else(|_| {
        warn!("DATABASE_URL not set; using local dev default");
        "postgres://postgres:postgres@localhost:5432/breakdown".into()
    });
    let sierradb_url = env::var("SIERRADB_URL").unwrap_or_else(|_| {
        warn!("SIERRADB_URL not set; using local dev default");
        "redis://127.0.0.1:6379".into()
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
    let _scene_projector =
        infra::projectors::spawn_scene_projector(pool.clone(), Arc::clone(&redis_client)).await?;
    let _character_projector =
        infra::projectors::spawn_character_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;
    let _costume_projector =
        infra::projectors::spawn_costume_projector(pool.clone(), Arc::clone(&redis_client)).await?;
    let _calculation_projector =
        infra::projectors::spawn_calculation_projector(pool.clone(), Arc::clone(&redis_client))
            .await?;
    info!("projectors spawned");

    let ports = ProductionPorts::new(
        SceneCommandsImpl::new(cmd_service.clone()),
        SceneRepositoryImpl::new(pool.clone()),
        CharacterCommandsImpl::new(cmd_service.clone()),
        CharacterRepositoryImpl::new(pool.clone()),
        CostumeCommandsImpl::new(cmd_service.clone()),
        CostumeRepositoryImpl::new(pool.clone()),
        CalculationCommandsImpl::new(cmd_service.clone()),
        CalculationRepositoryImpl::new(pool.clone()),
    );
    let app_state = AppState::new(ports);

    let app = app_router().with_state(app_state);

    let bind_addr = env::var("BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:3000".into());
    let listener = tokio::net::TcpListener::bind(&bind_addr).await?;
    info!("🚀 Breakdown RS listening on {}", bind_addr);
    axum::serve(listener, app).await?;

    Ok(())
}
