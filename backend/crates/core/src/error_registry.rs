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
];

/// Resolve a registry entry by code. The problem builder never emits a code
/// absent from the registry; this lookup exists for tests and for the
/// bundle-coverage lint (Tranche 3).
pub fn problem_code(code: &'static str) -> Option<&'static ProblemCode> {
    PROBLEM_CODES.iter().find(|entry| entry.code == code)
}

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
