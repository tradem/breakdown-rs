// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kwaipilot/kat-coder-air-v2.5 (openrouter)

//! Saga that reacts to `ContinuityPhotoUnlinked` events on the `scene_shoot`
//! stream. Checks refcount via `projection_continuity_photo` and dispatches
//! `DeletePhoto` when zero.

use std::collections::HashMap;
use std::sync::Arc;

use anyhow::Result;
use breakdown_core::photo::commands::DeletePhoto;
use breakdown_core::photo::ports::{PhotoCommands, PhotoRepository};
use breakdown_core::scene_shoot::aggregate::SceneShootAggregate;
use breakdown_core::scene_shoot::events::SceneShootEvent;
use breakdown_core::shared::PhotoId;
use kameo_es::event_handler::EventHandlerStreamBuilder;
use kameo_es::event_handler::{EntityEventHandler, EventHandler, EventHandlerError, EventProcessor};
use kameo_es::{Entity, Event};
use redis::Client as RedisClient;
use sierradb_client::SierraAsyncClientExt;
use uuid::Uuid;

use breakdown_core::shared::SceneShootId;

use crate::event_store::PhotoCommandsImpl;
use crate::photo::repository::PhotoRepositoryImpl;
use crate::projectors::supervisor;

/// Saga that disptaches `DeletePhoto` when a continuity photo's refcount
/// reaches zero.
///
/// Tracks `ContinuityPhotoLinked` / `ContinuityPhotoUnlinked` events on the
/// `scene_shoot` stream. When a `ContinuityPhotoUnlinked` event brings the
/// in-memory refcount to zero, the saga also queries `projection_costume_photo`
/// to check for remaining costume-side references before dispatching delete.
#[derive(Clone, Debug)]
pub struct ContinuityDeletionSaga {
    repo: PhotoRepositoryImpl,
    commands: PhotoCommandsImpl,
    /// In-memory continuity-photo refcounts keyed by `PhotoId`.
    refcounts: HashMap<Uuid, u64>,
}

impl ContinuityDeletionSaga {
    pub fn new(repo: PhotoRepositoryImpl, commands: PhotoCommandsImpl) -> Self {
        Self {
            repo,
            commands,
            refcounts: HashMap::new(),
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
        event: Event<SceneShootEvent, ()>,
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

                    let photo_view = match self.repo.find_by_id(photo_id).await {
                        Ok(view) => view,
                        Err(_) => return Ok(()),
                    };
                    self.commands
                        .delete(DeletePhoto {
                            id: photo_id,
                            version: photo_view.version,
                        })
                        .await
                        .map_err(|e| anyhow::anyhow!("{e}"))?;
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
pub async fn spawn_continuity_deletion_saga(
    repo: PhotoRepositoryImpl,
    commands: PhotoCommandsImpl,
    redis_client: Arc<RedisClient>,
) -> Result<()> {
    let saga = ContinuityDeletionSaga::new(repo, commands);
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
