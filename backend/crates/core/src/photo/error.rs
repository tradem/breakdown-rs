use thiserror::Error;

use crate::shared::AggregateVersion;

#[derive(Error, Debug, Clone, PartialEq)]
pub enum PhotoError {
    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Photo not found: {id}")]
    NotFound { id: uuid::Uuid },

    #[error("Photo is already deleted")]
    AlreadyDeleted,

    #[error("Version mismatch on photo {expected:?}: expected {expected:?}, current {actual:?}")]
    VersionMismatch {
        expected: AggregateVersion,
        actual: AggregateVersion,
    },
}
