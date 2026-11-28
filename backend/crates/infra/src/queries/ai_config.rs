// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: qwen3.8-flash (opencode-go)

use breakdown_core::ai::{
    AiConfigRepository, AiConfigView, CostDisplayPreference, DocumentKind, LlmProvider,
    ReasoningEffort, ReasoningEffortChoice,
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
    /// The FLAT-path schedule prompt (CodeRabbit review, PR #967): only
    /// resolved for `DocumentKind::Schedule` jobs (the flat branch runs for
    /// legacy-PDF / plain-text sources; the page-streaming branch keeps
    /// `prompt`). `None` for script jobs.
    pub flat_prompt: Option<String>,
    /// Configured `reasoning_effort` (2026-11-20 investigation). `Auto` = no
    /// explicit level: the curated profile (if any), else the provider default.
    pub reasoning_effort: ReasoningEffortChoice,
    /// Optional Decision Model slot (issue #722). `None` = no scoring pass.
    pub decision: Option<AiWorkerDecisionConfig>,
    /// The operator's zero-data-retention attestation for this provider
    /// account (issue #968). Travels into every vision request so the
    /// pre-egress gate resolves `vision_egress_policy_for_config` from the
    /// CONFIGURED state, not from a compile-time default.
    pub zdr_attested: bool,
    /// Optional Vision slot (issue #1013): the provider/model/credential that
    /// carries PAGE IMAGES. `None` means "use the assistant pair", i.e. the
    /// pre-#1013 behaviour, and is also what a partially-set projection row
    /// degrades to (the aggregate validates the triple as a whole).
    pub vision: Option<AiWorkerVisionConfig>,
}

/// The resolved Vision slot for one claimed job (issue #1013): which
/// provider/model receives page images and which vaulted credential authorizes
/// it. All-or-nothing by construction, exactly like
/// [`AiWorkerDecisionConfig`].
#[derive(Debug, Clone)]
pub struct AiWorkerVisionConfig {
    pub provider: LlmProvider,
    pub model: String,
    /// The vision provider's credential. Equal to [`AiWorkerConfig::vault_key_id`]
    /// only when the vision provider IS the extraction provider (same-key reuse).
    pub vault_key_id: String,
    /// The attestation of the VISION provider account — a different account
    /// than the extraction one as soon as the providers differ (issue #968).
    pub zdr_attested: bool,
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
                   reasoning_effort,
                   decision_provider, decision_model, decision_vault_key_id,
                   vision_provider, vision_model, vision_vault_key_id,
                   vision_zdr_attested,
                   zdr_attested
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
        // CodeRabbit review, PR #967: the flat schedule path carries its own
        // prompt contract (flattened text in, `ShootingSchedule` out). A stored
        // `"schedule_flat"` key in the prompts JSONB wins; otherwise the
        // built-in flat default applies — never the page-streaming prompt.
        let flat_prompt = match kind {
            DocumentKind::Schedule => Some(parse_flat_schedule_prompt(&row)?),
            DocumentKind::Script => None,
        };

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

        // Vision slot (issue #1013): all four columns are set or the slot is
        // unused. A partially-set row (hand-edited projection) degrades to the
        // assistant-pair fallback — never a half-configured page client, and
        // never a reason to fail a job that would otherwise run.
        let vision_provider: Option<String> =
            row.try_get("vision_provider").map_err(map_sqlx_error)?;
        let vision_model: Option<String> = row.try_get("vision_model").map_err(map_sqlx_error)?;
        let vision_vault_key_id: Option<String> =
            row.try_get("vision_vault_key_id").map_err(map_sqlx_error)?;
        let vision = match (
            vision_provider.as_deref(),
            vision_model.as_deref(),
            vision_vault_key_id.as_deref(),
        ) {
            (Some(raw_provider), Some(model), Some(vault_key_id))
                if !model.trim().is_empty() && !vault_key_id.trim().is_empty() =>
            {
                match parse_provider(raw_provider.to_owned()) {
                    Ok(provider) => Some(AiWorkerVisionConfig {
                        provider,
                        model: model.to_owned(),
                        vault_key_id: vault_key_id.to_owned(),
                        zdr_attested: row.try_get("vision_zdr_attested").map_err(map_sqlx_error)?,
                    }),
                    // A projection-integrity defect: degrade to the assistant
                    // pair (the documented `None` contract) and say so.
                    Err(_) => {
                        tracing::warn!(
                            "ai worker config: unknown vision provider '{raw_provider}'; using the assistant pair for page images"
                        );
                        None
                    }
                }
            }
            (None, None, None) => None,
            _ => {
                tracing::warn!(
                    "ai worker config: partially set vision slot; using the assistant pair for page images"
                );
                None
            }
        };

        Ok(Some(AiWorkerConfig {
            config_id: row.try_get("id").map_err(map_sqlx_error)?,
            provider,
            model: row.try_get("assistant_model").map_err(map_sqlx_error)?,
            prompt,
            flat_prompt,
            vault_key_id: row.try_get("vault_key_id").map_err(map_sqlx_error)?,
            reasoning_effort: parse_optional_reasoning_effort(
                row.try_get::<Option<String>, _>("reasoning_effort")
                    .map_err(map_sqlx_error)?,
            ),
            decision,
            zdr_attested: row
                .try_get::<bool, _>("zdr_attested")
                .map_err(map_sqlx_error)?,
            vision,
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
                   vision_provider, vision_model, vision_vault_key_id,
                   vision_zdr_attested,
                   reasoning_effort, zdr_attested,
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
                   vision_provider, vision_model, vision_vault_key_id,
                   vision_zdr_attested,
                   reasoning_effort, zdr_attested,
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
    // String-keyed decode + filter back to document kinds (CodeRabbit's PR
    // #967 follow-up): the JSONB may additionally carry additive worker keys
    // such as `schedule_flat`, which a direct `HashMap<DocumentKind, _>`
    // decode would reject. The view only surfaces document kinds.
    let prompts: HashMap<DocumentKind, String> = document_kind_prompts(prompts_map_from_row(row)?);
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
        // Vision slot (issue #1013): NULL/NULL/NULL + FALSE is "use the
        // assistant pair", the state of every configuration written before
        // the slot existed.
        vision_provider: parse_optional_vision_provider(row)?,
        vision_model: row
            .try_get::<Option<String>, _>("vision_model")
            .map_err(map_sqlx_error)?,
        vision_vault_key_id: row
            .try_get::<Option<String>, _>("vision_vault_key_id")
            .map_err(map_sqlx_error)?,
        vision_zdr_attested: row
            .try_get::<bool, _>("vision_zdr_attested")
            .map_err(map_sqlx_error)?,
        reasoning_effort: parse_optional_reasoning_effort(
            row.try_get::<Option<String>, _>("reasoning_effort")
                .map_err(map_sqlx_error)?,
        ),
        zdr_attested: row
            .try_get::<bool, _>("zdr_attested")
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

/// Parse the optional `vision_provider` projection column (issue #1013).
/// An unknown value degrades to `None` with a warning instead of failing the
/// read — a vision slot must never 500 a config fetch (the worker then falls
/// back to the assistant pair, which is the documented `None` contract).
fn parse_optional_vision_provider(row: &PgRow) -> Result<Option<LlmProvider>, DomainError> {
    let raw: Option<String> = row.try_get("vision_provider").map_err(map_sqlx_error)?;
    Ok(match raw.as_deref() {
        None => None,
        Some(value) => match parse_provider(value.to_owned()) {
            Ok(provider) => Some(provider),
            Err(_) => {
                tracing::warn!(
                    "ai config projection: unknown vision provider '{value}'; reporting none"
                );
                None
            }
        },
    })
}

fn parse_provider(value: String) -> Result<LlmProvider, DomainError> {
    match value.as_str() {
        "openai" => Ok(LlmProvider::OpenAI),
        "gemini" | "google" => Ok(LlmProvider::Gemini),
        "openrouter" => Ok(LlmProvider::OpenRouter),
        "eurouter" | "openrouter_eu" => Ok(LlmProvider::EURouter),
        // Issue #968 — EU vision fallbacks. The infra `PROVIDER_REGISTRY` keeps
        // the alias list; this projection parser accepts the canonical keys and
        // the `ovh` shorthand.
        "scaleway" => Ok(LlmProvider::Scaleway),
        "ovhcloud" | "ovh" => Ok(LlmProvider::Ovhcloud),
        "nebius" => Ok(LlmProvider::Nebius),
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

/// Parse the `reasoning_effort` projection column (2026-11-20 investigation).
///
/// `NULL` is the meaningful default — "send no field", the provider's own
/// effort — and maps to `None`. An unknown string is treated the same way
/// instead of failing the read: the value is validated at save time, so a
/// legacy or hand-edited row must not 500 a config fetch, and falling back to
/// "provider default" is the behaviour every configuration had before the
/// column existed.
fn parse_optional_reasoning_effort(value: Option<String>) -> ReasoningEffortChoice {
    let Some(raw) = value else {
        return ReasoningEffortChoice::Auto;
    };
    let normalized = raw.trim().to_ascii_lowercase();
    ReasoningEffort::ALL
        .into_iter()
        .find(|effort| effort.as_str() == normalized)
        .map(ReasoningEffortChoice::from)
        .unwrap_or(ReasoningEffortChoice::Auto)
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
    let prompts = prompts_map_from_row(row)?;
    resolve_prompt(prompts.get(kind.as_str()), kind)
}

fn map_sqlx_error(error: sqlx::Error) -> DomainError {
    DomainError::service_unavailable(format!("AI config database error: {error}"))
}

/// Decode the `prompts` JSONB as a STRING-keyed map (CodeRabbit's PR #967
/// follow-up): the map carries the two document kinds PLUS additive keys such
/// as `"schedule_flat"`, which a `HashMap<DocumentKind, _>` decode would
/// reject — one unknown key must not break every prompt lookup for the row.
fn prompts_map_from_row(
    row: &PgRow,
) -> Result<std::collections::HashMap<String, String>, DomainError> {
    let value = row
        .try_get::<serde_json::Value, _>("prompts")
        .map_err(map_sqlx_error)?;
    prompts_map_from_json(&value)
}

/// CodeRabbit's PR #967 follow-up: split out so the string-keyed decode —
/// tolerant of additive keys like `schedule_flat` — is regression-testable
/// without a database row.
fn prompts_map_from_json(
    value: &serde_json::Value,
) -> Result<std::collections::HashMap<String, String>, DomainError> {
    serde_json::from_value(value.clone())
        .map_err(|error| DomainError::validation(format!("invalid AI prompt projection: {error}")))
}

/// Filter the string-keyed prompt map back to document kinds for the
/// read-model view (additive worker keys such as `schedule_flat` are skipped,
/// not rejected — CodeRabbit's PR #967 follow-up; extracted for tests).
fn document_kind_prompts(
    prompts: std::collections::HashMap<String, String>,
) -> HashMap<DocumentKind, String> {
    prompts
        .into_iter()
        .filter_map(|(key, prompt)| match key.as_str() {
            "script" => Some((DocumentKind::Script, prompt)),
            "schedule" => Some((DocumentKind::Schedule, prompt)),
            _ => None,
        })
        .collect()
}

/// Resolve the FLAT-path schedule prompt (CodeRabbit review, PR #967): the
/// same stored-wins precedence as [`parse_prompt_for_kind`], keyed by the
/// string `"schedule_flat"` in the prompts JSONB (additive — old config rows
/// without the key fall back to the built-in flat default), else
/// [`crate::ai::default_flat_schedule_prompt`].
fn parse_flat_schedule_prompt(row: &PgRow) -> Result<String, DomainError> {
    let prompts = prompts_map_from_row(row)?;
    match prompts
        .get("schedule_flat")
        .map(|prompt| prompt.as_str())
        .filter(|prompt| !prompt.trim().is_empty())
    {
        Some(prompt) => Ok(prompt.to_owned()),
        None => crate::ai::default_flat_schedule_prompt(),
    }
}

#[cfg(test)]
mod prompt_resolution_tests {
    use super::{document_kind_prompts, prompts_map_from_json, resolve_prompt};
    use crate::ai::default_prompt;
    use breakdown_core::ai::DocumentKind;

    /// CodeRabbit's PR #967 round-3 follow-up: the string-keyed decode must
    /// tolerate the additive `schedule_flat` key (a DocumentKind-keyed decode
    /// would reject the WHOLE map), and the read-model view must still map the
    /// two document kinds out of a map that carries it.
    #[test]
    fn a_stored_schedule_flat_key_does_not_break_prompt_decoding_or_the_view() {
        let map = prompts_map_from_json(&serde_json::json!({
            "script": "script prompt",
            "schedule": "page prompt",
            "schedule_flat": "flat prompt"
        }))
        .expect("the additive key must not break the decode");
        assert_eq!(
            map.get("schedule_flat").map(String::as_str),
            Some("flat prompt")
        );

        let view_prompts = document_kind_prompts(map);
        assert_eq!(view_prompts.len(), 2, "only document kinds surface");
        assert_eq!(
            view_prompts
                .get(&DocumentKind::Schedule)
                .map(String::as_str),
            Some("page prompt")
        );
        assert!(view_prompts.contains_key(&DocumentKind::Script));
    }

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
