// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Hexagonal ports for the Character context.

use uuid::Uuid;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, EpisodeId, SeasonId};

use super::category::CharacterCategory;
use super::commands::{CreateCharacter, UpdateContactInfo, UpdateMeasurements};
use super::views::CharacterView;

/// Async write port for the `CharacterAggregate`.
#[allow(async_fn_in_trait)]
pub trait CharacterCommands: Send + Sync {
    async fn create(&self, cmd: CreateCharacter) -> Result<(Uuid, AggregateVersion), DomainError>;
    async fn update_measurements(
        &self,
        cmd: UpdateMeasurements,
    ) -> Result<AggregateVersion, DomainError>;
    async fn update_contact_info(
        &self,
        cmd: UpdateContactInfo,
    ) -> Result<AggregateVersion, DomainError>;
}

/// Async read port returning flat `CharacterView` projections.
#[allow(async_fn_in_trait)]
pub trait CharacterRepository: Send + Sync {
    async fn find_by_id(&self, id: Uuid) -> Result<CharacterView, DomainError>;
    async fn list_by_season(
        &self,
        season_id: SeasonId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<CharacterView>, DomainError>;
    /// List characters of a given category inside a season.
    async fn list_by_season_and_category(
        &self,
        season_id: SeasonId,
        category: CharacterCategory,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<CharacterView>, DomainError>;
    /// Derived read (Task 5.4): episodes a character appears in.
    /// Implemented as a JOIN over `projection_scene_character` → `projection_scene`.
    async fn appearances(&self, character_id: Uuid) -> Result<Vec<EpisodeId>, DomainError>;
}
