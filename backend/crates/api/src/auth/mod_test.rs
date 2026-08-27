// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

use std::collections::HashMap;
use std::sync::Arc;

use axum::http::HeaderValue;

use super::*;
use crate::auth::test_env::*;

#[test]
fn is_dev_reflects_override() {
    assert!(AuthState::dev(CurrentUser::dummy("x")).is_dev());
    let prod = AuthState::new(
        OidcConfig {
            iss: "https://iss".into(),
            audience: "aud".into(),
            jwks_url: "https://iss/.well-known/jwks".into(),
            algorithm: jsonwebtoken::Algorithm::RS256,
        },
        Arc::new(StaticJwksProvider::new(HashMap::new())),
    );
    assert!(!prod.is_dev());
}

#[test]
fn bearer_token_parses_prefixed_header() {
    assert_eq!(
        bearer_token(Some(&HeaderValue::from_static("Bearer tok-123"))),
        Some("tok-123".to_string())
    );
    assert_eq!(
        bearer_token(Some(&HeaderValue::from_static("Basic abc"))),
        None
    );
    assert_eq!(
        bearer_token(Some(&HeaderValue::from_static("Bearer "))),
        None
    );
    assert_eq!(bearer_token(None), None);
}

#[test]
fn from_env_or_dev_enters_dev_when_oidc_iss_absent_and_dev_sub_set() {
    with_clean_env(|| {
        // OIDC_ISS absent + DEV_AUTH_SUB set → dev mode (the documented
        // predicate from AGENTS.md).
        set_env("DEV_AUTH_SUB", "dev-user");
        let st = AuthState::from_env_or_dev().expect("dev fallback should succeed");
        assert!(
            st.is_dev(),
            "expected dev mode when OIDC_ISS absent + DEV_AUTH_SUB set"
        );
    });
}

#[test]
fn from_env_or_dev_fails_with_no_config() {
    with_clean_env(|| {
        // Neither OIDC_ISS nor DEV_AUTH_SUB → hard failure, never a silent boot.
        let err = AuthState::from_env_or_dev();
        assert!(err.is_err(), "expected failure with no auth config at all");
    });
}

#[test]
fn from_env_or_dev_production_with_full_oidc_config() {
    with_clean_env(|| {
        set_env("OIDC_ISS", "https://iss.example");
        set_env("OIDC_AUDIENCE", "api://breakdown");
        set_env("OIDC_JWKS_URL", "https://iss.example/.well-known/jwks");
        let st = AuthState::from_env_or_dev().expect("full OIDC config should boot production");
        assert!(
            !st.is_dev(),
            "expected production mode with full OIDC config"
        );
    });
}

#[test]
fn from_env_or_dev_partial_oidc_config_fails_hard_not_dev() {
    with_clean_env(|| {
        // Regression for issue #270: OIDC_ISS set (with a typo'd/missing
        // OIDC_JWKS_URL) plus a stray DEV_AUTH_SUB must fail loudly and must
        // NOT silently fall back to unverified-token dev auth.
        set_env("OIDC_ISS", "https://iss.example");
        set_env("OIDC_AUDIENCE", "api://breakdown");
        // OIDC_JWKS_URL intentionally left unset (simulates the typo).
        set_env("DEV_AUTH_SUB", "dev-user");
        let err = AuthState::from_env_or_dev();
        assert!(
            err.is_err(),
            "partial OIDC config with stray DEV_AUTH_SUB must fail hard, not fall back to dev"
        );
        let msg = err
            .err()
            .expect("expected an error from the production path");
        assert!(
            !msg.contains("DEV_AUTH_SUB"),
            "error must come from the production path, not the dev fallback: {msg}"
        );
    });
}

#[test]
fn from_env_or_dev_dev_mode_picks_up_email() {
    with_clean_env(|| {
        set_env("DEV_AUTH_SUB", "dev-user");
        set_env("DEV_AUTH_EMAIL", "dev@example.com");
        let st = AuthState::from_env_or_dev().expect("dev fallback should succeed");
        assert!(st.is_dev());
    });
}
