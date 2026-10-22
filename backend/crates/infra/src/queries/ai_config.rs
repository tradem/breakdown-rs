// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: qwen3.8-flash (opencode-go)

use breakdown_core::ai::{
    AiConfigRepository, AiConfigView, CostDisplayPreference, DecisionRubric, DocumentKind,
    LlmProvider,
};
use breakdown_core::error::DomainError;
use breakdown_core::error_registry::AI_CONFIG_NOT_FOUND;
use breakdown_core::shared::{AggregateVersion, UserId};
use sqlx::postgres::PgRow;
use sqlx::{PgPool, Row};
use std::collections::HashMap;
use uuid::Uuid;

/// Per-user AI configuration needed by the import worker loop to build an
/// LLM client for a claimed job. The job carries `user_id` but not a config
/// id, so the loop resolves the user's active config first.
#[derive(Debug, Clone)]
pub struct AiWorkerConfig {
    pub config_id: Uuid,
    pub provider: LlmProvider,
    pub model: String,
    pub prompt: String,
    pub vault_key_id: String,
    /// Optional Decision Model slot (issue #722). `None` = no scoring pass.
    pub decision: Option<AiWorkerDecisionConfig>,
}

/// The resolved Decision Model configuration for one claimed job (issue
/// #722): which provider/model evaluates the rubric and which vaulted
/// credential authorizes it. All-or-nothing by construction (the aggregate
/// validates the triple as a whole).
#[derive(Debug, Clone)]
pub struct AiWorkerDecisionConfig {
    pub provider: LlmProvider,
    pub model: String,
    pub vault_key_id: String,
}

#[derive(Clone, Debug)]
pub struct AiConfigRepositoryImpl {
    pool: PgPool,
}

impl AiConfigRepositoryImpl {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Resolve the active AI config for `user_id` and `kind`'s prompt.
    ///
    /// The worker loop needs provider + model + prompt + vault reference to
    /// build an LLM client for a claimed job, but the job only carries
    /// `user_id`. This query returns exactly that bundle. It prefers the
    /// user's own config and falls back to no row (caller maps the miss to a
    /// terminal job failure) — there is no synthetic global default because
    /// the API key lives in the per-user vault binding.
    pub async fn find_worker_config(
        &self,
        user_id: &UserId,
        kind: DocumentKind,
    ) -> Result<Option<AiWorkerConfig>, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, provider, assistant_model, prompts, vault_key_id,
                   decision_provider, decision_model, decision_vault_key_id
            FROM ai_import.projection_ai_config
            WHERE user_id = $1 AND revoked = FALSE
            ORDER BY updated_at DESC
            LIMIT 1
            "#,
        )
        .bind(user_id.as_str())
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;

        let Some(row) = row else {
            return Ok(None);
        };

        let provider = parse_provider(row.try_get("provider").map_err(map_sqlx_error)?)?;
        let prompt = parse_prompt_for_kind(&row, &kind)?;

        // Decision Model slot (issue #722): all three columns are NULL or
        // all set (the aggregate validates the triple). A partially-set row
        // (hand-edited projection) degrades to no scoring pass — never a
        // half-configured client.
        let decision_provider: Option<String> =
            row.try_get("decision_provider").map_err(map_sqlx_error)?;
        let decision_model: Option<String> =
            row.try_get("decision_model").map_err(map_sqlx_error)?;
        let decision_vault_key_id: Option<String> = row
            .try_get("decision_vault_key_id")
            .map_err(map_sqlx_error)?;
        let decision = match (
            decision_provider.as_deref(),
            decision_model.as_deref(),
            decision_vault_key_id.as_deref(),
        ) {
            (Some(raw_provider), Some(model), Some(vault_key_id))
                if !model.trim().is_empty() && !vault_key_id.trim().is_empty() =>
            {
                match parse_provider(raw_provider.to_owned()) {
                    Ok(provider) => Some(AiWorkerDecisionConfig {
                        provider,
                        model: model.to_owned(),
                        vault_key_id: vault_key_id.to_owned(),
                    }),
                    // An unknown provider string is a projection-integrity
                    // defect; degrade to no scoring pass and keep the job
                    // runnable (the scoring pass is best-effort by design).
                    Err(_) => {
                        tracing::warn!(
                            "ai worker config: unknown decision provider '{raw_provider}'; disabling the scoring pass"
                        );
                        None
                    }
                }
            }
            _ => None,
        };

        Ok(Some(AiWorkerConfig {
            config_id: row.try_get("id").map_err(map_sqlx_error)?,
            provider,
            model: row.try_get("assistant_model").map_err(map_sqlx_error)?,
            prompt,
            vault_key_id: row.try_get("vault_key_id").map_err(map_sqlx_error)?,
            decision,
        }))
    }
}

#[async_trait::async_trait]
impl AiConfigRepository for AiConfigRepositoryImpl {
    async fn find_by_id(&self, id: Uuid) -> Result<AiConfigView, DomainError> {
        let row = sqlx::query(
            r#"
            SELECT id, user_id, provider, assistant_model, image_model,
                   prompts, vault_key_id, cost_display_preference,
                   decision_provider, decision_model, decision_vault_key_id,
                   revoked, version
            FROM ai_import.projection_ai_config
            WHERE id = $1
            "#,
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?
        .ok_or(DomainError::NotFound {
            code: &AI_CONFIG_NOT_FOUND,
            resource: "ai-config",
            id,
        })?;

        map_config_row(&row)
    }

    /// List the caller's configs, newest first (issue #337).
    ///
    /// `LIMIT`/`OFFSET` are clamped to a sane range: `LIMIT`/`ORDER BY`
    /// cannot be bound as identifiers, so the values are sanitized in Rust
    /// (static SQL, `.bind()` for the user id — no string interpolation,
    /// AGENTS.md §3).
    async fn list_for_user(
        &self,
        user_id: &UserId,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<AiConfigView>, DomainError> {
        let limit = limit.clamp(1, 100);
        let offset = offset.max(0);
        let rows = sqlx::query(
            r#"
            SELECT id, user_id, provider, assistant_model, image_model,
                   prompts, vault_key_id, cost_display_preference,
                   decision_provider, decision_model, decision_vault_key_id,
                   revoked, version
            FROM ai_import.projection_ai_config
            WHERE user_id = $1
            ORDER BY updated_at DESC, id DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id.as_str())
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await
        .map_err(map_sqlx_error)?;
        rows.iter().map(map_config_row).collect()
    }
}

/// Map one `projection_ai_config` row to its view. Shared by `find_by_id`
/// and `list_for_user` so the parsing logic and its error messages stay in
/// one place.
fn map_config_row(row: &PgRow) -> Result<AiConfigView, DomainError> {
    let provider = parse_provider(row.try_get("provider").map_err(map_sqlx_error)?)?;
    let prompts: HashMap<DocumentKind, String> = row
        .try_get::<serde_json::Value, _>("prompts")
        .map_err(map_sqlx_error)
        .and_then(|value| {
            serde_json::from_value(value).map_err(|error| {
                DomainError::validation(format!("invalid AI prompt projection: {error}"))
            })
        })?;
    let mut prompt_kinds: Vec<_> = prompts.keys().copied().collect();
    prompt_kinds.sort_by_key(|kind| kind.as_str());
    // A kind is "stored" only when the text actually has content: a blank
    // value round-trips through JSONB as an empty string, and the worker
    // resolution below treats blank and absent identically (deployment
    // default), so the view must not claim a snapshot is in effect for it.
    let mut stored_prompt_kinds: Vec<_> = prompts
        .iter()
        .filter(|(_, prompt)| !prompt.trim().is_empty())
        .map(|(kind, _)| *kind)
        .collect();
    stored_prompt_kinds.sort_by_key(|kind| kind.as_str());
    Ok(AiConfigView {
        id: row.try_get("id").map_err(map_sqlx_error)?,
        user_id: UserId::from_sub(
            row.try_get::<String, _>("user_id")
                .map_err(map_sqlx_error)?,
        ),
        provider,
        assistant_model: row.try_get("assistant_model").map_err(map_sqlx_error)?,
        image_model: row.try_get("image_model").map_err(map_sqlx_error)?,
        prompts,
        prompt_kinds,
        stored_prompt_kinds,
        vault_key_id: row.try_get("vault_key_id").map_err(map_sqlx_error)?,
        cost_display_preference: parse_cost_display_preference(
            row.try_get("cost_display_preference")
                .map_err(map_sqlx_error)?,
        ),
        decision_provider: parse_optional_decision_provider(row)?,
        decision_model: row
            .try_get::<Option<String>, _>("decision_model")
            .map_err(map_sqlx_error)?,
        // The vault key reference is an opaque binding key, not a secret —
        // the same exposure level as `vault_key_id` on the same view.
        decision_vault_key_id: row
            .try_get::<Option<String>, _>("decision_vault_key_id")
            .map_err(map_sqlx_error)?,
        version: {
            let raw: i64 = row.try_get("version").map_err(map_sqlx_error)?;
            if raw < 0 {
                // Projection-integrity defect: a permanent condition, not a
                // transient service failure — retries cannot fix it.
                return Err(DomainError::validation(
                    "AI config aggregate version cannot be negative",
                ));
            }
            AggregateVersion(raw as u64)
        },
        revoked: row.try_get("revoked").map_err(map_sqlx_error)?,
    })
}

/// Parse the optional `decision_provider` projection column (issue #722).
/// An unknown value degrades to `None` with a warning instead of failing the
/// read — a decision configuration must never 500 a config fetch.
fn parse_optional_decision_provider(row: &PgRow) -> Result<Option<LlmProvider>, DomainError> {
    let raw: Option<String> = row.try_get("decision_provider").map_err(map_sqlx_error)?;
    Ok(match raw.as_deref() {
        None => None,
        Some(value) => match parse_provider(value.to_owned()) {
            Ok(provider) => Some(provider),
            Err(_) => {
                tracing::warn!(
                    "ai config projection: unknown decision provider '{value}'; reporting none"
                );
                None
            }
        },
    })
}

/// Silence the unused-import lint when `DecisionRubric` is only re-exported
/// by workers through this module path in later phases.
#[allow(dead_code)]
fn _rubric_type_witness(_: Option<DecisionRubric>) {}

fn parse_provider(value: String) -> Result<LlmProvider, DomainError> {
    match value.as_str() {
        "openai" => Ok(LlmProvider::OpenAI),
        "gemini" | "google" => Ok(LlmProvider::Gemini),
        "openrouter" => Ok(LlmProvider::OpenRouter),
        "eurouter" | "openrouter_eu" => Ok(LlmProvider::EURouter),
        "neuralwatt" => Ok(LlmProvider::Neuralwatt),
        "opencode-go" => Ok(LlmProvider::OpenCodeGo),
        "opencode" => Ok(LlmProvider::OpenCode),
        "ollama" => Ok(LlmProvider::Ollama),
        other => Err(DomainError::validation(format!(
            "unknown AI provider projection {other}"
        ))),
    }
}

/// Parse the `cost_display_preference` projection column (issue #675). Rows
/// written before the column existed carry the migration default `token`;
/// an unknown value falls back to `Token` instead of failing the read (a
/// display preference must never 500 a config fetch).
fn parse_cost_display_preference(value: String) -> CostDisplayPreference {
    match value.as_str() {
        "energy" => CostDisplayPreference::Energy,
        _ => CostDisplayPreference::Token,
    }
}

/// Deserialize the `prompts` JSONB column and return the prompt for `kind`.
/// Shared by `find_by_id` (which only needs the deserialized map) and
/// `find_worker_config` (which extracts one prompt), so the parsing logic and
/// its error messages stay in one place.
/// Resolve the prompt an import of `kind` runs with (design D6).
///
/// A stored, non-blank prompt wins — it is the operator's own text and a
/// deployment must not overwrite it behind their back. A blank or absent one
/// falls back to the deployment default instead of failing the job: an AI job
/// that died with "no prompt configured" over an empty field was never the
/// intent, and the default exists precisely to be the fallback. The stored
/// prompt's precedence is what the configuration surface has to disclose
/// (`AiConfigView::stored_prompt_kinds`), because it means the configuration
/// keeps a snapshot and does not follow later default updates.
pub(crate) fn resolve_prompt(
    stored: Option<&String>,
    kind: &DocumentKind,
) -> Result<String, DomainError> {
    match stored
        .map(|prompt| prompt.as_str())
        .filter(|prompt| !prompt.trim().is_empty())
    {
        Some(prompt) => Ok(prompt.to_owned()),
        None => crate::ai::prompts::default_prompt(*kind),
    }
}

fn parse_prompt_for_kind(row: &PgRow, kind: &DocumentKind) -> Result<String, DomainError> {
    let prompts: HashMap<DocumentKind, String> = row
        .try_get::<serde_json::Value, _>("prompts")
        .map_err(map_sqlx_error)
        .and_then(|value| {
            serde_json::from_value(value).map_err(|error| {
                DomainError::validation(format!("invalid AI prompt projection: {error}"))
            })
        })?;
    resolve_prompt(prompts.get(kind), kind)
}

fn map_sqlx_error(error: sqlx::Error) -> DomainError {
    DomainError::service_unavailable(format!("AI config database error: {error}"))
}

#[cfg(test)]
mod prompt_resolution_tests {
    use super::resolve_prompt;
    use crate::ai::default_prompt;
    use breakdown_core::ai::DocumentKind;

    /// Design D6's precedence, in both directions.
    #[test]
    fn a_stored_prompt_wins_over_the_deployment_default() {
        let stored = "my own extraction spec".to_owned();
        let resolved = resolve_prompt(Some(&stored), &DocumentKind::Script).unwrap();
        assert_eq!(resolved, stored);
        assert_ne!(
            resolved,
            default_prompt(DocumentKind::Script).unwrap(),
            "the test would pass even if the default were returned"
        );
    }

    /// The scenario the spec names "an empty stored prompt", plus the legacy
    /// shape that motivated it: a kind the configuration never carried. Both
    /// must import with the deployment default rather than fail the job.
    #[test]
    fn blank_or_absent_falls_back_to_the_deployment_default() {
        for kind in [DocumentKind::Script, DocumentKind::Schedule] {
            let expected = default_prompt(kind).unwrap();
            for stored in [None, Some(String::new()), Some("   \n ".to_owned())] {
                assert_eq!(
                    resolve_prompt(stored.as_ref(), &kind).unwrap(),
                    expected,
                    "kind {kind:?} with stored {stored:?} must follow the default"
                );
            }
        }
    }
}
