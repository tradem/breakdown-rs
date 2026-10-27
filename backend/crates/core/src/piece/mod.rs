// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Piece domain — the wardrobe **fundus** (one garment per aggregate).
//!
//! Characters do not own pieces; they wear `Outfit`s (`crate::outfit`) that
//! compose `0..n` pieces. Scenes cast outfits (`SceneOutfitBeat`).

pub mod aggregate;
pub mod commands;
pub mod error;
pub mod events;
pub mod ports;
pub mod views;

pub use aggregate::PieceAggregate;
pub use commands::{
    AddPieceDetail, AddPieceToSeason, CreatePiece, LinkPiecePhoto, RemovePieceDetail,
    RemovePieceFromSeason, RenamePiece, SetPieceCategory, UnlinkPiecePhoto, UpdatePieceDetail,
    UpdatePieceNotes,
};
pub use error::PieceError;
pub use events::{PieceDetail, PieceEvent};
pub use ports::{PieceCommands, PieceRepository};
pub use views::{PieceDetailView, PiecePhotoView, PieceView};
