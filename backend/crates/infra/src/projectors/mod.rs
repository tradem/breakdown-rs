// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.6-35b (neuralwatt)

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
mod scene_shoot;
mod season;
mod shooting_day;
pub mod supervisor;

pub use crate::photo::projector::PhotoProjector;
pub use audit::{
    AuditCategory, AuditProjector, BlockAuditProjector, CharacterAuditProjector, CostumeAuditProjector,
    CostumeCategoryAuditProjector, EpisodeAuditProjector, MembershipAuditProjector,
    PhotoAuditProjector, SceneAuditProjector, SceneShootAuditProjector, SeasonAuditProjector,
    ShootingDayAuditProjector,
};
pub use block::BlockProjector;
pub use character::CharacterProjector;
pub use costume::CostumeProjector;
pub use costume_category::CostumeCategoryProjector;
pub use episode::EpisodeProjector;
pub use membership::MembershipProjector;
pub use scene::SceneProjector;
pub use scene_shoot::SceneShootProjector;
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
use breakdown_core::scene_shoot::aggregate::SceneShootAggregate;
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
type SceneShootProcessor = PostgresProcessor<(SceneShootAggregate,), SceneShootProjector>;
type CharacterProcessor = PostgresProcessor<(CharacterAggregate,), CharacterProjector>;
type CostumeProcessor = PostgresProcessor<(CostumeAggregate,), CostumeProjector>;
type CostumeCategoryProcessor =
    PostgresProcessor<(CostumeCategoryAggregate,), CostumeCategoryProjector>;
type SeasonProcessor = PostgresProcessor<(SeasonAggregate,), SeasonProjector>;
type BlockProcessor = PostgresProcessor<(BlockAggregate,), BlockProjector>;
type EpisodeProcessor = PostgresProcessor<(EpisodeAggregate,), EpisodeProjector>;
type MembershipProcessor = PostgresProcessor<(BlockMembership,), MembershipProjector>;
// Category-specific audit processors (one per aggregate).
// These subscribe to SierraDB streams per-aggregate so the
// generalized auditor covers all 11 entity categories.
type SeasonAuditProcessor = PostgresProcessor<(SeasonAggregate,), SeasonAuditProjector>;
type BlockAuditProcessor = PostgresProcessor<(BlockAggregate,), BlockAuditProjector>;
type EpisodeAuditProcessor = PostgresProcessor<(EpisodeAggregate,), EpisodeAuditProjector>;
type SceneAuditProcessor = PostgresProcessor<(SceneAggregate,), SceneAuditProjector>;
type SceneShootAuditProcessor = PostgresProcessor<(SceneShootAggregate,), SceneShootAuditProjector>;
type ShootingDayAuditProcessor =
    PostgresProcessor<(ShootingDayAggregate,), ShootingDayAuditProjector>;
type CharacterAuditProcessor = PostgresProcessor<(CharacterAggregate,), CharacterAuditProjector>;
type CostumeAuditProcessor = PostgresProcessor<(CostumeAggregate,), CostumeAuditProjector>;
type CostumeCategoryAuditProcessor =
    PostgresProcessor<(CostumeCategoryAggregate,), CostumeCategoryAuditProjector>;
type PhotoAuditProcessor = PostgresProcessor<(PhotoAggregate,), PhotoAuditProjector>;
type MembershipAuditProcessor = PostgresProcessor<(BlockMembership,), MembershipAuditProjector>;

// Backward-compat alias — the original v1 used a single `BlockMembership` stream.
// (Already re-exported via the block above; left here for clarity.)
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
    let conn = redis_client.get_multiplexed_async_connection().await?;
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
    let conn = redis_client.get_multiplexed_async_connection().await?;
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
    let conn = redis_client.get_multiplexed_async_connection().await?;
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
    let conn = redis_client.get_multiplexed_async_connection().await?;
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
    let conn = redis_client.get_multiplexed_async_connection().await?;
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
    let conn = redis_client.get_multiplexed_async_connection().await?;
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
    let conn = redis_client.get_multiplexed_async_connection().await?;
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
    let conn = redis_client.get_multiplexed_async_connection().await?;
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

// ── Generalized audit projector spawns (1 per category) ──────────────

/// Spawn the season audit projector.
pub async fn spawn_season_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<SeasonAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor =
        SeasonAuditProcessor::new(pool, conn, CHECKPOINTS_TABLE, "audit:season", SeasonAuditProjector)
            .await?;
    let actor_ref = SeasonAuditProcessor::spawn(processor);
    run_projection_stream!(SeasonAggregate, "audit:season", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

/// Spawn the block audit projector.
pub async fn spawn_block_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<BlockAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor =
        BlockAuditProcessor::new(pool, conn, CHECKPOINTS_TABLE, "audit:block", BlockAuditProjector)
            .await?;
    let actor_ref = BlockAuditProcessor::spawn(processor);
    run_projection_stream!(BlockAggregate, "audit:block", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

/// Spawn the episode audit projector.
pub async fn spawn_episode_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<EpisodeAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor =
        EpisodeAuditProcessor::new(pool, conn, CHECKPOINTS_TABLE, "audit:episode", EpisodeAuditProjector)
            .await?;
    let actor_ref = EpisodeAuditProcessor::spawn(processor);
    run_projection_stream!(EpisodeAggregate, "audit:episode", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

/// Spawn the scene audit projector.
pub async fn spawn_scene_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<SceneAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor =
        SceneAuditProcessor::new(pool, conn, CHECKPOINTS_TABLE, "audit:scene", SceneAuditProjector)
            .await?;
    let actor_ref = SceneAuditProcessor::spawn(processor);
    run_projection_stream!(SceneAggregate, "audit:scene", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

/// Spawn the scene-shoot audit projector.
pub async fn spawn_scene_shoot_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<SceneShootAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor =
        SceneShootAuditProcessor::new(pool, conn, CHECKPOINTS_TABLE, "audit:scene_shoot", SceneShootAuditProjector)
            .await?;
    let actor_ref = SceneShootAuditProcessor::spawn(processor);
    run_projection_stream!(
        SceneShootAggregate,
        "audit:scene_shoot",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

/// Spawn the shooting-day audit projector.
pub async fn spawn_shooting_day_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<ShootingDayAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = ShootingDayAuditProcessor::new(
        pool,
        conn,
        CHECKPOINTS_TABLE,
        "audit:shooting_day",
        ShootingDayAuditProjector,
    )
    .await?;
    let actor_ref = ShootingDayAuditProcessor::spawn(processor);
    run_projection_stream!(
        ShootingDayAggregate,
        "audit:shooting_day",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

/// Spawn the character audit projector.
pub async fn spawn_character_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<CharacterAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = CharacterAuditProcessor::new(
        pool,
        conn,
        CHECKPOINTS_TABLE,
        "audit:character",
        CharacterAuditProjector,
    )
    .await?;
    let actor_ref = CharacterAuditProcessor::spawn(processor);
    run_projection_stream!(
        CharacterAggregate,
        "audit:character",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

/// Spawn the costume audit projector.
pub async fn spawn_costume_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<CostumeAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor =
        CostumeAuditProcessor::new(pool, conn, CHECKPOINTS_TABLE, "audit:costume", CostumeAuditProjector)
            .await?;
    let actor_ref = CostumeAuditProcessor::spawn(processor);
    run_projection_stream!(CostumeAggregate, "audit:costume", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

/// Spawn the costume-category audit projector.
pub async fn spawn_costume_category_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<CostumeCategoryAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = CostumeCategoryAuditProcessor::new(
        pool,
        conn,
        CHECKPOINTS_TABLE,
        "audit:costume_category",
        CostumeCategoryAuditProjector,
    )
    .await?;
    let actor_ref = CostumeCategoryAuditProcessor::spawn(processor);
    run_projection_stream!(
        CostumeCategoryAggregate,
        "audit:costume_category",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

/// Spawn the photo audit projector.
pub async fn spawn_photo_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<PhotoAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor =
        PhotoAuditProcessor::new(pool, conn, CHECKPOINTS_TABLE, "audit:photo", PhotoAuditProjector)
            .await?;
    let actor_ref = PhotoAuditProcessor::spawn(processor);
    run_projection_stream!(PhotoAggregate, "audit:photo", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

// ── Combined audit projector spawn (backward-compat + full coverage) ──

/// Spawn the backward-compat audit projector.
///
/// This spawns **all 11** category audit projectors. The returned
/// `ActorRef` is the membership audit projector (same as the original API).
pub async fn spawn_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<AuditProcessor>> {
    spawn_all_audit_projectors(pool.clone(), redis_client.clone()).await?;
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = MembershipAuditProcessor::new(
        pool,
        conn,
        CHECKPOINTS_TABLE,
        "audit:membership",
        MembershipAuditProjector,
    )
    .await?;
    let actor_ref = MembershipAuditProcessor::spawn(processor);
    run_projection_stream!(
        BlockMembership,
        "audit:membership",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

/// Spawn **all** generalized audit projectors at once.
///
/// This is the preferred entry point for new code that does not need
/// a specific `ActorRef` return value. It covers every aggregate
/// category including membership.
pub async fn spawn_all_audit_projectors(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<()> {
    for category in [
        AuditCategory::Season,
        AuditCategory::Block,
        AuditCategory::Episode,
        AuditCategory::Scene,
        AuditCategory::SceneShoot,
        AuditCategory::ShootingDay,
        AuditCategory::Character,
        AuditCategory::Costume,
        AuditCategory::CostumeCategory,
        AuditCategory::Photo,
        AuditCategory::Membership,
    ] {
        spawn_single_audit_projector(category, pool.clone(), redis_client.clone()).await?;
    }
    Ok(())
}

/// Spawn **one** specific audit projector by category.
///
/// This function must be updated whenever `AuditCategory` gains a variant —
/// the exhaustive `match` enforces compile-time coverage.
pub fn spawn_single_audit_projector(
    category: AuditCategory,
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> impl std::future::Future<Output = Result<()>> + Send {
    async move {
        // Exhaustive match on AuditCategory — adding a variant without
        // an arm causes a compile error.
        match category {
            AuditCategory::Season => {
                let _ = spawn_season_audit_projector(pool, redis_client).await?;
            }
            AuditCategory::Block => {
                let _ = spawn_block_audit_projector(pool, redis_client).await?;
            }
            AuditCategory::Episode => {
                let _ = spawn_episode_audit_projector(pool, redis_client).await?;
            }
            AuditCategory::Scene => {
                let _ = spawn_scene_audit_projector(pool, redis_client).await?;
            }
            AuditCategory::SceneShoot => {
                let _ = spawn_scene_shoot_audit_projector(pool, redis_client).await?;
            }
            AuditCategory::ShootingDay => {
                let _ = spawn_shooting_day_audit_projector(pool, redis_client).await?;
            }
            AuditCategory::Character => {
                let _ = spawn_character_audit_projector(pool, redis_client).await?;
            }
            AuditCategory::Costume => {
                let _ = spawn_costume_audit_projector(pool, redis_client).await?;
            }
            AuditCategory::CostumeCategory => {
                let _ = spawn_costume_category_audit_projector(pool, redis_client).await?;
            }
            AuditCategory::Photo => {
                let _ = spawn_photo_audit_projector(pool, redis_client).await?;
            }
            AuditCategory::Membership => {
                let _ = spawn_membership_audit_projector(pool, redis_client).await?;
            }
        }
        Ok(())
    }
}

/// Spawn the membership audit projector (independent of the others).
pub async fn spawn_membership_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<MembershipAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = MembershipAuditProcessor::new(
        pool,
        conn,
        CHECKPOINTS_TABLE,
        "audit:membership",
        MembershipAuditProjector,
    )
    .await?;
    let actor_ref = MembershipAuditProcessor::spawn(processor);
    run_projection_stream!(
        BlockMembership,
        "audit:membership",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

/// Spawn the shooting-day projector actor and start its SierraDB subscription loop.
pub async fn spawn_shooting_day_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<ShootingDayProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
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
    let conn = redis_client.get_multiplexed_async_connection().await?;
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

/// Spawn the scene-shoot projector actor and start its SierraDB subscription loop.
pub async fn spawn_scene_shoot_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<ActorRef<SceneShootProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = SceneShootProcessor::new(
        pool.clone(),
        conn,
        CHECKPOINTS_TABLE,
        "scene_shoot",
        SceneShootProjector,
    )
    .await?;
    let actor_ref = SceneShootProcessor::spawn(processor);
    run_projection_stream!(
        SceneShootAggregate,
        "scene_shoot",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}
