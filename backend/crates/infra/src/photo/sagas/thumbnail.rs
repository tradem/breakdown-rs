// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.6-35b (neuralwatt)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: glm-5.2 (neuralwatt)

use std::collections::HashMap;
use std::sync::Arc;

use anyhow::Result;
use breakdown_core::photo::aggregate::PhotoAggregate;
use breakdown_core::photo::commands::{GenerateVariant, NormalizeOriginal};
use breakdown_core::photo::events::PhotoEvent;
use breakdown_core::photo::ports::PhotoStorage;
use breakdown_core::shared::{
    AggregateVersion, EventMetadata, PhotoId, PhotoVariant, Provenance, SeriesId,
};
use kameo_es::command_service::CommandService;
use kameo_es::command_service::ExecuteExt;
use kameo_es::event_handler::EventHandlerStreamBuilder;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use kameo_es::event_handler::{EventHandlerError, EventProcessor};
use kameo_es::{Entity, Event};
use redis::Client as RedisClient;
use sierradb_client::ExpectedVersion;
use sierradb_client::SierraAsyncClientExt;

use crate::event_store::map_version_only;
use crate::photo::sagas::retry_transient;
use crate::photo::storage::OpenDalPhotoStorage;
use crate::projectors::supervisor;

/// Saga that reacts to `PhotoUploaded` events: fetches original bytes from
/// storage, decodes them, applies EXIF orientation correction, re-encodes
/// the original upright and EXIF-stripped, generates thumbnail and medium
/// variants, and dispatches the corresponding commands directly via
/// `PhotoAggregate::execute` with `Provenance::Saga`.
#[derive(Clone, Debug)]
pub struct PhotoThumbnailSaga {
    cmd_service: CommandService,
    storage: OpenDalPhotoStorage,
}

impl PhotoThumbnailSaga {
    pub fn new(cmd_service: CommandService, storage: OpenDalPhotoStorage) -> Self {
        Self {
            cmd_service,
            storage,
        }
    }
}

impl EventHandler<()> for PhotoThumbnailSaga {
    type Error = anyhow::Error;
}

impl EntityEventHandler<PhotoAggregate, ()> for PhotoThumbnailSaga {
    async fn handle(
        &mut self,
        _ctx: &mut (),
        _id: PhotoId,
        event: Event<PhotoEvent, EventMetadata>,
    ) -> Result<(), Self::Error> {
        if let PhotoEvent::PhotoUploaded { id, .. } = event.data {
            // CQRS boundary: audit context must come from the event data
            // (populated at the API edge), never from a read-model projection.
            // Missing metadata yields None — same tolerant best-effort path as
            // the old projection-based resolution.
            let series_id = event.metadata.data.as_ref().and_then(|m| m.series_id);
            self.process_upload_with_recovery(id, series_id).await?;
        }
        Ok(())
    }
}

impl PhotoThumbnailSaga {
    /// [`Self::process_upload`] wrapped in transient `ServiceUnavailable`
    /// retry (Vault recovery, issue #165). Retrying the action as a whole is
    /// safe: a `ServiceUnavailable` can only be raised while the SSE-C
    /// operator is not yet constructed — i.e. no storage operation has
    /// succeeded — so there is no partial progress to corrupt on retry.
    async fn process_upload_with_recovery(
        &self,
        id: PhotoId,
        series_id: Option<SeriesId>,
    ) -> Result<()> {
        retry_transient(|| self.process_upload(id, series_id)).await
    }

    async fn process_upload(&self, id: PhotoId, series_id: Option<SeriesId>) -> Result<()> {
        // Fetch the original bytes from storage.
        let photo_bytes = self.storage.fetch(id, PhotoVariant::Original).await?;

        // Decode the image, read EXIF orientation, and re-encode.
        let (re_encoded, rotated, thumb_bytes, medium_bytes) =
            Self::process_image(&photo_bytes.bytes)?;

        // Overwrite the original with the EXIF-stripped, re-encoded version.
        self.storage
            .store(
                id,
                PhotoVariant::Original,
                re_encoded,
                photo_bytes.content_type.clone(),
            )
            .await?;

        // Store the generated variants.
        self.storage
            .store(
                id,
                PhotoVariant::Thumb,
                thumb_bytes,
                "image/jpeg".to_string(),
            )
            .await?;
        self.storage
            .store(
                id,
                PhotoVariant::Medium,
                medium_bytes,
                "image/jpeg".to_string(),
            )
            .await?;

        // Dispatch the normalization command via Aggregate::execute.
        let norm_id = id;
        let norm_cmd = NormalizeOriginal {
            id,
            new_size: photo_bytes.size_bytes,
            rotated,
            series_id,
            version: AggregateVersion::INITIAL,
        };
        let result = PhotoAggregate::execute(&self.cmd_service, norm_id, norm_cmd)
            .expected_version(ExpectedVersion::Any)
            .metadata(EventMetadata {
                actor: None,
                provenance: Provenance::Saga("PhotoThumbnailSaga".to_string()),
                series_id,
            })
            .await;
        map_version_only(result)?;

        // Dispatch the Thumb variant generation command.
        let thumb_id = id;
        let thumb_cmd = GenerateVariant {
            id,
            variant: PhotoVariant::Thumb,
            size_bytes: 0,
            series_id,
            version: AggregateVersion::INITIAL,
        };
        let result = PhotoAggregate::execute(&self.cmd_service, thumb_id, thumb_cmd)
            .expected_version(ExpectedVersion::Any)
            .metadata(EventMetadata {
                actor: None,
                provenance: Provenance::Saga("PhotoThumbnailSaga".to_string()),
                series_id,
            })
            .await;
        map_version_only(result)?;

        // Dispatch the Medium variant generation command.
        let med_id = id;
        let med_cmd = GenerateVariant {
            id,
            variant: PhotoVariant::Medium,
            size_bytes: 0,
            series_id,
            version: AggregateVersion::INITIAL,
        };
        let result = PhotoAggregate::execute(&self.cmd_service, med_id, med_cmd)
            .expected_version(ExpectedVersion::Any)
            .metadata(EventMetadata {
                actor: None,
                provenance: Provenance::Saga("PhotoThumbnailSaga".to_string()),
                series_id,
            })
            .await;
        map_version_only(result)?;

        Ok(())
    }

    /// Decode the image bytes, read EXIF orientation, apply rotation,
    /// re-encode the original and generate thumb/medium variants.
    #[allow(clippy::type_complexity)]
    fn process_image(bytes: &[u8]) -> Result<(Vec<u8>, bool, Vec<u8>, Vec<u8>)> {
        let img = image::load_from_memory(bytes)
            .map_err(|e| anyhow::anyhow!("Failed to decode image: {e}"))?;

        // Read EXIF orientation and apply rotation.
        let (img, rotated) = {
            let mut cursor = std::io::Cursor::new(bytes);
            let exif_reader = exif::Reader::new();
            match exif_reader.read_from_container(&mut cursor) {
                Ok(exif) => {
                    let orientation = exif
                        .get_field(exif::Tag::Orientation, exif::In::PRIMARY)
                        .and_then(|f| f.value.get_uint(0))
                        .unwrap_or(1);
                    apply_orientation(img, orientation)
                }
                Err(_) => (img, false),
            }
        };

        // Re-encode the processed (possibly rotated) original as JPEG with quality ~95.
        let mut re_encoded = Vec::new();
        {
            let mut encoder =
                image::codecs::jpeg::JpegEncoder::new_with_quality(&mut re_encoded, 95);
            encoder
                .encode_image(&img)
                .map_err(|e| anyhow::anyhow!("Failed to re-encode original: {e}"))?;
        }

        // Generate thumbnail (~200×200).
        let thumb = img.thumbnail(200, 200);
        let mut thumb_bytes = Vec::new();
        {
            let mut encoder =
                image::codecs::jpeg::JpegEncoder::new_with_quality(&mut thumb_bytes, 80);
            encoder
                .encode_image(&thumb)
                .map_err(|e| anyhow::anyhow!("Failed to encode thumbnail: {e}"))?;
        }

        // Generate medium (~800×800).
        let medium = img.thumbnail(800, 800);
        let mut medium_bytes = Vec::new();
        {
            let mut encoder =
                image::codecs::jpeg::JpegEncoder::new_with_quality(&mut medium_bytes, 85);
            encoder
                .encode_image(&medium)
                .map_err(|e| anyhow::anyhow!("Failed to encode medium: {e}"))?;
        }

        Ok((re_encoded, rotated, thumb_bytes, medium_bytes))
    }
}

impl EventProcessor<(PhotoAggregate,), PhotoThumbnailSaga> for PhotoThumbnailSaga {
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

/// Spawn the thumbnail saga subscription loop (supervised, background).
///
/// Subscribes to the `photo` stream and processes `PhotoUploaded` events.
pub async fn spawn_photo_thumbnail_saga(
    cmd_service: CommandService,
    storage: OpenDalPhotoStorage,
    redis_client: Arc<RedisClient>,
) -> Result<()> {
    let saga = PhotoThumbnailSaga::new(cmd_service, storage);
    let _handle = supervisor::run_with_restart("photo_thumbnail_saga", move || {
        let mut saga = saga.clone();
        let client = redis_client.clone();
        async move {
            let mut manager = client.subscription_manager().await?;
            let mut stream =
                <(PhotoAggregate,)>::event_handler_stream(&mut manager, &mut saga).await?;
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

/// Apply EXIF orientation to an image, returning the (possibly rotated) image
/// and a boolean indicating whether rotation was applied.
fn apply_orientation(img: image::DynamicImage, orientation: u32) -> (image::DynamicImage, bool) {
    match orientation {
        3 => {
            // Rotated 180°
            (
                image::DynamicImage::from(image::imageops::rotate180(&img)),
                true,
            )
        }
        6 => {
            // Rotated 90° clockwise
            (
                image::DynamicImage::from(image::imageops::rotate90(&img)),
                true,
            )
        }
        8 => {
            // Rotated 270° clockwise
            (
                image::DynamicImage::from(image::imageops::rotate270(&img)),
                true,
            )
        }
        _ => (img, false), // 1 = normal, 2/4/5/7 = mirror-only (skipped in v1)
    }
}
