// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Character category — replaces the legacy `is_main_character` / `is_extra` bool pair.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

/// Exhaustive category for a Character.
///
/// Designed for **purely additive extension**: a new variant can be appended
/// later without breaking deserialization of already-persisted data (existing
/// rows only ever contain the original variants). Removing or renaming a variant
/// is a *breaking* change and requires a separate proposal.
///
/// The single enum makes illegal states unrepresentable — there is no
/// `(is_main_character = true, is_extra = true)` combination.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum CharacterCategory {
    /// Season-long principal role (persists across the whole season).
    #[default]
    MainCast,
    /// Single-Episode guest role.
    Guest,
    /// Background performer (Komparse).
    Extra,
}
