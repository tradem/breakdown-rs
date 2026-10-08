// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Flat read-model DTOs for the Season context.

use chrono::{DateTime, Utc};
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{AggregateVersion, ProjectId};

/// Complete season read model.
///
/// `updated_at` is sourced from the timestamp of the last applied `SeasonEvent`.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct SeasonView {
    pub id: Uuid,
    /// The tenant-level production container this season belongs to (`project_id`
    /// on the wire, issue #599).
    pub project_id: ProjectId,
    pub number: i32,
    pub title: Option<String>,
    /// Terminal lifecycle flag (issue #533): `true` once `SeasonArchived` was
    /// applied. Archived seasons keep number + inventory readable.
    pub archived: bool,
    /// Aggregate version for optimistic-locking round-trips.
    pub version: AggregateVersion,
    pub updated_at: DateTime<Utc>,
}
