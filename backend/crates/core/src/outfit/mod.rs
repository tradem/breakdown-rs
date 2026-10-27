// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Outfit domain — a character's composed look, built from `0..n` fundus
//! pieces. Scenes cast outfits (`SceneOutfitBeat`), never bare pieces.

pub mod aggregate;
pub mod commands;
pub mod error;
pub mod events;
pub mod ports;
pub mod views;

pub use aggregate::OutfitAggregate;
pub use commands::{
    AddPieceToOutfit, CreateOutfit, CreateOutfitVariant, LinkOutfitPhoto, RemovePieceFromOutfit,
    RenameOutfit, UnlinkOutfitPhoto, UpdateOutfitNotes,
};
pub use error::OutfitError;
pub use events::OutfitEvent;
pub use ports::{OutfitCommands, OutfitRepository};
pub use views::{OutfitPhotoView, OutfitPieceView, OutfitView};
