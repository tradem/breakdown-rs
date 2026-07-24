// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: kwaipilot/kat-coder-air-v2.5 (openrouter)

pub mod audit;
pub mod block;
pub mod character;
pub mod costume;
pub mod costume_category;
pub mod episode;
pub mod error;
pub mod membership;
pub mod photo;
pub mod scene;
pub mod scene_shoot;
pub mod season;
pub mod shared;
pub mod shooting_day;

/// Re-export photo shared types for use by infra and api layers.
pub use shared::{PhotoId, PhotoVariant, SceneShootId, SceneShootStatus, VariantStatus};

#[cfg(test)]
mod proptest;
