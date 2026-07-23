// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Fuzz target for all `Update*` request bodies and `VersionRequest`.
//!
//! These structs carry `AggregateVersion` + variant-specific fields.
//! Tests that deserialization of any byte sequence never panics.

#![cfg_attr(fuzzing, no_main)]

/// Stub main for non-fuzzing builds (CI runs `--all-targets`).
#[cfg(not(fuzzing))]
fn main() {}

use libfuzzer_sys::fuzz_target;

use serde::Deserialize;

use breakdown_core::shared::{AggregateVersion, LexicalSortKey};

// ── Shared helpers ───────────────────────────────────────────────────────────

/// Mirrors `breakdown_api::handlers::VersionRequest`.
#[derive(Debug, Deserialize)]
struct VersionRequest {
    pub version: AggregateVersion,
}

// ── Scene updates ────────────────────────────────────────────────────────────

/// Mirrors `breakdown_api::handlers::UpdateSceneDetailsRequest`.
#[derive(Debug, Deserialize)]
struct UpdateSceneDetailsRequest {
    pub details: breakdown_core::scene::events::SceneDetails,
    pub version: AggregateVersion,
}

// ── Character updates ────────────────────────────────────────────────────────

/// Mirrors `breakdown_api::handlers::UpdateMeasurementsRequest`.
#[derive(Debug, Deserialize)]
struct UpdateMeasurementsRequest {
    pub measurements: breakdown_core::character::events::CharacterMeasurements,
    pub version: AggregateVersion,
}

/// Mirrors `breakdown_api::handlers::UpdateContactInfoRequest`.
#[derive(Debug, Deserialize)]
struct UpdateContactInfoRequest {
    pub contact_info: breakdown_core::character::events::ContactInfo,
    pub version: AggregateVersion,
}

// ── Costume updates ──────────────────────────────────────────────────────────

/// Mirrors `breakdown_api::handlers::UpdateCostumeNotesRequest`.
#[derive(Debug, Deserialize)]
struct UpdateCostumeNotesRequest {
    pub notes: String,
    pub version: AggregateVersion,
}

// ── Hierarchy updates ────────────────────────────────────────────────────────

/// Mirrors `breakdown_api::handlers::RenameSeasonRequest`.
#[derive(Debug, Deserialize)]
struct RenameSeasonRequest {
    pub title: Option<String>,
    pub version: AggregateVersion,
}

/// Mirrors `breakdown_api::handlers::RenameEpisodeRequest`.
#[derive(Debug, Deserialize)]
struct RenameEpisodeRequest {
    pub name: Option<String>,
    pub version: AggregateVersion,
}

/// Mirrors `breakdown_api::handlers::UpdateBlockTimeSpanRequest`.
#[derive(Debug, Deserialize)]
struct UpdateBlockTimeSpanRequest {
    pub start_date: Option<chrono::NaiveDate>,
    pub end_date: Option<chrono::NaiveDate>,
    pub version: AggregateVersion,
}

// ── Shooting Day updates ─────────────────────────────────────────────────────

/// Mirrors `breakdown_api::handlers::UpdateShootingDayRequest`.
#[derive(Debug, Deserialize)]
struct UpdateShootingDayRequest {
    pub version: AggregateVersion,
    pub label: Option<String>,
    pub date: Option<chrono::NaiveDate>,
    pub order_key: Option<LexicalSortKey>,
}

// ── Costume Category updates ─────────────────────────────────────────────────

/// Mirrors `breakdown_api::handlers::UpdateCostumeCategoryRequest`.
#[derive(Debug, Deserialize)]
struct UpdateCostumeCategoryRequest {
    pub version: AggregateVersion,
    pub name: Option<String>,
    pub order_key: Option<LexicalSortKey>,
}

/// Mirrors `breakdown_api::handlers::AddCostumeDetailRequest`.
#[derive(Debug, Deserialize)]
struct AddCostumeDetailRequest {
    pub detail: breakdown_core::costume::events::CostumeDetail,
    pub version: AggregateVersion,
}

// ── Assignment requests ──────────────────────────────────────────────────────

/// Mirrors `breakdown_api::handlers::AssignCharacterRequest`.
#[derive(Debug, Deserialize)]
struct AssignCharacterRequest {
    pub character_id: uuid::Uuid,
    pub version: AggregateVersion,
}

/// Mirrors `breakdown_api::handlers::AssignCostumeRequest`.
#[derive(Debug, Deserialize)]
struct AssignCostumeRequest {
    pub character_id: uuid::Uuid,
    pub version: AggregateVersion,
}

/// Mirrors `breakdown_api::handlers::ScheduleSceneRequest`.
#[derive(Debug, Deserialize)]
struct ScheduleSceneRequest {
    pub shooting_day_id: breakdown_core::shared::ShootingDayId,
    pub version: AggregateVersion,
}

// ── Fuzz entry point ─────────────────────────────────────────────────────────

fuzz_target!(|data: &[u8]| {
    // VersionRequest (used in archive, unassign, remove-character)
    if let Ok(req) = serde_json::from_slice::<VersionRequest>(data) {
        let _ = req.version.0;
    }

    // Scene
    if let Ok(req) = serde_json::from_slice::<UpdateSceneDetailsRequest>(data) {
        let _ = req.details.scene_number;
        let _ = req.version.0;
    }

    // Character
    if let Ok(req) = serde_json::from_slice::<UpdateMeasurementsRequest>(data) {
        let _ = req.measurements.shoe_size;
        let _ = req.version.0;
    }
    if let Ok(req) = serde_json::from_slice::<UpdateContactInfoRequest>(data) {
        let _ = req.contact_info.phone;
        let _ = req.version.0;
    }

    // Costume
    if let Ok(req) = serde_json::from_slice::<UpdateCostumeNotesRequest>(data) {
        let _ = req.notes.len();
        let _ = req.version.0;
    }
    if let Ok(req) = serde_json::from_slice::<AddCostumeDetailRequest>(data) {
        let _ = req.detail.text.len();
        let _ = req.version.0;
    }

    // Hierarchy
    if let Ok(req) = serde_json::from_slice::<RenameSeasonRequest>(data) {
        let _ = req.title.as_deref();
        let _ = req.version.0;
    }
    if let Ok(req) = serde_json::from_slice::<RenameEpisodeRequest>(data) {
        let _ = req.name.as_deref();
        let _ = req.version.0;
    }
    if let Ok(req) = serde_json::from_slice::<UpdateBlockTimeSpanRequest>(data) {
        let _ = req.start_date;
        let _ = req.end_date;
        let _ = req.version.0;
    }

    // ShootingDay
    if let Ok(req) = serde_json::from_slice::<UpdateShootingDayRequest>(data) {
        let _ = req.label.as_deref();
        let _ = req.date;
        let _ = req.order_key.map(|k| k.0.len());
        let _ = req.version.0;
    }

    // CostumeCategory
    if let Ok(req) = serde_json::from_slice::<UpdateCostumeCategoryRequest>(data) {
        let _ = req.name.as_deref();
        let _ = req.order_key.map(|k| k.0.len());
        let _ = req.version.0;
    }

    // Assignments
    if let Ok(req) = serde_json::from_slice::<AssignCharacterRequest>(data) {
        let _ = req.character_id;
        let _ = req.version.0;
    }
    if let Ok(req) = serde_json::from_slice::<AssignCostumeRequest>(data) {
        let _ = req.character_id;
        let _ = req.version.0;
    }
    if let Ok(req) = serde_json::from_slice::<ScheduleSceneRequest>(data) {
        let _ = req.shooting_day_id.0;
        let _ = req.version.0;
    }
});
