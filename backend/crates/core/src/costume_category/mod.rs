// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! CostumeCategory domain — a season-scoped, user-editable vocabulary of part
//! types (Oberteil, Schuhe, …) used to categorise `CostumeDetail`s.

pub mod aggregate;
pub mod commands;
pub mod error;
pub mod events;
pub mod ports;
pub mod views;

pub use events::CostumeCategoryEvent;
pub use ports::{CostumeCategoryCommands, CostumeCategoryRepository};
pub use views::CostumeCategoryView;
