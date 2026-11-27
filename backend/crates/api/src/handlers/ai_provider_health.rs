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

/// How many distinct credentials one health read measures.
///
/// A config carries at most three credential slots (assistant, decision, vision),
/// so a provider realistically holds one to three of the caller's keys. The bound
/// keeps this read from becoming an unbounded fan-out of provider calls on a
/// pathological (or hostile) config history, and — exactly like the paged config
/// scan — it **fails closed** beyond it: a health read may say "I could not
/// answer", it must never answer for a subset of the caller's accounts.
const MAX_PROBED_CREDENTIALS: usize = 8;

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
    /// Every credential the caller holds for this provider, one entry per
    /// distinct Vault binding (issue #1013 review).
    ///
    /// The three fields above describe the `selected` entry only. They cannot
    /// describe all of them: since #1013 one config can name a page-image
    /// (vision) credential — even on the same provider and the same model id —
    /// whose account pays for the images, and a healthy text account would hide
    /// a broken vision one. Empty when the caller has no credential for this
    /// provider (an answer, not an error).
    ///
    /// `#[serde(default)]`: additive on the wire, the same rule as
    /// `AiProviderInfo::decision_capable` — a server that predates the field
    /// omits it, so the property is NOT `required` in the contract and a client
    /// built from an older spec keeps deserializing. A client must read an absent
    /// (or empty) list as "no per-credential detail" and fall back to the
    /// top-level verdict, never as "no credential".
    #[serde(default)]
    pub credentials: Vec<AiProviderCredentialView>,
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

/// One CREDENTIAL the caller holds for `{provider}` and the models it pays for
/// (issue #1013 review).
///
/// A provider can be paid by more than one of the caller's credentials: the
/// assistant pair, a distinct `decision_vault_key_id`, and — since #1013 — a
/// distinct `vision_vault_key_id` whose ACCOUNT serves the page images. They are
/// different accounts even on the same provider, so one verdict cannot answer
/// for all of them; this type is the per-account half of that answer.
///
/// No `vault_key_id` crosses the wire (schema hygiene of this module): a
/// credential is identified by the models it pays for and by the `selected` bit.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct AiProviderCredentialView {
    /// Whether this is the credential `credential_configured`/`probe_status`/
    /// `budget` above describe (exactly one entry carries it when the caller has
    /// a credential for this provider).
    pub selected: bool,
    /// Whether this credential could be resolved as an owned Vault binding. A
    /// `false` here with a listed model means the reference is stale, foreign or
    /// malformed — the state the account verdict cannot express.
    pub credential_configured: bool,
    /// The account-usability verdict measured with THIS credential.
    pub probe_status: AccountProbeStatus,
    /// The remaining budget as reported by THIS account.
    pub budget: Option<AiProviderBudgetView>,
    /// The configured models of `{provider}` this credential pays for, sorted and
    /// deduplicated.
    pub models: Vec<String>,
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

    // The SELECTED credential: the caller's own binding for the requested model,
    // else the first binding of the provider. Nothing is read when the caller has
    // no config at all — an unconfigured user is an answer, not an error.
    let selected_binding = select_binding(&bindings, requested_model.as_deref());
    let selected_vault_key_id =
        selected_binding.and_then(|binding| binding.vault_key_id.as_deref());

    // Every credential of this provider is measured on its own (issue #1013
    // review): one provider can be paid by several of the caller's accounts, and
    // the vision account is the one that pays for page images. The top-level
    // fields keep describing the SELECTED entry, so a caller that reads only them
    // sees the pre-#1013 answer unchanged.
    let groups = credential_groups(&bindings);
    if groups.len() > MAX_PROBED_CREDENTIALS {
        tracing::error!(
            caller = current_user.sub.as_str(),
            credentials = groups.len(),
            "#942 health: the caller holds more credentials for this provider than one read may probe — refusing to answer a partial credential state"
        );
        return Err(DomainError::service_unavailable(
            "the caller's provider credentials could not all be measured, so the credential state is unknown",
        )
        .into());
    }
    let mut credentials: Vec<AiProviderCredentialView> = Vec::with_capacity(groups.len());
    for group in &groups {
        let (configured, snapshot) = probe_credential(
            &state,
            &current_user.sub,
            provider,
            group.vault_key_id.as_str(),
        )
        .await;
        credentials.push(AiProviderCredentialView {
            selected: Some(group.vault_key_id.as_str()) == selected_vault_key_id,
            credential_configured: configured,
            probe_status: snapshot.status,
            budget: budget_view(&snapshot),
            models: group.models.clone(),
        });
    }

    let (credential_configured, probe_status, budget) =
        match credentials.iter().find(|credential| credential.selected) {
            Some(credential) => (
                credential.credential_configured,
                credential.probe_status,
                credential.budget,
            ),
            // No credential at all. `LocalTags` (Ollama) reads its own endpoint and is
            // measured anyway — the pre-#1013 shape, kept: "is a key stored" and "is
            // the account usable" are different questions.
            None => {
                let snapshot = match probe_capability(provider) {
                    ProbeCapability::LocalTags => {
                        state
                            .ports
                            .ai_provider_account_probe()
                            .probe_account(AccountProbeRequest {
                                user_id: &current_user.sub,
                                provider,
                                vault_key_id: "",
                                key: None,
                            })
                            .await
                    }
                    // `NoPreflight` (no verified zero-token endpoint) and
                    // `KeyEndpoint` (nothing to read it with) stay `unknown`: a
                    // health read never fabricates a verdict it did not measure.
                    ProbeCapability::NoPreflight | ProbeCapability::KeyEndpoint => {
                        AccountProbeSnapshot::unknown()
                    }
                };
                (false, snapshot.status, budget_view(&snapshot))
            }
        };

    let breakers =
        collect_breakers(&state, provider, requested_model.as_deref(), &bindings).await?;

    Ok(no_store_json(
        StatusCode::OK,
        AiProviderHealthView {
            provider,
            credential_configured,
            probe_status,
            budget,
            credentials,
            breakers,
        },
    ))
}

/// One credential of `{provider}` and the models it pays for.
#[derive(Debug, Clone, PartialEq, Eq)]
struct CredentialGroup {
    vault_key_id: String,
    models: Vec<String>,
}

/// The distinct credentials behind `bindings`, in `bindings` order (the
/// assistant pair first, then `image_model`, decision and vision), each with the
/// models it pays for.
///
/// `bindings` is already deduplicated by `(model, credential)`, so one credential
/// can appear with several models and several credentials can share one model.
fn credential_groups(bindings: &[ConfiguredBinding]) -> Vec<CredentialGroup> {
    let mut groups: Vec<CredentialGroup> = Vec::new();
    for binding in bindings {
        let Some(vault_key_id) = binding.vault_key_id.as_deref() else {
            // A `None` binding has no credential to probe; `select_binding` falls
            // back to the first binding that has one (or to none).
            continue;
        };
        match groups
            .iter_mut()
            .find(|group| group.vault_key_id == vault_key_id)
        {
            Some(group) => {
                if !group.models.iter().any(|model| model == &binding.model) {
                    group.models.push(binding.model.clone());
                }
            }
            None => groups.push(CredentialGroup {
                vault_key_id: vault_key_id.to_owned(),
                models: vec![binding.model.clone()],
            }),
        }
    }
    for group in &mut groups {
        group.models.sort_unstable();
    }
    groups
}

/// The wire shape of a probe's budget.
fn budget_view(snapshot: &AccountProbeSnapshot) -> Option<AiProviderBudgetView> {
    snapshot.budget.map(|budget| AiProviderBudgetView {
        remaining: budget.remaining,
    })
}

/// Read the caller's OWN credential for `vault_key_id` and measure the account
/// with it, returning `(was a usable binding found, snapshot)`.
///
/// `unknown` everywhere nothing was measured: no readable binding, a provider
/// without a verified zero-token endpoint, or a transport failure inside the
/// probe. The `LocalTags` capability (Ollama) reads its own endpoint and needs no
/// secret, so it is measured even without a readable binding — the "is a key
/// stored" answer stays `false`, and the two facts do not hide each other.
async fn probe_credential<P: Ports>(
    state: &AppState<P>,
    caller: &UserId,
    provider: LlmProvider,
    vault_key_id: &str,
) -> (bool, AccountProbeSnapshot) {
    let secret = read_own_credential(state, caller, vault_key_id).await;
    let configured = secret.is_some();
    let snapshot = match probe_capability(provider) {
        ProbeCapability::NoPreflight => AccountProbeSnapshot::unknown(),
        ProbeCapability::LocalTags => {
            state
                .ports
                .ai_provider_account_probe()
                .probe_account(AccountProbeRequest {
                    user_id: caller,
                    provider,
                    vault_key_id,
                    key: None,
                })
                .await
        }
        ProbeCapability::KeyEndpoint => match secret.as_deref() {
            Some(key) => {
                state
                    .ports
                    .ai_provider_account_probe()
                    .probe_account(AccountProbeRequest {
                        user_id: caller,
                        provider,
                        vault_key_id,
                        key: Some(key),
                    })
                    .await
            }
            None => AccountProbeSnapshot::unknown(),
        },
    };
    (configured, snapshot)
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
        // Issue #1013: the vision slot can name a DIFFERENT provider, and its
        // credential is what actually pays for the page images. Reporting only
        // the assistant pair would tell the operator the wrong account serves
        // the images (and hide a vision outage behind a healthy text row).
        if config.vision_provider == Some(provider)
            && let Some(vision_model) = config.vision_model.as_deref()
        {
            // `vision_vault_key_id` is optional on the wire only for replay of
            // pre-#1013 views; the aggregate validates the triple, so a missing
            // key falls back to the primary binding rather than "unconfigured".
            let key = config
                .vision_vault_key_id
                .as_deref()
                .unwrap_or(&config.vault_key_id);
            push_binding(&mut bindings, vision_model, key);
        }
    }
    bindings
}

/// Add one `(model, credential)` pair, deduplicated by **both** halves.
///
/// Deduplicating by model alone would drop a real, distinct credential: the
/// vision slot may name the same provider and even the same model id as the
/// assistant pair while a different Vault binding pays for the pages (the
/// aggregate allows exactly that, and it is the split-billing shape #1013
/// exists for). The assistant binding is pushed first, so a model-only dedupe
/// silently discarded the vision credential — and the health read then reported
/// the text account's verdict for the page-image account (issue #1013 review).
fn push_binding(bindings: &mut Vec<ConfiguredBinding>, model: &str, vault_key_id: &str) {
    if bindings.iter().any(|binding| {
        binding.model == model && binding.vault_key_id.as_deref() == Some(vault_key_id)
    }) {
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
