// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Membership domain errors.

use crate::shared::UserId;
use thiserror::Error;

#[derive(Error, Debug, Clone, PartialEq, Eq)]
pub enum MembershipError {
    #[error("Validation error: {0}")]
    ValidationError(String),

    /// A pending invitation already exists for this user (re-invite rejected).
    #[error("User {user_id} already has a pending invitation")]
    AlreadyInvited { user_id: UserId },

    /// No pending invitation exists for this user (accept rejected).
    #[error("No pending invitation for user {user_id}")]
    NoPendingInvitation { user_id: UserId },

    /// The user is not an active member of the block (grant/remove/leave rejected).
    #[error("User {user_id} is not an active member of this block")]
    NotActiveMember { user_id: UserId },

    /// `LeaveBlock` was dispatched without an authenticated actor in metadata.
    #[error("LeaveBlock requires an authenticated actor")]
    MissingActor,

    /// `BootstrapOwner` was dispatched on a block that already has members.
    /// Bootstrap is only allowed on an empty block (Decision A).
    #[error("Block {id:?} already has members; bootstrap is only allowed on an empty block")]
    BootstrapNotAllowed { id: crate::shared::BlockId },

    #[error("Block not found: {id:?}")]
    NotFound { id: crate::shared::BlockId },
}
