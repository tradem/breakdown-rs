// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: mimo-v2.5 (opencode-go)

#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
#![allow(unsafe_code)] // test-only env mutation (set_var/remove_var are unsafe in edition 2024)

//! Integration tests for the startup in-transit TLS gate
//! (ADR-024 / issue #156): production connection strings must carry
//! `sslmode=verify-full` + a pinned `sslrootcert`, `SIERRADB_URL` must be
//! `rediss://`, the S3 endpoints must be `https://`, and the AI payload
//! endpoint (issue #201) must be `https://` with a pinned root cert.

use api::tls_config::TlsConfig;

fn cfg(db: &str, migrator: Option<&str>, sierra: &str, s3: &str) -> TlsConfig {
    TlsConfig {
        database_url: Some(db.into()),
        migrator_database_url: migrator.map(str::to_string),
        sierradb_url: Some(sierra.into()),
        s3_endpoint: Some(s3.into()),
        vault_addr: Some("https://vault:8200".into()),
        vault_app_token_file: Some("/run/secrets-vault/app.token".into()),
        ..Default::default()
    }
}

/// A fully valid production config.
fn valid() -> TlsConfig {
    let mut c = cfg(
        "postgres://app:secret@postgres:5432/breakdown?sslmode=verify-full&sslrootcert=/certs/root_ca.crt",
        None,
        "rediss://stunnel:9091/?protocol=resp3",
        "https://caddy:9443",
    );
    c.ai_payload_s3_endpoint = Some("https://caddy:9443".into());
    c.ai_payload_s3_tls_root_cert = Some("/certs/root_ca.crt".into());
    c
}

#[test]
fn valid_production_config_passes() {
    assert_eq!(valid().violations(), Vec::<String>::new());
}

#[test]
fn plaintext_database_url_is_rejected() {
    let c = cfg(
        "postgres://app:secret@postgres:5432/breakdown",
        None,
        "rediss://stunnel:9091/?protocol=resp3",
        "https://caddy:9443",
    );
    let v = c.violations();
    assert!(
        v.iter().any(|v| v.contains("sslmode=verify-full")),
        "expected sslmode violation, got: {v:?}"
    );
    assert!(
        v.iter().any(|v| v.contains("sslrootcert")),
        "expected sslrootcert violation, got: {v:?}"
    );
}

#[test]
fn sslmode_prefer_is_rejected() {
    // verify-prefer / allow / disable all fail the prod gate.
    let c = cfg(
        "postgres://app:secret@postgres:5432/breakdown?sslmode=prefer&sslrootcert=/certs/root_ca.crt",
        None,
        "rediss://stunnel:9091/?protocol=resp3",
        "https://caddy:9443",
    );
    assert!(c.violations().iter().any(|v| v.contains("sslmode")));
}

#[test]
fn missing_pinned_root_is_rejected() {
    let c = cfg(
        "postgres://app:secret@postgres:5432/breakdown?sslmode=verify-full",
        None,
        "rediss://stunnel:9091/?protocol=resp3",
        "https://caddy:9443",
    );
    assert!(c.violations().iter().any(|v| v.contains("sslrootcert")));
}

#[test]
fn query_params_in_any_order_are_accepted() {
    // The validator parses query params order-independently (sslrootcert
    // before sslmode here).
    let mut c = valid();
    c.database_url = Some(
        "postgres://app:secret@postgres:5432/breakdown?sslrootcert=/certs/root_ca.crt&sslmode=verify-full"
            .into(),
    );
    assert_eq!(c.violations(), Vec::<String>::new());
}

#[test]
fn migrator_url_is_checked_independently() {
    let c = cfg(
        "postgres://app:secret@postgres:5432/breakdown?sslmode=verify-full&sslrootcert=/certs/root_ca.crt",
        Some("postgres://migrator:secret@postgres:5432/breakdown"),
        "rediss://stunnel:9091/?protocol=resp3",
        "https://caddy:9443",
    );
    let v = c.violations();
    assert!(
        v.iter().any(|v| v.contains("MIGRATOR_DATABASE_URL")),
        "expected migrator violation, got: {v:?}"
    );
}

#[test]
fn migrator_falling_back_to_database_url_is_fine() {
    // MIGRATOR_DATABASE_URL unset/equal to DATABASE_URL must not double-report.
    let c = cfg(
        "postgres://app:secret@postgres:5432/breakdown?sslmode=verify-full&sslrootcert=/certs/root_ca.crt",
        Some(
            "postgres://app:secret@postgres:5432/breakdown?sslmode=verify-full&sslrootcert=/certs/root_ca.crt",
        ),
        "rediss://stunnel:9091/?protocol=resp3",
        "https://caddy:9443",
    );
    assert_eq!(c.violations(), Vec::<String>::new());
}

#[test]
fn plaintext_sierradb_url_is_rejected() {
    let c = cfg(
        "postgres://app:secret@postgres:5432/breakdown?sslmode=verify-full&sslrootcert=/certs/root_ca.crt",
        None,
        "redis://sierradb:9090/?protocol=resp3",
        "https://caddy:9443",
    );
    let v = c.violations();
    assert!(v.iter().any(|v| v.contains("rediss")), "got: {v:?}");
}

#[test]
fn plaintext_s3_endpoint_is_rejected() {
    let c = cfg(
        "postgres://app:secret@postgres:5432/breakdown?sslmode=verify-full&sslrootcert=/certs/root_ca.crt",
        None,
        "rediss://stunnel:9091/?protocol=resp3",
        "http://garage:3900",
    );
    let v = c.violations();
    assert!(v.iter().any(|v| v.contains("S3_ENDPOINT")), "got: {v:?}");
}

#[test]
fn plaintext_ai_payload_endpoint_is_rejected() {
    let mut c = valid();
    c.ai_payload_s3_endpoint = Some("http://garage:3900".into());
    let v = c.violations();
    assert!(
        v.iter().any(|v| v.contains("AI_PAYLOAD_S3_ENDPOINT")),
        "got: {v:?}"
    );
}

#[test]
fn https_ai_payload_endpoint_without_root_cert_is_rejected() {
    let mut c = valid();
    c.ai_payload_s3_tls_root_cert = None;
    let v = c.violations();
    assert!(
        v.iter().any(|v| v.contains("AI_PAYLOAD_S3_TLS_ROOT_CERT")),
        "got: {v:?}"
    );
}

#[test]
fn unset_ai_payload_storage_is_allowed() {
    // AI payload storage is optional (in-memory fallback in dev); an unset
    // endpoint must not produce a violation.
    let mut c = valid();
    c.ai_payload_s3_endpoint = None;
    c.ai_payload_s3_tls_root_cert = None;
    assert_eq!(c.violations(), Vec::<String>::new());
}

#[test]
fn from_env_populates_ai_payload_fields() {
    // Guard: env mutation is process-global, so restore prior state in all
    // exit paths (set / missing) to avoid leaking into other tests.
    let prior_endpoint = std::env::var("AI_PAYLOAD_S3_ENDPOINT").ok();
    let prior_root_cert = std::env::var("AI_PAYLOAD_S3_TLS_ROOT_CERT").ok();

    unsafe {
        std::env::set_var("AI_PAYLOAD_S3_ENDPOINT", "https://caddy:9443");
        std::env::set_var("AI_PAYLOAD_S3_TLS_ROOT_CERT", "/certs/root_ca.crt");
    }
    let c = TlsConfig::from_env();

    unsafe {
        match prior_endpoint {
            Some(v) => std::env::set_var("AI_PAYLOAD_S3_ENDPOINT", v),
            None => std::env::remove_var("AI_PAYLOAD_S3_ENDPOINT"),
        }
        match prior_root_cert {
            Some(v) => std::env::set_var("AI_PAYLOAD_S3_TLS_ROOT_CERT", v),
            None => std::env::remove_var("AI_PAYLOAD_S3_TLS_ROOT_CERT"),
        }
    }

    assert_eq!(
        c.ai_payload_s3_endpoint.as_deref(),
        Some("https://caddy:9443")
    );
    assert_eq!(
        c.ai_payload_s3_tls_root_cert.as_deref(),
        Some("/certs/root_ca.crt")
    );
}

#[test]
fn plaintext_vault_addr_is_rejected() {
    let mut c = valid();
    c.vault_addr = Some("http://vault:8200".into());
    let v = c.violations();
    assert!(v.iter().any(|v| v.contains("VAULT_ADDR")), "got: {v:?}");
}

#[test]
fn missing_vault_token_path_is_rejected() {
    let mut c = valid();
    c.vault_app_token_file = None;
    let v = c.violations();
    assert!(
        v.iter().any(|v| v.contains("VAULT_APP_TOKEN_FILE")),
        "got: {v:?}"
    );
}

#[test]
fn report_backup_endpoints_are_checked() {
    let mut c = valid();
    c.report_backup_endpoint = Some("http://backup.example".into());
    let v = c.violations();
    assert!(
        v.iter().any(|v| v.contains("REPORT_BACKUP_ENDPOINT")),
        "got: {v:?}"
    );
}

// ---------------------------------------------------------------------------
// P1.5 — validate() returns Err when violations exist
// ---------------------------------------------------------------------------

/// `validate()` must return `Err` when there are violations — kills the
/// `replace validate -> Result<(), String> with Ok(())` mutant.
#[test]
fn validate_returns_err_for_invalid_config() {
    let mut c = valid();
    c.database_url = Some("postgres://app:pass@db:5432/breakdown?sslmode=disable".into());
    let result = c.validate();
    assert!(result.is_err(), "expected Err for invalid config");
    let err = result.unwrap_err();
    assert!(
        err.contains("sslmode=verify-full"),
        "error should mention sslmode, got: {err}"
    );
}

/// `validate()` returns `Ok(())` for a fully valid config.
#[test]
fn validate_returns_ok_for_valid_config() {
    assert!(valid().validate().is_ok());
}

/// `postgres_violations` rejects an empty `sslrootcert` — kills the
/// `replace match guard !root.trim().is_empty() with true` mutant.
#[test]
fn postgres_violations_rejects_empty_sslrootcert() {
    let c = TlsConfig {
        database_url: Some(
            "postgres://app:pass@db:5432/breakdown?sslmode=verify-full&sslrootcert=".into(),
        ),
        ..Default::default()
    };
    let v = c.violations();
    assert!(
        v.iter().any(|v| v.contains("sslrootcert")),
        "expected sslrootcert violation for empty value, got: {v:?}"
    );
}

/// `postgres_violations` rejects whitespace-only `sslrootcert`.
#[test]
fn postgres_violations_rejects_whitespace_sslrootcert() {
    // Use literal spaces (not URL-encoded) since query_params doesn't decode.
    let c = TlsConfig {
        database_url: Some(
            "postgres://app:pass@db:5432/breakdown?sslmode=verify-full&sslrootcert=  ".into(),
        ),
        ..Default::default()
    };
    let v = c.violations();
    assert!(
        v.iter().any(|v| v.contains("sslrootcert")),
        "expected sslrootcert violation for whitespace value, got: {v:?}"
    );
}
