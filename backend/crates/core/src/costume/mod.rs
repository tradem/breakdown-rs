// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! Costume domain.

pub mod aggregate;
pub mod commands;
pub mod error;
pub mod events;
pub mod ports;
pub mod views;

pub use events::CostumeDetail;
pub use ports::{CostumeCommands, CostumeRepository};
pub use views::{CostumeDetailView, CostumePhotoView, CostumeView};
