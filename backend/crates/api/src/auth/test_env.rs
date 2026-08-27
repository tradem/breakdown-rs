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

/// Auth-relevant env vars `with_clean_env` manages. Centralized so the
/// snapshot and the clear/restore sets can never drift apart (issue #285).
const AUTH_ENV_VARS: &[&str] = &[
    "OIDC_ISS",
    "OIDC_AUDIENCE",
    "OIDC_JWKS_URL",
    "DEV_AUTH_SUB",
    "DEV_AUTH_EMAIL",
    "AUTHZ_ENFORCE",
];

/// Drop guard that restores each auth env var to the value it had when
/// `with_clean_env` snapshotted it. Restoring in `Drop` (not after `f`)
/// guarantees the original env is reinstated even if `f` panics, so a test
/// cannot leak a value such as `DEV_AUTH_SUB` into a later test (CodeRabbit
/// review, issue #285).
struct EnvRestore {
    saved: Vec<(String, Option<String>)>,
}

#[allow(unsafe_code)] // test-only write; serialized through ENV_LOCK
impl Drop for EnvRestore {
    fn drop(&mut self) {
        for (key, val) in &self.saved {
            // SAFETY: test-only write. No reader observes a torn value because
            // `ENV_LOCK` serializes all env manipulation across the auth test
            // modules, and no leak sanitizer runs under `cargo test`.
            match val {
                Some(v) => unsafe { std::env::set_var(key.as_str(), v.as_str()) },
                None => unsafe { std::env::remove_var(key.as_str()) },
            }
        }
    }
}

/// Snapshot every auth-relevant env var, clear them all, then run `f` while
/// holding the shared env lock so the env-dependent tests never interleave.
/// After `f` returns (or unwinds) the original values are restored via
/// [`EnvRestore`], so a test that sets e.g. `DEV_AUTH_SUB` can never leak it
/// into a later test (CodeRabbit review, issue #285).
pub fn with_clean_env<F, R>(f: F) -> R
where
    F: FnOnce() -> R,
{
    let _guard = ENV_LOCK.lock().unwrap();
    let mut saved = Vec::with_capacity(AUTH_ENV_VARS.len());
    for &var in AUTH_ENV_VARS {
        // Reading env is safe; only writing it is `unsafe` since Rust 1.82.
        saved.push((var.to_string(), std::env::var(var).ok()));
    }
    let _restore = EnvRestore { saved };
    for &var in AUTH_ENV_VARS {
        remove_env(var);
    }
    f()
}
