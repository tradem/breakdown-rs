// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: qwen3.6-35b (neuralwatt)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: hy3 (opencode-go)

//! Projection actors – one `PostgresProcessor` per aggregate.
//!
//! Each projector has its own checkpoint row set inside `sierradb_event_checkpoints`
//! and can fail/catch-up independently (ADR-015).

mod ai_config;
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
mod settings;
mod shooting_day;
pub mod supervisor;

pub use crate::photo::projector::PhotoProjector;
pub use ai_config::AiConfigProjector;
pub use audit::{
    AuditCategory, AuditProjector, BlockAuditProjector, CharacterAuditProjector,
    CostumeAuditProjector, CostumeCategoryAuditProjector, EpisodeAuditProjector,
    MembershipAuditProjector, PhotoAuditProjector, SceneAuditProjector, SceneShootAuditProjector,
    SeasonAuditProjector, SettingsAuditProjector, ShootingDayAuditProjector,
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
pub use settings::SettingsProjector;
pub use shooting_day::ShootingDayProjector;

use std::sync::Arc;

use anyhow::{self, Result};
use breakdown_core::ai::aggregate::AiConfig;
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
use breakdown_core::settings::aggregate::SettingsAggregate;
use breakdown_core::shooting_day::aggregate::ShootingDayAggregate;
use kameo::actor::{ActorRef, Spawn};
use kameo_es::event_handler::EventHandlerStreamBuilder;
use kameo_es::event_handler::postgres::PostgresProcessor;
use redis::Client as RedisClient;
use sierradb_client::SierraAsyncClientExt;
use sqlx::PgPool;

const CHECKPOINTS_TABLE: &str = "sierradb_event_checkpoints";

/// Read-model contract version (ADR-020 D4).
///
/// Every projector stamps the `projector_version` column of the rows it
/// writes with this constant. Bump it only when the projectors' event-
/// consumption contract changes (a new required event field, a retyped
/// variant, a projector that no longer recognises a historical event): the
/// event-schema fixture-replay contract tests in `crates/integration-tests`
/// then fail until the bump is coordinated with a projector redeploy
/// (deploy-order rule, ADR-020 D4 / release-runbook §5).
pub const PROJECTOR_VERSION: i64 = 1;

/// Tunable projector flush / worker configuration.
///
/// `Default` is **production**: no overrides, preserving the upstream
/// `kameo_es::PostgresProcessor` defaults (workers = 16, live 2 s / 10
/// events, replay 10 s / 10 000 events). `fn test_profile` tightens these
/// for fast CI feedback and to avoid pool starvation in sequential test
/// runs (ADR-016) — it must never be used in production boot.
#[derive(Clone, Copy, Debug, Default)]
pub struct ProjectorFlushConfig {
    workers: Option<u16>,
    flush_live_interval_time: Option<Duration>,
    flush_live_interval_events: Option<u64>,
    flush_replay_interval_time: Option<Duration>,
    flush_replay_interval_events: Option<u64>,
}

impl ProjectorFlushConfig {
    /// Aggressive flush for tests: commit within 500 ms / 5 events and limit
    /// parallelism to 2 workers. Reduces wall-clock and pool pressure under
    /// sequential testcontainers runs.
    #[doc(hidden)]
    pub fn test_profile() -> Self {
        Self {
            workers: Some(2),
            flush_live_interval_time: Some(Duration::from_millis(500)),
            flush_live_interval_events: Some(5),
            flush_replay_interval_time: Some(Duration::from_secs(2)),
            flush_replay_interval_events: Some(50),
        }
    }

    /// Apply the overrides to a processor. `Default` leaves it untouched
    /// (production defaults stay intact); `test_profile` tightens flush/parallelism.
    pub fn apply<E, H>(self, processor: PostgresProcessor<E, H>) -> PostgresProcessor<E, H>
    where
        E: 'static,
        H: EventHandler<sqlx::Transaction<'static, Postgres>>
            + CompositeEventHandler<
                E,
                sqlx::Transaction<'static, Postgres>,
                PostgresEventProcessorError,
            > + Send
            + 'static,
        <H as EventHandler<sqlx::Transaction<'static, Postgres>>>::Error: fmt::Debug + Sync,
    {
        let mut p = processor;
        if let Some(w) = self.workers {
            p = p.workers(w);
        }
        if let Some(d) = self.flush_live_interval_time {
            p = p.flush_live_interval_time(d);
        }
        if let Some(n) = self.flush_live_interval_events {
            p = p.flush_live_interval_events(n);
        }
        if let Some(d) = self.flush_replay_interval_time {
            p = p.flush_replay_interval_time(d);
        }
        if let Some(n) = self.flush_replay_interval_events {
            p = p.flush_replay_interval_events(n);
        }
        p
    }
}

use kameo_es::event_handler::postgres::PostgresEventProcessorError;
use kameo_es::event_handler::{CompositeEventHandler, EventHandler};
use sqlx::Postgres;
use std::fmt;
use std::time::Duration;

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
type SettingsProcessor = PostgresProcessor<(SettingsAggregate,), SettingsProjector>;
type AiConfigProcessor = PostgresProcessor<(AiConfig,), AiConfigProjector>;
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
type SettingsAuditProcessor = PostgresProcessor<(SettingsAggregate,), SettingsAuditProjector>;

// Backward-compat alias — the original v1 used a single `BlockMembership` stream.
// (Already re-exported via the block above; left here for clarity.)
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

/// Same as `run_projection_stream!` but returns the supervisor `JoinHandle`
/// instead of dropping it. Caller **must** keep the handle alive to prevent
/// the supervisor loop from being cancelled.
macro_rules! run_projection_stream_handle {
    ($entity:ty, $category:expr, $redis_client:expr, $actor_ref:expr) => {{
        let actor_ref_inner = $actor_ref.clone();
        let redis_client_inner = $redis_client.clone();
        let category = $category;

        let handle = supervisor::run_with_restart(category, move || {
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
        Ok::<_, anyhow::Error>(handle)
    }};
}

/// Holds all supervisor `JoinHandle`s for the audit projectors.
/// Dropping this struct drops all handles, which gracefully stops
/// all projector subscription loops.
#[must_use = "Projector handles must be kept alive to prevent suppression"]
pub struct AuditProjectorHandles {
    pub handles: [Option<tokio::task::JoinHandle<()>>; 12],
}

impl Default for AuditProjectorHandles {
    fn default() -> Self {
        Self::new()
    }
}

impl AuditProjectorHandles {
    pub fn new() -> Self {
        Self {
            handles: [
                None, None, None, None, None, None, None, None, None, None, None, None,
            ],
        }
    }

    pub fn store(&mut self, idx: usize, handle: tokio::task::JoinHandle<()>) {
        debug_assert!(idx < 12);
        self.handles[idx] = Some(handle);
    }
}

impl Drop for AuditProjectorHandles {
    fn drop(&mut self) {
        self.handles.iter_mut().for_each(|h| {
            if let Some(handle) = h.take() {
                handle.abort();
            }
        });
    }
}

/// Spawn the scene projector actor and start its SierraDB subscription loop in the background.
pub async fn spawn_scene_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<ActorRef<SceneProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        SceneProcessor::new(
            pool.clone(),
            conn,
            CHECKPOINTS_TABLE,
            "scene",
            SceneProjector,
        )
        .await?,
    );
    let actor_ref = SceneProcessor::spawn(processor);
    run_projection_stream!(SceneAggregate, "scene", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

/// Spawn the character projector actor and start its subscription loop.
pub async fn spawn_character_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<ActorRef<CharacterProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        CharacterProcessor::new(
            pool.clone(),
            conn,
            CHECKPOINTS_TABLE,
            "character",
            CharacterProjector,
        )
        .await?,
    );
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
    config: ProjectorFlushConfig,
) -> Result<ActorRef<CostumeProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        CostumeProcessor::new(
            pool.clone(),
            conn,
            CHECKPOINTS_TABLE,
            "costume",
            CostumeProjector,
        )
        .await?,
    );
    let actor_ref = CostumeProcessor::spawn(processor);
    run_projection_stream!(CostumeAggregate, "costume", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

/// Spawn the costume-category projector actor and start its SierraDB subscription loop.
pub async fn spawn_costume_category_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<ActorRef<CostumeCategoryProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        CostumeCategoryProcessor::new(
            pool.clone(),
            conn,
            CHECKPOINTS_TABLE,
            "costume_category",
            CostumeCategoryProjector,
        )
        .await?,
    );
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
    config: ProjectorFlushConfig,
) -> Result<ActorRef<SeasonProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        SeasonProcessor::new(
            pool.clone(),
            conn,
            CHECKPOINTS_TABLE,
            "season",
            SeasonProjector,
        )
        .await?,
    );
    let actor_ref = SeasonProcessor::spawn(processor);
    run_projection_stream!(SeasonAggregate, "season", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

/// Spawn the block projector actor and start its SierraDB subscription loop.
pub async fn spawn_block_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<ActorRef<BlockProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        BlockProcessor::new(
            pool.clone(),
            conn,
            CHECKPOINTS_TABLE,
            "block",
            BlockProjector,
        )
        .await?,
    );
    let actor_ref = BlockProcessor::spawn(processor);
    run_projection_stream!(BlockAggregate, "block", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

/// Spawn the episode projector actor and start its SierraDB subscription loop.
pub async fn spawn_episode_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<ActorRef<EpisodeProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        EpisodeProcessor::new(
            pool.clone(),
            conn,
            CHECKPOINTS_TABLE,
            "episode",
            EpisodeProjector,
        )
        .await?,
    );
    let actor_ref = EpisodeProcessor::spawn(processor);
    run_projection_stream!(EpisodeAggregate, "episode", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

/// Spawn the membership projector actor and start its SierraDB subscription loop.
pub async fn spawn_membership_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<ActorRef<MembershipProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        MembershipProcessor::new(
            pool.clone(),
            conn,
            CHECKPOINTS_TABLE,
            "membership",
            MembershipProjector,
        )
        .await?,
    );
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
    config: ProjectorFlushConfig,
) -> Result<ActorRef<SeasonAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        SeasonAuditProcessor::new(
            pool,
            conn,
            CHECKPOINTS_TABLE,
            "audit:season",
            SeasonAuditProjector,
        )
        .await?,
    );
    let actor_ref = SeasonAuditProcessor::spawn(processor);
    run_projection_stream_handle!(
        SeasonAggregate,
        "audit:season",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

/// Spawn the block audit projector.
pub async fn spawn_block_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<ActorRef<BlockAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        BlockAuditProcessor::new(
            pool,
            conn,
            CHECKPOINTS_TABLE,
            "audit:block",
            BlockAuditProjector,
        )
        .await?,
    );
    let actor_ref = BlockAuditProcessor::spawn(processor);
    run_projection_stream_handle!(
        BlockAggregate,
        "audit:block",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

/// Spawn the episode audit projector.
pub async fn spawn_episode_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<ActorRef<EpisodeAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        EpisodeAuditProcessor::new(
            pool,
            conn,
            CHECKPOINTS_TABLE,
            "audit:episode",
            EpisodeAuditProjector,
        )
        .await?,
    );
    let actor_ref = EpisodeAuditProcessor::spawn(processor);
    run_projection_stream_handle!(
        EpisodeAggregate,
        "audit:episode",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

/// Spawn the scene audit projector.
pub async fn spawn_scene_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<ActorRef<SceneAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        SceneAuditProcessor::new(
            pool,
            conn,
            CHECKPOINTS_TABLE,
            "audit:scene",
            SceneAuditProjector,
        )
        .await?,
    );
    let actor_ref = SceneAuditProcessor::spawn(processor);
    run_projection_stream_handle!(
        SceneAggregate,
        "audit:scene",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

/// Spawn the scene-shoot audit projector.
pub async fn spawn_scene_shoot_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<ActorRef<SceneShootAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        SceneShootAuditProcessor::new(
            pool,
            conn,
            CHECKPOINTS_TABLE,
            "audit:scene_shoot",
            SceneShootAuditProjector,
        )
        .await?,
    );
    let actor_ref = SceneShootAuditProcessor::spawn(processor);
    run_projection_stream_handle!(
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
    config: ProjectorFlushConfig,
) -> Result<ActorRef<ShootingDayAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        ShootingDayAuditProcessor::new(
            pool,
            conn,
            CHECKPOINTS_TABLE,
            "audit:shooting_day",
            ShootingDayAuditProjector,
        )
        .await?,
    );
    let actor_ref = ShootingDayAuditProcessor::spawn(processor);
    run_projection_stream_handle!(
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
    config: ProjectorFlushConfig,
) -> Result<ActorRef<CharacterAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        CharacterAuditProcessor::new(
            pool,
            conn,
            CHECKPOINTS_TABLE,
            "audit:character",
            CharacterAuditProjector,
        )
        .await?,
    );
    let actor_ref = CharacterAuditProcessor::spawn(processor);
    run_projection_stream_handle!(
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
    config: ProjectorFlushConfig,
) -> Result<ActorRef<CostumeAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        CostumeAuditProcessor::new(
            pool,
            conn,
            CHECKPOINTS_TABLE,
            "audit:costume",
            CostumeAuditProjector,
        )
        .await?,
    );
    let actor_ref = CostumeAuditProcessor::spawn(processor);
    run_projection_stream_handle!(
        CostumeAggregate,
        "audit:costume",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

/// Spawn the costume-category audit projector.
pub async fn spawn_costume_category_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<ActorRef<CostumeCategoryAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        CostumeCategoryAuditProcessor::new(
            pool,
            conn,
            CHECKPOINTS_TABLE,
            "audit:costume_category",
            CostumeCategoryAuditProjector,
        )
        .await?,
    );
    let actor_ref = CostumeCategoryAuditProcessor::spawn(processor);
    run_projection_stream_handle!(
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
    config: ProjectorFlushConfig,
) -> Result<ActorRef<PhotoAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        PhotoAuditProcessor::new(
            pool,
            conn,
            CHECKPOINTS_TABLE,
            "audit:photo",
            PhotoAuditProjector,
        )
        .await?,
    );
    let actor_ref = PhotoAuditProcessor::spawn(processor);
    run_projection_stream_handle!(
        PhotoAggregate,
        "audit:photo",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

/// Spawn audit projectors for a specific set of categories.
///
/// This is the entry point for test code that only needs a subset of
/// audit projectors, so different tests can hold their own isolated
/// `PgPool` instances without competing for connections.
pub async fn spawn_audit_projectors_for_types(
    categories: &[AuditCategory],
    handlers: &mut AuditProjectorHandles,
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<()> {
    for category in categories {
        spawn_single_audit_projector(
            *category,
            handlers,
            pool.clone(),
            redis_client.clone(),
            config,
        )
        .await?;
    }
    Ok(())
}

/// Spawn **all** generalized audit projectors at once.
///
/// This is the preferred entry point for new code that does not need
/// a specific `ActorRef` return value. It covers every aggregate
/// category including membership.
pub async fn spawn_all_audit_projectors(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<AuditProjectorHandles> {
    let categories = [
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
        AuditCategory::Settings,
    ];
    let mut handles = AuditProjectorHandles::new();
    for category in categories {
        spawn_single_audit_projector(
            category,
            &mut handles,
            pool.clone(),
            redis_client.clone(),
            config,
        )
        .await?;
    }
    Ok(handles)
}

/// Spawn **one** specific audit projector by category.
///
/// This function must be updated whenever `AuditCategory` gains a variant —
/// the exhaustive `match` enforces compile-time coverage.
pub async fn spawn_single_audit_projector(
    category: AuditCategory,
    handlers: &mut AuditProjectorHandles,
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<()> {
    // Exhaustive match on AuditCategory — adding a variant without
    // an arm causes a compile error.
    match category {
        AuditCategory::Season => {
            let conn = redis_client.get_multiplexed_async_connection().await?;
            let processor = config.apply(
                SeasonAuditProcessor::new(
                    pool,
                    conn,
                    CHECKPOINTS_TABLE,
                    "audit:season",
                    SeasonAuditProjector,
                )
                .await?,
            );
            let ar = SeasonAuditProcessor::spawn(processor);
            let handle = run_projection_stream_handle!(
                SeasonAggregate,
                "audit:season",
                redis_client,
                ar.clone()
            )?;
            handlers.store(AuditCategory::Season as usize, handle);
        }
        AuditCategory::Block => {
            let conn = redis_client.get_multiplexed_async_connection().await?;
            let processor = config.apply(
                BlockAuditProcessor::new(
                    pool,
                    conn,
                    CHECKPOINTS_TABLE,
                    "audit:block",
                    BlockAuditProjector,
                )
                .await?,
            );
            let ar = BlockAuditProcessor::spawn(processor);
            let handle = run_projection_stream_handle!(
                BlockAggregate,
                "audit:block",
                redis_client,
                ar.clone()
            )?;
            handlers.store(AuditCategory::Block as usize, handle);
        }
        AuditCategory::Episode => {
            let conn = redis_client.get_multiplexed_async_connection().await?;
            let processor = config.apply(
                EpisodeAuditProcessor::new(
                    pool,
                    conn,
                    CHECKPOINTS_TABLE,
                    "audit:episode",
                    EpisodeAuditProjector,
                )
                .await?,
            );
            let ar = EpisodeAuditProcessor::spawn(processor);
            let handle = run_projection_stream_handle!(
                EpisodeAggregate,
                "audit:episode",
                redis_client,
                ar.clone()
            )?;
            handlers.store(AuditCategory::Episode as usize, handle);
        }
        AuditCategory::Scene => {
            let conn = redis_client.get_multiplexed_async_connection().await?;
            let processor = config.apply(
                SceneAuditProcessor::new(
                    pool,
                    conn,
                    CHECKPOINTS_TABLE,
                    "audit:scene",
                    SceneAuditProjector,
                )
                .await?,
            );
            let ar = SceneAuditProcessor::spawn(processor);
            let handle = run_projection_stream_handle!(
                SceneAggregate,
                "audit:scene",
                redis_client,
                ar.clone()
            )?;
            handlers.store(AuditCategory::Scene as usize, handle);
        }
        AuditCategory::SceneShoot => {
            let conn = redis_client.get_multiplexed_async_connection().await?;
            let processor = config.apply(
                SceneShootAuditProcessor::new(
                    pool,
                    conn,
                    CHECKPOINTS_TABLE,
                    "audit:scene_shoot",
                    SceneShootAuditProjector,
                )
                .await?,
            );
            let ar = SceneShootAuditProcessor::spawn(processor);
            let handle = run_projection_stream_handle!(
                SceneShootAggregate,
                "audit:scene_shoot",
                redis_client,
                ar.clone()
            )?;
            handlers.store(AuditCategory::SceneShoot as usize, handle);
        }
        AuditCategory::ShootingDay => {
            let conn = redis_client.get_multiplexed_async_connection().await?;
            let processor = config.apply(
                ShootingDayAuditProcessor::new(
                    pool,
                    conn,
                    CHECKPOINTS_TABLE,
                    "audit:shooting_day",
                    ShootingDayAuditProjector,
                )
                .await?,
            );
            let ar = ShootingDayAuditProcessor::spawn(processor);
            let handle = run_projection_stream_handle!(
                ShootingDayAggregate,
                "audit:shooting_day",
                redis_client,
                ar.clone()
            )?;
            handlers.store(AuditCategory::ShootingDay as usize, handle);
        }
        AuditCategory::Character => {
            let conn = redis_client.get_multiplexed_async_connection().await?;
            let processor = config.apply(
                CharacterAuditProcessor::new(
                    pool,
                    conn,
                    CHECKPOINTS_TABLE,
                    "audit:character",
                    CharacterAuditProjector,
                )
                .await?,
            );
            let ar = CharacterAuditProcessor::spawn(processor);
            let handle = run_projection_stream_handle!(
                CharacterAggregate,
                "audit:character",
                redis_client,
                ar.clone()
            )?;
            handlers.store(AuditCategory::Character as usize, handle);
        }
        AuditCategory::Costume => {
            let conn = redis_client.get_multiplexed_async_connection().await?;
            let processor = config.apply(
                CostumeAuditProcessor::new(
                    pool,
                    conn,
                    CHECKPOINTS_TABLE,
                    "audit:costume",
                    CostumeAuditProjector,
                )
                .await?,
            );
            let ar = CostumeAuditProcessor::spawn(processor);
            let handle = run_projection_stream_handle!(
                CostumeAggregate,
                "audit:costume",
                redis_client,
                ar.clone()
            )?;
            handlers.store(AuditCategory::Costume as usize, handle);
        }
        AuditCategory::CostumeCategory => {
            let conn = redis_client.get_multiplexed_async_connection().await?;
            let processor = config.apply(
                CostumeCategoryAuditProcessor::new(
                    pool,
                    conn,
                    CHECKPOINTS_TABLE,
                    "audit:costume_category",
                    CostumeCategoryAuditProjector,
                )
                .await?,
            );
            let ar = CostumeCategoryAuditProcessor::spawn(processor);
            let handle = run_projection_stream_handle!(
                CostumeCategoryAggregate,
                "audit:costume_category",
                redis_client,
                ar.clone()
            )?;
            handlers.store(AuditCategory::CostumeCategory as usize, handle);
        }
        AuditCategory::Photo => {
            let conn = redis_client.get_multiplexed_async_connection().await?;
            let processor = config.apply(
                PhotoAuditProcessor::new(
                    pool,
                    conn,
                    CHECKPOINTS_TABLE,
                    "audit:photo",
                    PhotoAuditProjector,
                )
                .await?,
            );
            let ar = PhotoAuditProcessor::spawn(processor);
            let handle = run_projection_stream_handle!(
                PhotoAggregate,
                "audit:photo",
                redis_client,
                ar.clone()
            )?;
            handlers.store(AuditCategory::Photo as usize, handle);
        }
        AuditCategory::Membership => {
            let conn = redis_client.get_multiplexed_async_connection().await?;
            let processor = config.apply(
                MembershipAuditProcessor::new(
                    pool,
                    conn,
                    CHECKPOINTS_TABLE,
                    "audit:membership",
                    MembershipAuditProjector,
                )
                .await?,
            );
            let ar = MembershipAuditProcessor::spawn(processor);
            let handle = run_projection_stream_handle!(
                BlockMembership,
                "audit:membership",
                redis_client,
                ar.clone()
            )?;
            handlers.store(AuditCategory::Membership as usize, handle);
        }
        AuditCategory::Settings => {
            let conn = redis_client.get_multiplexed_async_connection().await?;
            let processor = config.apply(
                SettingsAuditProcessor::new(
                    pool,
                    conn,
                    CHECKPOINTS_TABLE,
                    "audit:settings",
                    SettingsAuditProjector,
                )
                .await?,
            );
            let ar = SettingsAuditProcessor::spawn(processor);
            let handle = run_projection_stream_handle!(
                SettingsAggregate,
                "audit:settings",
                redis_client,
                ar.clone()
            )?;
            handlers.store(AuditCategory::Settings as usize, handle);
        }
    }
    Ok(())
}

/// Spawn the membership audit projector (independent of the others).
pub async fn spawn_membership_audit_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<ActorRef<MembershipAuditProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        MembershipAuditProcessor::new(
            pool,
            conn,
            CHECKPOINTS_TABLE,
            "audit:membership",
            MembershipAuditProjector,
        )
        .await?,
    );
    let actor_ref = MembershipAuditProcessor::spawn(processor);
    run_projection_stream!(
        BlockMembership,
        "audit:membership",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

/// Spawn the Settings projector actor and start its SierraDB subscription loop.
pub async fn spawn_settings_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<ActorRef<SettingsProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        SettingsProcessor::new(pool, conn, CHECKPOINTS_TABLE, "settings", SettingsProjector)
            .await?,
    );
    let actor_ref = SettingsProcessor::spawn(processor);
    run_projection_stream!(
        SettingsAggregate,
        "settings",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

/// Spawn the AI configuration projector actor and start its SierraDB subscription loop.
pub async fn spawn_ai_config_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<ActorRef<AiConfigProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        AiConfigProcessor::new(
            pool,
            conn,
            CHECKPOINTS_TABLE,
            "ai_config",
            AiConfigProjector,
        )
        .await?,
    );
    let actor_ref = AiConfigProcessor::spawn(processor);
    run_projection_stream!(AiConfig, "ai_config", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

/// Spawn the shooting-day projector actor and start its SierraDB subscription loop.
pub async fn spawn_shooting_day_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<ActorRef<ShootingDayProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        ShootingDayProcessor::new(
            pool.clone(),
            conn,
            CHECKPOINTS_TABLE,
            "shooting_day",
            ShootingDayProjector,
        )
        .await?,
    );
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
    config: ProjectorFlushConfig,
) -> Result<ActorRef<PhotoProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        PhotoProcessor::new(
            pool.clone(),
            conn,
            CHECKPOINTS_TABLE,
            "photo",
            PhotoProjector,
        )
        .await?,
    );
    let actor_ref = PhotoProcessor::spawn(processor);
    run_projection_stream!(PhotoAggregate, "photo", redis_client, actor_ref.clone())?;
    Ok(actor_ref)
}

/// Spawn the scene-shoot projector actor and start its SierraDB subscription loop.
pub async fn spawn_scene_shoot_projector(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    config: ProjectorFlushConfig,
) -> Result<ActorRef<SceneShootProcessor>> {
    let conn = redis_client.get_multiplexed_async_connection().await?;
    let processor = config.apply(
        SceneShootProcessor::new(
            pool.clone(),
            conn,
            CHECKPOINTS_TABLE,
            "scene_shoot",
            SceneShootProjector,
        )
        .await?,
    );
    let actor_ref = SceneShootProcessor::spawn(processor);
    run_projection_stream!(
        SceneShootAggregate,
        "scene_shoot",
        redis_client,
        actor_ref.clone()
    )?;
    Ok(actor_ref)
}

// --- P4.1 mutation-hardening: spawn/flush/handle guards ---
//
// Kill the surviving mutants on `ProjectorFlushConfig::test_profile`
// (`Default::default()` substitution), `AuditProjectorHandles::store` (no-op),
// and `Drop for AuditProjectorHandles` (no abort). The projector-subscription
// and `handle` mutants require a live SierraDB + Postgres and live in the
// integration-tests crate.
#[cfg(test)]
mod mutation_tests {
    use super::*;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicBool, Ordering::SeqCst};

    #[test]
    fn test_profile_is_aggressive_and_non_default() {
        let cfg = ProjectorFlushConfig::test_profile();
        // The mutant `test_profile -> Default::default()` returns all-None,
        // so CI would run with production flush defaults (pool starvation).
        assert_eq!(cfg.workers, Some(2), "test_profile must pin 2 workers");
        assert_eq!(
            cfg.flush_live_interval_time,
            Some(Duration::from_millis(500)),
            "test_profile must tighten the live flush interval"
        );
        assert_eq!(
            cfg.flush_live_interval_events,
            Some(5),
            "test_profile must tighten the live flush event count"
        );
        assert_eq!(
            cfg.flush_replay_interval_events,
            Some(50),
            "test_profile must tighten the replay flush event count"
        );
        assert_ne!(
            cfg.workers,
            ProjectorFlushConfig::default().workers,
            "test_profile must differ from production default"
        );
    }

    #[tokio::test]
    async fn audit_projector_handles_store_records_handle() {
        let mut handles = AuditProjectorHandles::new();
        assert!(handles.handles[3].is_none());
        let handle = tokio::spawn(async {});
        handles.store(3, handle);
        assert!(
            handles.handles[3].is_some(),
            "store must record the JoinHandle at the given index"
        );
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn audit_projector_handles_drop_aborts_stored_handles() {
        // Park an infinite (never-notified) task; aborting it while parked on a
        // real await cancels the future and runs the guard's Drop.
        let never = std::sync::Arc::new(tokio::sync::Notify::new());
        struct AbortFlag(Arc<AtomicBool>);
        impl Drop for AbortFlag {
            fn drop(&mut self) {
                self.0.store(true, SeqCst);
            }
        }
        let flag = Arc::new(AtomicBool::new(false));
        let flag_clone = flag.clone();
        let mut handles = AuditProjectorHandles::new();
        let handle = tokio::spawn({
            let never = never.clone();
            let guard = AbortFlag(flag_clone);
            async move {
                // Keep the guard alive inside the future so it is only dropped
                // when `Drop` aborts this handle (cancelling the task). If `Drop`
                // failed to abort, the task would hang on `never` and the flag
                // would stay `false`, failing the assertion below.
                let _guard = guard;
                never.notified().await;
            }
        });
        handles.store(0, handle);
        drop(handles);
        // Cooperative cancellation: the aborted task drops its guard when the
        // runtime cancels it. Bounded cooperative yields, not a wall-clock sleep.
        for _ in 0..256 {
            tokio::task::yield_now().await;
        }
        assert!(
            flag.load(SeqCst),
            "Drop must abort stored projector handles"
        );
    }

    // --- spawn_* error-propagation guards ---
    //
    // These kill the `spawn_single_audit_projector -> Ok(())`,
    // `spawn_audit_projectors_for_types -> Ok(())` and
    // `spawn_all_audit_projectors -> Ok(Default::default())` mutants. The
    // projectors need a live SierraDB + Postgres to actually subscribe, so we
    // inject a connection that can never succeed and assert the spawn returns
    // `Err`. A mutant that swallows the error (returns `Ok`) would make these
    // assertions fail. (The live-DB `handle` / `write_audit_row` / block-handle
    // mutants are excluded in `.cargo/mutants.toml` per the `CommandsImpl>::`
    // precedent: they cannot be killed by fast whitebox unit tests in `infra`.)
    fn dead_pool() -> sqlx::PgPool {
        // connect_lazy never touches the network, so we get a pool that fails
        // on first use without hanging.
        sqlx::PgPool::connect_lazy("postgres://breakdown_app:breakdown_app@127.0.0.1:1/breakdown")
            .expect("connect_lazy must succeed for an unreachable target")
    }

    fn dead_redis() -> Arc<RedisClient> {
        Arc::new(RedisClient::open("redis://127.0.0.1:1/").expect("redis url must parse"))
    }

    #[tokio::test]
    async fn spawn_single_audit_projector_propagates_connection_error() {
        let result = spawn_single_audit_projector(
            AuditCategory::Season,
            &mut AuditProjectorHandles::new(),
            dead_pool(),
            dead_redis(),
            ProjectorFlushConfig::test_profile(),
        )
        .await;
        assert!(
            result.is_err(),
            "spawn_single_audit_projector must propagate connection errors"
        );
    }

    #[tokio::test]
    async fn spawn_audit_projectors_for_types_propagates_connection_error() {
        let categories = [AuditCategory::Season, AuditCategory::Block];
        let result = spawn_audit_projectors_for_types(
            &categories,
            &mut AuditProjectorHandles::new(),
            dead_pool(),
            dead_redis(),
            ProjectorFlushConfig::test_profile(),
        )
        .await;
        assert!(
            result.is_err(),
            "spawn_audit_projectors_for_types must propagate connection errors"
        );
    }

    #[tokio::test]
    async fn spawn_all_audit_projectors_propagates_connection_error() {
        let result = spawn_all_audit_projectors(
            dead_pool(),
            dead_redis(),
            ProjectorFlushConfig::test_profile(),
        )
        .await;
        assert!(
            result.is_err(),
            "spawn_all_audit_projectors must propagate connection errors"
        );
    }
}
