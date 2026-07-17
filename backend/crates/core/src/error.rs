// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Zentrale Domain-Fehler

use thiserror::Error;

use crate::block::error::BlockError;
use crate::character::error::CharacterError;
use crate::costume::error::CostumeError;
use crate::episode::error::EpisodeError;
use crate::scene::error::SceneError;
use crate::season::error::SeasonError;
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

impl From<EpisodeError> for DomainError {
    fn from(err: EpisodeError) -> Self {
        match err {
            EpisodeError::ValidationError(msg) => DomainError::ValidationError(msg),
            EpisodeError::NotFound { id } => DomainError::NotFound(format!("Episode({id})")),
        }
    }
}
