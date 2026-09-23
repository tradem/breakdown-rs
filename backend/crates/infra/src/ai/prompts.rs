// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)

use breakdown_core::ai::DocumentKind;
use breakdown_core::error::DomainError;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct PromptFile {
    script: PromptEntry,
    schedule: PromptEntry,
}

#[derive(Debug, Deserialize)]
struct PromptEntry {
    text: String,
}

/// The two prompt defaults served by `GET /v1/ai-import/defaults` (issue
/// #471): one text per document kind, read from the deployment's configured
/// prompt file (`AI_IMPORT_DEFAULT_PROMPTS_PATH`) or the built-in fallback.
#[derive(Debug, Clone)]
pub struct AiPromptDefaults {
    pub script: String,
    pub schedule: String,
}

fn load_prompt_file() -> Result<PromptFile, DomainError> {
    let source = match std::env::var("AI_IMPORT_DEFAULT_PROMPTS_PATH") {
        Ok(path) if !path.trim().is_empty() => std::fs::read_to_string(&path).map_err(|error| {
            DomainError::validation(format!("could not read AI prompt config {path}: {error}"))
        })?,
        _ => include_str!("../../../../config/default_ai_prompts.toml").to_owned(),
    };
    toml::from_str(&source)
        .map_err(|error| DomainError::validation(format!("invalid default AI prompts: {error}")))
}

/// The single-source defaults for both document kinds. Reads the prompt file
/// once and validates both entries, so the wire endpoint and the per-kind
/// worker seeding never drift (issue #471).
pub fn default_prompts() -> Result<AiPromptDefaults, DomainError> {
    let file = load_prompt_file()?;
    if file.script.text.trim().is_empty() {
        return Err(DomainError::validation(
            "default AI script prompt must not be empty",
        ));
    }
    if file.schedule.text.trim().is_empty() {
        return Err(DomainError::validation(
            "default AI schedule prompt must not be empty",
        ));
    }
    Ok(AiPromptDefaults {
        script: file.script.text,
        schedule: file.schedule.text,
    })
}

pub fn default_prompt(kind: DocumentKind) -> Result<String, DomainError> {
    let defaults = default_prompts()?;
    let prompt = match kind {
        DocumentKind::Script => defaults.script,
        DocumentKind::Schedule => defaults.schedule,
    };
    if prompt.trim().is_empty() {
        return Err(DomainError::validation(
            "default AI prompt must not be empty",
        ));
    }
    Ok(prompt)
}
