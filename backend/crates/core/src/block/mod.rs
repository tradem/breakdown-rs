// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Block domain — groups Episodes; rotation boundary for costume-department staff.

pub mod aggregate;
pub mod commands;
pub mod error;
pub mod events;
pub mod ports;
pub mod views;

pub use events::BlockEvent;
pub use ports::{BlockCommands, BlockRepository};
pub use views::BlockView;
