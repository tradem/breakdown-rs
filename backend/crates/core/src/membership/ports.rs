// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: hy4-preview (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Hexagonal ports for the membership context.
//!
//! `MembershipCommands` is the **write** seam (command-in) and
//! `MembershipRepository` is the **read** seam (flat views-out). Persistence is
//! owned by the `kameo_es` adapter in `infra`.

use crate::error::DomainError;
use crate::membership::Role;
use crate::shared::{BlockId, ProjectId, SeasonId, UserId};

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
    /// belongs to `project_id` (membership → block → season → project).
    ///
    /// This is the tenant-scoped counterpart of [`Self::is_active_member`] and
    /// backs the `GET /v1/audit` gate (issue #342): the audit journal is
    /// filtered by the `project_id` **query parameter**, so the caller's active
    /// block (the middleware's `X-Active-Block` scope) says nothing about
    /// whether they may read that project's journal.
    ///
    /// Unlike [`Self::has_active_costume_role_in_season`] this predicate is
    /// **role-agnostic**: any active membership in the project grants access,
    /// because the journal is an operational record of the whole production,
    /// not a costume-department artefact.
    async fn has_active_membership_in_project(
        &self,
        project_id: ProjectId,
        user_id: UserId,
    ) -> Result<bool, DomainError>;

    /// Check whether `user_id` holds any costume-dept role in **any** active
    /// block of the **project** `project_id` — the project-level analogue of
    /// [`Self::has_active_costume_role_in_season`], typed by the
    /// authorization level, not by a production-form-specific container
    /// (ADR-035 B2/S2).
    ///
    /// This is the photo-gate predicate as of issue #535: a costume-dept role
    /// (`costume_designer`, `wardrobe_supervisor`, `costume_assistant`) in any
    /// active block of the owning project authorizes costume-photo access
    /// **project-wide** — a deliberate authorization-boundary widening, so a
    /// wardrobe team that works across seasons of one production can manage
    /// the costumes it carries between them. Unlike
    /// [`Self::has_active_membership_in_project`] it is *not* role-agnostic:
    /// photos are a costume-department artefact, so the role filter of the
    /// season-scoped predicate is carried over unchanged.
    async fn has_active_costume_role_in_project(
        &self,
        project_id: ProjectId,
        user_id: UserId,
    ) -> Result<bool, DomainError>;

    /// Check whether `user_id` holds any costume-dept role in any active
    /// block of `season_id` (for season-scoped costume authorization).
    ///
    /// As of issue #535 the *photo* path no longer calls this predicate (ADR-035
    /// B2/S2 moved that boundary to [`Self::has_active_costume_role_in_project`]);
    /// the genuinely season-scoped costume operations keep it (target-season
    /// repertoire gates, category season-match).
    ///
    /// Costume-dept roles are `costume_designer`, `wardrobe_supervisor`,
    /// and `costume_assistant`.
    ///
    /// **Block scope only.** This predicate joins `projection_block`, so a
    /// season without blocks has no roles at all. Any season-scoped costume
    /// check that must also accept a project-scoped grant has to call
    /// [`Self::effective_costume_role_in_season`] instead — the report-archive
    /// predicate below is the deliberate exception that keeps this narrower
    /// resolution.
    async fn has_active_costume_role_in_season(
        &self,
        season_id: SeasonId,
        user_id: UserId,
    ) -> Result<bool, DomainError>;

    /// The caller's **effective** costume-department role in `season_id`.
    ///
    /// This is the one place the two authorization scopes are resolved, in
    /// order (design D2 of `openspec/changes/project-scoped-membership`):
    ///
    /// 1. an active block membership with a costume-dept role in any block of
    ///    `season_id` — [`Self::has_active_costume_role_in_season`], unchanged;
    /// 2. else an active **project-scoped** costume role on the project the
    ///    season belongs to ([`Self::has_active_costume_role_in_project`], with
    ///    the project resolved *from the season*, never from the request);
    /// 3. else `None`.
    ///
    /// It exists because a season without blocks is role-less by construction
    /// in the block scope: a block-less AI-import upload (`X-Declared-Season`,
    /// issue #829) could never authorize, not even for a costume designer of
    /// the production.
    ///
    /// Returns the **role itself**, not a boolean, because that is the only
    /// form in which the precedence is observable: a holder of a block-scoped
    /// `costume_assistant` and a project-scoped `costume_designer` resolves to
    /// the former inside that block's season (the spec's "both rows coexist,
    /// block first" scenario) and to the latter in a block-less season of the
    /// same project. A boolean would collapse the two.
    ///
    /// Fail-closed: a projection miss (neither scope has a row, or the season's
    /// `project_id` is not projected) and an unparsable role token are
    /// `Ok(None)`, and a repository error is `Err` — neither is ever an
    /// authorization. Deny-on-error is the caller's decision: the fallible
    /// policy surface keeps surfacing a read-model failure as a server error
    /// instead of disguising it as a `403`.
    ///
    /// Handlers and policies MUST NOT re-implement this precedence.
    async fn effective_costume_role_in_season(
        &self,
        season_id: SeasonId,
        user_id: UserId,
    ) -> Result<Option<Role>, DomainError>;

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

    /// Check whether `user_id` holds the deployment-scoped ops capability
    /// (`Role::OpsAdmin`) as an **active** member of any block (issue #409).
    ///
    /// Unlike the block/season-scoped predicates above this check is
    /// deliberately role-scoped but *not* block-scoped: projector health is
    /// deployment-wide infrastructure state, so any active `ops_admin`
    /// membership grants access regardless of which block carries it.
    async fn has_active_ops_role(&self, user_id: UserId) -> Result<bool, DomainError>;
}
