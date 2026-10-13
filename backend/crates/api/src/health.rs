// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

//! Structured health checks (issue #637).
//!
//! A small, `.NET Health Checks`-shaped registry: named dependency checks each
//! report a [`HealthStatus`], and [`HealthRegistry::report`] aggregates them
//! into one [`HealthReport`] with per-check duration and description. The
//! checks are constructed once at the composition root and stored on
//! [`crate::state::AppState`]; the public `GET /v1/health` route renders the
//! report (`200` for `Healthy`/`Degraded`, `503` for `Unhealthy`) so a
//! container/k8s probe and an operator see the same picture.
//!
//! The Vault check is the one this issue exists for: an expired app token used
//! to be indistinguishable from a transient outage, so imports burned their
//! retry budget. Here it is a first-class `Unhealthy` entry.

use std::collections::BTreeMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use async_trait::async_trait;
use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Serialize;
use utoipa::ToSchema;

use crate::state::{AppState, Ports};
use breakdown_core::settings::ports::CredentialVault;

/// Aggregate status of a health report, modelled on .NET's `HealthStatus`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, ToSchema)]
#[serde(rename_all = "PascalCase")]
pub enum HealthStatus {
    /// Every check passed.
    Healthy,
    /// A non-critical check is failing; the API still serves traffic.
    Degraded,
    /// At least one critical dependency is down.
    Unhealthy,
}

impl HealthStatus {
    /// The more severe of two statuses.
    pub const fn worst(self, other: Self) -> Self {
        match (self, other) {
            (Self::Unhealthy, _) | (_, Self::Unhealthy) => Self::Unhealthy,
            (Self::Degraded, _) | (_, Self::Degraded) => Self::Degraded,
            _ => Self::Healthy,
        }
    }

    /// HTTP status a probe should see for this aggregate status.
    pub const fn http_status(self) -> StatusCode {
        match self {
            Self::Healthy | Self::Degraded => StatusCode::OK,
            Self::Unhealthy => StatusCode::SERVICE_UNAVAILABLE,
        }
    }
}

/// Result of one dependency check.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct HealthEntry {
    pub status: HealthStatus,
    /// Wall-clock time the check took, in milliseconds.
    pub duration_ms: u64,
    /// Human-readable failure/success note (static text — never raw error
    /// detail, which could leak internal topology).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    /// Free-form tags (`ready`, `live`, …) for probe selection.
    pub tags: Vec<String>,
}

/// Aggregate health report rendered by `GET /v1/health`.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct HealthReport {
    pub status: HealthStatus,
    pub total_duration_ms: u64,
    pub entries: BTreeMap<String, HealthEntry>,
}

/// What a check returns; the registry stamps the timing and tags.
#[derive(Debug, Clone)]
pub struct HealthCheckOutcome {
    pub status: HealthStatus,
    pub description: Option<String>,
}

impl HealthCheckOutcome {
    pub const fn healthy() -> Self {
        Self {
            status: HealthStatus::Healthy,
            description: None,
        }
    }

    pub fn degraded(description: impl Into<String>) -> Self {
        Self {
            status: HealthStatus::Degraded,
            description: Some(description.into()),
        }
    }

    pub fn unhealthy(description: impl Into<String>) -> Self {
        Self {
            status: HealthStatus::Unhealthy,
            description: Some(description.into()),
        }
    }
}

/// A named dependency check.
#[async_trait]
pub trait HealthCheck: Send + Sync {
    /// Stable entry key in the report (e.g. `postgres`, `vault`).
    fn name(&self) -> &'static str;

    /// Probe-selection tags. Default: none.
    fn tags(&self) -> &'static [&'static str] {
        &[]
    }

    async fn check(&self) -> HealthCheckOutcome;
}

/// Per-check timeout for the public health surface (issue #637).
///
/// `GET /v1/health` is unauthenticated and runs every check; a slow
/// dependency (a blocked pool acquire, a connect with no read timeout) must
/// not stall the probe — or let unauthenticated callers stack slow requests.
/// A check that exceeds this bound is reported `Unhealthy` and the report
/// continues.
const HEALTH_CHECK_TIMEOUT: Duration = Duration::from_secs(2);

/// Registry of checks, built once at the composition root.
#[derive(Clone, Default)]
pub struct HealthRegistry {
    checks: Vec<Arc<dyn HealthCheck>>,
}

impl HealthRegistry {
    pub fn new(checks: Vec<Arc<dyn HealthCheck>>) -> Self {
        Self { checks }
    }

    /// Run every check and aggregate the results.
    ///
    /// The report preserves a stable key order via `BTreeMap`. Checks run
    /// sequentially: each is a bounded probe with its own timeout, and keeping
    /// the loop simple avoids pulling in a futures-join dependency here.
    pub async fn report(&self) -> HealthReport {
        let started = Instant::now();
        let mut entries = BTreeMap::new();
        let mut status = HealthStatus::Healthy;
        for check in &self.checks {
            let check_started = Instant::now();
            let outcome = match tokio::time::timeout(HEALTH_CHECK_TIMEOUT, check.check()).await {
                Ok(outcome) => outcome,
                Err(_) => {
                    tracing::warn!(check = check.name(), "health check timed out");
                    HealthCheckOutcome::unhealthy("health check timed out")
                }
            };
            status = status.worst(outcome.status);
            entries.insert(
                check.name().to_string(),
                HealthEntry {
                    status: outcome.status,
                    duration_ms: check_started.elapsed().as_millis() as u64,
                    description: outcome.description,
                    tags: check.tags().iter().map(|tag| (*tag).to_string()).collect(),
                },
            );
        }
        HealthReport {
            status,
            total_duration_ms: started.elapsed().as_millis() as u64,
            entries,
        }
    }
}

/// `GET /v1/health` — public, unversioned-by-policy readiness surface.
///
/// Public by design (the auth/authorization middleware exempt it): a container
/// probe must not need an OIDC token. It exposes only aggregate dependency
/// status and static descriptions, never credentials or internal addresses.
#[utoipa::path(
    get,
    path = "/health",
    tag = "handlers",
    responses(
        (status = 200, description = "All dependencies healthy or degraded", body = HealthReport),
        (status = 503, description = "At least one dependency is unhealthy", body = HealthReport)
    )
)]
pub async fn get_health<P: Ports>(State(state): State<AppState<P>>) -> Response {
    let report = state.health.report().await;
    (report.status.http_status(), Json(report)).into_response()
}

/// Postgres reachability check.
pub struct PostgresHealthCheck {
    pool: sqlx::PgPool,
}

impl PostgresHealthCheck {
    pub fn new(pool: sqlx::PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl HealthCheck for PostgresHealthCheck {
    fn name(&self) -> &'static str {
        "postgres"
    }

    fn tags(&self) -> &'static [&'static str] {
        &["ready"]
    }

    async fn check(&self) -> HealthCheckOutcome {
        match sqlx::query_scalar::<_, i32>("SELECT 1")
            .fetch_one(&self.pool)
            .await
        {
            Ok(_) => HealthCheckOutcome::healthy(),
            Err(error) => {
                tracing::warn!(%error, "postgres health check failed");
                HealthCheckOutcome::unhealthy("Postgres did not answer a trivial query")
            }
        }
    }
}

/// SierraDB (event store) reachability check: a RESP3 `PING`.
pub struct SierraDbHealthCheck {
    client: Arc<redis::Client>,
}

impl SierraDbHealthCheck {
    pub fn new(client: Arc<redis::Client>) -> Self {
        Self { client }
    }
}

#[async_trait]
impl HealthCheck for SierraDbHealthCheck {
    fn name(&self) -> &'static str {
        "sierradb"
    }

    fn tags(&self) -> &'static [&'static str] {
        &["ready"]
    }

    async fn check(&self) -> HealthCheckOutcome {
        let mut conn = match self.client.get_multiplexed_async_connection().await {
            Ok(conn) => conn,
            Err(error) => {
                tracing::warn!(%error, "sierradb health check could not connect");
                return HealthCheckOutcome::unhealthy("SierraDB connection failed");
            }
        };
        match redis::cmd("PING")
            .query_async::<redis::Value>(&mut conn)
            .await
        {
            Ok(_) => HealthCheckOutcome::healthy(),
            Err(error) => {
                tracing::warn!(%error, "sierradb health check PING failed");
                HealthCheckOutcome::unhealthy("SierraDB did not answer PING")
            }
        }
    }
}

/// Vault reachability **and** app-token validity check (issue #637).
///
/// The distinction matters: a reachable Vault that rejects our token is
/// `Unhealthy` (the credential is the failure), while a reachable Vault whose
/// token probe merely errored transiently is `Degraded`.
pub struct VaultHealthCheck {
    client: Arc<infra::vault::VaultClient>,
}

impl VaultHealthCheck {
    pub fn new(client: Arc<infra::vault::VaultClient>) -> Self {
        Self { client }
    }
}

#[async_trait]
impl HealthCheck for VaultHealthCheck {
    fn name(&self) -> &'static str {
        "vault"
    }

    fn tags(&self) -> &'static [&'static str] {
        &["ready"]
    }

    async fn check(&self) -> HealthCheckOutcome {
        if let Err(error) = self.client.check().await {
            tracing::warn!(%error, "vault health check: Vault unreachable");
            return HealthCheckOutcome::unhealthy("Vault is not reachable");
        }
        match self.client.token_valid().await {
            Ok(()) => HealthCheckOutcome::healthy(),
            Err(breakdown_core::error::DomainError::DependencyAuthFailed { .. }) => {
                HealthCheckOutcome::unhealthy("Vault app token is invalid or expired")
            }
            Err(error) => {
                tracing::warn!(%error, "vault health check: token lookup failed");
                HealthCheckOutcome::degraded(
                    "Vault is reachable but the token could not be verified",
                )
            }
        }
    }
}

/// Garage/S3 AI-payload bucket reachability check.
pub struct AiPayloadStorageHealthCheck {
    storage: Arc<infra::ai::OpenDalAiPayloadStorage>,
}

impl AiPayloadStorageHealthCheck {
    pub fn new(storage: Arc<infra::ai::OpenDalAiPayloadStorage>) -> Self {
        Self { storage }
    }
}

#[async_trait]
impl HealthCheck for AiPayloadStorageHealthCheck {
    fn name(&self) -> &'static str {
        "garage"
    }

    fn tags(&self) -> &'static [&'static str] {
        &["ready"]
    }

    async fn check(&self) -> HealthCheckOutcome {
        match self.storage.health_check().await {
            Ok(()) => HealthCheckOutcome::healthy(),
            Err(error) => {
                tracing::warn!(%error, "garage health check failed");
                HealthCheckOutcome::unhealthy("AI payload storage is not reachable")
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Fixed {
        name: &'static str,
        status: HealthStatus,
    }

    #[async_trait]
    impl HealthCheck for Fixed {
        fn name(&self) -> &'static str {
            self.name
        }

        async fn check(&self) -> HealthCheckOutcome {
            HealthCheckOutcome {
                status: self.status,
                description: None,
            }
        }
    }

    #[tokio::test]
    async fn aggregate_status_is_the_worst_of_all_checks() {
        let registry = HealthRegistry::new(vec![
            Arc::new(Fixed {
                name: "a",
                status: HealthStatus::Healthy,
            }),
            Arc::new(Fixed {
                name: "b",
                status: HealthStatus::Degraded,
            }),
            Arc::new(Fixed {
                name: "c",
                status: HealthStatus::Unhealthy,
            }),
        ]);
        let report = registry.report().await;
        assert_eq!(report.status, HealthStatus::Unhealthy);
        assert_eq!(report.entries.len(), 3);
        assert_eq!(report.entries["b"].status, HealthStatus::Degraded);
        assert_eq!(report.status.http_status(), StatusCode::SERVICE_UNAVAILABLE);
    }

    #[tokio::test]
    async fn healthy_registry_answers_200() {
        let registry = HealthRegistry::new(vec![Arc::new(Fixed {
            name: "a",
            status: HealthStatus::Healthy,
        })]);
        let report = registry.report().await;
        assert_eq!(report.status, HealthStatus::Healthy);
        assert_eq!(report.status.http_status(), StatusCode::OK);
    }

    struct Hanging;

    #[async_trait]
    impl HealthCheck for Hanging {
        fn name(&self) -> &'static str {
            "hanging"
        }

        async fn check(&self) -> HealthCheckOutcome {
            // Far longer than the probe timeout; with paused time this resolves
            // only if the timeout fails to fire.
            tokio::time::sleep(Duration::from_secs(3600)).await;
            HealthCheckOutcome::healthy()
        }
    }

    #[tokio::test(start_paused = true)]
    async fn a_check_that_exceeds_the_timeout_is_unhealthy() {
        let registry = HealthRegistry::new(vec![Arc::new(Hanging)]);
        let report = registry.report().await;
        assert_eq!(report.status, HealthStatus::Unhealthy);
        assert_eq!(report.entries["hanging"].status, HealthStatus::Unhealthy);
    }
}
