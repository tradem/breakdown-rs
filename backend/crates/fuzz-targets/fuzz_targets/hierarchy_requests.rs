// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Fuzz target for hierarchy creation request deserialization:
//! `CreateSeasonRequest`, `CreateBlockRequest`, `CreateEpisodeRequest`.
//!
//! Tests i32 (number) and Option<NaiveDate> fields for panic safety.

#![cfg_attr(fuzzing, no_main)]

/// Stub main for non-fuzzing builds (CI runs `--all-targets`).
#[cfg(not(fuzzing))]
fn main() {}

use libfuzzer_sys::fuzz_target;

use chrono::NaiveDate;
use serde::Deserialize;

use breakdown_core::shared::{BlockId, SeasonId, SeriesId};

/// Mirrors `breakdown_api::handlers::CreateSeasonRequest`.
#[derive(Debug, Deserialize)]
struct CreateSeasonRequest {
    series_id: SeriesId,
    number: i32,
    title: Option<String>,
}

/// Mirrors `breakdown_api::handlers::CreateBlockRequest`.
#[derive(Debug, Deserialize)]
struct CreateBlockRequest {
    season_id: SeasonId,
    series_id: SeriesId,
    number: i32,
    start_date: Option<NaiveDate>,
    end_date: Option<NaiveDate>,
}

/// Mirrors `breakdown_api::handlers::CreateEpisodeRequest`.
#[derive(Debug, Deserialize)]
struct CreateEpisodeRequest {
    block_id: BlockId,
    series_id: SeriesId,
    number: i32,
    name: Option<String>,
}

fuzz_target!(|data: &[u8]| {
    // ── Season ──────────────────────────────────────────────────────────
    if let Ok(req) = serde_json::from_slice::<CreateSeasonRequest>(data) {
        let _ = req.series_id.0;
        let _ = req.number;
        let _ = req.title.as_deref();

        let _cmd = breakdown_core::season::commands::CreateSeason {
            id: uuid::Uuid::now_v7(),
            series_id: req.series_id,
            number: req.number,
            title: req.title,
        };
    }

    // ── Block ───────────────────────────────────────────────────────────
    if let Ok(req) = serde_json::from_slice::<CreateBlockRequest>(data) {
        let _ = req.season_id.0;
        let _ = req.series_id.0;
        let _ = req.number;
        let _ = req.start_date;
        let _ = req.end_date;

        let _cmd = breakdown_core::block::commands::CreateBlock {
            id: uuid::Uuid::now_v7(),
            season_id: req.season_id,
            series_id: req.series_id,
            number: req.number,
            start_date: req.start_date,
            end_date: req.end_date,
        };
    }

    // ── Episode ─────────────────────────────────────────────────────────
    if let Ok(req) = serde_json::from_slice::<CreateEpisodeRequest>(data) {
        let _ = req.block_id.0;
        let _ = req.series_id.0;
        let _ = req.number;
        let _ = req.name.as_deref();

        let _cmd = breakdown_core::episode::commands::CreateEpisode {
            id: uuid::Uuid::now_v7(),
            block_id: req.block_id,
            series_id: req.series_id,
            number: req.number,
            name: req.name,
        };
    }
});
