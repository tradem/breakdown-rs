// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! `PhotoBinding` discriminator for the Photo aggregate.
//!
//! Distinguishes piece/outfit Anprobe photos (taken before the shoot for planning)
//! from continuity/Anschluss photos (taken during the shoot to document actual
//! states). The binding is carried on the `PhotoUploaded` event and on
//! `PhotoView`.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::SceneShootId;

/// Discriminates what a photo is attached to.
///
/// `Piece` — a single fundus garment's Anprobe/planning photo.
/// `Outfit` — a fitting photo of a composed look (also surfaced on every piece
/// of the outfit, see the `piece-fundus` capability).
/// `Continuity` — continuity photo taken during the shoot; `piece_id` is
/// `Option` so prop-only continuity shots are permitted (the edge case).
///
/// The `Default` implementation returns `Piece { piece_id: Uuid::nil() }` so
/// that historical `PhotoUploaded` events (pre-binding) deserialise as garment
/// photos, matching the backward-compat requirement.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum PhotoBinding {
    /// Piece (Anprobe) photo — one garment, taken before the shoot.
    Piece { piece_id: Uuid },
    /// Outfit (Anprobe) photo — a composed look, taken before the shoot.
    Outfit { outfit_id: Uuid },
    /// Continuity (Anschluss) photo — taken during the shoot.
    Continuity {
        scene_shoot_id: SceneShootId,
        #[serde(default)]
        piece_id: Option<Uuid>,
    },
}

impl Default for PhotoBinding {
    fn default() -> Self {
        Self::Piece {
            piece_id: Uuid::default(),
        }
    }
}
