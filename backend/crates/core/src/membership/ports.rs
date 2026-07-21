// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Hexagonal ports for the membership context.
//!
//! `MembershipCommands` is the **write** seam (command-in) and
//! `MembershipRepository` is the **read** seam (flat views-out). Persistence is
//! owned by the `kameo_es` adapter in `infra`.

use crate::error::DomainError;
use crate::shared::{BlockId, SeasonId, UserId};

use super::commands::{
    AcceptInvitation, BootstrapOwner, GrantRole, InviteMember, LeaveBlock, RemoveMember,
};
use super::views::MembershipView;

use async_trait::async_trait;

/// Async write port for the `BlockMembership` aggregate.
///
/// Every method takes the authenticated `actor` (`UserId`). The adapter attaches
/// it as `kameo_es` command `Metadata` for audit (Decision 6); for `LeaveBlock`
/// the actor is also the member being removed. Command payloads are unchanged.
#[async_trait]
pub trait MembershipCommands: Send + Sync {
    /// Invite `cmd.user_id` to the block with a proposed role.
    async fn invite(&self, actor: UserId, cmd: InviteMember) -> Result<(), DomainError>;
    /// Accept a pending invitation for `cmd.user_id`.
    async fn accept_invitation(
        &self,
        actor: UserId,
        cmd: AcceptInvitation,
    ) -> Result<(), DomainError>;
    /// Change an active member's role.
    async fn grant_role(&self, actor: UserId, cmd: GrantRole) -> Result<(), DomainError>;
    /// Remove an active member.
    async fn remove_member(&self, actor: UserId, cmd: RemoveMember) -> Result<(), DomainError>;
    /// The authenticated actor leaves the block.
    async fn leave_block(&self, actor: UserId, cmd: LeaveBlock) -> Result<(), DomainError>;
    /// Bootstrap the block's first (owner) member. Only succeeds when the block
    /// currently has zero members (Decision A): the block creator becomes an
    /// active member with the supplied role (default `CostumeAssistant`).
    async fn bootstrap_owner(&self, actor: UserId, cmd: BootstrapOwner) -> Result<(), DomainError>;
}

/// Async read port returning flat `MembershipView` projections.
#[async_trait]
pub trait MembershipRepository: Send + Sync {
    /// Fetch a single `(block_id, user_id)` membership row, if present.
    async fn find(
        &self,
        block_id: BlockId,
        user_id: UserId,
    ) -> Result<Option<MembershipView>, DomainError>;

    /// Paginated list of members of a block.
    async fn list_by_block(
        &self,
        block_id: BlockId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<MembershipView>, DomainError>;

    /// Convenience check: is `user_id` an *active* member of `block_id`?
    async fn is_active_member(
        &self,
        block_id: BlockId,
        user_id: UserId,
    ) -> Result<bool, DomainError>;

    /// Check whether `user_id` holds any costume-dept role in any active
    /// block of `season_id` (for season-scoped costume-photo authorization).
    ///
    /// Costume-dept roles are `costume_designer`, `wardrobe_supervisor`,
    /// and `costume_assistant`.
    async fn has_active_costume_role_in_season(
        &self,
        season_id: SeasonId,
        user_id: UserId,
    ) -> Result<bool, DomainError>;
}
