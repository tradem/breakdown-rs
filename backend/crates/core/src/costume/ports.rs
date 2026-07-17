// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Hexagonal ports for the Costume context.

use uuid::Uuid;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, SeasonId};

use super::commands::{
    AddDetail, AssignCostumeToCharacter, CreateCostume, LinkPhoto, RemoveDetail, UnassignCostume,
    UnlinkPhoto, UpdateCostumeNotes,
};
use super::views::CostumeView;

/// Async write port for the `CostumeAggregate`.
#[allow(async_fn_in_trait)]
pub trait CostumeCommands: Send + Sync {
    async fn create(&self, cmd: CreateCostume) -> Result<(Uuid, AggregateVersion), DomainError>;
    async fn update_notes(&self, cmd: UpdateCostumeNotes) -> Result<AggregateVersion, DomainError>;
    async fn assign_to_character(
        &self,
        cmd: AssignCostumeToCharacter,
    ) -> Result<AggregateVersion, DomainError>;
    async fn unassign(&self, cmd: UnassignCostume) -> Result<AggregateVersion, DomainError>;
    async fn add_detail(&self, cmd: AddDetail) -> Result<AggregateVersion, DomainError>;
    async fn remove_detail(&self, cmd: RemoveDetail) -> Result<AggregateVersion, DomainError>;
    async fn link_photo(&self, cmd: LinkPhoto) -> Result<AggregateVersion, DomainError>;
    async fn unlink_photo(&self, cmd: UnlinkPhoto) -> Result<AggregateVersion, DomainError>;
}

/// Async read port returning flat `CostumeView` projections.
#[allow(async_fn_in_trait)]
pub trait CostumeRepository: Send + Sync {
    async fn find_by_id(&self, id: Uuid) -> Result<CostumeView, DomainError>;
    async fn list_by_season(
        &self,
        season_id: SeasonId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<CostumeView>, DomainError>;
    async fn costumes_by_character(
        &self,
        character_id: Uuid,
    ) -> Result<Vec<CostumeView>, DomainError>;
    /// Fetch a costume together with all details and linked photos.
    async fn costume_with_details_photos(&self, id: Uuid) -> Result<CostumeView, DomainError>;
}
