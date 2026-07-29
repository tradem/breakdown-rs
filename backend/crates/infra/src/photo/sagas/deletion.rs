// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

use std::collections::HashMap;
use std::sync::Arc;

use anyhow::Result;
use breakdown_core::character::ports::CharacterRepository;
use breakdown_core::costume::aggregate::CostumeAggregate;
use breakdown_core::costume::events::CostumeEvent;
use breakdown_core::costume::ports::CostumeRepository;
use breakdown_core::episode::ports::EpisodeRepository;
use breakdown_core::photo::aggregate::PhotoAggregate;
use breakdown_core::photo::binding::PhotoBinding;
use breakdown_core::photo::commands::DeletePhoto;
use breakdown_core::photo::ports::PhotoRepository;
use breakdown_core::scene::ports::SceneRepository;
use breakdown_core::scene_shoot::ports::SceneShootRepository;
use breakdown_core::season::ports::SeasonRepository;
use breakdown_core::shared::{AggregateVersion, EventMetadata, PhotoId, Provenance, SeriesId};
use kameo_es::command_service::CommandService;
use kameo_es::command_service::ExecuteExt;
use kameo_es::event_handler::EventHandlerStreamBuilder;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use kameo_es::event_handler::{EventHandlerError, EventProcessor};
use kameo_es::{Entity, Event};
use redis::Client as RedisClient;
use sierradb_client::ExpectedVersion;
use sierradb_client::SierraAsyncClientExt;
use uuid::Uuid;

use crate::event_store::map_version_only;
use crate::photo::repository::PhotoRepositoryImpl;
use crate::projectors::supervisor;
use crate::queries::{
    CharacterRepositoryImpl, CostumeRepositoryImpl, EpisodeRepositoryImpl, SceneRepositoryImpl,
    SceneShootRepositoryImpl, SeasonRepositoryImpl,
};

/// Saga that reacts to `PhotoUnlinked` events on the `costume` stream.
/// When the refcount reaches zero, dispatches `DeletePhoto` on the `Photo`
/// aggregate directly via `Aggregate::execute` with `Provenance::Saga`.
///
/// Refcounts are tracked **in-memory** (`refcounts` map), NOT by querying the
/// projection. This avoids a race with the costume projector, which writes to
/// `projection_costume_photo` asynchronously. Since `start_from()` returns an
/// empty checkpoint, the saga replays all past events on every start and builds
/// accurate state from scratch.
#[derive(Clone, Debug)]
pub struct PhotoDeletionSaga {
    cmd_service: CommandService,
    repo: PhotoRepositoryImpl,
    costume_repo: CostumeRepositoryImpl,
    character_repo: CharacterRepositoryImpl,
    season_repo: SeasonRepositoryImpl,
    scene_shoot_repo: SceneShootRepositoryImpl,
    scene_repo: SceneRepositoryImpl,
    episode_repo: EpisodeRepositoryImpl,
    /// In-memory photo-link refcounts keyed by `PhotoId`.
    /// Incremented on `PhotoLinked`, decremented on `PhotoUnlinked`.
    /// When a count reaches 0, `DeletePhoto` is dispatched.
    refcounts: HashMap<Uuid, u64>,
}

impl PhotoDeletionSaga {
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
            PhotoBinding::Continuity { scene_shoot_id, .. } => {
                let ss = self
                    .scene_shoot_repo
                    .find_by_id(scene_shoot_id)
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

impl EventHandler<()> for PhotoDeletionSaga {
    type Error = anyhow::Error;
}

impl EntityEventHandler<CostumeAggregate, ()> for PhotoDeletionSaga {
    async fn handle(
        &mut self,
        _ctx: &mut (),
        _id: Uuid,
        event: Event<CostumeEvent, ()>,
    ) -> Result<(), Self::Error> {
        match event.data {
            CostumeEvent::PhotoLinked { photo_id, .. } => {
                *self.refcounts.entry(photo_id).or_insert(0) += 1;
            }
            CostumeEvent::PhotoUnlinked { photo_id, .. } => {
                let entry = self.refcounts.entry(photo_id).or_insert(0);
                *entry = entry.saturating_sub(1);

                if *entry == 0 {
                    self.refcounts.remove(&photo_id);

                    // Fetch the current version to dispatch delete with the
                    // correct expected version.
                    let photo_id = PhotoId::from_uuid(photo_id);
                    let version = match self.repo.find_by_id(photo_id).await {
                        Ok(view) => view.version,
                        Err(_) => {
                            // Photo not found in projections — skip.
                            return Ok(());
                        }
                    };
                    let series_id = self.resolve_series_id(photo_id).await?;
                    let result = PhotoAggregate::execute(
                        &self.cmd_service,
                        photo_id,
                        DeletePhoto {
                            id: photo_id,
                            version,
                        },
                    )
                    .expected_version(ExpectedVersion::Exact(
                        crate::event_store::domain_to_stream(version).unwrap(),
                    ))
                    .metadata(EventMetadata {
                        actor: None,
                        provenance: Provenance::Saga("PhotoDeletionSaga".to_string()),
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

impl EventProcessor<(CostumeAggregate,), PhotoDeletionSaga> for PhotoDeletionSaga {
    type Context = ();
    type Error = anyhow::Error;

    async fn start_from(&self) -> Result<HashMap<u16, u64>, Self::Error> {
        Ok(HashMap::new())
    }

    async fn process_event(
        &mut self,
        event: Event,
    ) -> Result<(), EventHandlerError<Self::Error, <Self as EventHandler<()>>::Error>> {
        if event.stream_id.category() != CostumeAggregate::category() {
            return Ok(());
        }
        let id = event
            .entity_id::<CostumeAggregate>()
            .map_err(|_| EventHandlerError::ParseID(event.stream_id.cardinal_id().to_string()))?;
        let event = event
            .as_entity::<CostumeAggregate>()
            .map_err(|(event, err)| EventHandlerError::DeserializeEvent {
                entity: CostumeAggregate::category(),
                event: event.name,
                err,
            })?;
        EntityEventHandler::<CostumeAggregate, ()>::handle(self, &mut (), id, event)
            .await
            .map_err(EventHandlerError::Handler)
    }
}

/// Spawn the deletion saga subscription loop (supervised, background).
///
/// Subscribes to the `costume` stream and processes `PhotoUnlinked` events.
pub async fn spawn_photo_deletion_saga(
    cmd_service: CommandService,
    repo: PhotoRepositoryImpl,
    costume_repo: CostumeRepositoryImpl,
    character_repo: CharacterRepositoryImpl,
    season_repo: SeasonRepositoryImpl,
    scene_shoot_repo: SceneShootRepositoryImpl,
    scene_repo: SceneRepositoryImpl,
    episode_repo: EpisodeRepositoryImpl,
    redis_client: Arc<RedisClient>,
) -> Result<()> {
    let saga = PhotoDeletionSaga::new(
        cmd_service,
        repo,
        costume_repo,
        character_repo,
        season_repo,
        scene_shoot_repo,
        scene_repo,
        episode_repo,
    );
    let _handle = supervisor::run_with_restart("photo_deletion_saga", move || {
        let mut saga = saga.clone();
        let client = redis_client.clone();
        async move {
            let mut manager = client.subscription_manager().await?;
            let mut stream =
                <(CostumeAggregate,)>::event_handler_stream(&mut manager, &mut saga).await?;
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
