// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Flat read-model DTOs for the membership context.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::shared::{BlockId, UserId};

use crate::membership::Role;

/// Membership lifecycle state in the read model.
///
/// `snake_case` serialization keeps the Postgres `state` text column stable
/// and human-readable.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum MembershipStateKind {
    /// Invited, but not yet accepted.
    Pending,
    /// Accepted and active with a role.
    Active,
}

/// Complete membership read model row for one `(block_id, user_id)` pair.
///
/// `joined_at` is the timestamp of the `InvitationAccepted` event, sourced
/// from the event stream (not from aggregate state).
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct MembershipView {
    pub block_id: BlockId,
    pub user_id: UserId,
    pub role: Role,
    pub state: MembershipStateKind,
    pub joined_at: DateTime<Utc>,
}
