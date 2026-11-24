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
    /// CodeRabbit review, PR #967: the flat (legacy-PDF / plain-text) schedule
    /// path gets its own prompt — its input is flattened text and its output
    /// schema is `ShootingSchedule`, not the page-image `SchedulePageExtraction`
    /// contract the `[schedule]` prompt describes. OPTIONAL so an older
    /// deployment prompt file without `[schedule_flat]` keeps loading
    /// (CodeRabbit's PR #967 follow-up): the built-in flat default fills in.
    #[serde(default)]
    schedule_flat: Option<PromptEntry>,
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
    /// Flat-path schedule prompt (flattened text in, `ShootingSchedule` out).
    pub schedule_flat: String,
}

/// The prompt file compiled into the binary: the fallback `load_prompt_file`
/// serves when no deployment override is configured. Exposed `pub(crate)` so
/// a regression test can assert on the *embedded* wording even when
/// `AI_IMPORT_DEFAULT_PROMPTS_PATH` points at a deployment's own prompt file
/// (CodeRabbit, issue #607) — the test and the fallback read one constant, so
/// they cannot drift apart.
pub(crate) const EMBEDDED_PROMPT_FILE: &str =
    include_str!("../../../../config/default_ai_prompts.toml");

fn load_prompt_file() -> Result<PromptFile, DomainError> {
    let source = match std::env::var("AI_IMPORT_DEFAULT_PROMPTS_PATH") {
        Ok(path) if !path.trim().is_empty() => std::fs::read_to_string(&path).map_err(|error| {
            DomainError::validation(format!("could not read AI prompt config {path}: {error}"))
        })?,
        _ => EMBEDDED_PROMPT_FILE.to_owned(),
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
    // A deployment override without a `[schedule_flat]` entry (or with a
    // blank one) falls back to the BUILT-IN flat prompt — never to the
    // page-image prompt, and never to a load failure (CodeRabbit's PR #967
    // follow-up).
    let schedule_flat = match file.schedule_flat {
        Some(entry) if !entry.text.trim().is_empty() => entry.text,
        _ => built_in_flat_schedule_prompt()?,
    };
    Ok(AiPromptDefaults {
        script: file.script.text,
        schedule: file.schedule.text,
        schedule_flat,
    })
}

/// The built-in `[schedule_flat]` text, read from the compiled-in prompt file
/// (independent of `AI_IMPORT_DEFAULT_PROMPTS_PATH`), so a deployment override
/// that predates the flat prompt still gets a working flat default.
fn built_in_flat_schedule_prompt() -> Result<String, DomainError> {
    let file: PromptFile = toml::from_str(EMBEDDED_PROMPT_FILE).map_err(|error| {
        DomainError::validation(format!("invalid built-in AI prompts: {error}"))
    })?;
    file.schedule_flat
        .map(|entry| entry.text)
        .filter(|text| !text.trim().is_empty())
        .ok_or_else(|| {
            DomainError::validation(
                "the built-in AI prompt file must carry a [schedule_flat] entry",
            )
        })
}

/// The flat-path schedule prompt (CodeRabbit review, PR #967). Stored
/// configuration prompts cannot override it yet — the stored-prompt map is
/// keyed by [`DocumentKind`], and the flat path is a transport detail of the
/// same schedule job, not a third kind.
pub fn default_flat_schedule_prompt() -> Result<String, DomainError> {
    let defaults = default_prompts()?;
    let prompt = defaults.schedule_flat;
    if prompt.trim().is_empty() {
        return Err(DomainError::validation(
            "default AI flat-schedule prompt must not be empty",
        ));
    }
    Ok(prompt)
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
