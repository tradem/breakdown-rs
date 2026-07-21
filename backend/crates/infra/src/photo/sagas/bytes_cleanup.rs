// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

use std::collections::HashMap;

use anyhow::Result;
use breakdown_core::photo::aggregate::PhotoAggregate;
use breakdown_core::photo::events::PhotoEvent;
use kameo_es::event_handler::{EventHandlerError, EventProcessor};
use kameo_es::{Entity, Event};
use breakdown_core::photo::ports::PhotoStorage;
use breakdown_core::shared::PhotoId;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};

use crate::photo::storage::OpenDalPhotoStorage;

/// Saga that reacts to `PhotoDeleted` events and removes the actual bytes
/// from the S3-compatible storage (Garage). Idempotent under redelivery.
#[derive(Clone, Debug)]
pub struct PhotoBytesCleanupSaga {
    storage: OpenDalPhotoStorage,
}

impl PhotoBytesCleanupSaga {
    pub fn new(storage: OpenDalPhotoStorage) -> Self {
        Self { storage }
    }
}

impl EventHandler<()> for PhotoBytesCleanupSaga {
    type Error = anyhow::Error;
}

impl EntityEventHandler<PhotoAggregate, ()> for PhotoBytesCleanupSaga {
    async fn handle(
        &mut self,
        _ctx: &mut (),
        _id: PhotoId,
        event: Event<PhotoEvent, ()>,
    ) -> Result<(), Self::Error> {
        match event.data {
            PhotoEvent::PhotoDeleted { id, .. } => {
                self.storage
                    .delete_all(id)
                    .await
                    .map_err(|e| anyhow::anyhow!("{e}"))?;
            }
            _ => {}
        }
        Ok(())
    }
}

impl EventProcessor<(PhotoAggregate,), PhotoBytesCleanupSaga> for PhotoBytesCleanupSaga {
    type Context = ();
    type Error = anyhow::Error;

    async fn start_from(&self) -> Result<HashMap<u16, u64>, Self::Error> {
        Ok(HashMap::new())
    }

    async fn process_event(
        &mut self,
        event: Event,
    ) -> Result<(), EventHandlerError<Self::Error, <Self as EventHandler<()>>::Error>> {
        if event.stream_id.category() != PhotoAggregate::category() {
            return Ok(());
        }
        let id = event
            .entity_id::<PhotoAggregate>()
            .map_err(|_| EventHandlerError::ParseID(event.stream_id.cardinal_id().to_string()))?;
        let event = event
            .as_entity::<PhotoAggregate>()
            .map_err(|(event, err)| EventHandlerError::DeserializeEvent {
                entity: PhotoAggregate::category(),
                event: event.name,
                err,
            })?;
        EntityEventHandler::<PhotoAggregate, ()>::handle(self, &mut (), id, event)
            .await
            .map_err(EventHandlerError::Handler)
    }
}
