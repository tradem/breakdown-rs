use async_trait::async_trait;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, PhotoId, PhotoVariant};

use super::commands::{
    DeletePhoto, GenerateVariant, MarkVariantFailed, NormalizeOriginal, UploadPhoto,
};
use super::views::{PhotoBytes, PhotoView};

/// Byte-storage port for photo data (CRUD — intentionally NOT CQRS-split).
///
/// This is a side-effect store: events say bytes *should* exist; the sagas
/// enforce that by calling `store`/`delete_all`. The port is type-safe over
/// `PhotoId` + `PhotoVariant`; key layout is an infra-internal concern.
#[async_trait]
pub trait PhotoStorage: Send + Sync {
    /// Store bytes for a given photo variant. Overwrites existing bytes for
    /// the same (photo_id, variant) pair.
    async fn store(
        &self,
        id: PhotoId,
        variant: PhotoVariant,
        bytes: Vec<u8>,
        content_type: String,
    ) -> Result<(), DomainError>;

    /// Fetch bytes for a given photo variant. Returns `NotFound` if the
    /// object does not exist in storage.
    async fn fetch(&self, id: PhotoId, variant: PhotoVariant) -> Result<PhotoBytes, DomainError>;

    /// Delete all variants for a given photo. Idempotent — returns success
    /// even if some or all objects are already absent.
    async fn delete_all(&self, id: PhotoId) -> Result<(), DomainError>;

    /// List all photo_ids currently present in storage (for GC reconciliation).
    /// Returns a set of known ids; the adapter should deduplicate.
    async fn list(&self) -> Result<Vec<PhotoId>, DomainError>;
}

/// Write port for the `Photo` aggregate, dispatching commands via kameo_es.
#[async_trait]
pub trait PhotoCommands: Send + Sync {
    async fn upload(&self, cmd: UploadPhoto) -> Result<AggregateVersion, DomainError>;
    async fn normalize_original(
        &self,
        cmd: NormalizeOriginal,
    ) -> Result<AggregateVersion, DomainError>;
    async fn generate_variant(&self, cmd: GenerateVariant)
    -> Result<AggregateVersion, DomainError>;
    async fn mark_variant_failed(
        &self,
        cmd: MarkVariantFailed,
    ) -> Result<AggregateVersion, DomainError>;
    async fn delete(&self, cmd: DeletePhoto) -> Result<AggregateVersion, DomainError>;
}

/// Read port for the `Photo` aggregate projection.
#[async_trait]
pub trait PhotoRepository: Send + Sync {
    /// Find a photo by ID, returning the full `PhotoView` with variants.
    async fn find_by_id(&self, id: PhotoId) -> Result<PhotoView, DomainError>;

    /// List all known photo_ids from the projection (for GC reconciliation).
    async fn list_known_ids(&self) -> Result<Vec<PhotoId>, DomainError>;

    /// Count how many costume links reference this photo (refcount check).
    async fn count_links(&self, photo_id: PhotoId) -> Result<u64, DomainError>;
}
