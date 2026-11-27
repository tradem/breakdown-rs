// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! `GET /v1/ai-import/providers/{provider}/health` (issue #942 W4) — the
//! provider-health and budget read.
//!
//! Four claims fail silently if they regress, so each has a case here:
//!
//! 1. **The credential is the caller's own.** The route resolves the Vault
//!    binding from the caller's `AiConfig` rows and an ownership check — never
//!    from another user's binding (which would leak that account's verdict and
//!    balance).
//! 2. **"Not configured" is an answer, not an error.** A caller without a
//!    readable binding gets `200` — never a `404`/`500` (and never a fabricated
//!    `0`). For a provider whose probe needs a key (`KeyEndpoint`) that means
//!    `credential_configured: false`, `probe_status: unknown`, `budget: null`; a
//!    `LocalTags` provider (Ollama) is probed without any binding, so the same
//!    `false` can sit next to a measured `usable`.
//! 3. **The wire carries no tenant material.** `trial_job` (a job id that may
//!    belong to somebody else) is a boolean, and no `vault_key_id`, bearer token
//!    or upstream body appears in the document.
//! 4. **A denial is a 403 and probes nothing.** The credential-role gate runs
//!    before any Vault read or upstream call.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
use crate::common;

use std::collections::HashMap;
use std::sync::Arc;

use api::auth::CurrentUser;
use api::handlers::ai_provider_health::{AiProviderHealthQuery, get_ai_provider_health};
use api::problems::{Path, Query};
use api::state::AppState;
use axum::extract::State;
use axum::http::StatusCode;

use breakdown_core::ai::{
    AccountBudget, AccountProbeSnapshot, AccountProbeStatus, AiConfigView, CostDisplayPreference,
    DocumentKind, LlmProvider, OpenBreaker, ProviderBreakerSnapshot, ProviderBreakerState,
};
use breakdown_core::shared::{AggregateVersion, BlockId, UserId};
use common::*;

const USER_A: &str = "ai-provider-health-user-a";
const USER_B: &str = "ai-provider-health-user-b";
const MODEL: &str = "mistral-large-3";
/// A page-image model curated for EURouter (issue #1013).
const VISION_MODEL: &str = "qwen3-vl-30b-a3b";
/// Two distinct binding references, so the isolation cases can prove WHICH one
/// was read (the second belongs to the other user).
const VAULT_KEY_A: &str = "settings-01890f47-3c4d-7b21-9c0e-2a5f8b6d1e33";

fn user(sub: &str) -> CurrentUser {
    CurrentUser::dummy(sub)
}

async fn state(ports: FakePorts) -> AppState<FakePorts> {
    AppState::with_ai_import(
        ports,
        /*ai_import_enabled=*/ true,
        /*max_document_bytes=*/ 1024,
        Vec::new(),
    )
}

/// Seed an active credential-role membership so the AUTHZ gate resolves allow
/// from rows rather than from an override.
async fn seed_credential_member(ports: &FakePorts, sub: &str) {
    ports
        .membership_repo
        .seed_credential_designer(BlockId::new(), UserId::from_sub(sub))
        .await;
}

fn ai_config(sub: &str, vault_key_id: &str) -> AiConfigView {
    AiConfigView {
        id: uuid::Uuid::now_v7(),
        user_id: UserId::from_sub(sub),
        provider: LlmProvider::EURouter,
        assistant_model: MODEL.to_owned(),
        image_model: None,
        prompts: HashMap::from([(DocumentKind::Script, "script-prompt".to_owned())]),
        prompt_kinds: vec![DocumentKind::Script],
        stored_prompt_kinds: vec![DocumentKind::Script],
        vault_key_id: vault_key_id.to_owned(),
        cost_display_preference: CostDisplayPreference::Token,
        decision_provider: None,
        decision_model: None,
        decision_vault_key_id: None,
        reasoning_effort: breakdown_core::ai::ReasoningEffortChoice::Auto,
        zdr_attested: false,
        vision_provider: None,
        vision_model: None,
        vision_vault_key_id: None,
        vision_zdr_attested: false,
        version: AggregateVersion::INITIAL,
        revoked: false,
    }
}

/// Seed a caller's own binding: an AI config pointing at a settings binding the
/// caller owns, plus a readable Vault secret.
async fn seed_own_credential(ports: &FakePorts, sub: &str, vault_key_id: &str, secret: &str) {
    let config = ai_config(sub, vault_key_id);
    ports
        .ai_config_repo
        .views
        .lock()
        .await
        .insert(config.id, config);
    ports
        .settings_repo
        .bind_vault_key(vault_key_id, "eurouter", sub)
        .await;
    *ports.credential_vault.available.lock().await = true;
    *ports.credential_vault.secret.lock().await = Some(secret.to_owned());
}

async fn call(
    state: &AppState<FakePorts>,
    sub: &str,
    provider: &str,
    model: Option<&str>,
) -> Result<axum::response::Response, api::problems::ApiError> {
    get_ai_provider_health::<FakePorts>(
        State(state.clone()),
        user(sub),
        Path(provider.to_owned()),
        Query(AiProviderHealthQuery {
            model: model.map(str::to_owned),
        }),
    )
    .await
}

async fn body_json(response: axum::response::Response) -> (StatusCode, serde_json::Value) {
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("read the response body");
    let value = serde_json::from_slice(&bytes).expect("the response is a JSON document");
    (status, value)
}

#[tokio::test]
async fn the_callers_own_credential_is_probed_and_reported() {
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_A).await;
    seed_own_credential(&ports, USER_A, VAULT_KEY_A, "sk-caller-a").await;
    *ports.ai_provider_account_probe.snapshot.lock().await = AccountProbeSnapshot {
        status: AccountProbeStatus::Usable,
        budget: Some(AccountBudget {
            remaining: Some(12.5),
        }),
    };
    let state = state(ports.clone()).await;

    let response = call(&state, USER_A, "eurouter", None)
        .await
        .expect("a credential-role member may read their provider health");
    let (status, body) = body_json(response).await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["provider"], "eurouter");
    assert_eq!(body["credential_configured"], true);
    assert_eq!(body["probe_status"], "usable");
    assert_eq!(body["budget"]["remaining"], 12.5);

    // The probe received THIS caller's credential — the recorded request is the
    // security property, not the answer.
    let recorded = ports.ai_provider_account_probe.recorded().await;
    assert_eq!(recorded.len(), 1);
    assert_eq!(recorded[0].user_id, USER_A);
    assert_eq!(recorded[0].provider, LlmProvider::EURouter);
    assert_eq!(recorded[0].vault_key_id, VAULT_KEY_A);
    assert_eq!(recorded[0].key.as_deref(), Some("sk-caller-a"));
}

#[tokio::test]
async fn a_binding_owned_by_somebody_else_is_never_read() {
    // User B's config references a binding owned by user A. The route must not
    // read it: that would publish a verdict derived from A's secret (and an
    // existence oracle for A's bindings).
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_B).await;
    let config = ai_config(USER_B, VAULT_KEY_A);
    ports
        .ai_config_repo
        .views
        .lock()
        .await
        .insert(config.id, config);
    ports
        .settings_repo
        .bind_vault_key(VAULT_KEY_A, "eurouter", USER_A)
        .await;
    *ports.credential_vault.available.lock().await = true;
    *ports.credential_vault.secret.lock().await = Some("sk-caller-a".to_owned());
    *ports.ai_provider_account_probe.snapshot.lock().await = AccountProbeSnapshot {
        status: AccountProbeStatus::Usable,
        budget: None,
    };
    let state = state(ports.clone()).await;

    let response = call(&state, USER_B, "eurouter", None)
        .await
        .expect("a foreign binding degrades, it does not error");
    let (status, body) = body_json(response).await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["credential_configured"], false);
    assert_eq!(body["probe_status"], "unknown");
    assert_eq!(body["budget"], serde_json::Value::Null);
    // The decisive assertion: no probe ran at all, so no verdict derived from
    // another user's credential can exist.
    assert!(ports.ai_provider_account_probe.recorded().await.is_empty());
}

#[tokio::test]
async fn an_unconfigured_caller_gets_an_answer_not_an_error() {
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_A).await;
    let state = state(ports.clone()).await;

    let response = call(&state, USER_A, "eurouter", None)
        .await
        .expect("an unconfigured caller is an answer, never a 404/500");
    let (status, body) = body_json(response).await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["credential_configured"], false);
    assert_eq!(body["probe_status"], "unknown");
    assert_eq!(body["budget"], serde_json::Value::Null);
    // No config → no model → no breaker rows for the caller's pairs, and no
    // fabricated pair invented from nothing.
    assert_eq!(body["breakers"], serde_json::json!([]));
    assert!(ports.ai_provider_account_probe.recorded().await.is_empty());
}

#[tokio::test]
async fn a_provider_without_a_budget_read_reports_null_never_zero() {
    // The provider answered and reports NO limit configured: `budget` exists and
    // its `remaining` is null. Collapsing that into `budget: null` (or into `0`)
    // is the fabrication this case forbids.
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_A).await;
    seed_own_credential(&ports, USER_A, VAULT_KEY_A, "sk-caller-a").await;
    *ports.ai_provider_account_probe.snapshot.lock().await = AccountProbeSnapshot {
        status: AccountProbeStatus::Usable,
        budget: Some(AccountBudget { remaining: None }),
    };
    let state = state(ports.clone()).await;

    let (status, body) = body_json(
        call(&state, USER_A, "eurouter", None)
            .await
            .expect("the read succeeds"),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["probe_status"], "usable");
    // The `budget` OBJECT must exist and say `remaining: null`. Indexing
    // (`body["budget"]["remaining"]`) cannot tell a missing key from an explicit
    // null, so it would also pass for `budget: null` — the collapse this case
    // forbids.
    assert_eq!(
        body.get("budget"),
        Some(&serde_json::json!({ "remaining": serde_json::Value::Null })),
        "an unconfigured limit is a budget OBJECT with a null remaining: {body}"
    );
}

#[tokio::test]
async fn an_exhausted_account_is_not_usable_and_keeps_its_zero() {
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_A).await;
    seed_own_credential(&ports, USER_A, VAULT_KEY_A, "sk-caller-a").await;
    *ports.ai_provider_account_probe.snapshot.lock().await = AccountProbeSnapshot {
        status: AccountProbeStatus::NotUsable,
        budget: Some(AccountBudget {
            remaining: Some(0.0),
        }),
    };
    let state = state(ports.clone()).await;

    let (_, body) = body_json(
        call(&state, USER_A, "eurouter", None)
            .await
            .expect("the read succeeds"),
    )
    .await;

    assert_eq!(body["probe_status"], "not_usable");
    // A real measured 0 is reported as 0 — the "never fabricate" rule forbids
    // inventing a zero, not reporting a measured one.
    assert_eq!(body["budget"]["remaining"], 0.0);
}

#[tokio::test]
async fn a_capability_denial_is_a_403_and_reads_nothing() {
    let ports = FakePorts::default();
    *ports.membership_repo.credential_role_override.lock().await = Some(Ok(false));
    seed_own_credential(&ports, USER_A, VAULT_KEY_A, "sk-caller-a").await;
    let state = state(ports.clone()).await;

    let error = call(&state, USER_A, "eurouter", None)
        .await
        .expect_err("a denied caller must get an error");
    assert_eq!(error.into_problem().status, 403);
    // The gate runs first: no Vault read and no upstream probe happened.
    assert!(ports.ai_provider_account_probe.recorded().await.is_empty());
}

#[tokio::test]
async fn a_disabled_feature_is_404() {
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_A).await;
    let state = AppState::with_ai_import(
        ports,
        /*ai_import_enabled=*/ false,
        /*max_document_bytes=*/ 1024,
        Vec::new(),
    );

    let error = call(&state, USER_A, "eurouter", None)
        .await
        .expect_err("the rollout switch must gate the route");
    assert_eq!(error.into_problem().status, 404);
}

#[tokio::test]
async fn an_unknown_provider_key_is_422() {
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_A).await;
    let state = state(ports).await;

    let error = call(&state, USER_A, "not-a-provider", None)
        .await
        .expect_err("an unknown provider key is a validation error");
    assert_eq!(error.into_problem().status, 422);
}

#[tokio::test]
async fn a_breaker_row_exposes_the_trial_as_a_boolean_never_a_job_id() {
    // `provider_health.trial_job_id` names the job allowed to run the half-open
    // trial — possibly another user's job. The wire must carry the FACT only.
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_A).await;
    seed_own_credential(&ports, USER_A, VAULT_KEY_A, "sk-caller-a").await;
    let trial_job = uuid::Uuid::now_v7();
    ports
        .ai_provider_health
        .seed(
            LlmProvider::EURouter,
            MODEL,
            ProviderBreakerSnapshot {
                state: ProviderBreakerState::HalfOpen,
                consecutive_failures: 3,
                flap_count: 1,
                retry_at: None,
                trial_job: Some(trial_job),
            },
        )
        .await;
    let state = state(ports.clone()).await;

    let (status, body) = body_json(
        call(&state, USER_A, "eurouter", None)
            .await
            .expect("the read succeeds"),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    let breaker = &body["breakers"][0];
    assert_eq!(breaker["model"], MODEL);
    assert_eq!(breaker["state"], "half_open");
    assert_eq!(breaker["consecutive_failures"], 3);
    assert_eq!(breaker["trial_granted"], true);

    let document = serde_json::to_string(&body).expect("serialize the document");
    assert!(
        !document.contains(&trial_job.to_string()),
        "the trial's job id must never cross the wire: {document}"
    );
    assert!(
        !document.contains(VAULT_KEY_A),
        "the opaque Vault reference must never cross the wire: {document}"
    );
    assert!(
        !document.contains("sk-caller-a"),
        "the bearer token must never cross the wire: {document}"
    );
}

#[tokio::test]
async fn a_requested_model_scopes_the_breaker_list() {
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_A).await;
    seed_own_credential(&ports, USER_A, VAULT_KEY_A, "sk-caller-a").await;
    let state = state(ports.clone()).await;

    let (_, body) = body_json(
        call(&state, USER_A, "eurouter", Some("some-other-model"))
            .await
            .expect("the read succeeds"),
    )
    .await;

    let breakers = body["breakers"].as_array().expect("an array");
    assert_eq!(breakers.len(), 1);
    assert_eq!(breakers[0]["model"], "some-other-model");
}

#[tokio::test]
async fn an_open_breaker_of_an_unconfigured_pair_is_reported() {
    // An outage that holds the fleet is exactly what a user needs to see before
    // starting an import — even for a pair they have no config for. The row
    // carries no tenant data, so this is not a leak.
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_A).await;
    seed_own_credential(&ports, USER_A, VAULT_KEY_A, "sk-caller-a").await;
    *ports.ai_provider_health.open.lock().await = vec![OpenBreaker {
        provider: LlmProvider::EURouter,
        model: "fleet-wide-stalled".to_owned(),
        state: ProviderBreakerState::Open,
        retry_at: None,
        trial_job: None,
        probe_started_at: None,
    }];
    let state = state(ports.clone()).await;

    let (_, body) = body_json(
        call(&state, USER_A, "eurouter", None)
            .await
            .expect("the read succeeds"),
    )
    .await;

    let models: Vec<&str> = body["breakers"]
        .as_array()
        .expect("an array")
        .iter()
        .filter_map(|row| row["model"].as_str())
        .collect();
    assert!(models.contains(&MODEL), "the caller's own pair: {models:?}");
    assert!(
        models.contains(&"fleet-wide-stalled"),
        "the open pair of the provider: {models:?}"
    );
    // Sorted, so the rendering is stable across reads.
    let mut sorted = models.clone();
    sorted.sort_unstable();
    assert_eq!(models, sorted);
}

#[tokio::test]
async fn a_breaker_read_failure_is_a_server_error_not_a_healthy_answer() {
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_A).await;
    seed_own_credential(&ports, USER_A, VAULT_KEY_A, "sk-caller-a").await;
    *ports.ai_provider_health.error.lock().await = Some("provider_health read model down".into());
    let state = state(ports).await;

    let error = call(&state, USER_A, "eurouter", None)
        .await
        .expect_err("a broken read model must not render as 'all closed'");
    assert_eq!(error.into_problem().status, 500);
}

#[tokio::test]
async fn a_revoked_config_is_not_a_configured_credential() {
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_A).await;
    seed_own_credential(&ports, USER_A, VAULT_KEY_A, "sk-caller-a").await;
    {
        let mut views = ports.ai_config_repo.views.lock().await;
        for view in views.values_mut() {
            view.revoked = true;
        }
    }
    let state = state(ports.clone()).await;

    let (_, body) = body_json(
        call(&state, USER_A, "eurouter", None)
            .await
            .expect("the read succeeds"),
    )
    .await;

    assert_eq!(body["credential_configured"], false);
    assert!(ports.ai_provider_account_probe.recorded().await.is_empty());
}

#[tokio::test]
async fn the_response_is_not_stored_by_any_intermediary() {
    // A budget number is account-scoped: an HTTP cache must never replay one
    // caller's answer to another.
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_A).await;
    seed_own_credential(&ports, USER_A, VAULT_KEY_A, "sk-caller-a").await;
    let state = state(ports).await;

    let response = call(&state, USER_A, "eurouter", None)
        .await
        .expect("the read succeeds");
    assert_eq!(
        response
            .headers()
            .get(axum::http::header::CACHE_CONTROL)
            .and_then(|value| value.to_str().ok()),
        Some("no-store")
    );
}

#[tokio::test]
async fn an_over_long_model_query_is_422() {
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_A).await;
    let state = state(ports).await;
    let too_long = Arc::new("m".repeat(201));

    let error = call(&state, USER_A, "eurouter", Some(too_long.as_str()))
        .await
        .expect_err("an unbounded key must be refused");
    assert_eq!(error.into_problem().status, 422);
}

#[tokio::test]
async fn an_active_config_behind_a_page_of_revoked_ones_is_still_found() {
    // Revoked rows are history and never become bindings — but they must not be
    // able to HIDE a live one. A single fixed page would have read only the 50
    // newest (here: all revoked) rows and answered `credential_configured:
    // false` for a caller whose binding is intact.
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_A).await;
    seed_own_credential(&ports, USER_A, VAULT_KEY_A, "sk-caller-a").await;
    {
        let mut views = ports.ai_config_repo.views.lock().await;
        // Deterministic order (the fake mirrors production's newest-first by
        // id): every revoked row outranks the one active row, which therefore
        // only appears on the SECOND page.
        for index in 0..120u128 {
            let mut revoked = ai_config(USER_A, VAULT_KEY_A);
            revoked.id = uuid::Uuid::from_u128(1_000_000 + index);
            revoked.revoked = true;
            views.insert(revoked.id, revoked);
        }
        for view in views.values_mut() {
            if !view.revoked {
                view.id = uuid::Uuid::from_u128(1);
            }
        }
    }
    *ports.ai_provider_account_probe.snapshot.lock().await = AccountProbeSnapshot {
        status: AccountProbeStatus::Usable,
        budget: None,
    };
    let state = state(ports.clone()).await;

    let (status, body) = body_json(
        call(&state, USER_A, "eurouter", None)
            .await
            .expect("the read succeeds"),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        body["credential_configured"], true,
        "the active config behind the revoked page is the caller's credential"
    );
    let recorded = ports.ai_provider_account_probe.recorded().await;
    assert_eq!(recorded.len(), 1);
    assert_eq!(recorded[0].vault_key_id, VAULT_KEY_A);
}

#[tokio::test]
async fn a_model_scoped_read_still_reports_the_callers_provider_credential() {
    // `?model=` scopes the breaker snapshot; it does not answer "do I have a
    // credential at this provider". A caller with a binding for model A and a
    // request for model B has one, and every hosted probe is account-scoped.
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_A).await;
    seed_own_credential(&ports, USER_A, VAULT_KEY_A, "sk-caller-a").await;
    *ports.ai_provider_account_probe.snapshot.lock().await = AccountProbeSnapshot {
        status: AccountProbeStatus::Usable,
        budget: None,
    };
    let state = state(ports.clone()).await;

    let (_, body) = body_json(
        call(
            &state,
            USER_A,
            "eurouter",
            Some("a-model-nobody-configured"),
        )
        .await
        .expect("the read succeeds"),
    )
    .await;

    assert_eq!(
        body["credential_configured"], true,
        "an unmatched model must fall back to the provider's first binding"
    );
    let recorded = ports.ai_provider_account_probe.recorded().await;
    assert_eq!(recorded.len(), 1);
    assert_eq!(recorded[0].vault_key_id, VAULT_KEY_A);
    assert_eq!(recorded[0].key.as_deref(), Some("sk-caller-a"));
}

#[tokio::test]
async fn an_unfinished_config_scan_is_a_503_not_a_partial_credential_state() {
    // The page loop is bounded, so it can stop before the end. An incomplete
    // scan must NOT be answered: it would report `credential_configured` from
    // rows nobody read, which is the very defect the paging fixes, one order of
    // magnitude further out. Failing closed is the honest answer, and the route
    // already declares the 503 the client renders as "read failed + retry".
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_A).await;
    seed_own_credential(&ports, USER_A, VAULT_KEY_A, "sk-caller-a").await;
    {
        let mut views = ports.ai_config_repo.views.lock().await;
        // Exactly the ceiling: every page comes back full, so the loop cannot
        // prove it reached the end.
        for index in 0..5000u128 {
            let mut config = ai_config(USER_A, VAULT_KEY_A);
            config.id = uuid::Uuid::from_u128(2_000_000 + index);
            config.revoked = true;
            views.insert(config.id, config);
        }
    }
    let state = state(ports.clone()).await;

    let error = call(&state, USER_A, "eurouter", None)
        .await
        .expect_err("an unfinished scan must not answer a credential state");
    assert_eq!(error.into_problem().status, 503);
    assert!(ports.ai_provider_account_probe.recorded().await.is_empty());
}

#[tokio::test]
async fn a_local_provider_is_measured_without_any_stored_key() {
    // A `LocalTags` provider (Ollama) reads its own endpoint and needs no Vault
    // binding, so a caller with no config at all still gets a MEASURED verdict
    // next to `credential_configured: false`. The two fields answer different
    // questions; the contract must not claim that the first forces `unknown`.
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_A).await;
    *ports.ai_provider_account_probe.snapshot.lock().await = AccountProbeSnapshot {
        status: AccountProbeStatus::Usable,
        budget: None,
    };
    let state = state(ports.clone()).await;

    let (status, body) = body_json(
        call(&state, USER_A, "ollama", None)
            .await
            .expect("a local provider needs no stored credential"),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        body["credential_configured"], false,
        "no key is stored — and none is required"
    );
    assert_eq!(
        body["probe_status"], "usable",
        "the local probe measured the endpoint, so its verdict is the answer"
    );
    assert_eq!(body["budget"], serde_json::Value::Null);
    let recorded = ports.ai_provider_account_probe.recorded().await;
    assert_eq!(recorded.len(), 1);
    assert_eq!(recorded[0].provider, LlmProvider::Ollama);
    assert_eq!(recorded[0].key, None);
}

/// Issue #1013: the vision slot can name the SAME provider with a different
/// model (and its own credential). The health read must list it as a configured
/// pair, otherwise the operator sees a healthy text row while the page-image
/// model — the one that actually bills the images — is invisible.
#[tokio::test]
async fn the_configured_vision_model_appears_as_a_bound_pair() {
    let ports = FakePorts::default();
    seed_credential_member(&ports, USER_A).await;
    seed_own_credential(&ports, USER_A, VAULT_KEY_A, "sk-caller-a").await;
    // Give the caller's config a vision slot on the SAME provider but with its
    // own credential, which is the "split billing, one provider" shape.
    {
        let mut views = ports.ai_config_repo.views.lock().await;
        let config = views
            .values_mut()
            .next()
            .expect("the seeded config must exist");
        config.vision_provider = Some(LlmProvider::EURouter);
        config.vision_model = Some(VISION_MODEL.to_owned());
        config.vision_vault_key_id = Some(VAULT_KEY_A.to_owned());
    }
    let state = state(ports.clone()).await;

    let response = call(&state, USER_A, "eurouter", None)
        .await
        .expect("a credential-role member may read their provider health");
    let (status, body) = body_json(response).await;
    assert_eq!(status, StatusCode::OK);

    let models: Vec<&str> = body["breakers"]
        .as_array()
        .expect("breakers is an array")
        .iter()
        .filter_map(|row| row["model"].as_str())
        .collect();
    assert!(
        models.contains(&MODEL),
        "the assistant model must stay listed: {models:?}"
    );
    assert!(
        models.contains(&VISION_MODEL),
        "the vision model must be listed as a configured pair (issue #1013): {models:?}"
    );
}
