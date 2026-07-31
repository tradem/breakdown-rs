// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.6-35b (neuralwatt)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: hy3 (opencode-go)

//! Saga that reacts to `ContinuityPhotoUnlinked` events on the `scene_shoot`
//! stream. Checks refcount via `projection_continuity_photo` and dispatches
//! `DeletePhoto` when zero.

use std::collections::HashMap;
use std::sync::Arc;

use anyhow::Result;
use breakdown_core::character::ports::CharacterRepository;
use breakdown_core::costume::ports::CostumeRepository;
use breakdown_core::episode::ports::EpisodeRepository;
use breakdown_core::photo::aggregate::PhotoAggregate;
use breakdown_core::photo::binding::PhotoBinding;
use breakdown_core::photo::commands::DeletePhoto;
use breakdown_core::photo::ports::PhotoRepository;
use breakdown_core::scene::ports::SceneRepository;
use breakdown_core::scene_shoot::aggregate::SceneShootAggregate;
use breakdown_core::scene_shoot::events::SceneShootEvent;
use breakdown_core::scene_shoot::ports::SceneShootRepository;
use breakdown_core::season::ports::SeasonRepository;
use breakdown_core::shared::{EventMetadata, PhotoId, Provenance, SceneShootId, SeriesId};
use kameo_es::command_service::CommandService;
use kameo_es::command_service::ExecuteExt;
use kameo_es::event_handler::EventHandlerStreamBuilder;
use kameo_es::event_handler::{
    EntityEventHandler, EventHandler, EventHandlerError, EventProcessor,
};
use kameo_es::{Entity, Event};
use redis::Client as RedisClient;
use sierradb_client::ExpectedVersion;
use sierradb_client::SierraAsyncClientExt;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::event_store::map_version_only;
use crate::photo::repository::PhotoRepositoryImpl;
use crate::projectors::supervisor;
use crate::queries::{
    CharacterRepositoryImpl, CostumeRepositoryImpl, EpisodeRepositoryImpl, SceneRepositoryImpl,
    SceneShootRepositoryImpl, SeasonRepositoryImpl,
};

/// Saga that dispatches `DeletePhoto` when a continuity photo's refcount
/// reaches zero, directly via `Aggregate::execute` with `Provenance::Saga`.
///
/// Tracks `ContinuityPhotoLinked` / `ContinuityPhotoUnlinked` events on the
/// `scene_shoot` stream. When a `ContinuityPhotoUnlinked` event brings the
/// in-memory refcount to zero, the saga also queries `projection_costume_photo`
/// to check for remaining costume-side references before dispatching delete.
#[derive(Clone, Debug)]
pub struct ContinuityDeletionSaga {
    cmd_service: CommandService,
    repo: PhotoRepositoryImpl,
    costume_repo: CostumeRepositoryImpl,
    character_repo: CharacterRepositoryImpl,
    season_repo: SeasonRepositoryImpl,
    scene_shoot_repo: SceneShootRepositoryImpl,
    scene_repo: SceneRepositoryImpl,
    episode_repo: EpisodeRepositoryImpl,
    pg_pool: PgPool,
    /// In-memory continuity-photo refcounts keyed by `PhotoId`.
    refcounts: HashMap<Uuid, u64>,
}

impl ContinuityDeletionSaga {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        cmd_service: CommandService,
        repo: PhotoRepositoryImpl,
        costume_repo: CostumeRepositoryImpl,
        character_repo: CharacterRepositoryImpl,
        season_repo: SeasonRepositoryImpl,
        scene_shoot_repo: SceneShootRepositoryImpl,
        scene_repo: SceneRepositoryImpl,
        episode_repo: EpisodeRepositoryImpl,
        pg_pool: PgPool,
    ) -> Self {
        Self {
            cmd_service,
            repo,
            costume_repo,
            character_repo,
            season_repo,
            scene_shoot_repo,
            scene_repo,
            episode_repo,
            pg_pool,
            refcounts: HashMap::new(),
        }
    }

    /// Resolve `series_id` from the photo's binding.
    async fn resolve_series_id(
        &self,
        photo_id: PhotoId,
    ) -> Result<Option<SeriesId>, anyhow::Error> {
        let binding = self
            .repo
            .find_by_id(photo_id)
            .await
            .map_err(|e| anyhow::anyhow!("{e}"))?
            .binding;
        match binding {
            PhotoBinding::Costume { costume_id } => {
                let costume = self
                    .costume_repo
                    .find_by_id(costume_id)
                    .await
                    .map_err(|e| anyhow::anyhow!("{e}"))?;
                match costume.character_id {
                    Some(character_id) => {
                        let ch = self
                            .character_repo
                            .find_by_id(character_id)
                            .await
                            .map_err(|e| anyhow::anyhow!("{e}"))?;
                        Ok(Some(
                            self.season_repo
                                .find_by_id(ch.season_id.0)
                                .await
                                .map_err(|e| anyhow::anyhow!("{e}"))?
                                .series_id,
                        ))
                    }
                    None => Ok(None),
                }
            }
            PhotoBinding::Continuity { scene_shoot_id: _, .. } => {
                // The binding in projection_photo is a generic marker.
                // The actual scene_shoot_id is in projection_continuity_photo.
                let row = sqlx::query(
                    r#"
                    SELECT scene_shoot_id
                    FROM projection_continuity_photo
                    WHERE photo_id = $1
                    LIMIT 1
                    "#,
                )
                .bind(photo_id.0)
                .fetch_optional(&self.pg_pool)
                .await
                .map_err(|e| anyhow::anyhow!("{e}"))?;

                let scene_shoot_id: Uuid = match row {
                    Some(r) => r.try_get("scene_shoot_id").map_err(|e| anyhow::anyhow!("{e}"))?,
                    None => {
                        // No continuity record — shouldn't happen for a continuity-bound photo.
                        return Ok(None);
                    }
                };

                let ss = self
                    .scene_shoot_repo
                    .find_by_id(SceneShootId(scene_shoot_id))
                    .await
                    .map_err(|e| anyhow::anyhow!("{e}"))?;
                let sc = self
                    .scene_repo
                    .find_by_id(ss.scene_id)
                    .await
                    .map_err(|e| anyhow::anyhow!("{e}"))?;
                Ok(Some(
                    self.episode_repo
                        .find_by_id(sc.episode_id.0)
                        .await
                        .map_err(|e| anyhow::anyhow!("{e}"))?
                        .series_id,
                ))
            }
        }
    }
}

impl EventHandler<()> for ContinuityDeletionSaga {
    type Error = anyhow::Error;
}

impl EntityEventHandler<SceneShootAggregate, ()> for ContinuityDeletionSaga {
    async fn handle(
        &mut self,
        _ctx: &mut (),
        _id: SceneShootId,
        event: Event<SceneShootEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        match event.data {
            SceneShootEvent::ContinuityPhotoLinked { photo_id, .. } => {
                *self.refcounts.entry(photo_id.0).or_insert(0) += 1;
            }
            SceneShootEvent::ContinuityPhotoUnlinked { photo_id, .. } => {
                let entry = self.refcounts.entry(photo_id.0).or_insert(0);
                *entry = entry.saturating_sub(1);

                if *entry == 0 {
                    self.refcounts.remove(&photo_id.0);

                    // Also check costume-side refcounts before deleting.
                    match self.repo.count_links(photo_id).await {
                        Ok(costume_refs) if costume_refs > 0 => {
                            // Still referenced by a costume — don't delete.
                            return Ok(());
                        }
                        Ok(_) => {
                            // No remaining references — proceed with delete.
                        }
                        Err(_) => {
                            // Photo not found in projections — skip.
                            return Ok(());
                        }
                    }

                    let photo_view = self.repo.find_by_id(photo_id).await.map_err(|e| anyhow::anyhow!("{e}"))?;
                    let series_id = self.resolve_series_id(photo_id).await?;
                    let stream_version = crate::event_store::domain_to_stream(photo_view.version)
                        .ok_or_else(|| {
                        anyhow::anyhow!(
                            "photo {photo_id} has version 0 — cannot determine stream version"
                        )
                    })?;
                    let result = PhotoAggregate::execute(
                        &self.cmd_service,
                        photo_id,
                        DeletePhoto {
                            id: photo_id,
                            version: photo_view.version,
                        },
                    )
                    .expected_version(ExpectedVersion::Exact(stream_version))
                    .metadata(EventMetadata {
                        actor: None,
                        provenance: Provenance::Saga("ContinuityDeletionSaga".to_string()),
                        series_id,
                    })
                    .await;
                    map_version_only(result).map_err(|e| anyhow::anyhow!("{e}"))?;
                }
            }
            _ => {}
        }
        Ok(())
    }
}

impl EventProcessor<(SceneShootAggregate,), ContinuityDeletionSaga> for ContinuityDeletionSaga {
    type Context = ();
    type Error = anyhow::Error;

    async fn start_from(&self) -> Result<HashMap<u16, u64>> {
        Ok(HashMap::new())
    }

    async fn process_event(
        &mut self,
        event: Event,
    ) -> Result<(), EventHandlerError<Self::Error, <Self as EventHandler<()>>::Error>> {
        if event.stream_id.category() != SceneShootAggregate::category() {
            return Ok(());
        }
        let id = event
            .entity_id::<SceneShootAggregate>()
            .map_err(|_| EventHandlerError::ParseID(event.stream_id.cardinal_id().to_string()))?;
        let event = event
            .as_entity::<SceneShootAggregate>()
            .map_err(|(event, err)| EventHandlerError::DeserializeEvent {
                entity: SceneShootAggregate::category(),
                event: event.name,
                err,
            })?;
        EntityEventHandler::<SceneShootAggregate, ()>::handle(self, &mut (), id, event)
            .await
            .map_err(EventHandlerError::Handler)
    }
}

/// Spawn the continuity deletion saga subscription loop (supervised, background).
#[allow(clippy::too_many_arguments)]
pub async fn spawn_continuity_deletion_saga(
    cmd_service: CommandService,
    repo: PhotoRepositoryImpl,
    costume_repo: CostumeRepositoryImpl,
    character_repo: CharacterRepositoryImpl,
    season_repo: SeasonRepositoryImpl,
    scene_shoot_repo: SceneShootRepositoryImpl,
    scene_repo: SceneRepositoryImpl,
    episode_repo: EpisodeRepositoryImpl,
    pg_pool: PgPool,
    redis_client: Arc<RedisClient>,
) -> Result<()> {
    let saga = ContinuityDeletionSaga::new(
        cmd_service,
        repo,
        costume_repo,
        character_repo,
        season_repo,
        scene_shoot_repo,
        scene_repo,
        episode_repo,
        pg_pool,
    );
    let _handle = supervisor::run_with_restart("continuity_deletion_saga", move || {
        let mut saga = saga.clone();
        let client = redis_client.clone();
        async move {
            let mut manager = client.subscription_manager().await?;
            let mut stream =
                <(SceneShootAggregate,)>::event_handler_stream(&mut manager, &mut saga).await?;
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
