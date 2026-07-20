// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! `ShootingDay` aggregate – an Episode-scoped scheduling unit (a Drehtag).
//!
//! A `ShootingDay` is its own event-sourced aggregate. It owns its ordering
//! (`order_key: LexicalSortKey`), an optional calendar `date`, and import
//! `source` provenance. Cross-aggregate references to it (from `Scene`) are
//! soft-archived rather than hard-deleted.

pub mod aggregate;
pub mod commands;
pub mod error;
pub mod events;
pub mod ports;
pub mod views;

pub use commands::{ArchiveShootingDay, CreateShootingDay, ReorderShootingDay, RenameShootingDay, RescheduleShootingDay};
pub use error::ShootingDayError;
pub use events::{ShootingDayEvent, ShootingDaySource};
pub use ports::{ShootingDayCommands, ShootingDayRepository};
pub use views::ShootingDayView;
