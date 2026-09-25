// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)
// Co-authored-by: longcat-2.0 (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

use chrono::{DateTime, Utc};
use kameo_es::{Apply, Command, Context, Entity, Metadata};

use crate::photo::binding::PhotoBinding;
use crate::shared::{AggregateVersion, EventMetadata, PhotoId, PhotoVariant, VariantStatus};

use super::commands::*;
use super::error::PhotoError;
use super::events::*;

/// A record of a single variant's generation state (internal aggregate state).
#[derive(Debug, Clone)]
pub struct PhotoVariantRecord {
    pub kind: PhotoVariant,
    pub status: VariantStatus,
    pub size_bytes: u64,
}

/// State of the Photo aggregate.
///
/// Tracks lifecycle: upload → normalisation → variant generation → deletion.
#[derive(Debug, Clone, Default)]
pub struct PhotoAggregate {
    pub id: PhotoId,
    pub content_type: String,
    pub size_bytes: u64,
    pub variants: Vec<PhotoVariantRecord>,
    /// When the EXIF-stripped original was stored, if normalization completed.
    pub exif_stripped_at: Option<DateTime<Utc>>,
    /// When the photo was soft-deleted. `None` means active.
    pub deleted_at: Option<DateTime<Utc>>,
    /// What this photo is attached to (Costume or Continuity).
    pub binding: PhotoBinding,
    pub version: AggregateVersion,
}

impl PhotoAggregate {
    fn check_not_deleted(&self) -> Result<(), PhotoError> {
        if self.deleted_at.is_some() {
            return Err(PhotoError::AlreadyDeleted);
        }
        Ok(())
    }

    fn check_version(&self, expected: AggregateVersion) -> Result<(), PhotoError> {
        if expected != self.version {
            return Err(PhotoError::VersionMismatch {
                expected,
                actual: self.version,
            });
        }
        Ok(())
    }
}

impl Entity for PhotoAggregate {
    type ID = PhotoId;
    type Event = PhotoEvent;
    type Metadata = EventMetadata;

    fn category() -> &'static str {
        "photo"
    }
}

impl Apply for PhotoAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<EventMetadata>) {
        match event {
            PhotoEvent::PhotoUploaded {
                id,
                content_type,
                size_bytes,
                variant_statuses,
                binding,
                version,
            } => {
                self.id = id;
                self.content_type = content_type;
                self.size_bytes = size_bytes;
                self.variants = variant_statuses
                    .into_iter()
                    .map(|(kind, status)| PhotoVariantRecord {
                        kind,
                        status,
                        size_bytes: 0,
                    })
                    .collect();
                self.binding = binding;
                self.version = version;
            }
            PhotoEvent::OriginalNormalized {
                new_size, version, ..
            } => {
                // Update the original variant's size
                if let Some(original) = self
                    .variants
                    .iter_mut()
                    .find(|v| v.kind == PhotoVariant::Original)
                {
                    original.size_bytes = new_size;
                    original.status = VariantStatus::Ready;
                }
                self.size_bytes = new_size;
                self.exif_stripped_at = Some(Utc::now());
                self.version = version;
            }
            PhotoEvent::VariantGenerated {
                variant,
                size_bytes,
                version,
                ..
            } => {
                if let Some(rec) = self.variants.iter_mut().find(|v| v.kind == variant) {
                    rec.status = VariantStatus::Ready;
                    rec.size_bytes = size_bytes;
                }
                self.version = version;
            }
            PhotoEvent::VariantFailed {
                variant, version, ..
            } => {
                if let Some(rec) = self.variants.iter_mut().find(|v| v.kind == variant) {
                    rec.status = VariantStatus::Failed;
                }
                self.version = version;
            }
            PhotoEvent::PhotoDeleted { version, .. } => {
                self.deleted_at = Some(Utc::now());
                self.version = version;
            }
        }
    }
}

impl Command<UploadPhoto> for PhotoAggregate {
    type Error = PhotoError;

    fn handle(
        &self,
        cmd: UploadPhoto,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        // If this is a new aggregate (initial state), any upload is valid.
        // If the aggregate already exists, it must be the initial replay.
        Ok(vec![PhotoEvent::PhotoUploaded {
            id: cmd.id,
            content_type: cmd.content_type,
            size_bytes: cmd.size_bytes,
            variant_statuses: vec![
                (PhotoVariant::Original, VariantStatus::Pending),
                (PhotoVariant::Thumb, VariantStatus::Pending),
                (PhotoVariant::Medium, VariantStatus::Pending),
            ],
            binding: cmd.binding,
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<NormalizeOriginal> for PhotoAggregate {
    type Error = PhotoError;

    fn handle(
        &self,
        cmd: NormalizeOriginal,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        self.check_not_deleted()?;
        // Idempotency for saga redelivery (issue #515): the thumbnail saga
        // may replay `PhotoUploaded` after the aggregate has already advanced,
        // so re-normalizing an already `Ready` original is a no-op rather than
        // a version conflict. The `cmd.version` field is advisory for this
        // saga-only command — the emitted event version is always derived from
        // the aggregate's own state (`self.version.next()`).
        if self
            .variants
            .iter()
            .any(|v| v.kind == PhotoVariant::Original && v.status == VariantStatus::Ready)
        {
            return Ok(vec![]);
        }
        Ok(vec![PhotoEvent::OriginalNormalized {
            id: self.id,
            new_size: cmd.new_size,
            rotated: cmd.rotated,
            version: self.version.next(),
        }])
    }
}

impl Command<GenerateVariant> for PhotoAggregate {
    type Error = PhotoError;

    fn handle(
        &self,
        cmd: GenerateVariant,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        self.check_not_deleted()?;
        // Idempotency for saga redelivery (issue #515): the thumbnail saga may
        // replay `PhotoUploaded` after the variant was already generated (the
        // aggregate has advanced past the caller's stale expected version), so
        // regenerating an already `Ready` variant is a no-op rather than an
        // error. The `cmd.version` field is advisory for this saga-only
        // command — the emitted event version is always derived from the
        // aggregate's own state (`self.version.next()`).
        if self
            .variants
            .iter()
            .any(|v| v.kind == cmd.variant && v.status == VariantStatus::Ready)
        {
            return Ok(vec![]);
        }
        Ok(vec![PhotoEvent::VariantGenerated {
            id: self.id,
            variant: cmd.variant,
            size_bytes: cmd.size_bytes,
            version: self.version.next(),
        }])
    }
}

impl Command<MarkVariantFailed> for PhotoAggregate {
    type Error = PhotoError;

    fn handle(
        &self,
        cmd: MarkVariantFailed,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        self.check_not_deleted()?;
        self.check_version(cmd.version)?;
        Ok(vec![PhotoEvent::VariantFailed {
            id: self.id,
            variant: cmd.variant,
            error: cmd.error,
            version: self.version.next(),
        }])
    }
}

impl Command<DeletePhoto> for PhotoAggregate {
    type Error = PhotoError;

    fn handle(
        &self,
        cmd: DeletePhoto,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        self.check_not_deleted()?;
        self.check_version(cmd.version)?;
        Ok(vec![PhotoEvent::PhotoDeleted {
            id: self.id,
            version: self.version.next(),
        }])
    }
}

#[cfg(test)]
mod tests {
    // Test code lifts the workspace clippy panics/unwrap lints via
    // `#![cfg_attr(test, allow(...))]` in `crates/core/src/lib.rs`.

    use std::borrow::Cow;
    use std::collections::{HashMap, HashSet};
    use std::sync::LazyLock;
    use std::time::Instant;

    use chrono::Utc;
    use kameo_es::{Command, Context, Metadata, StreamId};

    use super::*;
    use crate::shared::EventMetadata;

    type CausationTracking = HashMap<StreamId, (u64, HashSet<Cow<'static, str>>)>;

    /// Build a minimal `Context` for command-handle tests. Leaks a `Box`ed
    /// `Metadata` and uses a `LazyLock`'ed empty causation map so every field
    /// outlives `'static` (test-only).
    fn test_ctx() -> Context<'static, PhotoAggregate> {
        static TRACKING: LazyLock<CausationTracking> = LazyLock::new(HashMap::new);
        let metadata: &'static Metadata<EventMetadata> = Box::leak(Box::new(Metadata {
            data: None,
            ..Default::default()
        }));
        Context {
            metadata,
            causation_tracking: &TRACKING,
            time: Utc::now(),
            executed_at: Instant::now(),
        }
    }

    fn sample_photo() -> PhotoAggregate {
        PhotoAggregate {
            id: PhotoId::new(),
            content_type: "image/jpeg".to_string(),
            size_bytes: 1024,
            variants: vec![
                PhotoVariantRecord {
                    kind: PhotoVariant::Original,
                    status: VariantStatus::Ready,
                    size_bytes: 1024,
                },
                PhotoVariantRecord {
                    kind: PhotoVariant::Thumb,
                    status: VariantStatus::Pending,
                    size_bytes: 0,
                },
                PhotoVariantRecord {
                    kind: PhotoVariant::Medium,
                    status: VariantStatus::Pending,
                    size_bytes: 0,
                },
            ],
            exif_stripped_at: None,
            deleted_at: None,
            binding: PhotoBinding::Costume {
                costume_id: uuid::Uuid::now_v7(),
            },
            version: AggregateVersion::INITIAL,
        }
    }

    /// Kills `replace PhotoAggregate::check_not_deleted -> Result<(), PhotoError>
    /// with Ok(())`: a soft-deleted photo must reject a `DeletePhoto` command
    /// with `AlreadyDeleted`, not silently succeed.
    #[test]
    fn delete_photo_on_deleted_aggregate_is_rejected() {
        let mut photo = sample_photo();
        photo.deleted_at = Some(Utc::now());

        let cmd = DeletePhoto {
            id: photo.id,
            series_id: None,
            version: AggregateVersion::INITIAL,
        };

        let err = photo
            .handle(cmd, test_ctx())
            .expect_err("DeletePhoto on a deleted aggregate must fail with AlreadyDeleted");
        assert_eq!(err, PhotoError::AlreadyDeleted);
    }

    /// Kills `replace == with !=` in the `GenerateVariant` idempotency guard
    /// (issue #515): regenerating a variant that is *already* `Ready` must be
    /// a **no-op** (no duplicate event), not the inverse.
    #[test]
    fn generate_variant_is_idempotent_when_already_ready() {
        let photo = sample_photo();
        // Original is Ready in the sample — regenerating it must not emit.
        let cmd = GenerateVariant {
            id: photo.id,
            variant: PhotoVariant::Original,
            size_bytes: 0,
            series_id: None,
            version: AggregateVersion::INITIAL,
        };

        let events = photo
            .handle(cmd, test_ctx())
            .expect("Regenerating a Ready variant must not fail");
        assert!(
            events.is_empty(),
            "no duplicate event for an already-Ready variant"
        );
    }

    /// Kills `replace == with !=` in the `NormalizeOriginal` idempotency guard
    /// (issue #515): re-normalizing an already-normalized (`Ready`) original
    /// must be a **no-op**, not the inverse.
    #[test]
    fn normalize_original_is_idempotent_when_already_ready() {
        let photo = sample_photo();
        // Original is Ready in the sample — re-normalizing it must not emit.
        let cmd = NormalizeOriginal {
            id: photo.id,
            new_size: 2048,
            rotated: false,
            series_id: None,
            version: AggregateVersion::INITIAL,
        };

        let events = photo
            .handle(cmd, test_ctx())
            .expect("Re-normalizing a Ready original must not fail");
        assert!(
            events.is_empty(),
            "no duplicate event for an already-normalized original"
        );
    }

    /// Complements the above: generating a `Pending` variant succeeds and
    /// emits `VariantGenerated`, proving the guard distinguishes Ready from
    /// Pending (the `==`→`!=` mutant would invert this).
    #[test]
    fn generate_variant_succeeds_for_pending_variant() {
        let photo = sample_photo();
        let cmd = GenerateVariant {
            id: photo.id,
            variant: PhotoVariant::Thumb,
            size_bytes: 0,
            series_id: None,
            version: AggregateVersion::INITIAL,
        };

        let events = photo
            .handle(cmd, test_ctx())
            .expect("Generating a Pending variant must succeed");
        assert_eq!(events.len(), 1);
        assert!(matches!(
            events[0],
            PhotoEvent::VariantGenerated {
                variant: PhotoVariant::Thumb,
                ..
            }
        ));
    }
}
