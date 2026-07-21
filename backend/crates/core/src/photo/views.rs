use chrono::{DateTime, Utc};
use serde::Serialize;
use utoipa::ToSchema;

use crate::shared::{AggregateVersion, PhotoId, PhotoVariant, VariantStatus};

/// A single variant's public view.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct PhotoVariantView {
    pub kind: PhotoVariant,
    pub status: VariantStatus,
    pub size_bytes: u64,
}

/// Complete photo read model, populated by the projector.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct PhotoView {
    pub id: PhotoId,
    pub content_type: String,
    pub size_bytes: u64,
    pub variants: Vec<PhotoVariantView>,
    pub exif_stripped_at: Option<DateTime<Utc>>,
    pub version: AggregateVersion,
}

/// Metadata about an uploaded photo (used at upload time).
#[derive(Debug, Clone)]
pub struct PhotoMetadata {
    pub content_type: String,
    pub size_bytes: u64,
}

/// Bytes retrieved from storage, with associated metadata.
#[derive(Debug, Clone)]
pub struct PhotoBytes {
    pub bytes: Vec<u8>,
    pub content_type: String,
    pub size_bytes: u64,
    /// Optional ETag from the storage backend.
    pub etag: Option<String>,
}

/// Configuration for the periodic orphan-GC sweep.
#[derive(Debug, Clone)]
pub struct PhotoGcConfig {
    /// Whether the GC sweep is enabled at all.
    pub enabled: bool,
    /// Interval between sweep runs (seconds).
    pub interval_secs: u64,
    /// Only delete orphans older than this (seconds).
    pub max_age_secs: u64,
    /// Maximum number of orphans to process per run.
    pub batch_size: u64,
    /// When true, log orphans but do not delete.
    pub dry_run: bool,
}
