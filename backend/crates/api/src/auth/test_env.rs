// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

//! Shared helpers for auth test modules that read or write process-global
//! environment variables.
//!
//! Env vars are process-global and `cargo test` runs tests in parallel, so any
//! test that touches auth env vars (`OIDC_ISS`, `DEV_AUTH_SUB`, `AUTHZ_ENFORCE`,
//! …) must serialize through the single [`ENV_LOCK`] defined here. A
//! module-local lock would not coordinate across `mod_test`, `authorization_test`,
//! and any future module, reintroducing the exact race this helpers exists to
//! prevent (issue #285).

use std::sync::Mutex;

/// Serializes every env-var mutation across the auth test modules. A single
/// process-global lock — never a per-module one — is required so the modules
/// never interleave their env manipulation.
pub static ENV_LOCK: Mutex<()> = Mutex::new(());

/// `std::env::set_var` is `unsafe` since Rust 1.82 (a concurrent reader can
/// race with leak sanitizers). Localized here; callers serialize via
/// [`ENV_LOCK`].
#[allow(unsafe_code)] // test-only write; serialized through ENV_LOCK
pub fn set_env(key: &str, value: &str) {
    // SAFETY: test-only write. No reader observes a torn value because
    // `ENV_LOCK` serializes all env manipulation across the auth test
    // modules, and no leak sanitizer runs under `cargo test`.
    unsafe { std::env::set_var(key, value) };
}

/// `std::env::remove_var` is `unsafe` (see [`set_env`]).
#[allow(unsafe_code)] // test-only write; serialized through ENV_LOCK
pub fn remove_env(key: &str) {
    // SAFETY: same rationale as `set_env` — test-only, serialized by ENV_LOCK.
    unsafe { std::env::remove_var(key) };
}

/// Clear every auth-relevant env var, then run `f` while holding the shared
/// env lock so the env-dependent tests never interleave.
pub fn with_clean_env<F, R>(f: F) -> R
where
    F: FnOnce() -> R,
{
    let _guard = ENV_LOCK.lock().unwrap();
    for var in [
        "OIDC_ISS",
        "OIDC_AUDIENCE",
        "OIDC_JWKS_URL",
        "DEV_AUTH_SUB",
        "DEV_AUTH_EMAIL",
        "AUTHZ_ENFORCE",
    ] {
        remove_env(var);
    }
    f()
}
