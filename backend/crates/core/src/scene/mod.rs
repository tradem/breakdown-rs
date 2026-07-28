// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Scene domain.

pub mod aggregate;
pub mod commands;
pub mod error;
pub mod events;
pub mod ports;
pub mod views;

pub use aggregate::SceneAggregate;
pub use commands::{
    AssignCharacter, CreateScene, RemoveCharacter, ScheduleSceneOnShootingDay,
    UnscheduleSceneFromShootingDay, UpdateSceneDetails,
};
pub use error::SceneError;
pub use events::{SceneDetails, SceneEvent};
pub use ports::{SceneCommands, SceneRepository};
pub use views::SceneView;
