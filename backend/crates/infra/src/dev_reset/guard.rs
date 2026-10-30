// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! Prod refusal for the reset tooling (issue #770).
//!
//! The reset deletes business data and — at level `business` — the whole event
//! store. It must be impossible to point it at anything but a local development
//! stack, so the guard is deliberately multi-layered (defence in depth, not a
//! single check):
//!
//! 1. the operator must acknowledge the mode explicitly (`--env dev`),
//! 2. `APP_ENV`, when set, must say `development`/`dev`,
//! 3. `REQUIRE_IN_TRANSIT_TLS=true` (the production TLS gate, ADR-024) refuses,
//! 4. both `DATABASE_URL` and `SIERRADB_URL` must resolve to a loopback host.
//!
//! Every layer is a pure function over a [`DevEnvironment`] so the whole matrix
//! is unit-tested without touching a real database.

/// The environment facts the guard decides on.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DevEnvironment {
    /// `APP_ENV` — unset in the shipped dev flow, so absence is not a refusal.
    pub app_env: Option<String>,
    pub database_url: String,
    pub sierradb_url: String,
    /// `AI_PAYLOAD_S3_ENDPOINT` — the bucket the reset deletes payload objects
    /// from. `None` when AI payload storage is not configured.
    pub ai_payload_endpoint: Option<String>,
    /// `S3_ENDPOINT` — the bucket the reset deletes photo (and report staging)
    /// objects from. `None` when object storage is not configured.
    pub object_storage_endpoint: Option<String>,
    pub require_in_transit_tls: bool,
}

/// Why the tool refuses to run.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Refusal {
    /// `--env dev` was not passed.
    MissingDevAcknowledgement,
    /// `APP_ENV` is set to something that is not a development value.
    AppEnvNotDevelopment { value: String },
    /// The production in-transit TLS gate is armed.
    TransitTlsRequired,
    /// A connection URL does not point at the local machine.
    NonLocalTarget { which: &'static str, host: String },
    /// A connection URL could not be parsed. `value` is **redacted**: the
    /// userinfo is replaced, so a password can never reach the CLI output or a
    /// captured log (issue #770 review).
    UnparseableUrl { which: &'static str, value: String },
}

impl Refusal {
    /// Operator-facing explanation, including what to do about it.
    pub fn reason(&self) -> String {
        match self {
            Self::MissingDevAcknowledgement => {
                "refusing to run without an explicit `--env dev` acknowledgement".to_string()
            }
            Self::AppEnvNotDevelopment { value } => format!(
                "refusing to run with APP_ENV={value}: the reset tooling only runs against a \
                 development stack (APP_ENV=development or unset)"
            ),
            Self::TransitTlsRequired => {
                "refusing to run with REQUIRE_IN_TRANSIT_TLS=true: that is the production TLS \
                 gate (ADR-024), so this is not a development stack"
                    .to_string()
            }
            Self::NonLocalTarget { which, host } => format!(
                "refusing to run against {which} host {host:?}: only loopback targets \
                 (localhost, 127.0.0.0/8, ::1) are allowed"
            ),
            Self::UnparseableUrl { which, value } => {
                format!("cannot parse {which} {value:?} into a host — refusing to guess")
            }
        }
    }
}

impl DevEnvironment {
    /// Reads the environment the API itself boots from.
    pub fn from_env() -> Self {
        Self {
            app_env: std::env::var("APP_ENV").ok(),
            database_url: std::env::var("DATABASE_URL").unwrap_or_default(),
            sierradb_url: std::env::var("SIERRADB_URL").unwrap_or_default(),
            ai_payload_endpoint: non_empty_env("AI_PAYLOAD_S3_ENDPOINT"),
            object_storage_endpoint: non_empty_env("S3_ENDPOINT"),
            require_in_transit_tls: std::env::var("REQUIRE_IN_TRANSIT_TLS")
                .map(|value| value.eq_ignore_ascii_case("true") || value == "1")
                .unwrap_or(false),
        }
    }

    /// The database host the guard resolved (for the confirmation prompt).
    pub fn database_host(&self) -> Option<String> {
        url_host(&self.database_url)
    }

    /// `host/database` — what the operator must retype to confirm.
    pub fn target_label(&self) -> String {
        let host = self.database_host().unwrap_or_else(|| "?".to_string());
        let database = url_database(&self.database_url).unwrap_or_else(|| "?".to_string());
        format!("{host}/{database}")
    }
}

/// Applies every guard layer. `dev_ack` is the `--env dev` acknowledgement.
pub fn check(env: &DevEnvironment, dev_ack: bool) -> Result<(), Refusal> {
    if !dev_ack {
        return Err(Refusal::MissingDevAcknowledgement);
    }
    if let Some(value) = env.app_env.as_deref()
        && !is_development_value(value)
    {
        return Err(Refusal::AppEnvNotDevelopment {
            value: value.to_string(),
        });
    }
    if env.require_in_transit_tls {
        return Err(Refusal::TransitTlsRequired);
    }

    let database_host = url_host(&env.database_url).ok_or_else(|| Refusal::UnparseableUrl {
        which: "DATABASE_URL",
        value: redact_url(&env.database_url),
    })?;
    if !is_loopback(&database_host) {
        return Err(Refusal::NonLocalTarget {
            which: "DATABASE_URL",
            host: database_host,
        });
    }

    let event_store_host = url_host(&env.sierradb_url).ok_or_else(|| Refusal::UnparseableUrl {
        which: "SIERRADB_URL",
        value: redact_url(&env.sierradb_url),
    })?;
    if !is_loopback(&event_store_host) {
        return Err(Refusal::NonLocalTarget {
            which: "SIERRADB_URL",
            host: event_store_host,
        });
    }

    // The reset also **deletes objects**, so the buckets it purges must be local
    // too: a local database with a shared/remote bucket would delete data that
    // is not part of this dev stack (issue #770 review).
    for (which, endpoint) in [
        ("AI_PAYLOAD_S3_ENDPOINT", env.ai_payload_endpoint.as_deref()),
        ("S3_ENDPOINT", env.object_storage_endpoint.as_deref()),
    ] {
        let Some(endpoint) = endpoint else {
            continue;
        };
        let host = url_host(endpoint).ok_or_else(|| Refusal::UnparseableUrl {
            which,
            value: redact_url(endpoint),
        })?;
        if !is_loopback(&host) {
            return Err(Refusal::NonLocalTarget { which, host });
        }
    }

    Ok(())
}

/// Reads an env var, treating an empty value as "not configured".
fn non_empty_env(key: &str) -> Option<String> {
    std::env::var(key)
        .ok()
        .filter(|value| !value.trim().is_empty())
}

/// `development`, `dev` and `local` are the accepted development spellings.
fn is_development_value(value: &str) -> bool {
    matches!(
        value.trim().to_ascii_lowercase().as_str(),
        "development" | "dev" | "local"
    )
}

/// Replaces the userinfo of a connection URL with `***` so a diagnostic can
/// name the URL without leaking a password.
///
/// Works on unparsable input too — it is a string operation, not a parse:
/// everything up to the **last** `@` in the authority is redacted.
pub fn redact_url(url: &str) -> String {
    let Some((scheme, rest)) = url.split_once("://") else {
        return "<unparsable>".to_string();
    };
    let authority_end = rest.find(['/', '?']).unwrap_or(rest.len());
    let (authority, tail) = rest.split_at(authority_end);
    match authority.rsplit_once('@') {
        Some((_, host)) => format!("{scheme}://***@{host}{tail}"),
        None => format!("{scheme}://{authority}{tail}"),
    }
}

/// Extracts the host from a connection URL (`scheme://user:pass@host:port/db`).
pub fn url_host(url: &str) -> Option<String> {
    let (_, rest) = url.split_once("://")?;
    let authority = rest.split(['/', '?']).next()?;
    if authority.is_empty() {
        return None;
    }
    // Strip the userinfo (`user:pass@`), which may itself contain `@`.
    let host_port = match authority.rsplit_once('@') {
        Some((_, host_port)) => host_port,
        None => authority,
    };
    if host_port.is_empty() {
        return None;
    }
    // IPv6 literals keep their brackets so `[::1]` stays recognisable.
    if let Some(stripped) = host_port.strip_prefix('[') {
        let end = stripped.find(']')?;
        return Some(format!("[{}]", &stripped[..end]));
    }
    Some(host_port.split(':').next()?.to_string())
}

/// Extracts the database name from a PostgreSQL URL (`.../breakdown?sslmode=…`).
pub fn url_database(url: &str) -> Option<String> {
    let (_, rest) = url.split_once("://")?;
    let path_start = rest.find('/')?;
    let path = &rest[path_start + 1..];
    let name = path.split(['?', '#']).next()?;
    if name.is_empty() {
        None
    } else {
        Some(name.to_string())
    }
}

/// Loopback detection — the only targets the reset tooling accepts.
pub fn is_loopback(host: &str) -> bool {
    let host = host.trim().trim_end_matches('.');
    if host.eq_ignore_ascii_case("localhost") || host == "[::1]" || host == "::1" {
        return true;
    }
    // 127.0.0.0/8
    match host.split('.').collect::<Vec<_>>().as_slice() {
        ["127", b, c, d] => [b, c, d].iter().all(|octet| octet.parse::<u8>().is_ok()),
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn env(database: &str, event_store: &str) -> DevEnvironment {
        DevEnvironment {
            app_env: None,
            database_url: database.to_string(),
            sierradb_url: event_store.to_string(),
            ai_payload_endpoint: None,
            object_storage_endpoint: None,
            require_in_transit_tls: false,
        }
    }

    fn local() -> DevEnvironment {
        env(
            "postgres://postgres:postgres@localhost:5432/breakdown",
            "redis://127.0.0.1:9090/?protocol=resp3",
        )
    }

    #[test]
    fn local_stack_is_allowed() {
        assert_eq!(check(&local(), true), Ok(()));
    }

    #[test]
    fn missing_acknowledgement_refuses() {
        assert_eq!(
            check(&local(), false),
            Err(Refusal::MissingDevAcknowledgement)
        );
    }

    #[test]
    fn production_app_env_refuses() {
        let mut environment = local();
        environment.app_env = Some("production".to_string());
        assert_eq!(
            check(&environment, true),
            Err(Refusal::AppEnvNotDevelopment {
                value: "production".to_string()
            })
        );
    }

    #[test]
    fn development_app_env_spellings_are_accepted() {
        for value in ["development", "dev", "DEV", " local "] {
            let mut environment = local();
            environment.app_env = Some(value.to_string());
            assert_eq!(check(&environment, true), Ok(()), "value {value:?}");
        }
    }

    #[test]
    fn transit_tls_gate_refuses() {
        let mut environment = local();
        environment.require_in_transit_tls = true;
        assert_eq!(check(&environment, true), Err(Refusal::TransitTlsRequired));
    }

    #[test]
    fn remote_database_refuses() {
        let environment = env(
            "postgres://user:secret@db.prod.internal:5432/breakdown",
            "redis://127.0.0.1:9090/?protocol=resp3",
        );
        assert_eq!(
            check(&environment, true),
            Err(Refusal::NonLocalTarget {
                which: "DATABASE_URL",
                host: "db.prod.internal".to_string()
            })
        );
    }

    #[test]
    fn remote_event_store_refuses() {
        let environment = env(
            "postgres://postgres:postgres@localhost:5432/breakdown",
            "rediss://stunnel:9091/?protocol=resp3",
        );
        assert_eq!(
            check(&environment, true),
            Err(Refusal::NonLocalTarget {
                which: "SIERRADB_URL",
                host: "stunnel".to_string()
            })
        );
    }

    /// A password containing `@` must not be mistaken for the host separator.
    #[test]
    fn password_with_at_sign_does_not_hide_the_host() {
        let environment = env(
            "postgres://user:p@ss@10.1.2.3:5432/breakdown",
            "redis://127.0.0.1:9090/",
        );
        assert_eq!(
            check(&environment, true),
            Err(Refusal::NonLocalTarget {
                which: "DATABASE_URL",
                host: "10.1.2.3".to_string()
            })
        );
    }

    #[test]
    fn empty_urls_refuse_instead_of_defaulting() {
        assert_eq!(
            check(&env("", "redis://127.0.0.1:9090/"), true),
            // An empty URL has no scheme, so the redacted form is the marker.
            Err(Refusal::UnparseableUrl {
                which: "DATABASE_URL",
                value: "<unparsable>".to_string()
            })
        );
    }

    /// A password must never reach the diagnostic (issue #770 review).
    #[test]
    fn unparsable_url_diagnostics_are_redacted() {
        let environment = env(
            "postgres://user:s3cr3t@/breakdown",
            "redis://127.0.0.1:9090/",
        );
        let refusal = check(&environment, true).expect_err("must refuse");
        let message = refusal.reason();
        assert!(!message.contains("s3cr3t"), "password leaked: {message}");
        assert!(
            message.contains("***"),
            "expected a redaction marker: {message}"
        );
    }

    #[test]
    fn redact_url_matrix() {
        assert_eq!(
            redact_url("postgres://user:s3cr3t@localhost:5432/breakdown"),
            "postgres://***@localhost:5432/breakdown"
        );
        assert_eq!(
            redact_url("rediss://user:s3cr3t@host:9091/?protocol=resp3"),
            "rediss://***@host:9091/?protocol=resp3"
        );
        // No userinfo: nothing to redact, the URL stays readable.
        assert_eq!(
            redact_url("postgres://localhost:5432/breakdown"),
            "postgres://localhost:5432/breakdown"
        );
        // Not a URL at all: no scheme, no leak.
        assert_eq!(redact_url("user:s3cr3t"), "<unparsable>");
    }

    #[test]
    fn url_host_variants() {
        assert_eq!(
            url_host("postgres://postgres:postgres@localhost:5432/breakdown").as_deref(),
            Some("localhost")
        );
        assert_eq!(
            url_host("redis://127.0.0.1:9090/?protocol=resp3").as_deref(),
            Some("127.0.0.1")
        );
        assert_eq!(
            url_host("postgres://[::1]:5432/breakdown").as_deref(),
            Some("[::1]")
        );
        assert_eq!(
            url_host("postgres://host/breakdown").as_deref(),
            Some("host")
        );
        assert_eq!(url_host("not-a-url"), None);
        assert_eq!(url_host("postgres://"), None);
    }

    #[test]
    fn url_database_variants() {
        assert_eq!(
            url_database("postgres://postgres:postgres@localhost:5432/breakdown").as_deref(),
            Some("breakdown")
        );
        assert_eq!(
            url_database("postgres://localhost:5432/breakdown?sslmode=disable").as_deref(),
            Some("breakdown")
        );
        assert_eq!(url_database("postgres://localhost:5432/").as_deref(), None);
    }

    #[test]
    fn loopback_matrix() {
        for host in [
            "localhost",
            "LOCALHOST",
            "127.0.0.1",
            "127.10.20.30",
            "[::1]",
            "::1",
        ] {
            assert!(is_loopback(host), "{host} must be loopback");
        }
        for host in [
            "0.0.0.0",
            "10.0.0.1",
            "128.0.0.1",
            "localhost.prod",
            "db.internal",
            "127.0.0.256",
            "",
        ] {
            assert!(!is_loopback(host), "{host} must not be loopback");
        }
    }

    /// A local database with a remote bucket would delete someone else's objects
    /// (issue #770 review).
    #[test]
    fn remote_object_storage_refuses() {
        let mut environment = local();
        environment.ai_payload_endpoint = Some("https://s3.eu-central-1.example.com".to_string());
        assert_eq!(
            check(&environment, true),
            Err(Refusal::NonLocalTarget {
                which: "AI_PAYLOAD_S3_ENDPOINT",
                host: "s3.eu-central-1.example.com".to_string()
            })
        );

        let mut environment = local();
        environment.object_storage_endpoint = Some("http://10.0.0.5:3900".to_string());
        assert_eq!(
            check(&environment, true),
            Err(Refusal::NonLocalTarget {
                which: "S3_ENDPOINT",
                host: "10.0.0.5".to_string()
            })
        );
    }

    #[test]
    fn local_object_storage_is_allowed() {
        let mut environment = local();
        environment.ai_payload_endpoint = Some("http://localhost:3900".to_string());
        environment.object_storage_endpoint = Some("http://127.0.0.1:3900".to_string());
        assert_eq!(check(&environment, true), Ok(()));
    }

    #[test]
    fn unparsable_object_storage_endpoint_is_redacted() {
        let mut environment = local();
        environment.object_storage_endpoint = Some("user:s3cr3t@broken".to_string());
        let refusal = check(&environment, true).expect_err("must refuse");
        assert!(!refusal.reason().contains("s3cr3t"), "{refusal:?}");
    }

    #[test]
    fn target_label_names_host_and_database() {
        assert_eq!(local().target_label(), "localhost/breakdown");
    }
}
