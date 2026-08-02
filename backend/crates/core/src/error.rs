// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Zentrale Domain-Fehler

use thiserror::Error;

use crate::block::error::BlockError;
use crate::character::error::CharacterError;
use crate::costume::error::CostumeError;
use crate::costume_category::error::CostumeCategoryError;
use crate::episode::error::EpisodeError;
use crate::membership::error::MembershipError;
use crate::photo::error::PhotoError;
use crate::scene::error::SceneError;
use crate::scene_shoot::error::SceneShootError;
use crate::season::error::SeasonError;
use crate::settings::error::SettingsError;
use crate::shared::AggregateVersion;
use crate::shooting_day::error::ShootingDayError;

#[derive(Error, Debug, Clone, PartialEq)]
pub enum DomainError {
    #[error("Entity not found: {0}")]
    NotFound(String),

    #[error("Unauthorized: {0}")]
    Unauthorized(String),

    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Conflict: {0}")]
    Conflict(String),

    #[error("Service unavailable: {0}")]
    ServiceUnavailable(String),

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
            ShootingDayError::NotFound { id } => {
                DomainError::NotFound(format!("ShootingDay({id})"))
            }
            ShootingDayError::ArchivedCannotBeMutated { id } => DomainError::Conflict(format!(
                "ShootingDay({id}) is archived and cannot be mutated"
            )),
            ShootingDayError::DuplicateOrderKey(key) => {
                DomainError::Conflict(format!("order key {key} already exists for this episode"))
            }
            ShootingDayError::VersionMismatch { expected, actual } => {
                DomainError::VersionConflict {
                    entity: "ShootingDay".into(),
                    expected,
                    current: actual,
                }
            }
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

impl From<SceneShootError> for DomainError {
    fn from(err: SceneShootError) -> Self {
        match err {
            SceneShootError::ValidationError(msg) => DomainError::ValidationError(msg),
            SceneShootError::NotFound { id } => DomainError::NotFound(format!("SceneShoot({id})")),
            SceneShootError::PairAlreadyExists => DomainError::Conflict(
                "A SceneShoot already exists for this (scene, shooting_day) pair".into(),
            ),
            SceneShootError::VersionMismatch {
                entity,
                expected,
                actual,
            } => DomainError::VersionConflict {
                entity,
                expected,
                current: actual,
            },
            SceneShootError::PlannedOrderFrozen => {
                DomainError::Conflict("Planned order is frozen".into())
            }
            SceneShootError::NoteNotFound { note_id } => {
                DomainError::NotFound(format!("Note({note_id})"))
            }
            SceneShootError::AlreadyLinked { photo_id } => DomainError::Conflict(format!(
                "Continuity photo {photo_id} is already linked to this SceneShoot"
            )),
            SceneShootError::AlreadyStarted => {
                DomainError::Conflict("SceneShoot is already started".into())
            }
            SceneShootError::TerminalState { status } => {
                DomainError::Conflict(format!("SceneShoot is in terminal state {status:?}"))
            }
        }
    }
}

impl From<SettingsError> for DomainError {
    fn from(err: SettingsError) -> Self {
        match err {
            SettingsError::EmptyProvider => {
                DomainError::ValidationError("credential provider must not be empty".into())
            }
            SettingsError::EmptyVaultKey => {
                DomainError::ValidationError("vault key reference must not be empty".into())
            }
            SettingsError::ProviderMismatch => {
                DomainError::Conflict("credential provider cannot change during rotation".into())
            }
            SettingsError::NotFound => DomainError::NotFound("Settings credential".into()),
            SettingsError::AlreadyRevoked => {
                DomainError::Conflict("credential binding is already revoked".into())
            }
            SettingsError::VersionMismatch { expected, actual } => DomainError::VersionConflict {
                entity: "Settings".into(),
                expected,
                current: actual,
            },
        }
    }
}

impl From<PhotoError> for DomainError {
    fn from(err: PhotoError) -> Self {
        match err {
            PhotoError::ValidationError(msg) => DomainError::ValidationError(msg),
            PhotoError::NotFound { id } => DomainError::NotFound(format!("Photo({id})")),
            PhotoError::AlreadyDeleted => DomainError::Conflict("Photo is already deleted".into()),
            PhotoError::VersionMismatch { expected, actual } => DomainError::VersionConflict {
                entity: "Photo".into(),
                expected,
                current: actual,
            },
        }
    }
}
