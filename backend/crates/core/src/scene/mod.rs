// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Scene domain.

pub mod aggregate;
pub mod commands;
pub mod error;
pub mod events;
pub mod outfit;
pub mod ports;
pub mod views;

pub use aggregate::SceneAggregate;
pub use commands::{
    AddOutfitBeat, AssignCharacter, CreateScene, RemoveCharacter, RemoveOutfitBeat,
    ScheduleSceneOnShootingDay, UnscheduleSceneFromShootingDay, UpdateOutfitBeat,
    UpdateSceneDetails,
};
pub use error::SceneError;
pub use events::{SceneDetails, SceneEvent, SceneSource, default_scene_source};
pub use outfit::SceneOutfitBeat;
pub use ports::{SceneCommands, SceneRepository};
pub use views::{SceneOutfitBeatView, SceneView};
