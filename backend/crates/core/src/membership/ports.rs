// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: hy4-preview (opencode-go)

//! Hexagonal ports for the membership context.
//!
//! `MembershipCommands` is the **write** seam (command-in) and
//! `MembershipRepository` is the **read** seam (flat views-out). Persistence is
//! owned by the `kameo_es` adapter in `infra`.

use crate::error::DomainError;
use crate::shared::{BlockId, SeasonId, SeriesId, UserId};

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

    /// Check whether `user_id` is an *active* member of **any** block that
    /// belongs to `series_id` (membership → block → season → series).
    ///
    /// This is the tenant-scoped counterpart of [`Self::is_active_member`] and
    /// backs the `GET /v1/audit` gate (issue #342): the audit journal is
    /// filtered by the `series_id` **query parameter**, so the caller's active
    /// block (the middleware's `X-Active-Block` scope) says nothing about
    /// whether they may read that series' journal.
    ///
    /// Unlike [`Self::has_active_costume_role_in_season`] this predicate is
    /// **role-agnostic**: any active membership in the series grants access,
    /// because the journal is an operational record of the whole production,
    /// not a costume-department artefact.
    async fn has_active_membership_in_series(
        &self,
        series_id: SeriesId,
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

    /// Check whether `user_id` holds a role permitted to manually enqueue
    /// report archival (`costume_designer` or `wardrobe_supervisor` only).
    ///
    /// `costume_assistant` is intentionally excluded — manual archival is a
    /// deliberate remediation action, not for every season assistant.
    async fn has_active_report_archive_role_in_season(
        &self,
        season_id: SeasonId,
        user_id: UserId,
    ) -> Result<bool, DomainError>;

    /// Check whether `user_id` is an active CostumeDesigner or
    /// CostumeAssistant in any block. This is the settings credential gate;
    /// WardrobeSupervisor is intentionally excluded by ADR-027.
    async fn has_active_credential_role(&self, user_id: UserId) -> Result<bool, DomainError>;
}
