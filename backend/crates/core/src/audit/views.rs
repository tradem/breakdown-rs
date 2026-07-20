// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Read-model DTO for a single audit / journal entry.

use chrono::{DateTime, Utc};
use serde::Serialize;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::{BlockId, UserId};

/// One row of the audit journal: who (`actor`) did what (`event_type` on
/// `entity_type`/`entity_id`) when (`occurred_at`), with the event `payload`.
///
/// `series_id` is the tenant dimension prepared for per-`SeriesId` tenancy
/// (decision 9.2) and is `NULL` in v1. `payload` is the raw event serialized
/// as JSON (generic, so any context's events fit the same row).
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct AuditEntry {
    pub id: Uuid,
    pub entity_type: String,
    pub entity_id: String,
    pub event_type: String,
    pub block_id: Option<BlockId>,
    pub series_id: Option<Uuid>,
    pub actor: Option<UserId>,
    pub payload: serde_json::Value,
    pub occurred_at: DateTime<Utc>,
}
