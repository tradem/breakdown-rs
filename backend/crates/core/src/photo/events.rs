use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::shared::{AggregateVersion, PhotoId, PhotoVariant, VariantStatus};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum PhotoEvent {
    /// A photo has been uploaded. All three variants are initially `Pending`.
    PhotoUploaded {
        id: PhotoId,
        content_type: String,
        size_bytes: u64,
        /// Original is pending; Thumb and Medium are pending.
        variant_statuses: Vec<(PhotoVariant, VariantStatus)>,
        version: AggregateVersion,
    },
    /// The original has been re-encoded upright and EXIF-stripped.
    OriginalNormalized {
        id: PhotoId,
        /// Size of the re-encoded original.
        new_size: u64,
        /// Whether the image was rotated.
        rotated: bool,
        version: AggregateVersion,
    },
    /// A variant (Thumb or Medium) has been generated successfully.
    VariantGenerated {
        id: PhotoId,
        variant: PhotoVariant,
        size_bytes: u64,
        version: AggregateVersion,
    },
    /// A variant generation has failed.
    VariantFailed {
        id: PhotoId,
        variant: PhotoVariant,
        error: String,
        version: AggregateVersion,
    },
    /// The photo has been deleted (terminal event).
    PhotoDeleted {
        id: PhotoId,
        version: AggregateVersion,
    },
}

impl kameo_es::EventType for PhotoEvent {
    fn event_type(&self) -> &'static str {
        match self {
            Self::PhotoUploaded { .. } => "PhotoUploaded",
            Self::OriginalNormalized { .. } => "OriginalNormalized",
            Self::VariantGenerated { .. } => "VariantGenerated",
            Self::VariantFailed { .. } => "VariantFailed",
            Self::PhotoDeleted { .. } => "PhotoDeleted",
        }
    }
}
