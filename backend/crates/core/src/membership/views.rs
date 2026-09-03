// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy4-preview (opencode-go)

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

impl MembershipStateKind {
    /// Plain-text token of the variant — the **storage representation** of the
    /// `projection_membership.state` column.
    ///
    /// Distinct from the serde form for the same reason as [`Role::as_str`]:
    /// the wire format is JSON (`"active"`), the column stores the bare token
    /// (`active`) so `m.state = 'active'` matches in the authz predicates.
    /// A unit test pins both representations to the same token.
    pub const fn as_str(self) -> &'static str {
        match self {
            MembershipStateKind::Pending => "pending",
            MembershipStateKind::Active => "active",
        }
    }

    /// Inverse of [`MembershipStateKind::as_str`]: `None` for an unknown token.
    pub fn from_token(token: &str) -> Option<Self> {
        match token {
            "pending" => Some(MembershipStateKind::Pending),
            "active" => Some(MembershipStateKind::Active),
            _ => None,
        }
    }
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
