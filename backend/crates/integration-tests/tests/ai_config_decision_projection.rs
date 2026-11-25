// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
//! Contract: a Decision Model written through the real command adapter reaches
//! the projection and is visible to the worker (issue #769).
//!
//! #769 reported a silent loss of a user-visible configuration change: the app
//! showed a Decision Model as saved while the aggregate held exactly two events
//! without any `decision_*` payload, the projection had all three columns NULL,
//! and the worker therefore resolved `decision: None` — no scoring pass, no
//! stars. The write path itself carries the triple correctly (tri-state
//! `UpdateAiConfig`, `#[serde(default)]` event fields, projector columns), so
//! this test pins the whole chain end to end against the production adapters:
//!
//! `AiConfigCommandsImpl::create` (no decision)
//!   → `AiConfigCommandsImpl::update` (adds the triple)
//!   → SierraDB → `spawn_ai_config_projector` → `projection_ai_config`
//!   → `AiConfigRepositoryImpl::find_worker_config` (what the worker resolves).
//!
//! A regression anywhere in that chain (a dropped request field, an event field
//! that stops round-tripping, a projector column that stops being written) fails
//! here instead of silently producing an unscored import.

mod fixtures;

use std::collections::HashMap;
use std::time::Duration;

use anyhow::{Result, anyhow};
use breakdown_core::ai::commands::{CreateAiConfig, UpdateAiConfig};
use breakdown_core::ai::ports::{AiConfigCommands, AiConfigRepository, LlmProvider};
use breakdown_core::ai::reasoning::ReasoningEffortChoice;
use breakdown_core::ai::views::{CostDisplayPreference, DocumentKind};
use breakdown_core::shared::{AggregateVersion, UserId};
use infra::event_store::AiConfigCommandsImpl;
use infra::projectors::{ProjectorFlushConfig, spawn_ai_config_projector};
use infra::queries::AiConfigRepositoryImpl;
use kameo_es::command_service::CommandService;
use sqlx::PgPool;
use uuid::Uuid;

const PROJECTION_DEADLINE: Duration = Duration::from_secs(15);
const POLL_INTERVAL: Duration = Duration::from_millis(150);
const TEST_SUB: &str = "ai-config-decision-test-user";
const DECISION_MODEL: &str = "clef-flash";
/// EURouter publishes `supported_parameters` including `reasoning_effort` for
/// `mistral-small-4` (`low|medium|high`), so it is the pair this test can store
/// an explicit level on. `mistral-large-3` declares no such parameter.
const EXTRACTION_MODEL: &str = "mistral-small-4";

fn test_user() -> UserId {
    UserId::from_sub(TEST_SUB)
}

/// Poll `projection_ai_config` until the row's `decision_model` matches the
/// expected value, returning `(decision_provider, decision_model,
/// decision_vault_key_id)`.
///
/// Polling on the *decision* columns — not on row existence — is what makes this
/// test meaningful: the create event alone inserts the row with NULL decision
/// columns, so waiting for the row would pass before the update is projected and
/// hide exactly the regression #769 describes.
async fn await_projected_decision_triple(pool: &PgPool, id: Uuid) -> Result<Option<String>> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let row: Option<(Option<String>, Option<String>)> = sqlx::query_as(
            "SELECT decision_provider, decision_model \
             FROM ai_import.projection_ai_config WHERE id = $1",
        )
        .bind(id)
        .fetch_optional(pool)
        .await
        .map_err(|e| anyhow!("projection_ai_config read failed: {e}"))?;

        if let Some((provider, model)) = row
            && provider.as_deref() == Some("eurouter")
            && model.as_deref() == Some(DECISION_MODEL)
        {
            return Ok(model);
        }
        if std::time::Instant::now() > deadline {
            anyhow::bail!(
                "decision triple not projected into ai_import.projection_ai_config in time \
                 (issue #769: the configured Decision Model must reach the read model)"
            );
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }
}

/// Poll the projected `reasoning_effort` column until it carries a level.
///
/// Polling the VALUE — not row existence — is the point: the create inserts the
/// row with `reasoning_effort` NULL, so the same row is already there before the
/// projector has written the level, and a row-existence wait would pass while the
/// column stayed empty.
async fn await_projected_reasoning_effort(pool: &PgPool, id: Uuid) -> Result<Option<String>> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let level: Option<Option<String>> = sqlx::query_scalar(
            "SELECT reasoning_effort FROM ai_import.projection_ai_config WHERE id = $1",
        )
        .bind(id)
        .fetch_optional(pool)
        .await
        .map_err(|e| anyhow!("reasoning_effort read failed: {e}"))?;

        if let Some(level) = level.flatten() {
            return Ok(Some(level));
        }
        if std::time::Instant::now() > deadline {
            anyhow::bail!(
                "reasoning_effort not projected into ai_import.projection_ai_config in time \
                 (the user-chosen level must reach the read model)"
            );
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }
}

/// Poll the projected `zdr_attested` column until it carries `expected`.
///
/// Polling the VALUE is the point: `false` is the fail-closed default the create
/// already writes, so a row-existence (or "is false") wait would pass before the
/// projector ever processed the update.
async fn await_projected_zdr(pool: &PgPool, id: Uuid, expected: bool) -> Result<()> {
    let deadline = std::time::Instant::now() + PROJECTION_DEADLINE;
    loop {
        let projected: Option<bool> = sqlx::query_scalar(
            "SELECT zdr_attested FROM ai_import.projection_ai_config WHERE id = $1",
        )
        .bind(id)
        .fetch_optional(pool)
        .await
        .map_err(|e| anyhow!("zdr_attested read failed: {e}"))?;

        if projected == Some(expected) {
            return Ok(());
        }
        if std::time::Instant::now() > deadline {
            anyhow::bail!(
                "projected zdr_attested never reached {expected} (issue #968: the attestation must \
                 reach the read model, and a credential change must clear it)"
            );
        }
        tokio::time::sleep(POLL_INTERVAL).await;
    }
}

/// Assert the attestation on all three surfaces the page call depends on: the
/// projection column, the `AiConfigView` the client renders, and the worker
/// configuration the egress gate resolves.
async fn assert_zdr_everywhere(pool: &PgPool, config_id: Uuid, expected: bool) -> Result<()> {
    await_projected_zdr(pool, config_id, expected).await?;
    let read_view = AiConfigRepositoryImpl::new(pool.clone())
        .find_by_id(config_id)
        .await
        .expect("the read model must serve the config");
    assert_eq!(
        read_view.zdr_attested, expected,
        "AiConfigView.zdr_attested (the client renders the toggle from it)"
    );
    let worker_config = AiConfigRepositoryImpl::new(pool.clone())
        .find_worker_config(&test_user(), DocumentKind::Script)
        .await
        .expect("worker config resolution must succeed")
        .expect("the caller has one active config");
    assert_eq!(
        worker_config.zdr_attested, expected,
        "the worker configuration the vision egress gate resolves"
    );
    Ok(())
}

/// A PATCH carrying nothing but what the case under test varies, so each step
/// differs from the previous one in exactly the credential or the attestation.
fn update_cmd(
    id: Uuid,
    version: AggregateVersion,
    vault_key_id: &str,
    zdr_attested: Option<bool>,
) -> UpdateAiConfig {
    UpdateAiConfig {
        id,
        provider: LlmProvider::EURouter,
        assistant_model: EXTRACTION_MODEL.to_owned(),
        image_model: None,
        prompts: HashMap::from([(DocumentKind::Script, "script-prompt".to_owned())]),
        vault_key_id: vault_key_id.to_owned(),
        cost_display_preference: None,
        decision_provider: None,
        decision_model: None,
        decision_vault_key_id: None,
        reasoning_effort: None,
        zdr_attested,
        version,
    }
}

#[tokio::test]
async fn decision_model_reaches_projection_and_worker_config() -> Result<()> {
    let (pool, _pg_guard) = fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra_guard) = fixtures::spawn_sierradb().await?;

    let _projector = spawn_ai_config_projector(
        pool.clone(),
        std::sync::Arc::clone(&redis_client),
        ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let conn = redis_client.get_multiplexed_async_connection().await?;
    let commands = AiConfigCommandsImpl::new(CommandService::new(conn));

    // 1) Create a config WITHOUT a Decision Model — the state #769 found in the
    //    store (two events, no `decision_*` payload).
    let config_id = Uuid::now_v7();
    let created = commands
        .create(
            test_user(),
            CreateAiConfig {
                id: config_id,
                user_id: test_user(),
                provider: LlmProvider::EURouter,
                assistant_model: EXTRACTION_MODEL.to_owned(),
                image_model: None,
                prompts: HashMap::from([(DocumentKind::Script, "script-prompt".to_owned())]),
                vault_key_id: "extraction-key".to_owned(),
                cost_display_preference: CostDisplayPreference::Token,
                decision_provider: None,
                decision_model: None,
                decision_vault_key_id: None,
                // An EXPLICIT level, not `Auto`: the user-chosen value is what
                // has to survive command -> event -> projection -> worker.
                reasoning_effort: ReasoningEffortChoice::Low,
                zdr_attested: false,
            },
        )
        .await
        .expect("create must append AiConfigCreated");
    assert_eq!(created.0, config_id);
    assert_eq!(created.1, AggregateVersion::INITIAL);

    // 2) Add the Decision Model via PATCH — the write the app reported as saved.
    //    Same-key reuse: decision provider == extraction provider, so the
    //    extraction credential doubles as the decision credential.
    let updated = commands
        .update(
            test_user(),
            UpdateAiConfig {
                id: config_id,
                provider: LlmProvider::EURouter,
                assistant_model: EXTRACTION_MODEL.to_owned(),
                image_model: None,
                prompts: HashMap::from([(DocumentKind::Script, "script-prompt".to_owned())]),
                vault_key_id: "extraction-key".to_owned(),
                cost_display_preference: None,
                decision_provider: Some(Some(LlmProvider::EURouter)),
                decision_model: Some(Some(DECISION_MODEL.to_owned())),
                decision_vault_key_id: Some(Some("extraction-key".to_owned())),
                reasoning_effort: None,
                version: created.1,
                zdr_attested: None,
            },
        )
        .await
        .expect("update must append AiConfigUpdated with the decision triple");
    assert_eq!(
        updated,
        AggregateVersion(created.1.0 + 1),
        "adding a Decision Model must append a new aggregate version"
    );

    // 3) The projector writes the triple into the read model.
    let projected_model = await_projected_decision_triple(&pool, config_id).await?;
    assert_eq!(projected_model.as_deref(), Some(DECISION_MODEL));

    let stored_vault_key: Option<String> = sqlx::query_scalar(
        "SELECT decision_vault_key_id FROM ai_import.projection_ai_config WHERE id = $1",
    )
    .bind(config_id)
    .fetch_one(&pool)
    .await
    .map_err(|e| anyhow!("decision_vault_key_id read failed: {e}"))?;
    assert_eq!(stored_vault_key.as_deref(), Some("extraction-key"));

    // 4) The worker resolves exactly what #769 found missing.
    let worker_config = AiConfigRepositoryImpl::new(pool.clone())
        .find_worker_config(&test_user(), DocumentKind::Script)
        .await
        .expect("worker config resolution must succeed")
        .expect("the caller has one active config");
    assert_eq!(worker_config.config_id, config_id);
    let decision = worker_config
        .decision
        .expect("the worker must resolve the configured Decision Model (issue #769)");
    assert_eq!(decision.provider, LlmProvider::EURouter);
    assert_eq!(decision.model, DECISION_MODEL);
    assert_eq!(decision.vault_key_id, "extraction-key");

    // 5) The EXPLICIT level survives the whole chain — command -> event ->
    //    projection column -> read view -> worker config. Every link is asserted,
    //    because a single dropped field keeps the rest of this test green while
    //    the user's choice silently becomes `auto`.
    assert_eq!(
        await_projected_reasoning_effort(&pool, config_id).await?,
        Some("low".to_owned()),
        "the projected column must hold the declared level, not NULL"
    );
    let read_view = AiConfigRepositoryImpl::new(pool.clone())
        .find_by_id(config_id)
        .await
        .expect("the read model must serve the config");
    assert_eq!(read_view.reasoning_effort, ReasoningEffortChoice::Low);
    assert_eq!(worker_config.reasoning_effort, ReasoningEffortChoice::Low);

    Ok(())
}

/// Contract: the zero-data-retention attestation (issue #968) survives the whole
/// `command -> event -> event-store -> projector -> projection -> worker config`
/// chain, and stops applying when the CREDENTIAL it was given for is replaced.
///
/// The attestation asserts one organization's `ZDR Mode` switch, which nothing in
/// this workspace can observe. A dropped projection write, a projector that
/// maps the field for `Created` but not for `Updated`, or an aggregate that
/// inherits a stored `true` onto a replacement key would each let a page image
/// egress under a retention guarantee the account does not provide — and the
/// fixture in the #769 test cannot see any of it, because it supplies `false`
/// (indistinguishable from "never projected").
#[tokio::test]
async fn zdr_attestation_round_trips_and_is_bound_to_its_credential() -> Result<()> {
    let (pool, _pg_guard) = fixtures::spawn_postgres().await?;
    let (redis_client, _sierra_conn, _sierra_guard) = fixtures::spawn_sierradb().await?;

    let _projector = spawn_ai_config_projector(
        pool.clone(),
        std::sync::Arc::clone(&redis_client),
        ProjectorFlushConfig::test_profile(),
    )
    .await?;

    let conn = redis_client.get_multiplexed_async_connection().await?;
    let commands = AiConfigCommandsImpl::new(CommandService::new(conn));

    // 1) Create with the attestation SET.
    let config_id = Uuid::now_v7();
    let created = commands
        .create(
            test_user(),
            CreateAiConfig {
                id: config_id,
                user_id: test_user(),
                provider: LlmProvider::EURouter,
                assistant_model: EXTRACTION_MODEL.to_owned(),
                image_model: None,
                prompts: HashMap::from([(DocumentKind::Script, "script-prompt".to_owned())]),
                vault_key_id: "attested-key".to_owned(),
                cost_display_preference: CostDisplayPreference::Token,
                decision_provider: None,
                decision_model: None,
                decision_vault_key_id: None,
                reasoning_effort: ReasoningEffortChoice::Low,
                zdr_attested: true,
            },
        )
        .await
        .expect("create must append AiConfigCreated");
    assert_eq!(created.1, AggregateVersion::INITIAL);
    assert_zdr_everywhere(&pool, config_id, true).await?;

    // 2) A prompt-only edit that OMITS the field keeps it — the credential did
    //    not change, so the attestation still describes this account.
    let preserved = commands
        .update(
            test_user(),
            update_cmd(config_id, created.1, "attested-key", None),
        )
        .await
        .expect("an omitted attestation must not be rejected");
    assert_eq!(preserved, AggregateVersion(created.1.0 + 1));
    assert_zdr_everywhere(&pool, config_id, true).await?;

    // 3) Replacing the CREDENTIAL clears it: the new account's `ZDR Mode` is not
    //    observable, so the inherited `true` would be an unverified claim.
    let replaced = commands
        .update(
            test_user(),
            update_cmd(config_id, preserved, "replacement-key", None),
        )
        .await
        .expect("a key change without an attestation must still be accepted");
    assert_eq!(replaced, AggregateVersion(preserved.0 + 1));
    assert_zdr_everywhere(&pool, config_id, false).await?;

    // 4) Re-attesting the replacement account in the SAME request carries it.
    let reattested = commands
        .update(
            test_user(),
            update_cmd(config_id, replaced, "replacement-key", Some(true)),
        )
        .await
        .expect("an explicit attestation must be stored");
    assert_eq!(reattested, AggregateVersion(replaced.0 + 1));
    assert_zdr_everywhere(&pool, config_id, true).await?;

    // 5) An explicit revocation still reaches every reader.
    let revoked = commands
        .update(
            test_user(),
            update_cmd(config_id, reattested, "replacement-key", Some(false)),
        )
        .await
        .expect("an explicit revocation must be stored");
    assert_eq!(revoked, AggregateVersion(reattested.0 + 1));
    assert_zdr_everywhere(&pool, config_id, false).await?;

    Ok(())
}
