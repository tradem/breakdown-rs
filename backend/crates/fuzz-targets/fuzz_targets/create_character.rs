// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Fuzz target for `CreateCharacterRequest` deserialization.
//!
//! Tests that arbitrary byte sequences fed as JSON never cause a panic and
//! that the `CharacterCategory` enum round-trips safely.

#![cfg_attr(fuzzing, no_main)]

use libfuzzer_sys::fuzz_target;

use serde::Deserialize;
use uuid::Uuid;

use breakdown_core::character::category::CharacterCategory;
use breakdown_core::shared::SeasonId;

/// Mirrors `breakdown_api::handlers::CreateCharacterRequest`.
#[derive(Debug, Deserialize)]
struct CreateCharacterRequest {
    season_id: SeasonId,
    name: String,
    category: CharacterCategory,
}

fuzz_target!(|data: &[u8]| {
    // ── Path A: direct JSON deserialization ──────────────────────────
    // Must never panic for any byte sequence.
    let Ok(req) = serde_json::from_slice::<CreateCharacterRequest>(data) else {
        return;
    };

    // ── Path B: validate deserialized invariants ─────────────────────
    // - name can be any string (including empty) — no panic expected
    // - category is a round-tripped enum — check it's a valid value
    let _ = req.season_id.0;
    let _ = req.name.len();
    match req.category {
        CharacterCategory::MainCast
        | CharacterCategory::Guest
        | CharacterCategory::Extra => {}
    }

    // B1: construct the actual command (CreateCharacter has no measurements/contact_info fields)
    let _cmd = breakdown_core::character::commands::CreateCharacter {
        id: Uuid::now_v7(),
        season_id: req.season_id,
        name: req.name,
        category: req.category,
    };
});
