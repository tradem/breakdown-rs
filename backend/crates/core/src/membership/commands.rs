// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Membership domain commands.

use crate::shared::{BlockId, UserId};
use kameo_es::CommandName;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::membership::Role;

/// Invite a `user_id` to the block with a proposed `role` (pending until accepted).
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct InviteMember {
    pub block_id: BlockId,
    pub user_id: UserId,
    pub role: Role,
}

/// Accept a pending invitation. The `user_id` becomes an active member.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct AcceptInvitation {
    pub block_id: BlockId,
    pub user_id: UserId,
}

/// Change an active member's role (prior role replaced).
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct GrantRole {
    pub block_id: BlockId,
    pub user_id: UserId,
    pub role: Role,
}

/// Remove an active member (issued by another member / admin).
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct RemoveMember {
    pub block_id: BlockId,
    pub user_id: UserId,
}

/// Self-service leave: the authenticated actor removes themselves. The actor
/// `UserId` is supplied via command `Metadata` (Decision 6), not in this
/// payload, so the command carries only the `block_id` it is scoped to.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct LeaveBlock {
    pub block_id: BlockId,
}

/// Bootstrap the block's first (owner) member.
///
/// This command breaks the chicken-and-egg between `InviteMember` (gated by
/// active-membership at the API layer) and the need for at least one active
/// member: it is dispatched by the `create_block` handler, which is the only
/// path that can seed the first member. The aggregate only accepts it when the
/// block currently has **zero** members (see `MembershipError::BootstrapNotAllowed`),
/// so it cannot be abused to (re)claim ownership once a member already exists.
///
/// The bootstrapped member becomes an active member with `role` (default
/// `CostumeAssistant` for the block creator).
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct BootstrapOwner {
    pub block_id: BlockId,
    pub user_id: UserId,
    pub role: Role,
}

impl CommandName for InviteMember {
    fn command_name() -> &'static str {
        "InviteMember"
    }
}

impl CommandName for AcceptInvitation {
    fn command_name() -> &'static str {
        "AcceptInvitation"
    }
}

impl CommandName for GrantRole {
    fn command_name() -> &'static str {
        "GrantRole"
    }
}

impl CommandName for RemoveMember {
    fn command_name() -> &'static str {
        "RemoveMember"
    }
}

impl CommandName for LeaveBlock {
    fn command_name() -> &'static str {
        "LeaveBlock"
    }
}

impl CommandName for BootstrapOwner {
    fn command_name() -> &'static str {
        "BootstrapOwner"
    }
}
