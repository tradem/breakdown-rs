// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.6-35b (neuralwatt)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: glm-5.2 (neuralwatt)
// Co-authored-by: longcat-2.0 (opencode-go)

use std::collections::HashMap;
use std::sync::Arc;

use anyhow::Result;
use breakdown_core::photo::aggregate::PhotoAggregate;
use breakdown_core::photo::commands::{GenerateVariant, NormalizeOriginal};
use breakdown_core::photo::events::PhotoEvent;
use breakdown_core::photo::ports::PhotoStorage;
use breakdown_core::shared::{
    AggregateVersion, EventMetadata, PhotoId, PhotoVariant, Provenance, SeriesId, VariantStatus,
};
use kameo_es::command_service::CommandService;
use kameo_es::command_service::ExecuteExt;
use kameo_es::command_service::ExecuteResult;
use kameo_es::error::ExecuteError;
use kameo_es::event_handler::EventHandlerStreamBuilder;
use kameo_es::event_handler::{EntityEventHandler, EventHandler};
use kameo_es::event_handler::{EventHandlerError, EventProcessor};
use kameo_es::{Apply, Entity, Event, Metadata, StreamId};
use redis::Client as RedisClient;
use sierradb_client::AsyncCommands;
use sierradb_client::ExpectedVersion;
use sierradb_client::SierraAsyncClientExt;

use crate::photo::sagas::retry_transient;
use crate::photo::storage::OpenDalPhotoStorage;
use crate::projectors::supervisor;

/// Saga that reacts to `PhotoUploaded` events: fetches original bytes from
/// storage, decodes them, applies EXIF orientation correction, re-encodes
/// the original upright and EXIF-stripped, generates thumbnail and medium
/// variants, and dispatches the corresponding commands directly via
/// `PhotoAggregate::execute` with `Provenance::Saga`.
///
/// Redelivery safety (issue #515): `NormalizeOriginal` / `GenerateVariant`
/// are idempotent at the aggregate — re-running them when the original/variant
/// is already `Ready` is a no-op. The `version` passed in each command and
/// `ExpectedVersion::Any` are advisory; the aggregate derives the event
/// version from its own state, so replaying `PhotoUploaded` after the
/// aggregate has advanced converges instead of version-conflicting.
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

    /// Rebuild the photo aggregate's current state from the event store.
    ///
    /// Read-side sagas must not consult a read-model projection (CQRS
    /// boundary); the photo event stream is the write-side source of truth.
    /// Used only to short-circuit redelivery so a completed photo is never
    /// re-encoded / re-stored lossily (issue #515). A stream with no events
    /// yields the default (empty) aggregate state, which no caller treats as
    /// complete.
    async fn current_photo_state(&self, id: PhotoId) -> Result<PhotoAggregate> {
        let stream_id = StreamId::new_from_parts(PhotoAggregate::category(), id).to_string();
        let mut conn = self.cmd_service.conn();
        let mut state = PhotoAggregate::default();
        let mut from_version = 0u64;
        loop {
            let batch: sierradb_client::EventBatch = conn
                .escan(&stream_id, from_version, None, Some(1_000))
                .await
                .map_err(|e| anyhow::anyhow!("escan photo stream {stream_id}: {e}"))?;
            for event in &batch.events {
                let photo_event: PhotoEvent = ciborium::from_reader(event.payload.as_slice())
                    .map_err(|e| anyhow::anyhow!("deserialize photo stream {stream_id}: {e}"))?;
                state.apply(photo_event, Metadata::default());
                from_version = event.stream_version + 1;
            }
            if !batch.has_more {
                break;
            }
        }
        Ok(state)
    }

    async fn process_upload(&self, id: PhotoId, series_id: Option<SeriesId>) -> Result<()> {
        // Redelivery guard (issue #515): read the aggregate's current state
        // from the event store (the write-side source of truth — never a
        // read-model projection) and only redo work that is still missing.
        // A fully processed, or already deleted, photo is a complete no-op:
        // re-encoding an already-encoded original would add another lossy JPEG
        // generation and degrade the persisted bytes on every redelivery.
        let state = self.current_photo_state(id).await?;
        if state.deleted_at.is_some() {
            return Ok(());
        }
        let complete = state.variants.len() == 3
            && state
                .variants
                .iter()
                .all(|v| v.status == VariantStatus::Ready);
        if complete {
            return Ok(());
        }
        let original_ready = variant_ready(&state, PhotoVariant::Original);
        let thumb_ready = variant_ready(&state, PhotoVariant::Thumb);
        let medium_ready = variant_ready(&state, PhotoVariant::Medium);

        // Fetch the original bytes from storage.
        let photo_bytes = self.storage.fetch(id, PhotoVariant::Original).await?;

        // Decode the image, read EXIF orientation, and re-encode.
        let (re_encoded, rotated, thumb_bytes, medium_bytes) =
            Self::process_image(&photo_bytes.bytes)?;
        // Variant byte sizes are passed through to `GenerateVariant` so the
        // read model reports real sizes.
        let thumb_size = thumb_bytes.len() as u64;
        let medium_size = medium_bytes.len() as u64;

        // Overwrite the original with the EXIF-stripped, re-encoded version —
        // but only when it is not already the normalized original, so a
        // partial redelivery never runs a second lossy generation on it.
        if !original_ready {
            self.storage
                .store(
                    id,
                    PhotoVariant::Original,
                    re_encoded,
                    photo_bytes.content_type.clone(),
                )
                .await?;
        }

        // Store only the variants that are still missing.
        if !thumb_ready {
            self.storage
                .store(
                    id,
                    PhotoVariant::Thumb,
                    thumb_bytes,
                    "image/jpeg".to_string(),
                )
                .await?;
        }
        if !medium_ready {
            self.storage
                .store(
                    id,
                    PhotoVariant::Medium,
                    medium_bytes,
                    "image/jpeg".to_string(),
                )
                .await?;
        }

        // Dispatch the normalization command via Aggregate::execute. The
        // command is idempotent (no-op when the original is already Ready),
        // so a redelivery after the aggregate has advanced is safe; the
        // `version` field is advisory for this saga-provenance command.
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
        Self::map_saga_execute(result)?;

        // Dispatch the Thumb variant generation command. Idempotent at the
        // aggregate (no-op when the variant is already Ready) — see issue #515.
        let thumb_id = id;
        let thumb_cmd = GenerateVariant {
            id,
            variant: PhotoVariant::Thumb,
            size_bytes: thumb_size,
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
        Self::map_saga_execute(result)?;

        // Dispatch the Medium variant generation command. Idempotent at the
        // aggregate (no-op when the variant is already Ready) — see issue #515.
        let med_id = id;
        let med_cmd = GenerateVariant {
            id,
            variant: PhotoVariant::Medium,
            size_bytes: medium_size,
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
        Self::map_saga_execute(result)?;

        Ok(())
    }

    /// Map a saga `execute` result, treating the idempotent no-op as success.
    ///
    /// The saga commands (`NormalizeOriginal`/`GenerateVariant`) are
    /// idempotent at the aggregate (issue #515): on redelivery, once the work
    /// is already done, `Command::handle` returns no events and the command
    /// service reports `Executed(vec![])`. That empty outcome is success for a
    /// redelivering saga — unlike the API command adapters (`map_version_only`
    /// rejects empty event lists), producing no events is not an error here.
    /// Real failures (domain `Handle` errors, store write conflicts) still
    /// propagate.
    fn map_saga_execute<Ent, Err>(
        result: Result<ExecuteResult<Ent>, ExecuteError<Err>>,
    ) -> Result<(), anyhow::Error>
    where
        Ent: kameo_es::Entity + kameo_es::Apply + std::fmt::Debug + Send + Sync + 'static,
        Err: std::fmt::Debug,
    {
        match result {
            Ok(_) => Ok(()),
            Err(err) => Err(anyhow::anyhow!("{err}")),
        }
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

/// Whether a variant of a photo aggregate state is already `Ready`.
fn variant_ready(state: &PhotoAggregate, kind: PhotoVariant) -> bool {
    state
        .variants
        .iter()
        .any(|v| v.kind == kind && v.status == VariantStatus::Ready)
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

#[cfg(test)]
mod tests {
    // Test code lifts the workspace clippy panics/unwrap lints via
    // `#![cfg_attr(test, allow(...))]` in `crates/infra/src/lib.rs`.

    use image::DynamicImage;

    use super::*;

    /// Encode a `DynamicImage` as a JPEG with quality 95 (mirrors production).
    fn encode_jpeg(img: &DynamicImage) -> Vec<u8> {
        let mut buf = Vec::new();
        let mut encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut buf, 95);
        encoder.encode_image(img).expect("test fixture jpeg encode");
        buf
    }

    /// Kill the 12 `process_image -> Ok((vec![], ...))` mutants: the real
    /// function returns valid, non-empty JPEGs whose decoded dimensions
    /// respect the 200×200 (thumb) and 800×800 (medium) bounds. The mutant
    /// returns empty or 1-byte vecs that fail to decode.
    #[test]
    fn process_image_returns_valid_variant_jpegs_with_bounded_dimensions() {
        // 1000×800 source → thumb must fit 200×200, medium must fit 800×800.
        let src = DynamicImage::new_rgb8(1000, 800);
        let bytes = encode_jpeg(&src);

        let (re_encoded, rotated, thumb_bytes, medium_bytes) =
            PhotoThumbnailSaga::process_image(&bytes).expect("process_image");

        // Re-encoded original is a valid JPEG preserving dimensions.
        assert!(!re_encoded.is_empty());
        assert!(!rotated, "no EXIF orientation in a bare RGB buffer");
        let re = image::load_from_memory(&re_encoded).expect("re_encoded decodes");
        assert_eq!(re.width(), 1000);
        assert_eq!(re.height(), 800);

        // Thumbnail fits within 200×200.
        assert!(!thumb_bytes.is_empty());
        let thumb = image::load_from_memory(&thumb_bytes).expect("thumb decodes");
        assert!(thumb.width() <= 200, "thumb width {}", thumb.width());
        assert!(thumb.height() <= 200, "thumb height {}", thumb.height());

        // Medium fits within 800×800.
        assert!(!medium_bytes.is_empty());
        let medium = image::load_from_memory(&medium_bytes).expect("medium decodes");
        assert!(medium.width() <= 800, "medium width {}", medium.width());
        assert!(medium.height() <= 800, "medium height {}", medium.height());
    }

    /// A 1×1 source image still yields decodable, non-empty variants — kills
    /// the `Ok((vec![], ...))` mutants that return empty bodies even for tiny
    /// inputs.
    #[test]
    fn process_image_handles_tiny_source() {
        let src = DynamicImage::new_rgb8(1, 1);
        let bytes = encode_jpeg(&src);

        let (re_encoded, _rotated, thumb_bytes, medium_bytes) =
            PhotoThumbnailSaga::process_image(&bytes).expect("process_image");

        assert!(!re_encoded.is_empty());
        assert!(!thumb_bytes.is_empty());
        assert!(!medium_bytes.is_empty());
        // All three must still decode as valid JPEGs.
        image::load_from_memory(&re_encoded).expect("re_encoded decodes");
        image::load_from_memory(&thumb_bytes).expect("thumb decodes");
        image::load_from_memory(&medium_bytes).expect("medium decodes");
    }
}
