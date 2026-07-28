// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Season-seeding saga — the canonical "event-reactor-issues-commands" pattern.
//!
//! Subscribes to the `season` stream and, on every `SeasonCreated`, dispatches
//! `CreateCostumeCategory` commands for each entry of a configurable default
//! seed. It is replay-safe: before seeding it checks `count_for_season` and
//! skips when the season already has categories, so reprocessing `SeasonCreated`
//! on projector restart never double-seeds. This is the precedent for the
//! future AI-imported ShootingDay flow.

use std::collections::HashMap;
use std::sync::Arc;

use anyhow::Result;
use breakdown_core::costume_category::commands::CreateCostumeCategory;
use breakdown_core::costume_category::ports::{CostumeCategoryCommands, CostumeCategoryRepository};
use breakdown_core::season::aggregate::SeasonAggregate;
use breakdown_core::season::events::SeasonEvent;
use breakdown_core::shared::{LexicalSortKey, SeasonId};
use kameo_es::command_service::CommandService;
use kameo_es::event_handler::{
    EntityEventHandler, EventHandler, EventHandlerError, EventHandlerStreamBuilder, EventProcessor,
};
use kameo_es::{Entity, Event};
use redis::Client as RedisClient;
use sierradb_client::SierraAsyncClientExt;
use sqlx::PgPool;
use uuid::Uuid;

use crate::event_store::CostumeCategoryCommandsImpl;
use crate::projectors::supervisor;
use crate::queries::CostumeCategoryRepositoryImpl;

/// Monotonic seed order keys (single printable-ASCII, lexicographically ordered).
/// There is no concurrent insertion during seeding, so a simple sequence suffices.
const SEED_ORDER_KEYS: &[&str] = &["a", "b", "c", "d", "e"];

/// Hard-coded fallback used only if the embedded TOML fails to parse.
const DEFAULT_SEED_FALLBACK: &[&str] = &["Oberteil", "Unterteil", "Schuhe", "Jacke", "Accessoires"];

#[derive(Debug, Clone, serde::Deserialize)]
pub struct DefaultCostumeCategoriesToml {
    pub names: Vec<String>,
}

/// Load the configurable default costume-category seed.
///
/// Precedence: `DEFAULT_COSTUME_CATEGORIES` env var (comma-separated) overrides
/// the embedded `config/default_costume_categories.toml`. Parsed in `infra`
/// (never in `core`).
pub fn load_default_costume_categories() -> Vec<String> {
    if let Ok(raw) = std::env::var("DEFAULT_COSTUME_CATEGORIES") {
        let parsed: Vec<String> = raw
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();
        if !parsed.is_empty() {
            return parsed;
        }
    }

    const EMBEDDED: &str = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../config/default_costume_categories.toml"
    ));
    match toml::from_str::<DefaultCostumeCategoriesToml>(EMBEDDED) {
        Ok(cfg) => cfg.names,
        Err(_) => DEFAULT_SEED_FALLBACK
            .iter()
            .map(|s| s.to_string())
            .collect(),
    }
}

/// The season-seeding saga subscriber.
#[derive(Clone, Debug)]
pub struct SeasonSeedingSaga {
    commands: CostumeCategoryCommandsImpl,
    repo: CostumeCategoryRepositoryImpl,
    seed: Vec<String>,
}

impl SeasonSeedingSaga {
    pub fn new(
        commands: CostumeCategoryCommandsImpl,
        repo: CostumeCategoryRepositoryImpl,
        seed: Vec<String>,
    ) -> Self {
        Self {
            commands,
            repo,
            seed,
        }
    }

    /// Idempotently seed one category per seed entry for `season_id`.
    async fn seed_for_season(&self, season_id: SeasonId) -> Result<()> {
        seed_season(&self.commands, &self.repo, &self.seed, season_id).await
    }
}

/// Generic seeding core, separated from the subscriber so it can be unit-tested
/// with in-memory fakes. Idempotent: skips when the season already has any
/// categories (the `count_for_season` guard), so replaying `SeasonCreated`
/// never double-seeds.
pub async fn seed_season<C, R>(
    commands: &C,
    repo: &R,
    seed: &[String],
    season_id: SeasonId,
) -> Result<()>
where
    C: CostumeCategoryCommands,
    R: CostumeCategoryRepository,
{
    let count = repo
        .count_for_season(season_id)
        .await
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    if count > 0 {
        return Ok(());
    }
    for (i, name) in seed.iter().enumerate() {
        let order_key = SEED_ORDER_KEYS.get(i).copied().unwrap_or("z");
        let cmd = CreateCostumeCategory {
            id: Uuid::now_v7(),
            season_id,
            name: name.clone(),
            order_key: LexicalSortKey::from_static(order_key),
        };
        commands
            .create(cmd)
            .await
            .map_err(|e| anyhow::anyhow!("{e}"))?;
    }
    Ok(())
}

impl EventHandler<()> for SeasonSeedingSaga {
    type Error = anyhow::Error;
}

impl EntityEventHandler<SeasonAggregate, ()> for SeasonSeedingSaga {
    async fn handle(
        &mut self,
        _ctx: &mut (),
        _id: Uuid,
        event: Event<SeasonEvent, ()>,
    ) -> Result<(), Self::Error> {
        if let SeasonEvent::SeasonCreated { id, .. } = event.data {
            self.seed_for_season(SeasonId(id)).await?;
        }
        Ok(())
    }
}

impl EventProcessor<(SeasonAggregate,), SeasonSeedingSaga> for SeasonSeedingSaga {
    type Context = ();
    type Error = anyhow::Error;

    async fn start_from(&self) -> Result<HashMap<u16, u64>, Self::Error> {
        // Always replay from the beginning; the idempotency guard in
        // `seed_for_season` makes reprocessing safe.
        Ok(HashMap::new())
    }

    async fn process_event(
        &mut self,
        event: Event,
    ) -> Result<(), EventHandlerError<Self::Error, <Self as EventHandler<()>>::Error>> {
        if event.stream_id.category() != SeasonAggregate::category() {
            return Ok(());
        }
        let id = event
            .entity_id::<SeasonAggregate>()
            .map_err(|_| EventHandlerError::ParseID(event.stream_id.cardinal_id().to_string()))?;
        let event = event
            .as_entity::<SeasonAggregate>()
            .map_err(|(event, err)| EventHandlerError::DeserializeEvent {
                entity: SeasonAggregate::category(),
                event: event.name,
                err,
            })?;
        EntityEventHandler::<SeasonAggregate, ()>::handle(self, &mut (), id, event)
            .await
            .map_err(EventHandlerError::Handler)
    }
}

/// Spawn the season-seeding saga subscription loop (supervised, background).
pub async fn spawn_season_seeding_saga(
    pool: PgPool,
    redis_client: Arc<RedisClient>,
    cmd_service: CommandService,
) -> Result<()> {
    let seed = load_default_costume_categories();
    let repo = CostumeCategoryRepositoryImpl::new(pool.clone());
    let commands = CostumeCategoryCommandsImpl::new(cmd_service);
    let saga = SeasonSeedingSaga::new(commands, repo, seed);
    let redis_client_inner = redis_client.clone();
    let _handle = supervisor::run_with_restart("season_seeding_saga", move || {
        let mut saga = saga.clone();
        let client = redis_client_inner.clone();
        async move {
            let mut manager = client.subscription_manager().await?;
            let mut stream =
                <(SeasonAggregate,)>::event_handler_stream(&mut manager, &mut saga).await?;
            stream
                .run(&mut saga)
                .await
                .map_err(|e| anyhow::anyhow!("{e}"))?;
            Ok::<_, anyhow::Error>(())
        }
    })
    .await?;
    drop(_handle);
    Ok(())
}

