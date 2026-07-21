// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Projection actors – one `PostgresProcessor` per aggregate.
//!
//! Each projector has its own checkpoint row set inside `sierradb_event_checkpoints`
//! and can fail/catch-up independently (ADR-015).

mod audit;
mod block;
mod character;
mod costume;
mod costume_category;
mod episode;
mod membership;
mod scene;
mod season;
mod shooting_day;
pub(crate) mod supervisor;

pub use crate::photo::projector::PhotoProjector;
pub use audit::AuditProjector;
pub use block::BlockProjector;
pub use character::CharacterProjector;
pub use costume::CostumeProjector;
pub use costume_category::CostumeCategoryProjector;
pub use episode::EpisodeProjector;
pub use membership::MembershipProjector;
pub use scene::SceneProjector;
pub use season::SeasonProjector;
pub use shooting_day::ShootingDayProjector;

use std::sync::Arc;

use anyhow::{self, Result};
use breakdown_core::block::aggregate::BlockAggregate;
use breakdown_core::character::aggregate::CharacterAggregate;
use breakdown_core::costume::aggregate::CostumeAggregate;
use breakdown_core::costume_category::aggregate::CostumeCategoryAggregate;
use breakdown_core::episode::aggregate::EpisodeAggregate;
use breakdown_core::membership::aggregate::BlockMembership;
use breakdown_core::photo::aggregate::PhotoAggregate;
use breakdown_core::scene::aggregate::SceneAggregate;
use breakdown_core::season::aggregate::SeasonAggregate;
use breakdown_core::shooting_day::aggregate::ShootingDayAggregate;
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
type CostumeCategoryProcessor =
    PostgresProcessor<(CostumeCategoryAggregate,), CostumeCategoryProjector>;
type SeasonProcessor = PostgresProcessor<(SeasonAggregate,), SeasonProjector>;
type BlockProcessor = PostgresProcessor<(BlockAggregate,), BlockProjector>;
type EpisodeProcessor = PostgresProcessor<(EpisodeAggregate,), EpisodeProjector>;
type MembershipProcessor = PostgresProcessor<(BlockMembership,), MembershipProjector>;
type AuditProcessor = PostgresProcessor<(BlockMembership,), AuditProjector>;
type ShootingDayProcessor = PostgresProcessor<(ShootingDayAggregate,), ShootingDayProjector>;
type PhotoProcessor = PostgresProcessor<(PhotoAggregate,), PhotoProjector>;

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

/// Spawn the costume-category projector actor and start its SierraDB subscription loop.
pub async fn spawn_costume_category_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<CostumeCategoryProcessor>> {
    let conn = redis_client.get_multiplexed_tokio_connection().await?;
    let processor = CostumeCategoryProcessor::new(
        pool.clone(),
        conn,
        CHECKPOINTS_TABLE,
        "costume_category",
        CostumeCategoryProjector,
    )
    .await?;
    let actor_ref = CostumeCategoryProcessor::spawn(processor);
    run_projection_stream!(
        CostumeCategoryAggregate,
        "costume_category",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

/// Spawn the season projector actor and start its SierraDB subscription loop.
pub async fn spawn_season_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<SeasonProcessor>> {
    let conn = redis_client.get_multiplexed_tokio_connection().await?;
    let processor = SeasonProcessor::new(
        pool.clone(),
        conn,
        CHECKPOINTS_TABLE,
        "season",
        SeasonProjector,
    )
    .await?;
    let actor_ref = SeasonProcessor::spawn(processor);
    run_projection_stream!(SeasonAggregate, "season", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

/// Spawn the block projector actor and start its SierraDB subscription loop.
pub async fn spawn_block_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<BlockProcessor>> {
    let conn = redis_client.get_multiplexed_tokio_connection().await?;
    let processor = BlockProcessor::new(
        pool.clone(),
        conn,
        CHECKPOINTS_TABLE,
        "block",
        BlockProjector,
    )
    .await?;
    let actor_ref = BlockProcessor::spawn(processor);
    run_projection_stream!(BlockAggregate, "block", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

/// Spawn the episode projector actor and start its SierraDB subscription loop.
pub async fn spawn_episode_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<EpisodeProcessor>> {
    let conn = redis_client.get_multiplexed_tokio_connection().await?;
    let processor = EpisodeProcessor::new(
        pool.clone(),
        conn,
        CHECKPOINTS_TABLE,
        "episode",
        EpisodeProjector,
    )
    .await?;
    let actor_ref = EpisodeProcessor::spawn(processor);
    run_projection_stream!(EpisodeAggregate, "episode", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

/// Spawn the membership projector actor and start its SierraDB subscription loop.
pub async fn spawn_membership_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<MembershipProcessor>> {
    let conn = redis_client.get_multiplexed_tokio_connection().await?;
    let processor = MembershipProcessor::new(
        pool.clone(),
        conn,
        CHECKPOINTS_TABLE,
        "membership",
        MembershipProjector,
    )
    .await?;
    let actor_ref = MembershipProcessor::spawn(processor);
    run_projection_stream!(
        BlockMembership,
        "membership",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

/// Spawn the audit projector actor and start its SierraDB subscription loop.
pub async fn spawn_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<AuditProcessor>> {
    let conn = redis_client.get_multiplexed_tokio_connection().await?;
    let processor = AuditProcessor::new(
        pool.clone(),
        conn,
        CHECKPOINTS_TABLE,
        "audit",
        AuditProjector,
    )
    .await?;
    let actor_ref = AuditProcessor::spawn(processor);
    run_projection_stream!(BlockMembership, "audit", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

/// Spawn the shooting-day projector actor and start its SierraDB subscription loop.
pub async fn spawn_shooting_day_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<ShootingDayProcessor>> {
    let conn = redis_client.get_multiplexed_tokio_connection().await?;
    let processor = ShootingDayProcessor::new(
        pool.clone(),
        conn,
        CHECKPOINTS_TABLE,
        "shooting_day",
        ShootingDayProjector,
    )
    .await?;
    let actor_ref = ShootingDayProcessor::spawn(processor);
    run_projection_stream!(
        ShootingDayAggregate,
        "shooting_day",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

/// Spawn the photo projector actor and start its SierraDB subscription loop.
pub async fn spawn_photo_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<PhotoProcessor>> {
    let conn = redis_client.get_multiplexed_tokio_connection().await?;
    let processor = PhotoProcessor::new(
        pool.clone(),
        conn,
        CHECKPOINTS_TABLE,
        "photo",
        PhotoProjector,
    )
    .await?;
    let actor_ref = PhotoProcessor::spawn(processor);
    run_projection_stream!(PhotoAggregate, "photo", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}
