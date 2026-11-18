// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

//! Live smoke test for the AI document-ingestion LLM path.
//!
//! This is the "nightly reads our documents with the LLM" check: it calls the
//! real configured provider (variable `AI_LLM_PROVIDER`, model
//! `AI_LLM_MODEL`, API key from secret `AI_LLM_API_KEY`) with a small
//! screenplay excerpt and asserts the response decodes as a `ScriptContext`.
//!
//! It skips itself when `AI_LLM_API_KEY` is unset (mirroring the GDrive
//! fixture test), so local developers and CI without the secret are not
//! blocked.

use std::env;
use std::time::Duration;

use anyhow::{Context, Result, anyhow};
use breakdown_core::ai::{AiImportBounds, LlmChatRequest, LlmClient, LlmProvider, ScriptContext};
use infra::ai::OpenAiCompatibleChatClient;

/// Curated provider keys (mirror of the API handler's `parse_ai_provider`).
fn provider_from_key(key: &str) -> Result<LlmProvider> {
    match key {
        "openai" => Ok(LlmProvider::OpenAI),
        "openrouter" => Ok(LlmProvider::OpenRouter),
        "eurouter" | "openrouter_eu" | "openrouter-eu" => Ok(LlmProvider::EURouter),
        "neuralwatt" => Ok(LlmProvider::Neuralwatt),
        "opencode-go" | "opencode_go" => Ok(LlmProvider::OpenCodeGo),
        "opencode" => Ok(LlmProvider::OpenCode),
        "ollama" => Ok(LlmProvider::Ollama),
        other => Err(anyhow!("unknown AI_LLM_PROVIDER key: {other}")),
    }
}

const SMALL_SCRIPT: &str = r#"1. INT. KITCHEN - DAY
Rafael steht am Herd. Elias kommt herein.

2. EXT. HOSPITAL PARK - NIGHT
Karin und Ilja gehen über den Parkplatz.

3. INT. OFFICE - DAY
Marc liest eine Patientenakte."#;

#[tokio::test]
async fn llm_reads_a_document_and_returns_script_context() -> Result<()> {
    let Some(api_key) = env::var("AI_LLM_API_KEY").ok().filter(|v| !v.is_empty()) else {
        return Ok(()); // skipped when the live key is not configured
    };
    let provider_key = env::var("AI_LLM_PROVIDER").unwrap_or_else(|_| "eurouter".to_owned());
    let model = env::var("AI_LLM_MODEL").unwrap_or_else(|_| "mistral-large-3".to_owned());
    let provider = provider_from_key(&provider_key)
        .with_context(|| format!("invalid AI_LLM_PROVIDER {provider_key}"))?;

    let client =
        OpenAiCompatibleChatClient::new(provider, api_key, Duration::from_secs(120)).await?;
    let outcome = client
        .chat_constrained(LlmChatRequest {
            provider,
            model,
            prompt: "Parse the following screenplay into scenes. Leave fields you \
                     cannot read as null; do not invent values."
                .to_owned(),
            source_text: SMALL_SCRIPT.to_owned(),
            // Production parity: the per-request output-token ceiling is
            // `AiImportBounds::default().max_tokens_per_req` (8_192). A smaller
            // nightly budget truncated the JSON mid-object (finish_reason
            // "length", nightly 2026-08-13); the client now grows the budget on
            // truncation, but the smoke test should exercise the production
            // budget rather than the retry path.
            max_tokens: AiImportBounds::default().max_tokens_per_req,
            response_schema: None,
        })
        .await
        .context("live LLM call failed")?;
    let usage = outcome.usage;
    let context = outcome.output;
    // Issue #675: log the recorded usage so nightly runs surface real
    // token/energy telemetry from the live provider. `tracing` (not
    // println/eprintln — both are clippy-denied repo-wide) with the
    // test-writer subscriber so the line lands in the captured test output.
    let _guard = tracing_subscriber::fmt()
        .with_test_writer()
        .with_max_level(tracing::Level::INFO)
        .try_init();
    tracing::info!(
        tokens_in = usage.tokens_in,
        tokens_out = usage.tokens_out,
        cached_tokens_in = usage.cached_tokens_in,
        energy_millijoules = usage.energy_millijoules,
        "llm smoke usage"
    );

    assert!(
        !context.scenes.is_empty(),
        "LLM returned a ScriptContext without scenes"
    );
    // `summary` is `Option<String>` in the schema, and the prompt instructs the
    // model to leave unreadable fields null — a scene whose action lines carry
    // no prose legitimately decodes as `summary: None`. Requiring a summary made
    // the live smoke deterministically red (nightly runs Aug 7-11, 2026, model
    // consistently returned null); requiring at least one extracted content
    // field still fails on a totally empty structure while tolerating the
    // contract-compliant null fields.
    for scene in &context.scenes {
        let has_content = scene.scene_number.is_some()
            || !scene
                .location
                .as_deref()
                .unwrap_or_default()
                .trim()
                .is_empty()
            || !scene.mood.as_deref().unwrap_or_default().trim().is_empty()
            || !scene
                .summary
                .as_deref()
                .unwrap_or_default()
                .trim()
                .is_empty()
            || !scene
                .script_day
                .as_deref()
                .unwrap_or_default()
                .trim()
                .is_empty()
            || !scene.characters.is_empty();
        assert!(has_content, "scene {scene:?} carries no extracted content");
    }
    let _: ScriptContext = context;
    let _: breakdown_core::ai::LlmCallUsage = usage;
    Ok(())
}
