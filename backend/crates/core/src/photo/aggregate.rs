use chrono::{DateTime, Utc};
use kameo_es::{Apply, Command, Context, Entity, Metadata};

use crate::shared::{AggregateVersion, PhotoId, PhotoVariant, VariantStatus};

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
    type Metadata = ();

    fn category() -> &'static str {
        "photo"
    }
}

impl Apply for PhotoAggregate {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<()>) {
        match event {
            PhotoEvent::PhotoUploaded {
                id,
                content_type,
                size_bytes,
                variant_statuses,
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
        self.check_version(cmd.version)?;
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
        self.check_version(cmd.version)?;
        if self
            .variants
            .iter()
            .any(|v| v.kind == cmd.variant && v.status == VariantStatus::Ready)
        {
            return Err(PhotoError::ValidationError(format!(
                "Variant {:?} is already ready",
                cmd.variant
            )));
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
#[path = "aggregate_test.rs"]
mod tests;
