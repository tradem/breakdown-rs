// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! `SceneShoot` aggregate — models the association between a `Scene` and a
//! `ShootingDay`, carrying both planned (Dispo / Soll) and actual (Ist)
//! execution data.
//!
//! Each `(scene_id, shooting_day_id)` pair has its own event-sourced stream.
//! A reshoot of the same scene on a different day is a *new* pair (new
//! `SceneShoot` stream); the prior stream is not amended.

pub mod aggregate;
pub mod commands;
pub mod error;
pub mod events;
pub mod ports;
pub mod views;

pub use commands::{
    AddSceneShootNote, LinkContinuityPhoto, PlanSceneShoot, RemoveSceneShootNote,
    ReplanSceneShoot, SetActualOrder, SkipSceneShoot, StartSceneShoot, UnlinkContinuityPhoto,
    UpdateSceneShootNote, FinishSceneShoot,
};
pub use error::SceneShootError;
pub use events::{SceneShootEvent, SceneShootNote};
pub use ports::{SceneShootCommands, SceneShootReportRepository, SceneShootRepository};
pub use views::SceneShootView;
