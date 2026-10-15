// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

//! Hexagonal ports for the Character context.

// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

use uuid::Uuid;

use crate::error::DomainError;
use crate::shared::{AggregateVersion, SeasonId, UserId};

use super::category::CharacterCategory;
use super::commands::{
    CreateCharacter, UpdateCharacterCategory, UpdateContactInfo, UpdateMeasurements,
};
use super::views::{CharacterAppearanceView, CharacterView};

/// Async write port for the `CharacterAggregate`.
#[allow(async_fn_in_trait)]
pub trait CharacterCommands: Send + Sync {
    async fn create(
        &self,
        actor: UserId,
        cmd: CreateCharacter,
    ) -> Result<(Uuid, AggregateVersion), DomainError>;
    async fn update_measurements(
        &self,
        actor: UserId,
        cmd: UpdateMeasurements,
    ) -> Result<AggregateVersion, DomainError>;
    async fn update_contact_info(
        &self,
        actor: UserId,
        cmd: UpdateContactInfo,
    ) -> Result<AggregateVersion, DomainError>;
    /// Change the role type (issue #678).
    async fn update_category(
        &self,
        actor: UserId,
        cmd: UpdateCharacterCategory,
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
    /// Derived read (issue #621): the scenes a character appears in, in
    /// script order (`scene_number`), each carrying the character's own
    /// ordered costume beats. Backs the role-extract route
    /// `GET /v1/characters/{id}/appearances`.
    ///
    /// Implemented as a JOIN over `projection_scene_character` →
    /// `projection_scene` with a per-scene costume subquery.
    async fn character_appearances(
        &self,
        character_id: Uuid,
    ) -> Result<Vec<CharacterAppearanceView>, DomainError>;
}
