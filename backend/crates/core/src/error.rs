// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Zentrale Domain-Fehler

use thiserror::Error;

use crate::block::error::BlockError;
use crate::character::error::CharacterError;
use crate::costume::error::CostumeError;
use crate::costume_category::error::CostumeCategoryError;
use crate::episode::error::EpisodeError;
use crate::membership::error::MembershipError;
use crate::scene::error::SceneError;
use crate::season::error::SeasonError;
use crate::shooting_day::error::ShootingDayError;
use crate::shared::AggregateVersion;

#[derive(Error, Debug, Clone, PartialEq)]
pub enum DomainError {
    #[error("Entity not found: {0}")]
    NotFound(String),

    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Conflict: {0}")]
    Conflict(String),

    #[error("Version conflict on {entity}: expected {expected:?}, current {current:?}")]
    VersionConflict {
        entity: String,
        expected: AggregateVersion,
        current: AggregateVersion,
    },
}

impl From<SceneError> for DomainError {
    fn from(err: SceneError) -> Self {
        match err {
            SceneError::ValidationError(msg) => DomainError::ValidationError(msg),
            SceneError::CharacterNotFound { id } => {
                DomainError::NotFound(format!("Character({id})"))
            }
            SceneError::NotFound { id } => DomainError::NotFound(format!("Scene({id})")),
            SceneError::CharacterAlreadyAssigned => {
                DomainError::Conflict("Character already assigned to this scene".into())
            }
            SceneError::AlreadyScheduled { shooting_day_id } => DomainError::Conflict(format!(
                "Scene is already scheduled on shooting day {shooting_day_id}"
            )),
            SceneError::NotScheduled { shooting_day_id } => DomainError::Conflict(format!(
                "Scene is not scheduled on shooting day {shooting_day_id}"
            )),
        }
    }
}

impl From<CharacterError> for DomainError {
    fn from(err: CharacterError) -> Self {
        match err {
            CharacterError::ValidationError(msg) => DomainError::ValidationError(msg),
            CharacterError::NotFound { id } => DomainError::NotFound(format!("Character({id})")),
        }
    }
}

impl From<CostumeError> for DomainError {
    fn from(err: CostumeError) -> Self {
        match err {
            CostumeError::ValidationError(msg) => DomainError::ValidationError(msg),
            CostumeError::NotFound { id } => DomainError::NotFound(format!("Costume({id})")),
            CostumeError::AlreadyAssigned { assigned_to } => DomainError::Conflict(format!(
                "Costume already assigned to character {assigned_to}"
            )),
        }
    }
}

impl From<ShootingDayError> for DomainError {
    fn from(err: ShootingDayError) -> Self {
        match err {
            ShootingDayError::ValidationError(msg) => DomainError::ValidationError(msg),
            ShootingDayError::NotFound { id } => DomainError::NotFound(format!("ShootingDay({id})")),
            ShootingDayError::ArchivedCannotBeMutated { id } => DomainError::Conflict(format!(
                "ShootingDay({id}) is archived and cannot be mutated"
            )),
            ShootingDayError::DuplicateOrderKey(key) => {
                DomainError::Conflict(format!("order key {key} already exists for this episode"))
            }
            ShootingDayError::VersionMismatch { expected, actual } => DomainError::VersionConflict {
                entity: "ShootingDay".into(),
                expected,
                current: actual,
            },
        }
    }
}

impl From<SeasonError> for DomainError {
    fn from(err: SeasonError) -> Self {
        match err {
            SeasonError::ValidationError(msg) => DomainError::ValidationError(msg),
            SeasonError::NotFound { id } => DomainError::NotFound(format!("Season({id})")),
        }
    }
}

impl From<BlockError> for DomainError {
    fn from(err: BlockError) -> Self {
        match err {
            BlockError::ValidationError(msg) => DomainError::ValidationError(msg),
            BlockError::NotFound { id } => DomainError::NotFound(format!("Block({id})")),
        }
    }
}

impl From<CostumeCategoryError> for DomainError {
    fn from(err: CostumeCategoryError) -> Self {
        match err {
            CostumeCategoryError::ValidationError(msg) => DomainError::ValidationError(msg),
            CostumeCategoryError::ArchivedCannotBeMutated { id } => DomainError::Conflict(format!(
                "CostumeCategory({id}) is archived and cannot be mutated"
            )),
            CostumeCategoryError::VersionMismatch { expected, actual } => {
                DomainError::VersionConflict {
                    entity: "CostumeCategory".into(),
                    expected,
                    current: actual,
                }
            }
        }
    }
}

impl From<EpisodeError> for DomainError {
    fn from(err: EpisodeError) -> Self {
        match err {
            EpisodeError::ValidationError(msg) => DomainError::ValidationError(msg),
            EpisodeError::NotFound { id } => DomainError::NotFound(format!("Episode({id})")),
        }
    }
}

impl From<MembershipError> for DomainError {
    fn from(err: MembershipError) -> Self {
        match err {
            MembershipError::ValidationError(msg) => DomainError::ValidationError(msg),
            MembershipError::AlreadyInvited { user_id } => {
                DomainError::Conflict(format!("User {user_id} already has a pending invitation"))
            }
            MembershipError::NoPendingInvitation { user_id } => {
                DomainError::Conflict(format!("No pending invitation for user {user_id}"))
            }
            MembershipError::NotActiveMember { user_id } => {
                DomainError::Conflict(format!("User {user_id} is not an active member"))
            }
            MembershipError::MissingActor => {
                DomainError::ValidationError("LeaveBlock requires an authenticated actor".into())
            }
            MembershipError::BootstrapNotAllowed { id } => DomainError::Conflict(format!(
                "Block {id:?} already has members; bootstrap is only allowed on an empty block"
            )),
            MembershipError::NotFound { id } => DomainError::NotFound(format!("Block({id:?})")),
        }
    }
}
