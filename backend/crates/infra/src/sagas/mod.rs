// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Event-reactor sagas — subscribers that issue commands in reaction to events.

pub mod season_seeding;

pub use season_seeding::{
    SeasonSeedingSaga, load_default_costume_categories, spawn_season_seeding_saga,
};
