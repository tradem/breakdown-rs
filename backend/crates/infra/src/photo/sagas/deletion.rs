// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use std::collections::HashMap;
use std::sync::Arc;

use anyhow::Result;
use breakdown_core::costume::aggregate::CostumeAggregate;
use breakdown_core::costume::events::CostumeEvent;
use breakdown_core::photo::commands::DeletePhoto;
use breakdown_core::photo::ports::{PhotoCommands, PhotoRepository};
use breakdown_core::shared::PhotoId;
use kameo_es::event_handler::EventHandlerStreamBuilder;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use kameo_es::event_handler::{EventHandlerError, EventProcessor};
use kameo_es::{Entity, Event};
use redis::Client as RedisClient;
use sierradb_client::SierraAsyncClientExt;
use uuid::Uuid;

use crate::event_store::PhotoCommandsImpl;
use crate::photo::repository::PhotoRepositoryImpl;
use crate::projectors::supervisor;

/// Saga that reacts to `PhotoUnlinked` events on the `costume` stream.
/// When the refcount reaches zero, dispatches `DeletePhoto` on the `Photo`
/// aggregate.
#[derive(Clone, Debug)]
pub struct PhotoDeletionSaga {
    repo: PhotoRepositoryImpl,
    commands: PhotoCommandsImpl,
}

impl PhotoDeletionSaga {
    pub fn new(repo: PhotoRepositoryImpl, commands: PhotoCommandsImpl) -> Self {
        Self { repo, commands }
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
        if let CostumeEvent::PhotoUnlinked { photo_id, .. } = event.data {
            let photo_id = PhotoId::from_uuid(photo_id);
            let refs = self
                .repo
                .count_links(photo_id)
                .await
                .map_err(|e| anyhow::anyhow!("{e}"))?;
            if refs == 0 {
                // Fetch the current version to dispatch delete with the
                // correct expected version.
                let version = match self.repo.find_by_id(photo_id).await {
                    Ok(view) => view.version,
                    Err(_) => {
                        // Photo not found in projections — skip.
                        return Ok(());
                    }
                };
                self.commands
                    .delete(DeletePhoto {
                        id: photo_id,
                        version,
                    })
                    .await
                    .map_err(|e| anyhow::anyhow!("{e}"))?;
            }
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
    repo: PhotoRepositoryImpl,
    commands: PhotoCommandsImpl,
    redis_client: Arc<RedisClient>,
) -> Result<()> {
    let saga = PhotoDeletionSaga::new(repo, commands);
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
