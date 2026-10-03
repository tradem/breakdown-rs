// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

//! Scene costume beats: the ordered per-(scene, character) casting relation.
//!
//! A scene is a unit interval of story time; the costume of a character within
//! it is a function of that interval — expressed as a dense, zero-based,
//! per-character `order` that supports the `on change` device (more than one
//! costume of one character in one scene). See OpenSpec change
//! `546-scene-costume-assignment`.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// One costume state of one character within one scene.
///
/// `order` is dense, zero-based and unique per character within the scene;
/// it is computed by the aggregate (`max + 1`), never client-supplied on the
/// add path. Reordering happens as remove + add, which keeps the event
/// history legible.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
pub struct SceneCostumeBeat {
    pub character_id: Uuid,
    pub costume_id: Uuid,
    /// Dense, zero-based, unique per character within this scene.
    pub order: u32,
    /// Optional free-text cue for the wardrobe crew ("nach dem Telefonat").
    pub note: Option<String>,
}
