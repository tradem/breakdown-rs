// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Hexagonal ports for the Outfit context.

use uuid::Uuid;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, UserId};

use super::commands::{
    AddPieceToOutfit, CreateOutfit, CreateOutfitVariant, LinkOutfitPhoto, RemovePieceFromOutfit,
    RenameOutfit, UnlinkOutfitPhoto, UpdateOutfitNotes,
};
use super::views::OutfitView;

/// Async write port for the `OutfitAggregate`.
#[allow(async_fn_in_trait)]
pub trait OutfitCommands: Send + Sync {
    async fn create(
        &self,
        actor: UserId,
        cmd: CreateOutfit,
    ) -> Result<(Uuid, AggregateVersion), DomainError>;
    /// Create an independent copy-on-write variant. The source outfit is
    /// resolved at the API edge and carried in the command — the adapter never
    /// reads the source stream or projection (CQRS boundary).
    async fn create_variant(
        &self,
        actor: UserId,
        cmd: CreateOutfitVariant,
    ) -> Result<(Uuid, AggregateVersion), DomainError>;
    async fn rename(
        &self,
        actor: UserId,
        cmd: RenameOutfit,
    ) -> Result<AggregateVersion, DomainError>;
    async fn update_notes(
        &self,
        actor: UserId,
        cmd: UpdateOutfitNotes,
    ) -> Result<AggregateVersion, DomainError>;
    async fn add_piece(
        &self,
        actor: UserId,
        cmd: AddPieceToOutfit,
    ) -> Result<AggregateVersion, DomainError>;
    async fn remove_piece(
        &self,
        actor: UserId,
        cmd: RemovePieceFromOutfit,
    ) -> Result<AggregateVersion, DomainError>;
    async fn link_photo(
        &self,
        actor: UserId,
        cmd: LinkOutfitPhoto,
    ) -> Result<AggregateVersion, DomainError>;
    async fn unlink_photo(
        &self,
        actor: UserId,
        cmd: UnlinkOutfitPhoto,
    ) -> Result<AggregateVersion, DomainError>;
}

/// Async read port returning flat `OutfitView` projections.
#[allow(async_fn_in_trait)]
pub trait OutfitRepository: Send + Sync {
    async fn find_by_id(&self, id: Uuid) -> Result<OutfitView, DomainError>;
    async fn list_by_character(&self, character_id: Uuid) -> Result<Vec<OutfitView>, DomainError>;
}
