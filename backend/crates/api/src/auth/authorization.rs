// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

//! Authorization policy for the API layer (Section 5, Decision D2/D5).
//!
//! The [`AuthorizationPolicy`] port and [`PolicyDecision`]/[`Action`] types
//! live in `core`; this module provides the concrete, membership-backed
//! implementation and the Axum middleware that enforces it. Authorization is
//! **action-scoped** (the caller's active block, Decision D2) and runs *after*
//! the [`crate::auth::auth_middleware`].

use std::sync::Arc;

use axum::extract::FromRequestParts;
use axum::http::{Method, StatusCode};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use breakdown_core::membership::MembershipRepository;
use breakdown_core::membership::policy::{
    Action, AuthContext, AuthorizationPolicy, PolicyDecision, SeasonAuthContext,
};

use crate::auth::{ActiveBlock, AuthError, CurrentUser};

/// Membership-backed authorization policy (v1: membership-only).
///
/// Generic over the read-model repository so it can be constructed with the
/// production `MembershipRepositoryImpl` (and remain unit-testable). Exposes
/// the dyn-safe [`AuthorizationPolicy`] port.
pub struct MembershipAuthorizationPolicy<Repo: MembershipRepository> {
    repo: Arc<Repo>,
}

impl<Repo: MembershipRepository> MembershipAuthorizationPolicy<Repo> {
    /// Build a policy that consults `repo` for active-membership.
    pub fn new(repo: Arc<Repo>) -> Self {
        Self { repo }
    }
}

#[async_trait::async_trait]
impl<Repo: MembershipRepository + 'static> AuthorizationPolicy
    for MembershipAuthorizationPolicy<Repo>
{
    async fn authorize(&self, ctx: &AuthContext) -> PolicyDecision {
        match self
            .repo
            .is_active_member(ctx.block_id, ctx.actor.clone())
            .await
        {
            Ok(true) => PolicyDecision::Allow,
            // Any error (or non-member) fails closed to Deny.
            _ => PolicyDecision::Deny,
        }
    }
}

/// Season-scoped costume-photo authorization policy (v1: derived).
///
/// Grants access if the user holds any costume-dept role
/// (`costume_designer`, `wardrobe_supervisor`, `costume_assistant`) in any
/// `active` block of the target season.
///
/// ## Between-blocks gap (v1 limitation)
///
/// A costumer between contracts (left Block 3, not yet in Block 5 of the
/// same season) loses photo access. This is accepted as correct from a
/// security standpoint — when a user is not on the production, they do not
/// get confidential photos.
///
/// ## v2 evolution (SeasonCrew)
///
/// When users hit the between-blocks gap, an additive `SeasonCrew` aggregate
/// will be introduced. The upgrade path is non-breaking:
/// `authorized = derived-from-active-block OR season-crew-grant`.
/// The `SeasonPhotoAccessPolicy` trait method signature is unchanged — only
/// the impl changes. See ADR-019, D4 for the full evolution plan.
pub struct SeasonPhotoAccessPolicy<Repo: MembershipRepository> {
    repo: Arc<Repo>,
}

impl<Repo: MembershipRepository> SeasonPhotoAccessPolicy<Repo> {
    /// Build a policy that consults `repo` for season-scoped active
    /// costume-dept membership.
    pub fn new(repo: Arc<Repo>) -> Self {
        Self { repo }
    }
}

#[async_trait::async_trait]
impl<Repo: MembershipRepository + 'static> AuthorizationPolicy for SeasonPhotoAccessPolicy<Repo> {
    async fn authorize(&self, _ctx: &AuthContext) -> PolicyDecision {
        // Block-scoped authorization is not applicable to photo access.
        PolicyDecision::Deny
    }

    async fn authorize_season(&self, ctx: &SeasonAuthContext) -> PolicyDecision {
        match self
            .repo
            .has_active_costume_role_in_season(ctx.season_id, ctx.actor.clone())
            .await
        {
            Ok(true) => PolicyDecision::Allow,
            // Any error (or non-costume-role) fails closed to Deny.
            _ => PolicyDecision::Deny,
        }
    }
}

/// Shared authorization state for the [`authorize_middleware`].
#[derive(Clone)]
pub struct AuthorizationState {
    policy: Arc<dyn AuthorizationPolicy>,
    /// When `true`, denials return `403`. When `false` (log-only / staged
    /// rollout), every request is allowed but denials are logged.
    enforce: bool,
}

impl AuthorizationState {
    /// Read-only access to the enforcement flag (for diagnostics/logging).
    pub fn enforce(&self) -> bool {
        self.enforce
    }

    /// Production/test state.
    pub fn new(policy: Arc<dyn AuthorizationPolicy>, enforce: bool) -> Self {
        Self { policy, enforce }
    }

    /// Read the enforcement flag from `AUTHZ_ENFORCE` (default: enforce).
    pub fn enforce_from_env() -> bool {
        std::env::var("AUTHZ_ENFORCE")
            .map(|v| v != "false" && v != "0")
            .unwrap_or(true)
    }

    /// Build the authorization state from the environment.
    ///
    /// In dev mode (`DEV_AUTH_SUB` set, i.e. the auth layer is not really
    /// verifying tokens) enforcement defaults to *off* (log-only) so local
    /// development works without seeded membership; set `AUTHZ_ENFORCE=true`
    /// to force enforcement even in dev. Production (no `DEV_AUTH_SUB`)
    /// enforces by default.
    pub fn from_env_or_dev(policy: Arc<dyn AuthorizationPolicy>) -> Self {
        let dev = std::env::var("DEV_AUTH_SUB").is_ok();
        let enforce = if dev {
            std::env::var("AUTHZ_ENFORCE")
                .map(|v| v != "false" && v != "0")
                .unwrap_or(false)
        } else {
            Self::enforce_from_env()
        };
        AuthorizationState::new(policy, enforce)
    }
}

/// How strongly a given route is gated.
enum Requirement {
    /// Authentication only (no active-block membership required).
    Authenticated,
    /// Requires the caller to be an active member of the active block.
    BlockMember,
}

/// Resolve the authorization requirement for a request path (Section 5.3/5.4).
///
/// Season endpoints and block *creation*/*listing* need only authentication;
/// every other (block-scoped) read or write requires active membership in the
/// active block conveyed by `X-Active-Block` (Decision D2). The active block is
/// not derived from the data being mutated (action-scoped, not data-scoped).
fn requirement_for(path: &str) -> Requirement {
    if path.starts_with("/seasons") {
        return Requirement::Authenticated;
    }
    // `/blocks` covers both `POST` (create + owner bootstrap) and `GET`
    // (list by season) — neither needs an existing active-block membership.
    if path == "/blocks" {
        return Requirement::Authenticated;
    }
    // Photo endpoints (upload, download, delete) are authenticated but not
    // block-scoped — they use season-scoped authorization (SeasonPhotoAccessPolicy)
    // which is checked inside the handler itself, not by this middleware.
    if path.contains("/photos") {
        return Requirement::Authenticated;
    }
    // Everything else (scenes, characters, costumes, episodes, and
    // block detail / time-span updates) is block-scoped.
    // Self-service invitation acceptance: the invitee is *not yet* an active
    // member (they are pending until they accept), so this endpoint cannot
    // require active-block membership. The domain command enforces that the
    // caller actually holds a pending invitation for this block.
    if path.ends_with("/members/accept") {
        return Requirement::Authenticated;
    }

    Requirement::BlockMember
}

/// Axum middleware implementing the `AuthorizationLayer` (Section 5).
///
/// Runs *after* [`crate::auth::auth_middleware`]. For block-scoped requests it
/// parses `X-Active-Block` (rejecting a missing/malformed header with `400`),
/// resolves the caller from extensions, and asks the policy. A panicking
/// policy MUST yield `403`, never `500`: the async policy call is isolated via
/// [`tokio::task::spawn`]; a panic surfaces as a [`tokio::task::JoinError`]
/// on `.await`, which `.unwrap_or(PolicyDecision::Deny)` maps to `Deny` → `403`.
pub async fn authorize_middleware(
    state: axum::extract::State<Arc<AuthorizationState>>,
    req: axum::http::Request<axum::body::Body>,
    next: Next,
) -> Response {
    let path = req.uri().path().to_string();
    // Documentation endpoints are public.
    if path.starts_with("/swagger-ui") || path.starts_with("/api-docs") {
        return next.run(req).await;
    }

    if matches!(requirement_for(&path), Requirement::Authenticated) {
        return next.run(req).await;
    }

    // Block-scoped: need a valid active block and an authenticated caller.
    // Parse `X-Active-Block` from the request parts (missing/malformed -> 400).
    let (mut parts, body) = req.into_parts();
    let active_block = match ActiveBlock::from_request_parts(&mut parts, &()).await {
        Ok(ab) => ab,
        Err(rej) => return rej.into_response(),
    };
    let current_user = parts.extensions.get::<CurrentUser>().cloned();
    let req = axum::http::Request::from_parts(parts, body);
    let current_user = match current_user {
        // Defensive: the auth layer should have populated this already.
        Some(u) => u,
        None => return AuthError::Unauthorized.into_response(),
    };

    let ctx = AuthContext {
        actor: current_user.sub,
        block_id: active_block.0,
        action: if req.method() == Method::GET {
            Action::Read
        } else {
            Action::Write
        },
    };

    // Panic-resistant evaluation (AC5): a panicking policy yields Deny → 403.
    let decision = tokio::task::spawn({
        let policy = state.policy.clone();
        let ctx = ctx.clone();
        async move { policy.authorize(&ctx).await }
    })
    .await
    .unwrap_or(PolicyDecision::Deny);

    let allowed = if state.enforce {
        matches!(decision, PolicyDecision::Allow)
    } else {
        if matches!(decision, PolicyDecision::Deny) {
            tracing::warn!(
                "AUTHZ(log-only): denied {} {} for {}",
                req.method(),
                path,
                ctx.actor
            );
        }
        true
    };

    if !allowed {
        return (
            StatusCode::FORBIDDEN,
            axum::Json(
                serde_json::json!({ "message": "not an active member of the active block" }),
            ),
        )
            .into_response();
    }

    next.run(req).await
}

#[cfg(test)]
#[path = "authorization_test.rs"]
mod env_tests;
