// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Hexagonal ports for the Piece (fundus) context.

use uuid::Uuid;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, SeasonId, UserId};

use super::commands::{
    AddPieceDetail, AddPieceToSeason, CreatePiece, LinkPiecePhoto, RemovePieceDetail,
    RemovePieceFromSeason, RenamePiece, SetPieceCategory, UnlinkPiecePhoto, UpdatePieceDetail,
    UpdatePieceNotes,
};
use super::views::PieceView;

/// Async write port for the `PieceAggregate`.
#[allow(async_fn_in_trait)]
pub trait PieceCommands: Send + Sync {
    async fn create(
        &self,
        actor: UserId,
        cmd: CreatePiece,
    ) -> Result<(Uuid, AggregateVersion), DomainError>;
    async fn rename(
        &self,
        actor: UserId,
        cmd: RenamePiece,
    ) -> Result<AggregateVersion, DomainError>;
    async fn update_notes(
        &self,
        actor: UserId,
        cmd: UpdatePieceNotes,
    ) -> Result<AggregateVersion, DomainError>;
    /// Add the piece to a season's repertoire. Idempotent: the adapter maps
    /// the aggregate's no-event repeat dispatch to an unchanged-version
    /// success.
    async fn add_to_season(
        &self,
        actor: UserId,
        cmd: AddPieceToSeason,
    ) -> Result<AggregateVersion, DomainError>;
    /// Remove the piece from a season's repertoire (idempotent mirror of
    /// [`Self::add_to_season`]).
    async fn remove_from_season(
        &self,
        actor: UserId,
        cmd: RemovePieceFromSeason,
    ) -> Result<AggregateVersion, DomainError>;
    async fn add_detail(
        &self,
        actor: UserId,
        cmd: AddPieceDetail,
    ) -> Result<AggregateVersion, DomainError>;
    async fn update_detail(
        &self,
        actor: UserId,
        cmd: UpdatePieceDetail,
    ) -> Result<AggregateVersion, DomainError>;
    async fn remove_detail(
        &self,
        actor: UserId,
        cmd: RemovePieceDetail,
    ) -> Result<AggregateVersion, DomainError>;
    /// Set (or clear, `None`) the piece's single category. The season
    /// invariant is an API-edge pre-check.
    async fn set_category(
        &self,
        actor: UserId,
        cmd: SetPieceCategory,
    ) -> Result<AggregateVersion, DomainError>;
    async fn link_photo(
        &self,
        actor: UserId,
        cmd: LinkPiecePhoto,
    ) -> Result<AggregateVersion, DomainError>;
    async fn unlink_photo(
        &self,
        actor: UserId,
        cmd: UnlinkPiecePhoto,
    ) -> Result<AggregateVersion, DomainError>;
}

/// Async read port returning flat `PieceView` projections.
#[allow(async_fn_in_trait)]
pub trait PieceRepository: Send + Sync {
    async fn find_by_id(&self, id: Uuid) -> Result<PieceView, DomainError>;
    async fn list_by_season(
        &self,
        season_id: SeasonId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<PieceView>, DomainError>;
    /// Fetch a piece together with all details and linked photos.
    async fn piece_with_details_photos(&self, id: Uuid) -> Result<PieceView, DomainError>;
    /// Seasons the piece stands in as **repertoire**, read from
    /// `projection_piece_season`. Empty for a piece not yet filed into any
    /// season.
    ///
    /// The binding is m:n — one piece may stand in several seasons'
    /// wardrobes — so callers must not assume a single season. A read-model
    /// port: only the API edge may consume it (CQRS boundary).
    async fn repertoire_seasons(&self, piece_id: Uuid) -> Result<Vec<SeasonId>, DomainError>;
}
