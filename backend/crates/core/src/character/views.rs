// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Flat read-model DTOs for the Character context.

use chrono::{DateTime, Utc};
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, ProjectId};

use super::events::{CharacterMeasurements, ContactInfo};

/// Complete character read model.
///
/// `updated_at` is sourced from the timestamp of the last applied `CharacterEvent`.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct CharacterView {
    pub id: Uuid,
    pub project_id: ProjectId,
    pub name: String,
    pub is_extra: bool,
    pub is_main_character: bool,
    pub measurements: CharacterMeasurements,
    pub contact: ContactInfo,
    /// Aggregate version for optimistic-locking round-trips.
    pub version: AggregateVersion,
    pub updated_at: DateTime<Utc>,
}
