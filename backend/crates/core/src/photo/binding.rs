// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kwaipilot/kat-coder-air-v2.5 (openrouter)

//! `PhotoBinding` discriminator for the Photo aggregate.
//!
//! Distinguishes costume/Anprobe photos (taken before the shoot for planning)
//! from continuity/Anschluss photos (taken during the shoot to document actual
//! states). The binding is carried on the `PhotoUploaded` event and on
//! `PhotoView`.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::shared::SceneShootId;

/// Discriminates what a photo is attached to.
///
/// `Costume` — Anprobe/planning photo (taken before the shoot).
/// `Continuity` — continuity photo taken during the shoot; `costume_id` is
/// `Option` so prop-only continuity shots are permitted (the edge case).
///
/// The `Default` implementation returns `Costume { costume_id: Uuid::nil() }`
/// so that historical `PhotoUploaded` events (pre-binding) deserialise as
/// costume photos, matching the backward-compat requirement.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum PhotoBinding {
    /// Costume (Anprobe) photo — taken before the shoot for planning.
    Costume { costume_id: Uuid },
    /// Continuity (Anschluss) photo — taken during the shoot.
    Continuity {
        scene_shoot_id: SceneShootId,
        #[serde(default)]
        costume_id: Option<Uuid>,
    },
}

impl Default for PhotoBinding {
    fn default() -> Self {
        Self::Costume {
            costume_id: Uuid::default(),
        }
    }
}
