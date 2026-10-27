// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Consolidated handler integration-test harness (issue #631).
//!
//! The case files share the single `common` test-support module declared
//! here; each case file imports it via `use crate::common;`. Linking happens
//! once for all of them instead of once per file (issue #631).

mod common;

#[path = "handler_authz.rs"]
mod handler_authz;

#[path = "handler_authz_batch2.rs"]
mod handler_authz_batch2;

#[path = "handler_character_appearances.rs"]
mod handler_character_appearances;

#[path = "handler_piece_category.rs"]
mod handler_piece_category;

#[path = "handler_piece_detail.rs"]
mod handler_piece_detail;

#[path = "handler_piece_repertoire.rs"]
mod handler_piece_repertoire;

#[path = "handler_piece_scope.rs"]
mod handler_piece_scope;

#[path = "handler_episode.rs"]
mod handler_episode;

#[path = "handler_membership.rs"]
mod handler_membership;

#[path = "handler_number_uniqueness.rs"]
mod handler_number_uniqueness;

#[path = "handler_ops.rs"]
mod handler_ops;

#[path = "handler_report.rs"]
mod handler_report;

#[path = "handler_scene.rs"]
mod handler_scene;

#[path = "handler_scene_outfit_beats.rs"]
mod handler_scene_outfit_beats;

#[path = "handler_season_archive.rs"]
mod handler_season_archive;

#[path = "handler_season_list.rs"]
mod handler_season_list;

#[path = "handler_season_membership.rs"]
mod handler_season_membership;

#[path = "handler_series_membership.rs"]
mod handler_series_membership;

#[path = "handler_shooting_day.rs"]
mod handler_shooting_day;

#[path = "handler_wrap_semantics.rs"]
mod handler_wrap_semantics;
