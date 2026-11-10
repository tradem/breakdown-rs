// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! The recovery probe (issue #871, D-A3).
//!
//! **Why this must exist:** a breaker that only opens is a one-way door. Once a
//! pair is `open`, no job of it is claimed (D-A2), so no paid call runs, so
//! `record_success` never fires — the pair would stay dead until an operator
//! intervened. The probe is the only thing that can end a non-`closed` state.
//!
//! **Why it is cheap:** it is the model-catalog read the AI-config screen already
//! uses (`GET {base}/models`), which costs no tokens. Reactive-only detection
//! would need a canary job that pays to learn the endpoint recovered — exactly
//! what the breaker exists to stop.
//!
//! **Why it needs a donor job:** the probe needs a usable credential, and the
//! only legitimate source is a worker's own key for its own job — never a
//! synthetic or shared one. The donor is one **actively held** job of the pair;
//! a pair with no held job has nobody to probe for, which is correct: nothing is
//! waiting on it. Its identity is selected once and kept (the log line names it),
//! never re-derived, because "a job of that user" would be a different job as
//! soon as the first one expired.
//!
//! **Why the probe is not a claimed job:** only `closed` admits a claim, so no
//! worker runs for the pair when the probe becomes due. It is a CAS'd task in the
//! sweeper family: lease → request outside any transaction → fenced result.
//! Never one transaction across the network call, or a hung probe would hold the
//! row lock and lock out the very takeover the lease exists to allow.
//!
//! **Why it judges reachability only:** a probe result is a verdict about the
//! *endpoint*, never about a document. It never retires or terminalizes a job —
//! a job whose own credential is dead is claimed, fails with
//! `dependency.auth-failed` through the existing permanent path (#637), and
//! terminalizes itself with the honest code the client already localizes.

use std::time::Duration;

use async_trait::async_trait;
use breakdown_core::ai::DocumentKind;
use breakdown_core::ai::ports::{LlmModelCatalog, LlmProvider, ProbeOutcome, ProviderHealth};
use breakdown_core::settings::CredentialVault;
use breakdown_core::shared::UserId;
use chrono::Utc;
use serde::Deserialize;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use super::CuratedProviderUrls;
use super::catalog::OpenAiCompatibleModelCatalog;
use super::provider_watch::PROVIDER_UNAVAILABLE_CODE;
use crate::queries::ai_config::AiConfigRepositoryImpl;

/// How many donor jobs one tick may try for one pair. A pair whose held jobs all
/// have unusable credentials is not probed forever: the bound keeps one tick
/// from turning into a credential sweep.
pub const PROBE_CANDIDATE_LIMIT: i64 = 3;

/// The identity of the job whose credential a probe may use.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DonorJob {
    pub id: Uuid,
    pub user_id: UserId,
    pub document_kind: DocumentKind,
}

/// The HTTP verdict of one probe, as a seam so the tick is testable without a
/// network (D-X4).
#[async_trait]
pub trait ProviderProbe: Send + Sync {
    /// Whether the endpoint for `provider` answers, using `donor`'s credential.
    ///
    /// Reachability only: `Reachable` means "the endpoint answered", which
    /// includes a credential rejection — a restricted key may hold
    /// `chat.completions` without `models.read`, and a key may even be replaced
    /// while the request is in flight.
    async fn probe(&self, provider: LlmProvider, donor: &DonorJob) -> ProbeOutcome;
}

/// The production probe: the model catalog for hosted providers, an
/// unauthenticated `GET /api/tags` for Ollama.
pub struct CatalogProviderProbe {
    catalog: OpenAiCompatibleModelCatalog,
    configs: AiConfigRepositoryImpl,
    credentials: std::sync::Arc<dyn CredentialVault>,
    http: reqwest::Client,
}

impl CatalogProviderProbe {
    /// The local-only HTTP client the Ollama probe uses.
    ///
    /// Same policy as every other local provider call (issue #170): the curated
    /// Ollama origin is plain HTTP, so the redirect policy pins it and no proxy
    /// is consulted. No credential is attached — that is the whole point of the
    /// split.
    pub fn local_http_client(
        timeout: Duration,
    ) -> Result<reqwest::Client, breakdown_core::error::DomainError> {
        reqwest::Client::builder()
            .timeout(timeout)
            .redirect(super::transport::curated_provider_redirect_policy())
            .no_proxy()
            .user_agent(super::user_agent::resolve_user_agent(LlmProvider::Ollama))
            .build()
            .map_err(|error| {
                breakdown_core::error::DomainError::service_unavailable(format!(
                    "could not build the local provider probe client: {error}"
                ))
            })
    }

    /// Build the probe.
    ///
    /// `http` is the local-only client used for Ollama: the curated base URL is
    /// plain HTTP and has **no** credential, so the hosted catalog client —
    /// which requires a non-empty key and always sends a bearer token — can
    /// neither probe it nor be allowed to try (that would leak a token to a
    /// plain-HTTP origin, CWE-319).
    pub fn new(
        catalog: OpenAiCompatibleModelCatalog,
        configs: AiConfigRepositoryImpl,
        credentials: std::sync::Arc<dyn CredentialVault>,
        http: reqwest::Client,
    ) -> Self {
        Self {
            catalog,
            configs,
            credentials,
            http,
        }
    }
}

#[derive(Deserialize)]
struct OllamaTags {
    #[serde(default)]
    #[allow(dead_code)] // the body is irrelevant; a decodable answer is the signal
    models: Vec<serde_json::Value>,
}

#[async_trait]
impl ProviderProbe for CatalogProviderProbe {
    async fn probe(&self, provider: LlmProvider, donor: &DonorJob) -> ProbeOutcome {
        if provider.is_local() {
            // Unauthenticated on purpose: no vault read at all on this path.
            let url = format!(
                "{}/api/tags",
                <CuratedProviderUrls as breakdown_core::ai::CuratedLlmProvider>::base_url(provider)
            );
            return match self.http.get(url).send().await {
                Ok(response) if response.status().is_success() => {
                    match response.json::<OllamaTags>().await {
                        Ok(_) => ProbeOutcome::Reachable,
                        Err(error) => {
                            tracing::warn!(
                                error = %error,
                                "#871 probe: Ollama answered but the body did not decode"
                            );
                            ProbeOutcome::Unreachable
                        }
                    }
                }
                Ok(response) => {
                    tracing::warn!(
                        status = %response.status(),
                        "#871 probe: Ollama endpoint rejected the probe"
                    );
                    ProbeOutcome::Unreachable
                }
                Err(error) => {
                    tracing::warn!(error = %error, "#871 probe: Ollama endpoint unreachable");
                    ProbeOutcome::Unreachable
                }
            };
        }

        // Hosted: the donor's own config names the vault binding. A donor whose
        // config is gone cannot supply a credential.
        let config = match self
            .configs
            .find_worker_config(&donor.user_id, donor.document_kind)
            .await
        {
            Ok(Some(config)) => config,
            Ok(None) => {
                tracing::warn!(
                    donor_job = %donor.id,
                    "#871 probe: donor job has no active AI configuration"
                );
                return local_credential_outcome();
            }
            Err(error) => {
                tracing::warn!(
                    donor_job = %donor.id,
                    error = %error,
                    "#871 probe: could not resolve the donor's AI configuration"
                );
                return local_credential_outcome();
            }
        };
        // The binding key names the SETTINGS credential that owns the secret;
        // recover the owner from the key itself (the `fetch_credential`
        // discipline in `worker_loop`).
        let Some(owner) = crate::vault::settings_id_from_binding_key(&config.vault_key_id) else {
            tracing::warn!(
                donor_job = %donor.id,
                "#871 probe: donor's vault key reference is malformed"
            );
            return local_credential_outcome();
        };
        let key = match self.credentials.fetch(owner, &config.vault_key_id).await {
            Ok(key) => key,
            Err(error) => {
                tracing::warn!(
                    donor_job = %donor.id,
                    error = %error,
                    "#871 probe: could not read the donor's credential"
                );
                return local_credential_outcome();
            }
        };
        match self.catalog.list(provider, key.as_str()).await {
            Ok(_) => ProbeOutcome::Reachable,
            Err(error) => classify_catalog_error(provider, &error),
        }
    }
}

/// A probe that could not obtain a credential **locally**.
///
/// Not a provider verdict, and therefore not grounds to stay open: holding every
/// job of the pair hostage to one user's missing key is precisely the "one user's
/// misconfiguration becomes an outage" failure D-A1 forbids. Closing is safe
/// because the affected job's own attempt then fails with the honest
/// `dependency.auth-failed` through the permanent path (#637) — the same
/// reasoning the design applies to a 401/403.
fn local_credential_outcome() -> ProbeOutcome {
    tracing::warn!(
        "#871 probe: no usable credential for the donor job — closing the breaker without a provider verdict"
    );
    ProbeOutcome::Reachable
}

/// Map a catalog failure onto reachability (D-A3's outcome table).
///
/// A credential rejection (401/403, or an entitlement 4xx) means the endpoint
/// **answered** — that is what the probe measures. A transport error, a timeout,
/// a 429 or a 5xx is the outage the breaker exists for.
fn classify_catalog_error(
    provider: LlmProvider,
    error: &breakdown_core::error::DomainError,
) -> ProbeOutcome {
    use breakdown_core::error::DomainError;
    match error {
        DomainError::DependencyAuthFailed { .. } | DomainError::Forbidden { .. } => {
            tracing::warn!(
                provider = provider.as_str(),
                "#871 probe: catalog credential rejected (401/403) — the endpoint answered"
            );
            ProbeOutcome::Reachable
        }
        DomainError::ServiceUnavailable { .. } => {
            tracing::warn!(
                provider = provider.as_str(),
                error = %error,
                "#871 probe: endpoint still unavailable"
            );
            ProbeOutcome::Unreachable
        }
        // A validation failure means the request could not even be formed (e.g.
        // an empty key): a local problem, handled like a missing credential.
        DomainError::Validation { .. } => local_credential_outcome(),
        // Anything else is not a reachability verdict; stay conservative and
        // keep the breaker open rather than resume paying into an unknown state.
        other => {
            tracing::warn!(
                provider = provider.as_str(),
                error = %other,
                "#871 probe: unclassified probe failure — staying open"
            );
            ProbeOutcome::Unreachable
        }
    }
}

/// Run the probe half of one watch tick.
///
/// For every non-`closed` pair whose probe is due: take the lease, select a
/// donor, ask the probe (outside any transaction), write the fenced result.
/// Returns how many probes ran.
pub async fn run_probes(
    pool: &PgPool,
    health: &dyn ProviderHealth,
    probe: &dyn ProviderProbe,
    owner: &str,
) -> Result<usize, breakdown_core::error::DomainError> {
    let mut probed = 0usize;
    for breaker in health.open_breakers(PROBE_TICK_PAIR_LIMIT).await? {
        // Only pairs whose window has elapsed are due; `try_begin_probe` is the
        // authority, this only avoids a pointless donor query.
        let Some(retry_at) = breaker.retry_at else {
            continue;
        };
        if retry_at > Utc::now() {
            continue;
        }
        let donors = donor_jobs(pool, breaker.provider, &breaker.model).await?;
        if donors.is_empty() {
            // Nobody is waiting on this pair: no credential to probe with, and
            // nothing to resume. It closes lazily on the next real call.
            tracing::debug!(
                provider = breaker.provider.as_str(),
                model = breaker.model,
                "#871 probe: no active held job — nothing to probe for"
            );
            continue;
        }
        let Some(lease) = health
            .try_begin_probe(breaker.provider, &breaker.model, owner)
            .await?
        else {
            // Another tick owns the lease, or the breaker moved on.
            continue;
        };
        let mut outcome = ProbeOutcome::Unreachable;
        for donor in donors.iter().take(PROBE_CANDIDATE_LIMIT as usize) {
            // Step 2: the request, outside any transaction.
            outcome = probe.probe(breaker.provider, donor).await;
            tracing::warn!(
                provider = breaker.provider.as_str(),
                model = breaker.model,
                donor_job = %donor.id,
                outcome = ?outcome,
                "#871 provider breaker: probe result"
            );
            if outcome == ProbeOutcome::Reachable {
                break;
            }
        }
        // Step 3: the fenced result write. A stale lease is discarded inside.
        match health.finish_probe(&lease, outcome).await {
            Ok(decision) => {
                probed += 1;
                if decision.closed {
                    // A close releases the pair's held jobs: they are claimable
                    // again through their own (now past) `next_attempt_at`.
                    tracing::warn!(
                        provider = breaker.provider.as_str(),
                        model = breaker.model,
                        "#871 provider breaker: closed after a successful probe"
                    );
                }
            }
            Err(error) => {
                tracing::debug!(
                    provider = breaker.provider.as_str(),
                    model = breaker.model,
                    error = %error,
                    "#871 probe: result discarded (stale lease)"
                );
            }
        }
    }
    Ok(probed)
}

/// How many degraded pairs one probe tick examines.
const PROBE_TICK_PAIR_LIMIT: i64 = 8;

/// The donor: one **actively held** job of the pair, newest first so a fresh
/// upload's credential is preferred over a long-held one.
///
/// The `state` predicate matters: the terminal expiry marker also leaves
/// `provider_hold` non-null, and an expired job must never be a credential donor.
async fn donor_jobs(
    pool: &PgPool,
    provider: LlmProvider,
    model: &str,
) -> Result<Vec<DonorJob>, breakdown_core::error::DomainError> {
    let rows = sqlx::query(
        r#"
        SELECT id, user_id, document_kind
        FROM ai_import.ai_import_job
        WHERE breaker_provider = $1
          AND breaker_model = $2
          AND status = 'failed'
          AND provider_hold IS NOT NULL
          AND (provider_hold ->> 'state') IN ('open', 'half_open')
        ORDER BY created_at DESC
        LIMIT $3
        "#,
    )
    .bind(provider.as_str())
    .bind(model)
    .bind(PROBE_CANDIDATE_LIMIT)
    .fetch_all(pool)
    .await
    .map_err(|error| {
        breakdown_core::error::DomainError::service_unavailable(format!("database error: {error}"))
    })?;
    let mut donors = Vec::with_capacity(rows.len());
    for row in rows {
        let kind = match row.try_get::<String, _>("document_kind").ok().as_deref() {
            Some("script") => DocumentKind::Script,
            Some("schedule") => DocumentKind::Schedule,
            other => {
                tracing::warn!(kind = ?other, "#871 probe: unknown document kind on donor job");
                continue;
            }
        };
        donors.push(DonorJob {
            id: row.try_get("id").map_err(|error| {
                breakdown_core::error::DomainError::service_unavailable(format!(
                    "database error: {error}"
                ))
            })?,
            user_id: UserId::from_sub(row.try_get::<String, _>("user_id").map_err(|error| {
                breakdown_core::error::DomainError::service_unavailable(format!(
                    "database error: {error}"
                ))
            })?),
            document_kind: kind,
        });
    }
    Ok(donors)
}

/// The probe request timeout, exported for the watch's own budgeting.
#[must_use]
pub const fn probe_timeout() -> Duration {
    Duration::from_secs(super::provider_health::probe_lease_window().as_secs())
}

/// The registered code the hold carries, re-exported so the probe module and the
/// watch cannot drift on the string the client branches on.
pub const fn provider_unavailable_code() -> &'static str {
    PROVIDER_UNAVAILABLE_CODE
}

#[cfg(test)]
mod tests {
    use super::*;
    use breakdown_core::error::DomainError;

    #[test]
    fn a_storage_outage_is_the_outage_the_breaker_tracks() {
        let outcome = classify_catalog_error(
            LlmProvider::OpenCodeGo,
            &DomainError::service_unavailable("HTTP 503"),
        );
        assert_eq!(outcome, ProbeOutcome::Unreachable);
    }

    #[test]
    fn a_local_request_problem_closes_the_breaker() {
        // The request could not even be formed (e.g. an empty key reference).
        // Holding every job of the pair hostage to one user's local
        // misconfiguration is the failure mode D-A1 forbids, and the affected
        // job's own attempt still surfaces the honest dependency code.
        let outcome = classify_catalog_error(
            LlmProvider::OpenCodeGo,
            &DomainError::validation("AI config vault key reference is malformed"),
        );
        assert_eq!(outcome, ProbeOutcome::Reachable);
    }

    #[test]
    fn the_probe_timeout_matches_the_lease() {
        // A probe must not outlive the lease it holds: otherwise its own result
        // would always arrive stale.
        assert_eq!(
            probe_timeout(),
            super::super::provider_health::probe_lease_window()
        );
    }
}
