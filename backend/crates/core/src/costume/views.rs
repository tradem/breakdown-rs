// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Flat read-model DTOs for the Costume context.

use chrono::{DateTime, Utc};
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::AggregateVersion;

/// Detailed costume element (e.g. belt, hat, shoes).
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct CostumeDetailView {
    pub id: Uuid,
    pub text: String,
}

/// Linked photo reference for a costume.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct CostumePhotoView {
    pub id: Uuid,
}

/// Complete costume read model, optionally populated with child details/photos.
///
/// `updated_at` is sourced from the timestamp of the last applied `CostumeEvent`.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct CostumeView {
    pub id: Uuid,
    pub character_id: Option<Uuid>,
    pub notes: String,
    pub details: Vec<CostumeDetailView>,
    pub photos: Vec<CostumePhotoView>,
    /// Aggregate version for optimistic-locking round-trips.
    pub version: AggregateVersion,
    pub updated_at: DateTime<Utc>,
}
