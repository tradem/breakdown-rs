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
use breakdown_core::ai::ports::{AiConfigCommands, LlmProvider};
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
const EXTRACTION_MODEL: &str = "mistral-large-3";

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
                version: created.1,
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

    Ok(())
}
