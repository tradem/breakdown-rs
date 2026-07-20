// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Episode domain — the work-unit scope for Scenes.

pub mod aggregate;
pub mod commands;
pub mod error;
pub mod events;
pub mod ports;
pub mod views;

pub use events::EpisodeEvent;
pub use ports::{EpisodeCommands, EpisodeRepository};
pub use views::EpisodeView;
