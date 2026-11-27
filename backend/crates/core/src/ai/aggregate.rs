// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)

use std::collections::HashMap;

use kameo_es::{Apply, Command, Context, Entity, Metadata};

#[cfg(test)]
#[path = "aggregate_tests.rs"]
mod aggregate_tests;
use uuid::Uuid;

use crate::shared::{AggregateVersion, EventMetadata, UserId};

use super::commands::{CreateAiConfig, RevokeAiConfig, UpdateAiConfig};
use super::error::AiConfigError;
use super::events::AiConfigEvent;
use super::ports::{LlmProvider, vision_egress_compliant, vision_egress_policy_for_config};
use super::reasoning::{ReasoningEffortChoice, supports_reasoning_effort};
use super::views::{CostDisplayPreference, DocumentKind};
use super::{decision, decision::is_decision_capable};

#[derive(Debug, Clone)]
pub struct AiConfig {
    pub id: Uuid,
    pub user_id: UserId,
    pub provider: Option<LlmProvider>,
    pub assistant_model: String,
    pub image_model: Option<String>,
    pub prompts: HashMap<DocumentKind, String>,
    pub vault_key_id: String,
    pub cost_display_preference: CostDisplayPreference,
    /// Optional Decision Model slot (issue #722): provider + model + vault
    /// key of the non-autoregressive scoring model. `None` when unset.
    pub decision_provider: Option<LlmProvider>,
    pub decision_model: Option<String>,
    pub decision_vault_key_id: Option<String>,
    /// Optional Vision slot (issue #1013): the provider, model and vault key
    /// that carry PAGE IMAGES (the page-streaming schedule extractor and the
    /// VLM structural-zoning pass). `None` means "use the assistant pair",
    /// which is byte-identical to the behaviour of every configuration
    /// written before this field existed.
    ///
    /// Deliberately NOT `image_model`, which is the diffusion *generation*
    /// seam (#673) and is read by no worker.
    pub vision_provider: Option<LlmProvider>,
    pub vision_model: Option<String>,
    pub vision_vault_key_id: Option<String>,
    /// Operator attestation that the VISION provider ACCOUNT has zero data
    /// retention enabled (issue #968 semantics, vision-scoped). Separate from
    /// [`Self::zdr_attested`] because the attestation is an account fact of a
    /// DIFFERENT account as soon as the vision provider differs from the
    /// extraction provider.
    pub vision_zdr_attested: bool,
    /// Requested `reasoning_effort` for the assistant model (2026-11-20
    /// investigation). `Auto` = no explicit level.
    pub reasoning_effort: ReasoningEffortChoice,
    /// Operator attestation that the provider ACCOUNT has zero data retention
    /// enabled (issue #968). Only meaningful for providers whose ZDR guarantee
    /// is an account switch; the vision egress gate reads it through
    /// `vision_egress_policy_for_config`.
    pub zdr_attested: bool,
    pub revoked: bool,
    pub version: AggregateVersion,
}

impl Default for AiConfig {
    fn default() -> Self {
        Self {
            id: Uuid::nil(),
            user_id: UserId::from_sub(""),
            provider: None,
            assistant_model: String::new(),
            image_model: None,
            prompts: HashMap::new(),
            vault_key_id: String::new(),
            cost_display_preference: CostDisplayPreference::default(),
            decision_provider: None,
            decision_model: None,
            decision_vault_key_id: None,
            vision_provider: None,
            vision_model: None,
            vision_vault_key_id: None,
            vision_zdr_attested: false,
            reasoning_effort: ReasoningEffortChoice::Auto,
            zdr_attested: false,
            revoked: false,
            version: AggregateVersion::default(),
        }
    }
}

impl Entity for AiConfig {
    type ID = Uuid;
    type Event = AiConfigEvent;
    type Metadata = EventMetadata;

    fn category() -> &'static str {
        "ai_config"
    }
}

impl Apply for AiConfig {
    fn apply(&mut self, event: Self::Event, _metadata: Metadata<EventMetadata>) {
        match event {
            AiConfigEvent::Created {
                id,
                user_id,
                provider,
                assistant_model,
                image_model,
                prompts,
                vault_key_id,
                cost_display_preference,
                decision_provider,
                decision_model,
                decision_vault_key_id,
                vision_provider,
                vision_model,
                vision_vault_key_id,
                vision_zdr_attested,
                reasoning_effort,
                zdr_attested,
                version,
            } => {
                self.id = id;
                self.user_id = user_id;
                self.provider = Some(provider);
                self.assistant_model = assistant_model;
                self.image_model = image_model;
                self.prompts = prompts;
                self.vault_key_id = vault_key_id;
                self.cost_display_preference = cost_display_preference;
                self.decision_provider = decision_provider;
                self.decision_model = decision_model;
                self.decision_vault_key_id = decision_vault_key_id;
                self.vision_provider = vision_provider;
                self.vision_model = vision_model;
                self.vision_vault_key_id = vision_vault_key_id;
                self.vision_zdr_attested = vision_zdr_attested;
                self.reasoning_effort = reasoning_effort;
                self.zdr_attested = zdr_attested;
                self.revoked = false;
                self.version = version;
            }
            AiConfigEvent::Updated {
                provider,
                assistant_model,
                image_model,
                prompts,
                vault_key_id,
                cost_display_preference,
                decision_provider,
                decision_model,
                decision_vault_key_id,
                vision_provider,
                vision_model,
                vision_vault_key_id,
                vision_zdr_attested,
                reasoning_effort,
                zdr_attested,
                version,
                ..
            } => {
                self.provider = Some(provider);
                self.assistant_model = assistant_model;
                self.image_model = image_model;
                self.prompts = prompts;
                self.vault_key_id = vault_key_id;
                if let Some(preference) = cost_display_preference {
                    self.cost_display_preference = preference;
                }
                // Resolved final value (design D1): the update handler emits
                // the whole resolved slot, so the projector and replay simply
                // assign it. Pre-#722 events replay to `None` via
                // `#[serde(default)]` — the same "no decision model" state.
                self.decision_provider = decision_provider;
                self.decision_model = decision_model;
                self.decision_vault_key_id = decision_vault_key_id;
                // Vision slot (issue #1013): the update emits the whole
                // resolved slot, so replay and the projector simply assign it.
                // Pre-#1013 events deserialize to `None`/`false` via
                // `#[serde(default)]` — "use the assistant pair", exactly how
                // those configurations behaved.
                self.vision_provider = vision_provider;
                self.vision_model = vision_model;
                self.vision_vault_key_id = vision_vault_key_id;
                self.vision_zdr_attested = vision_zdr_attested;
                self.reasoning_effort = reasoning_effort;
                // A patch that does not mention the attestation keeps it: an
                // older client editing the prompts must not silently reopen or
                // close the vision egress gate (issue #968).
                if let Some(attested) = zdr_attested {
                    self.zdr_attested = attested;
                }
                self.revoked = false;
                self.version = version;
            }
            AiConfigEvent::Revoked { version, .. } => {
                self.revoked = true;
                self.version = version;
            }
        }
    }
}

impl Command<CreateAiConfig> for AiConfig {
    type Error = AiConfigError;

    fn handle(
        &self,
        cmd: CreateAiConfig,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        validate_fields(
            cmd.assistant_model.as_str(),
            cmd.vault_key_id.as_str(),
            &cmd.prompts,
        )?;
        validate_decision_config(
            cmd.decision_provider,
            cmd.decision_model.as_deref(),
            cmd.decision_vault_key_id.as_deref(),
            // Creation always introduces the model → the catalog check runs.
            false,
        )?;
        validate_reasoning_effort(
            cmd.provider,
            cmd.assistant_model.as_str(),
            cmd.reasoning_effort,
        )?;
        // Vision slot (issue #1013). Creation always introduces the slot, so
        // the egress gate runs unconditionally: a provider that cannot carry
        // page images is refused HERE, while the refusal is still free,
        // instead of on the first paid page of an import.
        validate_vision_config(
            cmd.vision_provider,
            cmd.vision_model.as_deref(),
            cmd.vision_vault_key_id.as_deref(),
            cmd.vision_zdr_attested,
            cmd.provider,
            cmd.vault_key_id.as_str(),
        )?;
        Ok(vec![AiConfigEvent::Created {
            id: cmd.id,
            user_id: cmd.user_id,
            provider: cmd.provider,
            assistant_model: cmd.assistant_model,
            image_model: cmd.image_model,
            prompts: cmd.prompts,
            vault_key_id: cmd.vault_key_id,
            cost_display_preference: cmd.cost_display_preference,
            decision_provider: cmd.decision_provider,
            decision_model: cmd.decision_model,
            decision_vault_key_id: cmd.decision_vault_key_id,
            vision_provider: cmd.vision_provider,
            vision_model: cmd.vision_model,
            vision_vault_key_id: cmd.vision_vault_key_id,
            vision_zdr_attested: cmd.vision_zdr_attested,
            reasoning_effort: cmd.reasoning_effort,
            zdr_attested: cmd.zdr_attested,
            version: AggregateVersion::INITIAL,
        }])
    }
}

impl Command<UpdateAiConfig> for AiConfig {
    type Error = AiConfigError;

    fn handle(
        &self,
        cmd: UpdateAiConfig,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        let current_provider = self.provider.ok_or(AiConfigError::NotFound)?;
        if self.revoked {
            return Err(AiConfigError::AlreadyRevoked);
        }
        // A provider change is a credential hand-off, not a relabeling of the
        // existing binding. Keep the invariant that the old vault key cannot
        // be paired with a new provider; the client supplies a different,
        // provider-bound vault key for the replacement.
        if current_provider != cmd.provider && cmd.vault_key_id == self.vault_key_id {
            return Err(AiConfigError::ProviderMismatch);
        }
        if cmd.version != self.version {
            return Err(AiConfigError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        validate_fields(
            cmd.assistant_model.as_str(),
            cmd.vault_key_id.as_str(),
            &cmd.prompts,
        )?;
        // Tri-state resolution (see `UpdateAiConfig`): an omitted field keeps
        // the stored slot value, `Some(None)` clears it. The resolved triple
        // is validated as a whole, so a partial update cannot leave the
        // configuration half-set (e.g. a provider without a model).
        let decision_provider = cmd.decision_provider.unwrap_or(self.decision_provider);
        let decision_model = cmd
            .decision_model
            .unwrap_or_else(|| self.decision_model.clone());
        let decision_vault_key_id = cmd
            .decision_vault_key_id
            .unwrap_or_else(|| self.decision_vault_key_id.clone());
        // Catalog-rotation safety (issue #722 review): the curated check
        // runs only when the update CHANGES the model. A rotation that
        // removes a stored model must not brick unrelated updates
        // (prompt-only edits included) — the worker accepts any non-empty
        // model string of a configured decision provider.
        let model_unchanged = self.decision_provider == decision_provider
            && self.decision_model.as_deref() == decision_model.as_deref();
        validate_decision_config(
            decision_provider,
            decision_model.as_deref(),
            decision_vault_key_id.as_deref(),
            model_unchanged,
        )?;
        // Vision slot (issue #1013), tri-state and resolved as a WHOLE first:
        // an omitted field keeps the stored value, `Some(None)` clears it.
        let vision_provider = cmd.vision_provider.unwrap_or(self.vision_provider);
        let vision_model = cmd
            .vision_model
            .unwrap_or_else(|| self.vision_model.clone());
        let vision_vault_key_id = cmd
            .vision_vault_key_id
            .unwrap_or_else(|| self.vision_vault_key_id.clone());
        // The attestation describes ONE account's `ZDR Mode` switch, and
        // nothing in this workspace can observe the switch of a different
        // account (issue #968, applied to the vision slot). An omitted
        // attestation is inherited only while the CREDENTIAL it described is
        // unchanged; a replaced vision credential resolves to `false` unless
        // this request re-asserts it.
        let vision_credential_unchanged = vision_provider == self.vision_provider
            && vision_vault_key_id == self.vision_vault_key_id;
        let vision_zdr_attested = match cmd.vision_zdr_attested {
            Some(attested) => attested,
            None if vision_credential_unchanged => self.vision_zdr_attested,
            None => false,
        };
        // Catalogue/declaration safety, mirroring `model_unchanged` above: the
        // slot is re-validated only when it CHANGED, or when the extraction
        // (provider, key) pair it references for same-key reuse changed. A
        // declaration-table update must never brick an unrelated prompt edit of
        // an existing configuration — the worker's own pre-egress gate still
        // refuses at runtime, so nothing is weakened.
        let vision_slot_changed = vision_provider != self.vision_provider
            || vision_model != self.vision_model
            || vision_vault_key_id != self.vision_vault_key_id
            || vision_zdr_attested != self.vision_zdr_attested;
        let primary_pair_changed =
            current_provider != cmd.provider || cmd.vault_key_id != self.vault_key_id;
        if vision_slot_changed || primary_pair_changed {
            validate_vision_config(
                vision_provider,
                vision_model.as_deref(),
                vision_vault_key_id.as_deref(),
                vision_zdr_attested,
                cmd.provider,
                cmd.vault_key_id.as_str(),
            )?;
        }
        // An omitted field keeps the stored choice (an older client); `Auto`
        // is an explicit reset and arrives as a value, never as a missing field.
        let reasoning_effort = cmd.reasoning_effort.unwrap_or(self.reasoning_effort);
        // Catalogue-rotation safety, mirroring `model_unchanged`: only a CHANGED
        // triple is re-validated, so a catalogue update can never brick an
        // unrelated prompt-only edit of an existing configuration.
        //
        // The PROVIDER belongs in the comparison (review finding): a provider
        // change with a fresh vault key is a legitimate update, and the same
        // model id is answered by a different catalogue per provider — e.g.
        // Neuralwatt accepts `minimal` for `glm-5.3` while OpenCode declares
        // only `low|high`. Leaving the provider out skipped validation exactly
        // when the accepted value set changes, so the worker would then send an
        // undeclared level and pay a `400` on every import call.
        // An omitted attestation keeps the stored one (issue #968): revoking a
        // ZDR attestation must be an explicit act, never a side effect of an
        // unrelated prompt edit.
        //
        // …but only while the CREDENTIAL it described is unchanged (review
        // finding). `zdr_attested` asserts one organization's `ZDR Mode` switch,
        // and nothing in this workspace can observe the switch of a different
        // account. The worker resolves the CURRENT `vault_key_id` on every call
        // (`worker_loop`), so an inherited `true` would let page images egress
        // under a retention guarantee the replacement account does not provide.
        // A provider change always carries a fresh key (the
        // `ProviderMismatch` guard above), so the key comparison covers both.
        let credential_unchanged = cmd.vault_key_id == self.vault_key_id;
        let zdr_attested = match cmd.zdr_attested {
            Some(attested) => attested,
            None if credential_unchanged => self.zdr_attested,
            None => false,
        };
        let effort_unchanged = current_provider == cmd.provider
            && reasoning_effort == self.reasoning_effort
            && cmd.assistant_model == self.assistant_model;
        if !effort_unchanged {
            validate_reasoning_effort(
                cmd.provider,
                cmd.assistant_model.as_str(),
                reasoning_effort,
            )?;
        }
        Ok(vec![AiConfigEvent::Updated {
            id: self.id,
            provider: cmd.provider,
            assistant_model: cmd.assistant_model,
            image_model: cmd.image_model,
            prompts: cmd.prompts,
            vault_key_id: cmd.vault_key_id,
            cost_display_preference: cmd.cost_display_preference,
            decision_provider,
            decision_model,
            decision_vault_key_id,
            vision_provider,
            vision_model,
            vision_vault_key_id,
            vision_zdr_attested,
            reasoning_effort,
            // The RESOLVED value, so replay and the projector simply assign it
            // (mirrors `reasoning_effort` above).
            zdr_attested: Some(zdr_attested),
            version: self.version.next(),
        }])
    }
}

impl Command<RevokeAiConfig> for AiConfig {
    type Error = AiConfigError;

    fn handle(
        &self,
        cmd: RevokeAiConfig,
        _ctx: Context<'_, Self>,
    ) -> Result<Vec<Self::Event>, Self::Error> {
        if self.provider.is_none() {
            return Err(AiConfigError::NotFound);
        }
        if self.revoked {
            return Err(AiConfigError::AlreadyRevoked);
        }
        if cmd.version != self.version {
            return Err(AiConfigError::VersionMismatch {
                expected: cmd.version,
                actual: self.version,
            });
        }
        Ok(vec![AiConfigEvent::Revoked {
            id: self.id,
            version: self.version.next(),
        }])
    }
}

fn validate_fields(
    assistant_model: &str,
    vault_key_id: &str,
    prompts: &HashMap<DocumentKind, String>,
) -> Result<(), AiConfigError> {
    if assistant_model.trim().is_empty() {
        return Err(AiConfigError::EmptyModel);
    }
    if vault_key_id.trim().is_empty() {
        return Err(AiConfigError::EmptyVaultKey);
    }
    if prompts.values().any(|prompt| prompt.trim().is_empty()) {
        return Err(AiConfigError::EmptyPrompt);
    }
    Ok(())
}

/// Validate the requested `reasoning_effort` against the configured pair.
///
/// [`ReasoningEffortChoice::Auto`] is always valid — it defers to the curated
/// profile of the pair and otherwise to the provider's own default, which is
/// what every configuration written before this field existed did. An explicit
/// level is refused while the error is cheap — at save time — rather than
/// paying a `400` on every import call of that configuration.
fn validate_reasoning_effort(
    provider: LlmProvider,
    assistant_model: &str,
    choice: ReasoningEffortChoice,
) -> Result<(), AiConfigError> {
    // `Auto` carries no level, so there is nothing to check against the
    // catalogue: the resolution happens at request-build time instead.
    let Some(effort) = choice.effort() else {
        return Ok(());
    };
    if supports_reasoning_effort(provider, assistant_model, effort) {
        Ok(())
    } else {
        Err(AiConfigError::ReasoningEffortUnsupported)
    }
}

/// Validate the optional Vision slot as a whole (issue #1013): either every
/// field is unset, or a non-empty model ID and vault key reference accompany a
/// provider that may legally carry page images (ADR-041 `D2`).
///
/// Three checks, each refusing while the mistake is still cheap:
///
/// 1. **All-or-nothing** — half a slot cannot build a page-image client, so a
///    partially set slot is refused instead of silently degrading at import
///    time.
/// 2. **Same-key reuse rule** (the #722 precedent) — the extraction vault key
///    may be reused for vision only when the SAME provider serves both; a
///    foreign provider's key would authenticate a client built for another
///    endpoint.
/// 3. **Egress compliance** — `vision_egress_compliant` over
///    [`vision_egress_policy_for_config`], i.e. zero data retention, no
///    training on inputs and EU data residency, with the operator's
///    attestation lifting exactly the account-level flag the code cannot
///    observe. A non-compliant provider is refused at SAVE time, so the
///    operator learns it before a paid page call rather than on it.
fn validate_vision_config(
    provider: Option<LlmProvider>,
    model: Option<&str>,
    vault_key_id: Option<&str>,
    zdr_attested: bool,
    primary_provider: LlmProvider,
    primary_vault_key_id: &str,
) -> Result<(), AiConfigError> {
    let (Some(provider), Some(model), Some(vault_key_id)) = (provider, model, vault_key_id) else {
        // A partially set slot (including an attestation without a provider,
        // which would describe an account nothing uses) is always invalid.
        if provider.is_some() || model.is_some() || vault_key_id.is_some() || zdr_attested {
            return Err(AiConfigError::VisionProviderRequired);
        }
        return Ok(());
    };
    if model.trim().is_empty() {
        return Err(AiConfigError::EmptyVisionModel);
    }
    if vault_key_id.trim().is_empty() {
        return Err(AiConfigError::EmptyVisionVaultKey);
    }
    if vault_key_id == primary_vault_key_id && provider != primary_provider {
        return Err(AiConfigError::VisionVaultKeyMismatch);
    }
    if !vision_egress_compliant(vision_egress_policy_for_config(provider, zdr_attested)) {
        return Err(AiConfigError::VisionProviderUnsupported);
    }
    Ok(())
}

/// Validate the optional Decision Model slot as a whole (issue #722): either
/// every field is unset, or a decision-capable provider, a non-empty curated
/// model ID and a non-empty vault key reference are all present.
fn validate_decision_config(
    provider: Option<LlmProvider>,
    model: Option<&str>,
    vault_key_id: Option<&str>,
    model_unchanged: bool,
) -> Result<(), AiConfigError> {
    let (Some(provider), Some(model), Some(vault_key_id)) = (provider, model, vault_key_id) else {
        // Partially set is always invalid — including a provider without a
        // model/key: the worker could not build a scoring client.
        if provider.is_some() || model.is_some() || vault_key_id.is_some() {
            return Err(AiConfigError::DecisionProviderRequired);
        }
        return Ok(());
    };
    if !is_decision_capable(provider) {
        return Err(AiConfigError::DecisionProviderUnsupported);
    }
    if model.trim().is_empty() {
        return Err(AiConfigError::EmptyDecisionModel);
    }
    if !model_unchanged && !decision::is_curated_decision_model(provider, model) {
        return Err(AiConfigError::DecisionModelUnknown);
    }
    if vault_key_id.trim().is_empty() {
        return Err(AiConfigError::EmptyDecisionVaultKey);
    }
    Ok(())
}
