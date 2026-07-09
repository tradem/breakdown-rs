// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Projection actors – one `PostgresProcessor` per aggregate.
//!
//! Each projector has its own checkpoint row set inside `sierradb_event_checkpoints`
//! and can fail/catch-up independently (ADR-015).

mod calculation;
mod character;
mod costume;
mod scene;
mod supervisor;

pub use calculation::CalculationProjector;
pub use character::CharacterProjector;
pub use costume::CostumeProjector;
pub use scene::SceneProjector;

use std::sync::Arc;

use anyhow::{self, Result};
use breakdown_core::calculation::aggregate::CalculationAggregate;
use breakdown_core::character::aggregate::CharacterAggregate;
use breakdown_core::costume::aggregate::CostumeAggregate;
use breakdown_core::scene::aggregate::SceneAggregate;
use kameo::actor::{ActorRef, Spawn};
use kameo_es::event_handler::EventHandlerStreamBuilder;
use kameo_es::event_handler::postgres::PostgresProcessor;
use redis::Client as RedisClient;
use sierradb_client::SierraAsyncClientExt;
use sqlx::PgPool;

const CHECKPOINTS_TABLE: &str = "sierradb_event_checkpoints";

type SceneProcessor = PostgresProcessor<(SceneAggregate,), SceneProjector>;
type CharacterProcessor = PostgresProcessor<(CharacterAggregate,), CharacterProjector>;
type CostumeProcessor = PostgresProcessor<(CostumeAggregate,), CostumeProjector>;
type CalculationProcessor = PostgresProcessor<(CalculationAggregate,), CalculationProjector>;

/// Spawn a supervised projector subscription loop.
///
/// `category` is a human-readable name used in tracing.  The supervisor
/// wraps the SierraDB subscription + `stream.run()` in a restart loop
/// with exponential backoff and bounded retry budget.
macro_rules! run_projection_stream {
    ($entity:ty, $category:expr, $redis_client:expr, $actor_ref:expr) => {{
        let actor_ref_inner = $actor_ref.clone();
        let redis_client_inner = $redis_client.clone();
        let category = $category;

        let _handle = supervisor::run_with_restart(category, move || {
            let mut ar = actor_ref_inner.clone();
            let client = redis_client_inner.clone();
            async move {
                let mut manager = client.subscription_manager().await?;
                let mut stream = <($entity,)>::event_handler_stream(&mut manager, &mut ar).await?;
                stream
                    .run(&mut ar)
                    .await
                    .map_err(|e| anyhow::Error::from(e))
            }
        })
        .await?;
        // Drop immediately — the supervisor loop will restart and continue
        // in the background. We intentionally do not keep the JoinHandle,
        // so the supervisor is not prematurely aborted.
        drop(_handle);
        Ok::<_, anyhow::Error>(())
    }};
}

/// Spawn the scene projector actor and start its SierraDB subscription loop in the background.
pub async fn spawn_scene_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<SceneProcessor>> {
    let conn = redis_client.get_multiplexed_tokio_connection().await?;
    let processor = SceneProcessor::new(
        pool.clone(),
        conn,
        CHECKPOINTS_TABLE,
        "scene",
        SceneProjector,
    )
    .await?;
    let actor_ref = SceneProcessor::spawn(processor);
    run_projection_stream!(SceneAggregate, "scene", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

/// Spawn the character projector actor and start its subscription loop.
pub async fn spawn_character_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<CharacterProcessor>> {
    let conn = redis_client.get_multiplexed_tokio_connection().await?;
    let processor = CharacterProcessor::new(
        pool.clone(),
        conn,
        CHECKPOINTS_TABLE,
        "character",
        CharacterProjector,
    )
    .await?;
    let actor_ref = CharacterProcessor::spawn(processor);
    run_projection_stream!(
        CharacterAggregate,
        "character",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

/// Spawn the costume projector actor and start its subscription loop.
pub async fn spawn_costume_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<CostumeProcessor>> {
    let conn = redis_client.get_multiplexed_tokio_connection().await?;
    let processor = CostumeProcessor::new(
        pool.clone(),
        conn,
        CHECKPOINTS_TABLE,
        "costume",
        CostumeProjector,
    )
    .await?;
    let actor_ref = CostumeProcessor::spawn(processor);
    run_projection_stream!(CostumeAggregate, "costume", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

/// Spawn the calculation projector actor and start its subscription loop.
pub async fn spawn_calculation_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<CalculationProcessor>> {
    let conn = redis_client.get_multiplexed_tokio_connection().await?;
    let processor = CalculationProcessor::new(
        pool.clone(),
        conn,
        CHECKPOINTS_TABLE,
        "calculation",
        CalculationProjector,
    )
    .await?;
    let actor_ref = CalculationProcessor::spawn(processor);
    run_projection_stream!(
        CalculationAggregate,
        "calculation",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}
