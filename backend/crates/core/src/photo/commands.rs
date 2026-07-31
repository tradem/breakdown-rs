// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Photo domain commands.

use super::binding::PhotoBinding;
use serde::Deserialize;
use utoipa::ToSchema;

use crate::shared::{AggregateVersion, PhotoId, PhotoVariant, SeriesId};

/// Upload a new photo. The saga will later normalize the original and generate
/// variants.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved at the API edge from the
/// photo's binding, never queried again by the command adapter.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UploadPhoto {
    pub id: PhotoId,
    pub content_type: String,
    pub size_bytes: u64,
    /// What this photo is attached to (Costume or Continuity).
    /// Defaults to `Costume` for backward compat.
    #[serde(default)]
    pub binding: PhotoBinding,
    pub series_id: Option<SeriesId>,
}

/// Signal that the original has been re-encoded upright and EXIF-stripped.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved by the dispatching saga,
/// never queried again by the command adapter.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct NormalizeOriginal {
    pub id: PhotoId,
    pub new_size: u64,
    pub rotated: bool,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Signal that a variant (Thumb or Medium) has been generated.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved by the dispatching saga,
/// never queried again by the command adapter.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct GenerateVariant {
    pub id: PhotoId,
    pub variant: PhotoVariant,
    pub size_bytes: u64,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Signal that variant generation failed.
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved by the dispatching saga,
/// never queried again by the command adapter.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct MarkVariantFailed {
    pub id: PhotoId,
    pub variant: PhotoVariant,
    pub error: String,
    pub series_id: Option<SeriesId>,
    pub version: AggregateVersion,
}

/// Delete a photo (terminal — no further mutations allowed after this).
///
/// `series_id` is carried for the `EventMetadata` audit trail (the audit
/// projector keys on `series_id`); it is resolved by the dispatching saga,
/// never queried again by the command adapter.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct DeletePhoto {
    pub id: PhotoId,
    pub series_id: Option<SeriesId>,
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
