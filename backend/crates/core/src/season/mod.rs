// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Season domain — production-scope aggregate of the four-level hierarchy.

pub mod aggregate;
pub mod commands;
pub mod error;
pub mod events;
pub mod ports;
pub mod views;

pub use events::SeasonEvent;
pub use ports::{SeasonCommands, SeasonRepository};
pub use views::SeasonView;
