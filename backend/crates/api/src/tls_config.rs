// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.2 (neuralwatt)

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

#[cfg(test)]
mod tests {
    use super::*;

    fn cfg(db: &str, migrator: Option<&str>, sierra: &str, s3: &str) -> TlsConfig {
        TlsConfig {
            database_url: Some(db.into()),
            migrator_database_url: migrator.map(str::to_string),
            sierradb_url: Some(sierra.into()),
            s3_endpoint: Some(s3.into()),
            ..Default::default()
        }
    }

    /// A fully valid production config.
    fn valid() -> TlsConfig {
        cfg(
            "postgres://app:secret@postgres:5432/breakdown?sslmode=verify-full&sslrootcert=/certs/root_ca.crt",
            None,
            "rediss://stunnel:9091/?protocol=resp3",
            "https://caddy:9443",
        )
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
    fn report_backup_endpoints_are_checked() {
        let mut c = valid();
        c.report_backup_endpoint = Some("http://backup.example".into());
        let v = c.violations();
        assert!(
            v.iter().any(|v| v.contains("REPORT_BACKUP_ENDPOINT")),
            "got: {v:?}"
        );
    }

    #[test]
    fn query_params_parses_arbitrary_order() {
        let params =
            query_params("postgres://x?sslrootcert=/certs/root_ca.crt&sslmode=verify-full");
        assert_eq!(
            params.get("sslmode").map(String::as_str),
            Some("verify-full")
        );
        assert_eq!(
            params.get("sslrootcert").map(String::as_str),
            Some("/certs/root_ca.crt")
        );
    }
}
