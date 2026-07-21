// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Authorization policy *port* (Decision D5).
//!
//! The policy decision logic lives in `api` (it consults the membership read
//! model); `core` only defines the **port** so the domain stays DI-friendly
//! and free of `sqlx`/`axum`/OIDC concerns (ADR-017). The concrete
//! [`crate::membership::MembershipRepository`]-backed implementation lives in
//! `api::auth::authorization`.

use crate::shared::{BlockId, SeasonId, UserId};
use async_trait::async_trait;

/// The outcome of an authorization check.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PolicyDecision {
    /// The caller may perform the action.
    Allow,
    /// The caller is denied (fail closed).
    Deny,
}

/// The kind of action being authorized, scoped to the caller's active block.
///
/// v1 enforces a membership-only policy (any active member is allowed); the
/// `Action` is carried so future role-distinct rules can match on it without
/// changing the port (see `api-authorization` spec, "Role-based policy is
/// additive and explicit").
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    /// A block-scoped read (list/detail).
    Read,
    /// A block-scoped write (create/update/delete).
    Write,
}

/// Everything the policy needs to decide: who, where, and what.
#[derive(Debug, Clone)]
pub struct AuthContext {
    /// The authenticated actor (`UserId` from the OIDC `sub`).
    pub actor: UserId,
    /// The active `BlockId` the caller is acting in (Decision D2).
    pub block_id: BlockId,
    /// The kind of action being authorized.
    pub action: Action,
}

/// Season-scoped authorization context for costume-photo access.
///
/// Unlike `AuthContext` (which targets a single block), `SeasonAuthContext`
/// is used when access must be checked across *all* blocks in a season
/// — the photo authorization policy (`SeasonPhotoAccessPolicy`) grants
/// access if the user holds any costume-dept role in any active block of
/// the season (see ADR-019, D4).
#[derive(Debug, Clone)]
pub struct SeasonAuthContext {
    /// The authenticated actor (`UserId` from the OIDC `sub`).
    pub actor: UserId,
    /// The season whose costume photos the caller is trying to access.
    pub season_id: SeasonId,
    /// The kind of action being authorized.
    pub action: Action,
}

/// The authorization policy port.
///
/// Implementations are infallible: any error (e.g. a read-model failure) maps
/// to [`PolicyDecision::Deny`]. The `api` layer wraps the async call so a
/// *panicking* implementation still yields `Deny` (never a `500`).
#[async_trait]
pub trait AuthorizationPolicy: Send + Sync {
    /// Decide whether `ctx.actor` may perform `ctx.action` in `ctx.block_id`.
    async fn authorize(&self, ctx: &AuthContext) -> PolicyDecision;

    /// Decide whether `ctx.actor` may access costume-photo resources in
    /// `ctx.season_id`.
    ///
    /// The default implementation returns [`PolicyDecision::Deny`] so that
    /// existing block-scoped policies continue to work without changes.
    /// Season-scoped photo authorization is implemented by
    /// `SeasonPhotoAccessPolicy`.
    async fn authorize_season(&self, _ctx: &SeasonAuthContext) -> PolicyDecision {
        PolicyDecision::Deny
    }
}
