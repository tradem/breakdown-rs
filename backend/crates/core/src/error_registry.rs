// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

//! Stable problem-code registry (ADR-031).
//!
//! This module is dependency-free **data**: `core` must not know HTTP or
//! i18n (ADR-017). It defines the *identity* of every failure — the stable
//! `{context}.{reason}` machine code — together with the canonical HTTP
//! status, the constant English `title`, and the whitelist of extension
//! fields (S0/S1 classified; S2 is structurally banned, see ADR-031 D4).
//!
//! The API crate renders RFC 9457 `application/problem+json` documents from
//! this data (see `crates/api/src/problems`). The registry is the single
//! source for:
//! 1. the `code` member,
//! 2. the `type` URI anchor (derived, never stored separately),
//! 3. the localization message key (derived, 1:1 with the code).
//!
//! Published codes are never reused; removal requires an API major version
//! bump (ADR-021). Deprecated codes keep their locale messages until removal.

/// Documentation base used to derive the `type` URI anchor of every problem.
///
/// ADR-031 D2: `type` is `{base}/problems/{code}`. The base is a constant
/// until a final docs host is configured (the design leaves the host open);
/// hosting changes are non-breaking because the registry entry is the single
/// source for the URI.
pub const PROBLEM_DOCS_BASE: &str = "https://docs.breakdown.example";

/// One registered problem code (ADR-031 D2/D4).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProblemCode {
    /// Stable machine identity, `{context}.{reason}` lower kebab-case.
    pub code: &'static str,
    /// Canonical HTTP status for this code.
    pub status: u16,
    /// Constant English title — cacheable and spec-stable; never localized
    /// (only `detail` is, ADR-031 D1).
    pub title: &'static str,
    /// Whitelisted extension fields (S0/S1 classified; S2 never allowed).
    ///
    /// The problem builder only serializes fields declared here; anything
    /// else is refused loudly (Tranche 2 turns this into a compile-time
    /// guarantee via typed extension builders).
    pub extensions: &'static [&'static str],
}

impl ProblemCode {
    /// The RFC 9457 `type` member: `{base}/problems/{code}` (ADR-031 D2).
    pub fn type_uri(&self) -> String {
        format!("{PROBLEM_DOCS_BASE}/problems/{}", self.code)
    }

    /// The Fluent message key, derived 1:1 from the code:
    /// `scene.already-scheduled` → `problem-scene-already-scheduled`
    /// (ADR-031 D5; the bundle-coverage lint enforces the bijection).
    pub fn message_key(&self) -> String {
        format!("problem-{}", self.code.replace('.', "-"))
    }
}

// ---------------------------------------------------------------------------
// Framework codes (`http.*`, `auth.*`) and cross-cutting codes
// (`concurrency.*`). These are registered in Tranche 1 because the envelope,
// the auth middleware, the rejection handlers, and the panic fallback all
// need them from day one.
// ---------------------------------------------------------------------------

/// 400 — malformed JSON request body (extractor rejection).
pub const HTTP_BAD_JSON_BODY: ProblemCode = ProblemCode {
    code: "http.bad-json-body",
    status: 400,
    title: "Malformed JSON body",
    extensions: &[],
};

/// 400 — malformed path parameter (extractor rejection).
pub const HTTP_BAD_PATH_PARAM: ProblemCode = ProblemCode {
    code: "http.bad-path-param",
    status: 400,
    title: "Invalid path parameter",
    extensions: &[],
};

/// 400 — malformed/absent query parameter (extractor rejection or
/// handler-side required-param check).
pub const HTTP_BAD_QUERY_PARAM: ProblemCode = ProblemCode {
    code: "http.bad-query-param",
    status: 400,
    title: "Invalid query parameter",
    extensions: &[],
};

/// 400 — generic malformed request (path/body mismatch, bad headers).
pub const HTTP_BAD_REQUEST: ProblemCode = ProblemCode {
    code: "http.bad-request",
    status: 400,
    title: "Bad request",
    extensions: &[],
};

/// 415 — request content type not accepted (extractor/handler rejection).
pub const HTTP_UNSUPPORTED_MEDIA_TYPE: ProblemCode = ProblemCode {
    code: "http.unsupported-media-type",
    status: 415,
    title: "Unsupported media type",
    extensions: &[],
};

/// 413 — request body exceeds the configured size limit.
pub const HTTP_PAYLOAD_TOO_LARGE: ProblemCode = ProblemCode {
    code: "http.payload-too-large",
    status: 413,
    title: "Payload too large",
    extensions: &[],
};

/// 408 — upstream renderer exceeded its time budget.
pub const HTTP_REQUEST_TIMEOUT: ProblemCode = ProblemCode {
    code: "http.request-timeout",
    status: 408,
    title: "Request timeout",
    extensions: &[],
};

/// 404 — no route matches the request path.
pub const HTTP_ROUTE_NOT_FOUND: ProblemCode = ProblemCode {
    code: "http.route-not-found",
    status: 404,
    title: "Route not found",
    extensions: &[],
};

/// 500 — unhandled internal failure (panic fallback and handler 500s).
/// `detail` for this code is always static localized text; internal error
/// text never leaves the server (ADR-031 decision 6).
pub const HTTP_INTERNAL_ERROR: ProblemCode = ProblemCode {
    code: "http.internal-error",
    status: 500,
    title: "Internal server error",
    extensions: &[],
};

/// 401 — missing/invalid bearer token (auth middleware).
pub const AUTH_UNAUTHENTICATED: ProblemCode = ProblemCode {
    code: "auth.unauthenticated",
    status: 401,
    title: "Authentication required",
    extensions: &[],
};

/// 400 — `X-Active-Block` header absent on a block-scoped request.
pub const AUTH_MISSING_ACTIVE_BLOCK: ProblemCode = ProblemCode {
    code: "auth.missing-active-block",
    status: 400,
    title: "Missing active block",
    extensions: &[],
};

/// 400 — `X-Active-Block` header present but not a valid block id.
pub const AUTH_INVALID_ACTIVE_BLOCK: ProblemCode = ProblemCode {
    code: "auth.invalid-active-block",
    status: 400,
    title: "Invalid active block",
    extensions: &[],
};

/// 503 — the identity provider / JWKS endpoint is unreachable.
pub const AUTH_IDP_UNAVAILABLE: ProblemCode = ProblemCode {
    code: "auth.idp-unavailable",
    status: 503,
    title: "Identity provider unavailable",
    extensions: &[],
};

/// 409 — optimistic-concurrency check failed.
///
/// Extensions (ADR-031 D4):
/// - `expected_version` (S0 — client-supplied),
/// - `current_version` (S0 — aggregate version, in-scope after authz).
pub const CONCURRENCY_VERSION_MISMATCH: ProblemCode = ProblemCode {
    code: "concurrency.version-mismatch",
    status: 409,
    title: "Version conflict",
    extensions: &["expected_version", "current_version"],
};

// ---------------------------------------------------------------------------
// Generic `domain.*` codes — Tranche 1 stand-ins.
//
// These map the (still string-carrying) `DomainError` variants until Tranche 2
// restructures `DomainError` and registers per-aggregate codes such as
// `scene.already-scheduled`. They are deliberately generic: no extension
// fields, static detail.
// ---------------------------------------------------------------------------

/// 404 — resource not found (or deliberately hidden per the existence-oracle
/// policy, ADR-031 decision 5).
pub const DOMAIN_NOT_FOUND: ProblemCode = ProblemCode {
    code: "domain.not-found",
    status: 404,
    title: "Not found",
    extensions: &[],
};

/// 422 — well-formed request that violates a domain rule (RFC 9110
/// §15.5.21). Tranche 1 generic code; per-aggregate codes in Tranche 2.
pub const DOMAIN_VALIDATION: ProblemCode = ProblemCode {
    code: "domain.validation",
    status: 422,
    title: "Validation failed",
    extensions: &[],
};

/// 409 — state conflict (already assigned/scheduled, terminal state, …).
pub const DOMAIN_CONFLICT: ProblemCode = ProblemCode {
    code: "domain.conflict",
    status: 409,
    title: "Conflict",
    extensions: &[],
};

/// 403 — authenticated caller lacks permission (handler-internal authz gates).
pub const DOMAIN_FORBIDDEN: ProblemCode = ProblemCode {
    code: "domain.forbidden",
    status: 403,
    title: "Forbidden",
    extensions: &[],
};

/// 503 — an upstream dependency (Vault, renderer, …) is unavailable.
pub const DOMAIN_SERVICE_UNAVAILABLE: ProblemCode = ProblemCode {
    code: "domain.service-unavailable",
    status: 503,
    title: "Service unavailable",
    extensions: &[],
};

/// The registry (ADR-031 D2). The set below is deliberately small in
/// Tranche 1; per-aggregate codes land in Tranche 2 when `DomainError`
/// becomes structured.
pub static PROBLEM_CODES: &[ProblemCode] = &[
    HTTP_BAD_JSON_BODY,
    HTTP_BAD_PATH_PARAM,
    HTTP_BAD_QUERY_PARAM,
    HTTP_BAD_REQUEST,
    HTTP_UNSUPPORTED_MEDIA_TYPE,
    HTTP_PAYLOAD_TOO_LARGE,
    HTTP_REQUEST_TIMEOUT,
    HTTP_ROUTE_NOT_FOUND,
    HTTP_INTERNAL_ERROR,
    AUTH_UNAUTHENTICATED,
    AUTH_MISSING_ACTIVE_BLOCK,
    AUTH_INVALID_ACTIVE_BLOCK,
    AUTH_IDP_UNAVAILABLE,
    CONCURRENCY_VERSION_MISMATCH,
    DOMAIN_NOT_FOUND,
    DOMAIN_VALIDATION,
    DOMAIN_CONFLICT,
    DOMAIN_FORBIDDEN,
    DOMAIN_SERVICE_UNAVAILABLE,
    SEASON_NOT_FOUND,
    SEASON_VALIDATION,
    BLOCK_NOT_FOUND,
    BLOCK_VALIDATION,
    EPISODE_NOT_FOUND,
    EPISODE_VALIDATION,
    SCENE_NOT_FOUND,
    SCENE_CHARACTER_NOT_FOUND,
    SCENE_CHARACTER_ALREADY_ASSIGNED,
    SCENE_ALREADY_SCHEDULED,
    SCENE_NOT_SCHEDULED,
    SCENE_VALIDATION,
    CHARACTER_NOT_FOUND,
    CHARACTER_VALIDATION,
    COSTUME_NOT_FOUND,
    COSTUME_ALREADY_ASSIGNED,
    COSTUME_VALIDATION,
    COSTUME_CATEGORY_NOT_FOUND,
    COSTUME_CATEGORY_ARCHIVED,
    COSTUME_CATEGORY_VALIDATION,
    SHOOTING_DAY_NOT_FOUND,
    SHOOTING_DAY_ARCHIVED,
    SHOOTING_DAY_DUPLICATE_ORDER_KEY,
    SHOOTING_DAY_VALIDATION,
    SCENE_SHOOT_NOT_FOUND,
    SCENE_SHOOT_PAIR_ALREADY_EXISTS,
    SCENE_SHOOT_PLANNED_ORDER_FROZEN,
    SCENE_SHOOT_NOTE_NOT_FOUND,
    SCENE_SHOOT_ALREADY_LINKED,
    SCENE_SHOOT_ALREADY_STARTED,
    SCENE_SHOOT_TERMINAL_STATE,
    SCENE_SHOOT_VALIDATION,
    PHOTO_NOT_FOUND,
    PHOTO_ALREADY_DELETED,
    PHOTO_VALIDATION,
    MEMBERSHIP_ALREADY_INVITED,
    MEMBERSHIP_NO_PENDING_INVITATION,
    MEMBERSHIP_NOT_ACTIVE_MEMBER,
    MEMBERSHIP_MISSING_ACTOR,
    MEMBERSHIP_BOOTSTRAP_NOT_ALLOWED,
    MEMBERSHIP_NOT_FOUND,
    MEMBERSHIP_VALIDATION,
    SETTINGS_EMPTY_PROVIDER,
    SETTINGS_EMPTY_VAULT_KEY,
    SETTINGS_PROVIDER_MISMATCH,
    SETTINGS_NOT_FOUND,
    SETTINGS_ALREADY_REVOKED,
    AI_CONFIG_NOT_FOUND,
    AI_CONFIG_EMPTY_PROVIDER,
    AI_CONFIG_EMPTY_MODEL,
    AI_CONFIG_EMPTY_PROMPT,
    AI_CONFIG_EMPTY_VAULT_KEY,
    AI_CONFIG_PROVIDER_MISMATCH,
    AI_CONFIG_ALREADY_REVOKED,
];

/// Resolve a registry entry by code. The problem builder never emits a code
/// absent from the registry; this lookup exists for tests and for the
/// bundle-coverage lint (Tranche 3).
pub fn problem_code(code: &'static str) -> Option<&'static ProblemCode> {
    PROBLEM_CODES.iter().find(|entry| entry.code == code)
}

// ---------------------------------------------------------------------------
// Per-context domain codes (Tranche 2).
//
// Every typed error of every aggregate maps 1:1 to a code here. Naming:
// `{context}.{reason}` in lower kebab-case. `type` URIs and Fluent message
// keys are derived (see `ProblemCode::type_uri` / `message_key`); published
// codes are never reused (ADR-021 major-bump removal rule).
//
// Extension classification (ADR-031 D4):
//   S0 — identifier supplied by the client in the request (path/body/query):
//        always allowed.
//   S1 — aggregate identifier within the caller's authorized scope: allowed
//        only where the handler's AUTHZ-GATE ran before the failure.
//   S2 — person identifiers (OIDC `sub`, e-mail) and cross-tenant data:
//        structurally banned, enforced by the `s2-extension-ban` ast-grep
//        rule and the golden-file snapshots.
// ---------------------------------------------------------------------------

// --- season ---
pub const SEASON_VALIDATION: ProblemCode = ProblemCode {
    code: "season.validation",
    status: 422,
    title: "Season validation failed",
    extensions: &[],
};
pub const SEASON_NOT_FOUND: ProblemCode = ProblemCode {
    code: "season.not-found",
    status: 404,
    title: "Season not found",
    extensions: &["id"],
};

// --- block ---
pub const BLOCK_VALIDATION: ProblemCode = ProblemCode {
    code: "block.validation",
    status: 422,
    title: "Block validation failed",
    extensions: &[],
};
pub const BLOCK_NOT_FOUND: ProblemCode = ProblemCode {
    code: "block.not-found",
    status: 404,
    title: "Block not found",
    extensions: &["id"],
};

// --- episode ---
pub const EPISODE_VALIDATION: ProblemCode = ProblemCode {
    code: "episode.validation",
    status: 422,
    title: "Episode validation failed",
    extensions: &[],
};
pub const EPISODE_NOT_FOUND: ProblemCode = ProblemCode {
    code: "episode.not-found",
    status: 404,
    title: "Episode not found",
    extensions: &["id"],
};

// S1 gating audit (ADR-031 D4, task 2.8): every code below whose
// extension whitelist contains an S1 field is emitted only from handlers
// whose authorization gate ran *before* the failure can occur:
//   - `scene.already-scheduled` (offending_shooting_day_id S1) — produced by
//     `schedule_scene_on_shooting_day`; the route is `Requirement::BlockMember`
//     so `authorize_middleware` gates before the command runs.
//   - `costume.already-assigned` (assigned_character_id S1) — produced by
//     `assign_costume`; route `Requirement::BlockMember` (same gate).
//   - `scene-shoot.already-linked` (photo_id S1) — produced by
//     `link_continuity_photo`; the route is Authenticated-only, so the
//     handler runs its internal `// AUTHZ-GATE:` season-scoped membership
//     check before the command (verified in crates/api/src/handlers/mod.rs).
// The `http-error-surface` spec scenario "Conflict exposes the in-scope
// conflicting resource" is covered by golden snapshot
// `scene.already-scheduled.json`.

// --- scene ---
pub const SCENE_NOT_FOUND: ProblemCode = ProblemCode {
    code: "scene.not-found",
    status: 404,
    title: "Scene not found",
    extensions: &["id"],
};
pub const SCENE_CHARACTER_NOT_FOUND: ProblemCode = ProblemCode {
    code: "scene.character-not-found",
    status: 404,
    title: "Scene character not found",
    extensions: &["id"],
};
pub const SCENE_CHARACTER_ALREADY_ASSIGNED: ProblemCode = ProblemCode {
    code: "scene.character-already-assigned",
    status: 409,
    title: "Character already assigned to this scene",
    extensions: &[],
};
/// Conflict: the scene is already scheduled on *another* shooting day.
/// The offending day is an in-scope aggregate id (S1) — emitted only after
/// the handler's AUTHZ-GATE has passed (ADR-031 D4).
pub const SCENE_ALREADY_SCHEDULED: ProblemCode = ProblemCode {
    code: "scene.already-scheduled",
    status: 409,
    title: "Scene schedule conflict",
    extensions: &["offending_shooting_day_id"],
};
pub const SCENE_NOT_SCHEDULED: ProblemCode = ProblemCode {
    code: "scene.not-scheduled",
    status: 409,
    title: "Scene not scheduled on this day",
    extensions: &["shooting_day_id"],
};
pub const SCENE_VALIDATION: ProblemCode = ProblemCode {
    code: "scene.validation",
    status: 422,
    title: "Scene validation failed",
    extensions: &[],
};

// --- character ---
pub const CHARACTER_NOT_FOUND: ProblemCode = ProblemCode {
    code: "character.not-found",
    status: 404,
    title: "Character not found",
    extensions: &["id"],
};
pub const CHARACTER_VALIDATION: ProblemCode = ProblemCode {
    code: "character.validation",
    status: 422,
    title: "Character validation failed",
    extensions: &[],
};

// --- costume ---
pub const COSTUME_NOT_FOUND: ProblemCode = ProblemCode {
    code: "costume.not-found",
    status: 404,
    title: "Costume not found",
    extensions: &["id"],
};
/// Conflict: the costume is already assigned to a character. The assigned
/// character is in-scope (S1) — the caller passed the season auth gate.
pub const COSTUME_ALREADY_ASSIGNED: ProblemCode = ProblemCode {
    code: "costume.already-assigned",
    status: 409,
    title: "Costume already assigned",
    extensions: &["assigned_character_id"],
};
pub const COSTUME_VALIDATION: ProblemCode = ProblemCode {
    code: "costume.validation",
    status: 422,
    title: "Costume validation failed",
    extensions: &[],
};

// --- costume category ---
pub const COSTUME_CATEGORY_NOT_FOUND: ProblemCode = ProblemCode {
    code: "costume-category.not-found",
    status: 404,
    title: "Costume category not found",
    extensions: &["id"],
};
pub const COSTUME_CATEGORY_ARCHIVED: ProblemCode = ProblemCode {
    code: "costume-category.archived",
    status: 409,
    title: "Costume category is archived",
    extensions: &["id"],
};
pub const COSTUME_CATEGORY_VALIDATION: ProblemCode = ProblemCode {
    code: "costume-category.validation",
    status: 422,
    title: "Costume category validation failed",
    extensions: &[],
};

// --- shooting day ---
pub const SHOOTING_DAY_NOT_FOUND: ProblemCode = ProblemCode {
    code: "shooting-day.not-found",
    status: 404,
    title: "Shooting day not found",
    extensions: &["id"],
};
pub const SHOOTING_DAY_ARCHIVED: ProblemCode = ProblemCode {
    code: "shooting-day.archived",
    status: 409,
    title: "Shooting day is archived",
    extensions: &["id"],
};
pub const SHOOTING_DAY_DUPLICATE_ORDER_KEY: ProblemCode = ProblemCode {
    code: "shooting-day.duplicate-order-key",
    status: 409,
    title: "Duplicate order key",
    extensions: &[],
};
pub const SHOOTING_DAY_VALIDATION: ProblemCode = ProblemCode {
    code: "shooting-day.validation",
    status: 422,
    title: "Shooting day validation failed",
    extensions: &[],
};

// --- scene shoot ---
pub const SCENE_SHOOT_NOT_FOUND: ProblemCode = ProblemCode {
    code: "scene-shoot.not-found",
    status: 404,
    title: "Scene shoot not found",
    extensions: &["id"],
};
pub const SCENE_SHOOT_PAIR_ALREADY_EXISTS: ProblemCode = ProblemCode {
    code: "scene-shoot.pair-already-exists",
    status: 409,
    title: "Scene shoot pair already exists",
    extensions: &[],
};
pub const SCENE_SHOOT_PLANNED_ORDER_FROZEN: ProblemCode = ProblemCode {
    code: "scene-shoot.planned-order-frozen",
    status: 409,
    title: "Planned order is frozen",
    extensions: &[],
};
pub const SCENE_SHOOT_NOTE_NOT_FOUND: ProblemCode = ProblemCode {
    code: "scene-shoot.note-not-found",
    status: 404,
    title: "Scene shoot note not found",
    extensions: &["note_id"],
};
/// Conflict: the continuity photo is already linked to this scene shoot.
/// The photo id is in-scope (S1).
pub const SCENE_SHOOT_ALREADY_LINKED: ProblemCode = ProblemCode {
    code: "scene-shoot.already-linked",
    status: 409,
    title: "Continuity photo already linked",
    extensions: &["photo_id"],
};
pub const SCENE_SHOOT_ALREADY_STARTED: ProblemCode = ProblemCode {
    code: "scene-shoot.already-started",
    status: 409,
    title: "Scene shoot already started",
    extensions: &[],
};
pub const SCENE_SHOOT_TERMINAL_STATE: ProblemCode = ProblemCode {
    code: "scene-shoot.terminal-state",
    status: 409,
    title: "Scene shoot in terminal state",
    extensions: &[],
};
pub const SCENE_SHOOT_VALIDATION: ProblemCode = ProblemCode {
    code: "scene-shoot.validation",
    status: 422,
    title: "Scene shoot validation failed",
    extensions: &[],
};

// --- photo ---
pub const PHOTO_NOT_FOUND: ProblemCode = ProblemCode {
    code: "photo.not-found",
    status: 404,
    title: "Photo not found",
    extensions: &["id"],
};
pub const PHOTO_ALREADY_DELETED: ProblemCode = ProblemCode {
    code: "photo.already-deleted",
    status: 409,
    title: "Photo already deleted",
    extensions: &[],
};
pub const PHOTO_VALIDATION: ProblemCode = ProblemCode {
    code: "photo.validation",
    status: 422,
    title: "Photo validation failed",
    extensions: &[],
};

// --- membership ---
// Deliberately no `user_id` extension on any membership code: the OIDC `sub`
// is an S2 person identifier and must never appear in a problem body
// (ADR-031 D4, http-error-surface spec scenario "Person identifier is never
// echoed"). The reason text never names the identity either.
pub const MEMBERSHIP_VALIDATION: ProblemCode = ProblemCode {
    code: "membership.validation",
    status: 422,
    title: "Membership validation failed",
    extensions: &[],
};
pub const MEMBERSHIP_ALREADY_INVITED: ProblemCode = ProblemCode {
    code: "membership.already-invited",
    status: 409,
    title: "Already invited",
    extensions: &[],
};
pub const MEMBERSHIP_NO_PENDING_INVITATION: ProblemCode = ProblemCode {
    code: "membership.no-pending-invitation",
    status: 409,
    title: "No pending invitation",
    extensions: &[],
};
pub const MEMBERSHIP_NOT_ACTIVE_MEMBER: ProblemCode = ProblemCode {
    code: "membership.not-active-member",
    status: 409,
    title: "Not an active member",
    extensions: &[],
};
pub const MEMBERSHIP_MISSING_ACTOR: ProblemCode = ProblemCode {
    code: "membership.missing-actor",
    status: 422,
    title: "Authenticated actor required",
    extensions: &[],
};
pub const MEMBERSHIP_BOOTSTRAP_NOT_ALLOWED: ProblemCode = ProblemCode {
    code: "membership.bootstrap-not-allowed",
    status: 409,
    title: "Bootstrap not allowed",
    extensions: &[],
};
pub const MEMBERSHIP_NOT_FOUND: ProblemCode = ProblemCode {
    code: "membership.not-found",
    status: 404,
    title: "Membership not found",
    extensions: &[],
};

// --- settings (credentials) ---
pub const SETTINGS_EMPTY_PROVIDER: ProblemCode = ProblemCode {
    code: "settings.empty-provider",
    status: 422,
    title: "Credential provider must not be empty",
    extensions: &[],
};
pub const SETTINGS_EMPTY_VAULT_KEY: ProblemCode = ProblemCode {
    code: "settings.empty-vault-key",
    status: 422,
    title: "Vault key reference must not be empty",
    extensions: &[],
};
pub const SETTINGS_PROVIDER_MISMATCH: ProblemCode = ProblemCode {
    code: "settings.provider-mismatch",
    status: 409,
    title: "Credential provider cannot change during rotation",
    extensions: &[],
};
pub const SETTINGS_NOT_FOUND: ProblemCode = ProblemCode {
    code: "settings.not-found",
    status: 404,
    title: "Credential not found",
    extensions: &[],
};
pub const SETTINGS_ALREADY_REVOKED: ProblemCode = ProblemCode {
    code: "settings.already-revoked",
    status: 409,
    title: "Credential already revoked",
    extensions: &[],
};

// --- ai config ---
pub const AI_CONFIG_NOT_FOUND: ProblemCode = ProblemCode {
    code: "ai-config.not-found",
    status: 404,
    title: "AI configuration not found",
    extensions: &[],
};
pub const AI_CONFIG_EMPTY_PROVIDER: ProblemCode = ProblemCode {
    code: "ai-config.empty-provider",
    status: 422,
    title: "AI provider must be selected",
    extensions: &[],
};
pub const AI_CONFIG_EMPTY_MODEL: ProblemCode = ProblemCode {
    code: "ai-config.empty-model",
    status: 422,
    title: "AI assistant model must not be empty",
    extensions: &[],
};
pub const AI_CONFIG_EMPTY_PROMPT: ProblemCode = ProblemCode {
    code: "ai-config.empty-prompt",
    status: 422,
    title: "AI prompt must not be empty",
    extensions: &[],
};
pub const AI_CONFIG_EMPTY_VAULT_KEY: ProblemCode = ProblemCode {
    code: "ai-config.empty-vault-key",
    status: 422,
    title: "AI vault key reference must not be empty",
    extensions: &[],
};
pub const AI_CONFIG_PROVIDER_MISMATCH: ProblemCode = ProblemCode {
    code: "ai-config.provider-mismatch",
    status: 409,
    title: "AI provider cannot change",
    extensions: &[],
};
pub const AI_CONFIG_ALREADY_REVOKED: ProblemCode = ProblemCode {
    code: "ai-config.already-revoked",
    status: 409,
    title: "AI configuration already revoked",
    extensions: &[],
};

#[cfg(test)]
mod tests {
    use super::*;

    /// Registry sanity: codes are unique, kebab-case, and the derived `type`
    /// URI / message key are deterministic.
    #[test]
    fn registry_codes_are_unique_and_well_formed() {
        let mut seen = std::collections::HashSet::new();
        for entry in PROBLEM_CODES {
            assert!(seen.insert(entry.code), "duplicate code {}", entry.code);
            assert!(!entry.code.is_empty());
            assert!(
                entry.code.split('.').all(|seg| !seg.is_empty()),
                "code {} has an empty segment",
                entry.code
            );
            assert!(
                entry
                    .code
                    .split('.')
                    .all(|seg| seg.chars().all(|c| c.is_ascii_lowercase() || c == '-')),
                "code {} is not lower kebab-case",
                entry.code
            );
            assert!((400..=599).contains(&entry.status), "status out of range");
            assert!(!entry.title.is_empty());
            assert_eq!(
                entry.type_uri(),
                format!("{PROBLEM_DOCS_BASE}/problems/{}", entry.code)
            );
        }
    }

    /// The message key derivation is the documented 1:1 transform.
    #[test]
    fn message_key_is_deterministic() {
        assert_eq!(
            PROBLEM_CODES[0].message_key(),
            format!("problem-{}", PROBLEM_CODES[0].code.replace('.', "-"))
        );
        assert_eq!(
            HTTP_BAD_JSON_BODY.message_key(),
            "problem-http-bad-json-body"
        );
    }

    /// `problem_code` resolves registered codes and rejects unregistered ones.
    #[test]
    fn problem_code_lookup() {
        assert_eq!(
            problem_code("http.route-not-found"),
            Some(&HTTP_ROUTE_NOT_FOUND)
        );
        assert_eq!(problem_code("http.nonexistent"), None);
    }
}
