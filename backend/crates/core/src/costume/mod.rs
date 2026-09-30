// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)

//! Costume domain.

pub mod aggregate;
pub mod commands;
pub mod error;
pub mod events;
pub mod ports;
pub mod views;

pub use aggregate::CostumeAggregate;
pub use commands::{
    AddDetail, AssignCostumeToCharacter, CreateCostume, LinkPhoto, RemoveDetail,
    SetCostumeCategory, UnassignCostume, UnlinkPhoto, UpdateCostumeDetail, UpdateCostumeNotes,
};
pub use error::CostumeError;
pub use events::{CostumeDetail, CostumeEvent};
pub use ports::{CostumeCommands, CostumeRepository};
pub use views::{CostumeDetailView, CostumePhotoView, CostumeView};
