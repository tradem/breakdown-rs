use serde::Deserialize;
use utoipa::ToSchema;

use crate::shared::{AggregateVersion, PhotoId, PhotoVariant};

/// Upload a new photo. The saga will later normalize the original and generate
/// variants.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UploadPhoto {
    pub id: PhotoId,
    pub content_type: String,
    pub size_bytes: u64,
}

/// Signal that the original has been re-encoded upright and EXIF-stripped.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct NormalizeOriginal {
    pub id: PhotoId,
    pub new_size: u64,
    pub rotated: bool,
    pub version: AggregateVersion,
}

/// Signal that a variant (Thumb or Medium) has been generated.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct GenerateVariant {
    pub id: PhotoId,
    pub variant: PhotoVariant,
    pub size_bytes: u64,
    pub version: AggregateVersion,
}

/// Signal that variant generation failed.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct MarkVariantFailed {
    pub id: PhotoId,
    pub variant: PhotoVariant,
    pub error: String,
    pub version: AggregateVersion,
}

/// Delete a photo (terminal — no further mutations allowed after this).
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct DeletePhoto {
    pub id: PhotoId,
    pub version: AggregateVersion,
}

impl kameo_es::CommandName for UploadPhoto {
    fn command_name() -> &'static str {
        "UploadPhoto"
    }
}
impl kameo_es::CommandName for NormalizeOriginal {
    fn command_name() -> &'static str {
        "NormalizeOriginal"
    }
}
impl kameo_es::CommandName for GenerateVariant {
    fn command_name() -> &'static str {
        "GenerateVariant"
    }
}
impl kameo_es::CommandName for MarkVariantFailed {
    fn command_name() -> &'static str {
        "MarkVariantFailed"
    }
}
impl kameo_es::CommandName for DeletePhoto {
    fn command_name() -> &'static str {
        "DeletePhoto"
    }
}
