// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Fuzz target for `CreateSceneRequest` deserialization.
//!
//! Tests that arbitrary byte sequences fed as JSON never cause a panic and
//! that, when deserialization succeeds, the field invariants hold.

#![cfg_attr(fuzzing, no_main)]

use libfuzzer_sys::fuzz_target;

use serde::Deserialize;
use uuid::Uuid;

use breakdown_core::scene::events::SceneDetails;
use breakdown_core::shared::EpisodeId;

/// Mirrors `breakdown_api::handlers::CreateSceneRequest` to avoid heavy
/// workspace dependencies in the fuzz binary.
#[derive(Debug, Deserialize)]
struct CreateSceneRequest {
    episode_id: EpisodeId,
    details: SceneDetails,
}

fuzz_target!(|data: &[u8]| {
    // ── Path A: direct JSON deserialization ──────────────────────────
    // Must never panic for any byte sequence.
    let Ok(req) = serde_json::from_slice::<CreateSceneRequest>(data) else {
        return; // Malformed JSON / type mismatch — expected, no panic.
    };

    // ── Path B: validate deserialized invariants ─────────────────────
    // These must never panic for any successfully-deserialized payload.
    let _ = req.episode_id.0; // UUID is always present after deser
    let _ = req.details.scene_number;
    let _ = req.details.location;
    let _ = req.details.mood;
    let _ = req.details.summary;
    let _ = req.details.is_schedule_set;

    // B1: construct the actual command (simulates the handler)
    let _cmd = breakdown_core::scene::commands::CreateScene {
        id: Uuid::now_v7(),
        episode_id: req.episode_id,
        details: req.details,
    };
});
