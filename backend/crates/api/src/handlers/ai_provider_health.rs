// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! `GET /v1/ai-import/providers/{provider}/health` — the provider-health and
//! budget read (issue #942 W4).
//!
//! **Why it exists.** Issue #942 F5 recorded that the app could only say
//! "backend reachable" or "backend unreachable": a user whose *provider* was
//! stalling, whose credential was dead, or whose balance was exhausted saw the
//! same screen, and the only way to find out was to spend another doomed import
//! cycle. This route answers the two questions the client cannot answer itself
//! without leaking or guessing: *is **my** account usable right now* and *which
//! `(provider, model)` pairs are currently held*.
//!
//! **Why it is shaped the way it is (the four facts it keeps apart).**
//!
//! 1. `credential_configured` — do I have a Vault binding for this provider at
//!    all. `false` is an answer, not an error: the caller simply never saved a
//!    key, which is why the route answers `200` instead of `404`.
//! 2. `probe_status` — what the zero-token account read observed about **my**
//!    credential. `unknown` is a first-class value (no verified endpoint,
//!    transport failure, timeout) and is never rendered as a denial
//!    (`frontend-flutter/AGENTS.md` §1, issue #816).
//! 3. `budget` — three-valued, never a fabricated `0`: `null` means the provider
//!    reports no budget read at all, `{"remaining": null}` means it reports "no
//!    limit configured", and a number is a real remaining figure.
//! 4. `breakers` — the deployment-wide `(provider, model)` circuit-breaker rows.
//!    A **closed** breaker with a rejected credential is representable, and so is
//!    an **open** breaker for a healthy account: they are different facts about
//!    different things (a pair vs an account), and merging them into one verdict
//!    is what made the pre-#942 narrative wrong on every layer.
//!
//! **Tenant isolation (hard rule).** The credential is resolved strictly from
//! the caller's own `AiConfig` rows — `vault_key_id`/`decision_vault_key_id` →
//! `settings_id_from_binding_key` → an ownership check against the caller's
//! `settings` binding → the Vault read. The background probe's `donor_jobs`
//! credentials are **never** consulted here: those are another user's keys, and
//! a user-readable response must never carry a number derived from them. The
//! budget cache is keyed `(user_id, provider, vault_key_id)` for the same reason
//! (see `infra::ai::provider_probe::CachedAccountProbe`).
//!
//! **Wire hygiene.** No bearer token, no `vault_key_id`, no raw upstream body and
//! no `trial_job` (a job id may belong to another user) crosses this route; the
//! probe verdict is an enum and the trial is a boolean.

use axum::extract::State;
use axum::http::StatusCode;
use axum::response::Response;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use breakdown_core::ai::ports::{
    AccountProbeRequest, AccountProbeSnapshot, AccountProbeStatus, LlmProvider, probe_capability,
};
use breakdown_core::ai::{
    AiConfigRepository as _, AiConfigView, ProbeCapability, ProviderAccountProbe as _,
    ProviderBreakerState, ProviderHealth as _,
};
use breakdown_core::error::DomainError;
use breakdown_core::settings::{CredentialVault, SettingsRepository as _};
use breakdown_core::shared::UserId;
use infra::vault::settings_id_from_binding_key;

use crate::auth::CurrentUser;
use crate::handlers::{
    AppState, Ports, credential_role_gate, forbidden_ai_config, no_store_json, parse_ai_provider,
};
use crate::problems::{ApiError, Path, ProblemDetails, Query};

/// The longest model id this route accepts as a query parameter.
///
/// A bound, not a rule: the value is used as a breaker lookup key, and an
/// unbounded caller-supplied string must never become an unbounded cache or
/// database key.
const MAX_MODEL_QUERY_CHARS: usize = 200;

/// How many non-closed breaker rows one read may attach.
///
/// The sweeper's own tick limit is the natural ceiling: a provider with more
/// simultaneous open pairs than one tick can probe is degraded far beyond what a
/// per-pair list can usefully explain.
const BREAKER_VIEW_LIMIT: i64 = 100;

/// One page of the caller's config scan (the repository clamps `limit` to 100).
const CONFIG_SCAN_PAGE: i64 = 100;

/// Hard stop for the config scan.
///
/// A caller cannot paginate away the problem the page size solves — but a health
/// read must also not become an unbounded query loop over a pathological (or
/// hostile) data set. 50 pages is 5.000 configs for ONE user, far past any
/// legitimate history — and when the bound bites the read **fails closed**
/// (`503`) rather than answering from a partial scan (see
/// [`list_caller_configs`]).
const CONFIG_SCAN_MAX_PAGES: usize = 50;

/// Query of `GET /v1/ai-import/providers/{provider}/health`.
#[derive(Debug, Deserialize)]
pub struct AiProviderHealthQuery {
    /// Restrict the answer to one model of `{provider}`.
    ///
    /// Absent: the caller's own configured models for `{provider}` are read
    /// (assistant, image and — when it names the same provider — decision), plus
    /// any non-closed breaker row of the provider. Present: exactly that pair,
    /// whether or not the caller has a config for it.
    pub model: Option<String>,
}

/// One `(provider, model)` breaker row (issue #942 W4).
///
/// Deliberately **not** the raw `ProviderBreakerSnapshot`: that struct carries
/// `trial_job`, the id of the job currently allowed to run the half-open trial.
/// Serializing it would publish another user's job id, so the wire keeps a
/// boolean instead — the client only needs to know that a trial was granted.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct AiProviderBreakerView {
    pub provider: LlmProvider,
    /// The model half of the breaker key.
    pub model: String,
    /// `closed` admits paid calls; `open`/`half_open` hold them.
    pub state: ProviderBreakerState,
    /// Consecutive retryable failures on this pair, across all users and jobs.
    pub consecutive_failures: u32,
    /// How often the pair has reopened; a high count is a flapping provider.
    pub flap_count: u32,
    /// The next scheduled probe (`null` while `closed`).
    pub retry_at: Option<jiff::Timestamp>,
    /// Whether one un-retried trial call is currently granted for this pair.
    /// A boolean, never the trial's job id (see the type doc).
    ///
    /// `true` means the GRANT, not that a call is running: `begin_provider_trial`
    /// stamps the id and returns the job to the queue, so a worker may not have
    /// claimed it yet. Copy must not claim "trial in flight" from this bit.
    pub trial_granted: bool,
}

/// The account's remaining budget, where the provider reports one (issue #942
/// W4).
///
/// `remaining: null` is meaningful and must not be collapsed into the absent
/// `budget` object: it means the provider answered and reports **no limit
/// configured**, which is the opposite of an exhausted account.
#[derive(Debug, Clone, Copy, Serialize, ToSchema)]
pub struct AiProviderBudgetView {
    pub remaining: Option<f64>,
}

/// The provider-health read (issue #942 W4).
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct AiProviderHealthView {
    /// The provider this answer is about, echoed as the canonical wire key.
    pub provider: LlmProvider,
    /// Whether the caller has an active Vault binding for this provider.
    ///
    /// `false` is a complete answer: the route never fabricates a verdict it did
    /// not measure, and never answers `404` for a user who simply has not saved
    /// a key yet.
    ///
    /// It is **not** a promise that `probe_status` is `unknown`. A provider whose
    /// probe needs no credential (`ProbeCapability::LocalTags` — Ollama reads its
    /// own endpoint) is measured anyway, so `credential_configured: false` can sit
    /// next to a real `usable`/`not_usable`. The two fields answer different
    /// questions — "is a key stored" vs "is the account usable" — and a client
    /// must never let the first hide a measured answer to the second.
    pub credential_configured: bool,
    /// The account-usability verdict of the zero-token read.
    pub probe_status: AccountProbeStatus,
    /// The remaining budget, or `null` when the provider reports none / there is
    /// no credential to read it with.
    pub budget: Option<AiProviderBudgetView>,
    /// The `(provider, model)` breaker rows, ordered by model for a stable
    /// rendering.
    pub breakers: Vec<AiProviderBreakerView>,
}

/// One configured model of `{provider}` and the Vault binding that pays for it.
#[derive(Debug, Clone, PartialEq, Eq)]
struct ConfiguredBinding {
    model: String,
    /// `None` when the config's decision model has no separate binding (it then
    /// falls back to the primary binding on the worker path; the read reports
    /// the fallback rather than pretending the key is missing).
    vault_key_id: Option<String>,
}

/// `GET /ai-import/providers/{provider}/health`
///
/// Answers "is my AI account usable right now, how much budget is left, and which
/// `(provider, model)` pairs are held" without spending a paid call.
#[utoipa::path(
    get,
    // Pinned to the `handlers` tag on purpose: the tag otherwise derives from
    // the module path (`handlers::ai_provider_health`), which would split this
    // one operation into its own generated client class while every other AI
    // route lives in `HandlersApi` (cosmetic, but a client-side wart with no
    // upside).
    tag = "handlers",
    path = "/ai-import/providers/{provider}/health",
    params(
        ("provider" = String, Path, description = "Curated provider key (e.g. eurouter, neuralwatt)"),
        ("model" = Option<String>, Query, description = "Restrict the breaker snapshot to one model of the provider")
    ),
    responses(
        (status = 200, description = "Provider health + budget snapshot", body = AiProviderHealthView),
        (status = 403, description = "Credential management forbidden", body = ProblemDetails),
        (status = 404, description = "AI import disabled", body = ProblemDetails),
        (status = 422, description = "Unknown provider key", body = ProblemDetails),
        (status = 503, description = "Read model unavailable", body = ProblemDetails)
    )
)]
pub async fn get_ai_provider_health<P: Ports>(
    State(state): State<AppState<P>>,
    current_user: CurrentUser,
    Path(provider): Path<String>,
    Query(query): Query<AiProviderHealthQuery>,
) -> Result<Response, ApiError> {
    // AUTHZ-GATE: provider health is credential administration — it reports
    // whether the caller's own Vault binding is usable, so it is decided by the
    // (fallible) credential-role policy, exactly like `list_ai_configs`.
    if !credential_role_gate(&state, &current_user).await? {
        return Err(forbidden_ai_config());
    }
    if !state.ai_import_enabled {
        return Err(ApiError::FeatureDisabled("AI import is disabled"));
    }
    let provider = parse_ai_provider(&provider)?;
    let requested_model = normalize_requested_model(query.model.as_deref())?;

    let configs = list_caller_configs(&state, &current_user.sub).await?;
    let bindings = configured_bindings(&configs, provider);

    // The credential: the caller's OWN binding for the requested model, else the
    // first binding of the provider. Nothing is read when the caller has no
    // config at all — an unconfigured user is an answer, not an error.
    let binding = select_binding(&bindings, requested_model.as_deref());
    let secret = match binding.and_then(|binding| binding.vault_key_id.as_deref()) {
        Some(vault_key_id) => read_own_credential(&state, &current_user.sub, vault_key_id).await,
        None => None,
    };
    let credential_configured = secret.is_some();

    // The account verdict. `unknown` everywhere nothing was measured: no
    // credential, a provider without a verified zero-token endpoint, or a
    // transport failure inside the probe.
    let snapshot = match probe_capability(provider) {
        ProbeCapability::NoPreflight => AccountProbeSnapshot::unknown(),
        ProbeCapability::LocalTags => {
            state
                .ports
                .ai_provider_account_probe()
                .probe_account(AccountProbeRequest {
                    user_id: &current_user.sub,
                    provider,
                    vault_key_id: binding
                        .and_then(|b| b.vault_key_id.as_deref())
                        .unwrap_or(""),
                    key: None,
                })
                .await
        }
        ProbeCapability::KeyEndpoint => match (secret.as_deref(), binding) {
            (Some(key), Some(binding)) => {
                state
                    .ports
                    .ai_provider_account_probe()
                    .probe_account(AccountProbeRequest {
                        user_id: &current_user.sub,
                        provider,
                        vault_key_id: binding.vault_key_id.as_deref().unwrap_or(""),
                        key: Some(key),
                    })
                    .await
            }
            _ => AccountProbeSnapshot::unknown(),
        },
    };

    let breakers =
        collect_breakers(&state, provider, requested_model.as_deref(), &bindings).await?;

    Ok(no_store_json(
        StatusCode::OK,
        AiProviderHealthView {
            provider,
            credential_configured,
            probe_status: snapshot.status,
            budget: snapshot.budget.map(|budget| AiProviderBudgetView {
                remaining: budget.remaining,
            }),
            breakers,
        },
    ))
}

/// Validate and trim the optional `?model=` parameter.
fn normalize_requested_model(model: Option<&str>) -> Result<Option<String>, ApiError> {
    let Some(model) = model else {
        return Ok(None);
    };
    let model = model.trim();
    if model.is_empty() {
        return Ok(None);
    }
    if model.chars().count() > MAX_MODEL_QUERY_CHARS {
        return Err(DomainError::validation(format!(
            "model must be at most {MAX_MODEL_QUERY_CHARS} characters"
        ))
        .into());
    }
    Ok(Some(model.to_owned()))
}

/// The models `{provider}` pays for in `configs`, primary first, deduplicated by
/// model id.
///
/// Only non-revoked configs count: a revoked configuration is history, and
/// reporting its models as "configured" would claim a credential that the user
/// deliberately retired.
fn configured_bindings(configs: &[AiConfigView], provider: LlmProvider) -> Vec<ConfiguredBinding> {
    let mut bindings: Vec<ConfiguredBinding> = Vec::new();
    for config in configs.iter().filter(|config| !config.revoked) {
        if config.provider == provider {
            push_binding(&mut bindings, &config.assistant_model, &config.vault_key_id);
            if let Some(image_model) = config.image_model.as_deref() {
                push_binding(&mut bindings, image_model, &config.vault_key_id);
            }
        }
        if config.decision_provider == Some(provider)
            && let Some(decision_model) = config.decision_model.as_deref()
        {
            // The decision key is optional on the aggregate: without one the
            // worker pays with the primary binding of the same provider, which
            // is what this read reports rather than "unconfigured".
            let key = config
                .decision_vault_key_id
                .as_deref()
                .unwrap_or(&config.vault_key_id);
            push_binding(&mut bindings, decision_model, key);
        }
    }
    bindings
}

fn push_binding(bindings: &mut Vec<ConfiguredBinding>, model: &str, vault_key_id: &str) {
    if bindings.iter().any(|binding| binding.model == model) {
        return;
    }
    bindings.push(ConfiguredBinding {
        model: model.to_owned(),
        vault_key_id: Some(vault_key_id.to_owned()),
    });
}

/// The binding whose credential this read probes: the requested model's, else the
/// first configured one.
///
/// The `else` covers **both** an absent `?model=` and a requested model the
/// caller has no config for. The query parameter scopes the breaker snapshot; it
/// does not redefine "do I have a credential for this provider", which is a
/// provider-scoped question answered by any of the caller's bindings. A
/// model-scoped `find` alone reported `credential_configured: false` for a caller
/// who very much has one (every hosted probe is account-scoped, not
/// model-scoped).
fn select_binding<'a>(
    bindings: &'a [ConfiguredBinding],
    requested_model: Option<&str>,
) -> Option<&'a ConfiguredBinding> {
    requested_model
        .and_then(|model| bindings.iter().find(|binding| binding.model == model))
        .or_else(|| bindings.first())
}

/// Every config of the caller, paged to the end.
///
/// **Not one fixed page.** `configured_bindings` keeps only the non-revoked rows,
/// so a single 50-row page silently drops a still-active config once older rows
/// accumulate — a user who revokes and re-creates a key 50 times would read as
/// "no credential configured" while their binding is intact upstream. Revoked
/// rows are history and stay excluded from the bindings, but they must not be
/// able to hide an active one.
///
/// **An incomplete scan is an ERROR, never a partial answer** (review of #942).
/// The page loop is bounded so a pathological data set cannot make this read
/// unbounded work, and a bounded loop can stop early — which would re-introduce
/// the very defect the paging fixes, one order of magnitude further out: a
/// caller whose active config sits past the ceiling would read as "no credential
/// configured" while the log line stayed on the server. So the ceiling fails
/// closed with `503` (`service.unavailable`, already declared on this route and
/// rendered by the client as "read failed + retry"): a health read may say "I
/// could not answer", it must never answer `credential_configured: false` from
/// an unfinished scan.
async fn list_caller_configs<P: Ports>(
    state: &AppState<P>,
    caller: &UserId,
) -> Result<Vec<AiConfigView>, ApiError> {
    let mut configs: Vec<AiConfigView> = Vec::new();
    let mut offset: i64 = 0;
    for _ in 0..CONFIG_SCAN_MAX_PAGES {
        let batch = state
            .ports
            .ai_config_repo()
            .list_for_user(caller, CONFIG_SCAN_PAGE, offset)
            .await?;
        let is_last_page = (batch.len() as i64) < CONFIG_SCAN_PAGE;
        configs.extend(batch);
        if is_last_page {
            return Ok(configs);
        }
        offset += CONFIG_SCAN_PAGE;
    }
    tracing::error!(
        caller = caller.as_str(),
        scanned = configs.len(),
        "#942 health: the config scan did not finish — refusing to answer a partial credential state"
    );
    Err(DomainError::service_unavailable(
        "the caller's AI configs could not be read completely, so the credential state is unknown",
    )
    .into())
}

/// Read the caller's own credential for `vault_key_id`.
///
/// Two independent guards, in this order:
///
/// 1. `settings_id_from_binding_key` recovers the owning settings id from the
///    opaque reference; a malformed reference can never address an arbitrary
///    Vault path.
/// 2. the ownership check (`settings_repo().find_by_vault_key` → owner) refuses a
///    binding that belongs to somebody else. Without it a crafted or migrated
///    `AiConfig` row would make this route read a foreign secret and publish a
///    verdict derived from it — the confused-deputy shape #552 closed on the
///    write path.
///
/// A missing, foreign or unreadable binding is **not** an error here: it degrades
/// to `credential_configured: false`, because a health read must not turn one
/// user's stale reference into an error page (and must not become an existence
/// oracle for other users' bindings).
async fn read_own_credential<P: Ports>(
    state: &AppState<P>,
    caller: &UserId,
    vault_key_id: &str,
) -> Option<String> {
    let Some(owner) = settings_id_from_binding_key(vault_key_id) else {
        tracing::warn!(
            "#942 health: the caller's vault key reference is malformed — reporting no credential"
        );
        return None;
    };
    match state
        .ports
        .settings_repo()
        .find_by_vault_key(vault_key_id)
        .await
    {
        Ok(Some(view)) if view.owner.as_ref() == Some(caller) => {}
        Ok(_) => {
            tracing::warn!(
                "#942 health: the caller's vault key reference is not an owned settings binding — reporting no credential"
            );
            return None;
        }
        Err(error) => {
            tracing::warn!(
                error = %error,
                "#942 health: could not resolve the caller's settings binding — reporting no credential"
            );
            return None;
        }
    }
    match state
        .ports
        .credential_vault()
        .fetch(owner, vault_key_id)
        .await
    {
        Ok(secret) => Some(secret.as_str().to_owned()),
        Err(error) => {
            tracing::warn!(
                error = %error,
                "#942 health: could not read the caller's credential — reporting no credential"
            );
            None
        }
    }
}

/// The breaker rows this read reports: the requested pair, else the caller's
/// configured models, plus every non-closed row of the provider.
///
/// A **non-closed** row is included even when the caller has no config for that
/// pair: an outage that holds the fleet is exactly what an operator needs to see
/// before starting an import, and the row itself carries no tenant data.
async fn collect_breakers<P: Ports>(
    state: &AppState<P>,
    provider: LlmProvider,
    requested_model: Option<&str>,
    bindings: &[ConfiguredBinding],
) -> Result<Vec<AiProviderBreakerView>, ApiError> {
    let mut models: Vec<String> = match requested_model {
        Some(model) => vec![model.to_owned()],
        None => bindings
            .iter()
            .map(|binding| binding.model.clone())
            .collect(),
    };
    // Non-closed rows of this provider, in the sweeper's own selection order.
    let open = state
        .ports
        .ai_provider_health()
        .open_breakers(BREAKER_VIEW_LIMIT)
        .await?;
    for breaker in open.iter().filter(|row| row.provider == provider) {
        if !models.contains(&breaker.model) {
            models.push(breaker.model.clone());
        }
    }
    models.sort_unstable();
    models.dedup();

    let mut views = Vec::with_capacity(models.len());
    for model in models {
        let snapshot = state
            .ports
            .ai_provider_health()
            .state(provider, &model)
            .await?;
        views.push(AiProviderBreakerView {
            provider,
            model,
            state: snapshot.state,
            consecutive_failures: snapshot.consecutive_failures,
            flap_count: snapshot.flap_count,
            retry_at: snapshot.retry_at,
            // The raw `trial_job` is deliberately not published (see the type
            // doc): only the fact that a trial is granted.
            trial_granted: snapshot.trial_job.is_some(),
        });
    }
    Ok(views)
}
