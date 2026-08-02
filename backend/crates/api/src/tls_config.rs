// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Startup in-transit TLS configuration validation (ADR-024 / issue #156).
//!
//! In production every DB / event-store / object-store link is TLS-encrypted
//! end-to-end and pinned to the internal `step-ca` root:
//!
//! - Postgres links carry `sslmode=verify-full` **and** `sslrootcert=<mounted
//!   step-ca root>` in `DATABASE_URL` / `MIGRATOR_DATABASE_URL`.
//! - The SierraDB link uses the `rediss://` scheme (stunnel sidecar, since
//!   `tqwewe/sierradb:0.3.1` has no native TLS listener — verified against
//!   the upstream sources; see ADR-024 open question).
//! - The Garage S3 link uses `https://` (Caddy internal site) with the
//!   OpenDAL client pinned to the step-ca root via `S3_TLS_ROOT_CERT`.
//! - The Vault link uses `https://` with `VAULT_TLS_ROOT_CERT`, and the
//!   `VAULT_APP_TOKEN_FILE` path must be configured in production.
//!
//! The check is **explicitly opt-in** via `REQUIRE_IN_TRANSIT_TLS=true`
//! (set by `docker-compose.prod.yml`). It is deliberately *not* inferred from
//! `OIDC_ISS`, because the documented dev OIDC overlay (docker-compose.idp.yml)
//! runs the API on the host against plaintext DB URLs — inference would break
//! that local workflow. When the flag is off, dev defaults keep working
//! unchanged; when it is on, a missing `sslmode`, a plaintext `SIERRADB_URL`,
//! or an `http://` `S3_ENDPOINT` fails startup fast with a clear error.

use std::collections::BTreeMap;

/// Connection strings and endpoints the production startup must validate.
#[derive(Debug, Clone, Default)]
pub struct TlsConfig {
    pub database_url: Option<String>,
    pub migrator_database_url: Option<String>,
    pub sierradb_url: Option<String>,
    pub s3_endpoint: Option<String>,
    pub report_backup_endpoint: Option<String>,
    pub report_staging_endpoint: Option<String>,
    pub vault_addr: Option<String>,
    pub vault_app_token_file: Option<String>,
}

impl TlsConfig {
    /// Gather the values from the process environment.
    pub fn from_env() -> Self {
        Self {
            database_url: env_var("DATABASE_URL"),
            migrator_database_url: env_var("MIGRATOR_DATABASE_URL"),
            sierradb_url: env_var("SIERRADB_URL"),
            s3_endpoint: env_var("S3_ENDPOINT"),
            report_backup_endpoint: env_var("REPORT_BACKUP_ENDPOINT"),
            report_staging_endpoint: env_var("REPORT_BACKUP_STAGING_ENDPOINT"),
            vault_addr: env_var("VAULT_ADDR"),
            vault_app_token_file: env_var("VAULT_APP_TOKEN_FILE"),
        }
    }

    /// Run every rule; returns the list of violations (empty = valid).
    pub fn violations(&self) -> Vec<String> {
        let mut out = Vec::new();

        // Postgres links: `sslmode=verify-full` AND a pinned root are both
        // mandatory — verify-full alone would fall back to the system store,
        // which does not contain the internal step-ca root.
        if let Some(db) = self.database_url.as_deref() {
            out.extend(postgres_violations("DATABASE_URL", db));
        }
        let migrator = self
            .migrator_database_url
            .as_deref()
            .filter(|m| !m.is_empty())
            .filter(|m| Some(*m) != self.database_url.as_deref());
        if let Some(m) = migrator {
            out.extend(postgres_violations("MIGRATOR_DATABASE_URL", m));
        }

        // Event-store link: TLS scheme `rediss://` (stunnel sidecar).
        if let Some(url) = self.sierradb_url.as_deref()
            && !url.starts_with("rediss://")
        {
            out.push(format!(
                "SIERRADB_URL must use the TLS scheme 'rediss://' (stunnel sidecar, ADR-024), got: {url}"
            ));
        }

        // Vault links: HTTPS with a separately pinned internal CA. The
        // token path is a configuration contract; the file itself may be
        // populated asynchronously by the bootstrap service.
        match self.vault_addr.as_deref() {
            Some(url) if url.starts_with("https://") => {}
            Some(url) => out.push(format!(
                "VAULT_ADDR must use the TLS scheme 'https://' (internal Vault link, ADR-027), got: {url}"
            )),
            None => out.push(
                "VAULT_ADDR must be set when in-transit TLS is required (ADR-027)".into(),
            ),
        }
        if self.vault_app_token_file.is_none() {
            out.push(
                "VAULT_APP_TOKEN_FILE must be set when in-transit TLS is required (ADR-027)".into(),
            );
        }

        // Object-store links: `https://` (Caddy internal site, ADR-024).
        for (name, url) in [
            ("S3_ENDPOINT", self.s3_endpoint.as_deref()),
            (
                "REPORT_BACKUP_ENDPOINT",
                self.report_backup_endpoint.as_deref(),
            ),
            (
                "REPORT_BACKUP_STAGING_ENDPOINT",
                self.report_staging_endpoint.as_deref(),
            ),
        ] {
            if let Some(url) = url
                && !url.starts_with("https://")
            {
                out.push(format!(
                    "{name} must use the TLS scheme 'https://' (Caddy internal site, ADR-024), got: {url}"
                ));
            }
        }

        out
    }

    /// Convenience: `Ok(())` when valid, `Err` with all violations otherwise.
    pub fn validate(&self) -> Result<(), String> {
        let violations = self.violations();
        if violations.is_empty() {
            Ok(())
        } else {
            Err(format!(
                "in-transit TLS configuration invalid:\n  - {}",
                violations.join("\n  - ")
            ))
        }
    }
}

/// Rules that apply to a single Postgres connection string.
fn postgres_violations(name: &str, url: &str) -> Vec<String> {
    let mut out = Vec::new();
    let params = query_params(url);

    match params.get("sslmode").map(String::as_str) {
        Some("verify-full") => {}
        other => out.push(format!(
            "{name} must set sslmode=verify-full (got {other:?}); plaintext or lax prod DB links are refused (ADR-024)"
        )),
    }

    match params.get("sslrootcert") {
        Some(root) if !root.trim().is_empty() => {}
        _ => out.push(format!(
            "{name} must set sslrootcert=<mounted step-ca root> so the pinned internal CA is used (ADR-024)"
        )),
    }

    out
}

/// Parse `?k1=v1&k2=v2` query params from a connection string.
fn query_params(url: &str) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    let Some(query) = url.split('?').nth(1) else {
        return out;
    };
    for pair in query.split('&').filter(|p| !p.is_empty()) {
        let (k, v) = pair.split_once('=').unwrap_or((pair, ""));
        out.insert(k.to_string(), v.to_string());
    }
    out
}

fn env_var(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.trim().is_empty())
}
