// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

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
use breakdown_core::ai::{LlmChatRequest, LlmClient, LlmProvider, ScriptContext};
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

    let client = OpenAiCompatibleChatClient::new(provider, api_key, Duration::from_secs(120))?;
    let context = client
        .chat_constrained(LlmChatRequest {
            provider,
            model,
            prompt: "Parse the following screenplay into scenes. Leave fields you \
                     cannot read as null; do not invent values."
                .to_owned(),
            source_text: SMALL_SCRIPT.to_owned(),
            max_tokens: 2048,
            response_schema: None,
        })
        .await
        .context("live LLM call failed")?;

    assert!(
        !context.scenes.is_empty(),
        "LLM returned a ScriptContext without scenes"
    );
    for scene in &context.scenes {
        assert!(
            !scene
                .summary
                .as_deref()
                .unwrap_or_default()
                .trim()
                .is_empty(),
            "scene {scene:?} carries no summary"
        );
    }
    let _: ScriptContext = context;
    Ok(())
}
