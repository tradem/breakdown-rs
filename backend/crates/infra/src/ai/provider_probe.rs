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
//! **Why it is cheap:** it is a zero-token read — `GET {base}/key` where the
//! provider documents one, an unauthenticated `GET /api/tags` for Ollama, and no
//! request at all where neither exists (the window alone grants the trial).
//! Reactive-only detection would need a canary job that pays to learn the
//! endpoint recovered — exactly what the breaker exists to stop.
//!
//! **Why it is capability-accurate (issue #942 W1/F2):** the former probe read
//! the model catalog (`GET {base}/models`), which EURouter serves *publicly* — a
//! bogus bearer token is answered `200` in 0.2 s, so the probe could not see a
//! dead credential at all. The replacement measures what actually matters before
//! spending money: does **this account** still hold a usable credential and a
//! positive budget. It still does not prove the model's chat path — which is
//! exactly why a pass grants one un-retried trial instead of closing the breaker.
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

use async_trait::async_trait;
use breakdown_core::ai::DocumentKind;
use breakdown_core::ai::ports::AiImportQueue as _;
use breakdown_core::ai::ports::{LlmProvider, ProbeOutcome, ProviderHealth};
use breakdown_core::ai::{ProbeCapability, probe_capability};
use breakdown_core::settings::CredentialVault;
use breakdown_core::shared::UserId;
use jiff::Timestamp;
use serde::Deserialize;
use sqlx::{PgPool, Row};
use std::time::Duration;
use uuid::Uuid;

use super::CuratedProviderUrls;
use super::provider_watch::PROVIDER_UNAVAILABLE_CODE;
use super::queue::PgAiImportQueue as PgQueue;
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
    configs: AiConfigRepositoryImpl,
    credentials: std::sync::Arc<dyn CredentialVault>,
    http: reqwest::Client,
    /// The hosted `/key` client (issue #942 W1): curated redirect policy, no
    /// proxy, the same transport rules as every provider call (ADR-024).
    /// `None` when it could not be built — the probe then reports `NotUsable`
    /// rather than probing through a client without those rules.
    hosted: Option<reqwest::Client>,
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
        configs: AiConfigRepositoryImpl,
        credentials: std::sync::Arc<dyn CredentialVault>,
        http: reqwest::Client,
    ) -> Self {
        // A short, hard timeout: this read runs inside a watch tick and must
        // never become the thing that delays a probe window.
        let hosted = reqwest::Client::builder()
            .timeout(probe_timeout())
            .redirect(super::transport::curated_provider_redirect_policy())
            .no_proxy()
            .build()
            .ok();
        Self {
            configs,
            credentials,
            http,
            hosted,
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
        // Issue #942 W1: the curated capability decides, not the provider family.
        // A provider without a verified zero-token endpoint is not probed at all —
        // the elapsed window is the signal, and the single trial call is the
        // measurement.
        if probe_capability(provider) == ProbeCapability::NoPreflight {
            tracing::warn!(
                provider = provider.as_str(),
                "#942 probe: no verified zero-token endpoint — granting the time-gated trial"
            );
            return ProbeOutcome::Usable;
        }
        if provider.is_local() {
            // Unauthenticated on purpose: no vault read at all on this path.
            let url = ollama_probe_url(provider);
            return match self.http.get(url).send().await {
                Ok(response) if response.status().is_success() => {
                    match response.json::<OllamaTags>().await {
                        Ok(_) => ProbeOutcome::Usable,
                        Err(error) => {
                            tracing::warn!(
                                error = %error,
                                "#871 probe: Ollama answered but the body did not decode"
                            );
                            ProbeOutcome::NotUsable
                        }
                    }
                }
                Ok(response) => {
                    tracing::warn!(
                        status = %response.status(),
                        "#871 probe: Ollama endpoint rejected the probe"
                    );
                    ProbeOutcome::NotUsable
                }
                Err(error) => {
                    tracing::warn!(error = %error, "#871 probe: Ollama endpoint unreachable");
                    ProbeOutcome::NotUsable
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
        let Some(client) = &self.hosted else {
            tracing::warn!(
                provider = provider.as_str(),
                "#942 probe: no policy-compliant HTTP client — staying open instead of probing without the transport rules"
            );
            return ProbeOutcome::NotUsable;
        };
        self.probe_key_endpoint(provider, client, key.as_str())
            .await
    }
}

/// The body of a provider's `GET {base}/key` (OpenRouter-shaped).
#[derive(Deserialize)]
struct KeyBudget {
    #[serde(default)]
    data: Option<KeyBudgetData>,
}

#[derive(Deserialize)]
struct KeyBudgetData {
    /// `None` means "no limit configured" — a usable account.
    #[serde(default)]
    limit_remaining: Option<f64>,
}

impl KeyBudget {
    /// The remaining budget, when the provider reports one.
    fn remaining(&self) -> Option<f64> {
        self.data.as_ref().and_then(|data| data.limit_remaining)
    }
}

impl CatalogProviderProbe {
    /// `GET {base}/key` — the account-scoped usability preflight (issue #942 W1).
    ///
    /// The verdict table, in the order it is applied:
    ///
    /// | response | verdict | why |
    /// |---|---|---|
    /// | `200` + `limit_remaining <= 0` | `NotUsable` | the account cannot pay |
    /// | `200` (any shape, incl. unparsable) | `Usable` | the credential was accepted — the one thing this read proves |
    /// | `401`/`402`/`403` | `NotUsable` | dead or unpaid credential (F2: the old `/models` read answered `200` here) |
    /// | any other status | `NotUsable` | unknown — never resume paying on an unknown |
    /// | transport error / timeout | `NotUsable` | the outage the breaker exists for |
    ///
    /// A `200` never closes the breaker: it grants one un-retried trial, because
    /// a healthy account does not prove a healthy `(provider, model)` chat path.
    async fn probe_key_endpoint(
        &self,
        provider: LlmProvider,
        client: &reqwest::Client,
        key: &str,
    ) -> ProbeOutcome {
        let url = key_probe_url(provider);
        let response = match client
            .get(&url)
            .bearer_auth(key)
            .header(
                reqwest::header::USER_AGENT,
                super::user_agent::resolve_user_agent(provider),
            )
            .send()
            .await
        {
            Ok(response) => response,
            Err(error) => {
                tracing::warn!(
                    provider = provider.as_str(),
                    error = %error,
                    "#942 probe: /key request failed — staying open"
                );
                return ProbeOutcome::NotUsable;
            }
        };
        let status = response.status();
        if !status.is_success() {
            tracing::warn!(
                provider = provider.as_str(),
                status = %status,
                "#942 probe: /key rejected the credential (an unused `/models` read answers 200 here)",
            );
            return ProbeOutcome::NotUsable;
        }
        match response.json::<KeyBudget>().await {
            Ok(budget) => match budget.remaining() {
                Some(remaining) if remaining <= 0.0 => {
                    tracing::warn!(
                        provider = provider.as_str(),
                        remaining,
                        "#942 probe: /key reports no budget left"
                    );
                    ProbeOutcome::NotUsable
                }
                other => {
                    tracing::warn!(
                        provider = provider.as_str(),
                        limit_remaining = ?other,
                        "#942 probe: /key accepted the credential — granting one trial"
                    );
                    ProbeOutcome::Usable
                }
            },
            Err(error) => {
                // A `200` whose body we cannot read still proves the credential
                // was accepted, which is the strongest honest verdict available.
                tracing::warn!(
                    provider = provider.as_str(),
                    error = %error,
                    "#942 probe: /key answered 200 with an unreadable body — treating the credential as accepted"
                );
                ProbeOutcome::Usable
            }
        }
    }
}

/// `{base}/key` for the providers whose capability is
/// [`ProbeCapability::KeyEndpoint`].
///
/// Built from the curated base URL only — never from user input (ADR-024 SSRF
/// policy) — and exported so a test asserts on THIS function rather than on an
/// independently constructed expectation.
#[must_use]
pub fn key_probe_url(provider: LlmProvider) -> String {
    format!(
        "{}/key",
        <CuratedProviderUrls as breakdown_core::ai::CuratedLlmProvider>::base_url(provider)
    )
}

/// The URL the Ollama probe requests (issue #871).
///
/// A **shared builder** rather than an inline `format!`: the curated Ollama base
/// URL already ends in `/api` (`http://ollama:11434/api`), so appending
/// `/api/tags` would request `/api/api/tags` — a 404 the probe reads as
/// `Unreachable`, which would mean an Ollama breaker could never close and every
/// held job would dead-letter at its deadline even after Ollama recovered. The
/// test asserts on THIS function, so a regression in the probe cannot pass while
/// an independently constructed expectation stays green.
#[must_use]
pub fn ollama_probe_url(provider: LlmProvider) -> String {
    format!(
        "{}/tags",
        <CuratedProviderUrls as breakdown_core::ai::CuratedLlmProvider>::base_url(provider)
    )
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
        "#942 probe: no usable credential for the donor job — granting the time-gated trial instead of holding the pair hostage"
    );
    // Unchanged direction since #871: one user's missing key must never hold
    // every job of the pair (D-A1). The single trial still costs at most one
    // call, and that job then fails with the honest `dependency.auth-failed`.
    ProbeOutcome::Usable
}

/// Run the probe half of one watch tick.
///
/// For every non-`closed` pair whose probe is due: take the lease, select a
/// donor, ask the probe (outside any transaction), write the fenced result.
/// Returns how many probes ran.
pub async fn run_probes(
    pool: &PgPool,
    health: &dyn ProviderHealth,
    queue: &PgQueue,
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
        if retry_at > Timestamp::now() {
            continue;
        }
        // Issue #942 W1: a `half_open` pair whose last trial was consumed and
        // did NOT close the breaker (the paid call failed terminally, e.g. a
        // revoked key) has no holder. The elapsed window is the only gate left,
        // so the next single trial is granted directly — no metadata probe is
        // repeated, because `try_begin_probe` CASes from `open` only and the
        // trial call is the measurement that matters.
        if breaker.state == breakdown_core::ai::views::ProviderBreakerState::HalfOpen
            && breaker.trial_job.is_none()
        {
            match health
                .begin_provider_trial(breaker.provider, &breaker.model)
                .await?
            {
                Some(job) => tracing::warn!(
                    provider = breaker.provider.as_str(),
                    model = breaker.model,
                    trial_job = %job.as_uuid(),
                    "#942 provider breaker: window elapsed — next single trial granted"
                ),
                None => tracing::debug!(
                    provider = breaker.provider.as_str(),
                    model = breaker.model,
                    "#942 provider breaker: no holder and nobody waiting"
                ),
            }
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
        let mut outcome = ProbeOutcome::NotUsable;
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
            if outcome == ProbeOutcome::Usable {
                break;
            }
        }
        // Step 3: the fenced result write. A stale lease is discarded inside.
        match health.finish_probe(&lease, outcome).await {
            Ok(decision) => {
                probed += 1;
                if decision.trial_due {
                    // Issue #942 W1: a passing preflight opens the single-trial
                    // door — it does NOT close the breaker. One waiting job runs
                    // one un-retried call; only that call can close it.
                    // The grant is a `ProviderHealth` write (it stamps the
                    // breaker's token and makes the chosen job claimable again),
                    // so it goes through the port that owns that row.
                    match health
                        .begin_provider_trial(breaker.provider, &breaker.model)
                        .await?
                    {
                        Some(job) => tracing::warn!(
                            provider = breaker.provider.as_str(),
                            model = breaker.model,
                            trial_job = %job.as_uuid(),
                            "#942 provider breaker: preflight passed — one trial call granted"
                        ),
                        None => tracing::debug!(
                            provider = breaker.provider.as_str(),
                            model = breaker.model,
                            "#942 provider breaker: preflight passed, nobody waiting for the trial"
                        ),
                    }
                }
                if decision.closed {
                    // A close releases the pair's held jobs: they are claimable
                    // again through their own (now past) `next_attempt_at`, and
                    // the held banner must stop claiming a wait that is over.
                    // The series clock survives (D-C4).
                    let released = queue
                        .release_held_jobs(breaker.provider, &breaker.model)
                        .await?;
                    tracing::warn!(
                        provider = breaker.provider.as_str(),
                        model = breaker.model,
                        released = released.len(),
                        "#871 provider breaker: closed after a successful probe"
                    );
                } else if let Some(retry_at) = decision.retry_at {
                    // The probe failed: the held rows must follow the breaker,
                    // or they would display a resume time that has already
                    // passed (D-A6).
                    let refreshed = queue
                        .refresh_held_jobs(breaker.provider, &breaker.model, retry_at)
                        .await?;
                    tracing::warn!(
                        provider = breaker.provider.as_str(),
                        model = breaker.model,
                        refreshed = refreshed.len(),
                        "#871 provider breaker: probe failed — held rows re-pointed"
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

    /// The probe must request exactly `/api/tags`, not `/api/api/tags`
    /// (issue #871 review): the curated base URL already ends in `/api`, so a
    /// duplicated segment is a 404 that the probe would classify as
    /// `Unreachable` — an Ollama breaker could then never close.
    ///
    /// Asserts on [`ollama_probe_url`], the SAME function `probe` calls, so the
    /// test cannot stay green while the probe regresses (the earlier version
    /// rebuilt the URL independently and would have).
    #[test]
    fn the_probe_builds_the_undoubled_ollama_path() {
        let url = ollama_probe_url(LlmProvider::Ollama);
        assert_eq!(url, "http://ollama:11434/api/tags");
        assert!(
            !url.contains("/api/api/"),
            "the probe must not duplicate the /api segment: {url}"
        );
        // The path is exactly what Ollama serves, derived from the base URL the
        // chat client also uses.
        let base = <CuratedProviderUrls as breakdown_core::ai::CuratedLlmProvider>::base_url(
            LlmProvider::Ollama,
        );
        assert_eq!(
            url.strip_prefix(base),
            Some("/tags"),
            "the probe path is relative to the curated base: {url}"
        );
    }

    /// Issue #942 W1/F2: the preflight is `{base}/key`, NOT the public
    /// `{base}/models` — EURouter answers `200` for a bogus bearer token on the
    /// catalog read, so a probe pointed there can never see a dead credential.
    #[test]
    fn the_hosted_probe_requests_the_key_endpoint_for_the_documented_providers() {
        for provider in [LlmProvider::EURouter, LlmProvider::OpenRouter] {
            let url = key_probe_url(provider);
            let base =
                <CuratedProviderUrls as breakdown_core::ai::CuratedLlmProvider>::base_url(provider);
            assert_eq!(
                url.strip_prefix(base),
                Some("/key"),
                "{provider:?} must be preflighted on its documented /key endpoint: {url}"
            );
            assert!(
                !url.contains("/models"),
                "the public catalog read is not a usability preflight: {url}"
            );
        }
    }

    /// The capability table is exhaustive over `LlmProvider` by construction (no
    /// catch-all arm), and this pins the two decisions the issue spells out:
    /// `/key` for the OpenRouter-compatible gateways, `/api/tags` for Ollama, and
    /// no synthetic probe for the rest.
    #[test]
    fn the_capability_table_matches_the_verified_endpoints() {
        use breakdown_core::ai::ProbeCapability;
        use breakdown_core::ai::probe_capability;

        assert_eq!(
            probe_capability(LlmProvider::EURouter),
            ProbeCapability::KeyEndpoint
        );
        assert_eq!(
            probe_capability(LlmProvider::OpenRouter),
            ProbeCapability::KeyEndpoint
        );
        assert_eq!(
            probe_capability(LlmProvider::Ollama),
            ProbeCapability::LocalTags
        );
        for provider in [
            LlmProvider::OpenAI,
            LlmProvider::Gemini,
            LlmProvider::Neuralwatt,
            LlmProvider::OpenCode,
            LlmProvider::OpenCodeGo,
        ] {
            assert_eq!(
                probe_capability(provider),
                ProbeCapability::NoPreflight,
                "{provider:?} has no verified zero-token endpoint, so a metadata                  probe must not pretend to judge it"
            );
        }
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
