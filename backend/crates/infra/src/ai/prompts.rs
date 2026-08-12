// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
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

pub fn default_prompt(kind: DocumentKind) -> Result<String, DomainError> {
    let source = match std::env::var("AI_IMPORT_DEFAULT_PROMPTS_PATH") {
        Ok(path) if !path.trim().is_empty() => std::fs::read_to_string(&path).map_err(|error| {
            DomainError::validation(format!("could not read AI prompt config {path}: {error}"))
        })?,
        _ => include_str!("../../../../config/default_ai_prompts.toml").to_owned(),
    };
    let file: PromptFile = toml::from_str(&source)
        .map_err(|error| DomainError::validation(format!("invalid default AI prompts: {error}")))?;
    let prompt = match kind {
        DocumentKind::Script => file.script.text,
        DocumentKind::Schedule => file.schedule.text,
    };
    if prompt.trim().is_empty() {
        return Err(DomainError::validation(
            "default AI prompt must not be empty",
        ));
    }
    Ok(prompt)
}
