// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: mimo-v2.5 (opencode-go)

//! Unit tests for catalog, provider_registry, and prompts — kills mutations
//! in default_allowlist, curated_model_ids, and default_prompt.

use breakdown_core::ai::{CuratedLlmProvider, DocumentKind, LlmProvider};

use super::CuratedProviderUrls;

// ===========================================================================
// Catalog: default_allowlist — kills HashSet::new() / wrong values
// ===========================================================================

#[test]
fn default_allowlist_contains_known_models() {
    // The default allowlist is used internally; we verify the catalog
    // can be created (which validates the allowlist)
    let _catalog = super::OpenAiCompatibleModelCatalog::new()
        .expect("catalog should be created with valid allowlist");
}

// ===========================================================================
// Provider Registry: curated_model_ids — kills Vec::leak replacement
// ===========================================================================

#[test]
fn curated_model_ids_returns_non_empty_for_openai() {
    let models = super::provider_registry::curated_model_ids(LlmProvider::OpenAI);
    assert!(!models.is_empty(), "OpenAI should have curated models");
    assert!(
        models.iter().any(|m| m.contains("gpt")),
        "OpenAI should have gpt models: {models:?}"
    );
}

#[test]
fn curated_model_ids_returns_non_empty_for_openrouter() {
    let models = super::provider_registry::curated_model_ids(LlmProvider::OpenRouter);
    assert!(!models.is_empty(), "OpenRouter should have curated models");
}

#[test]
fn curated_model_ids_returns_non_empty_for_ollama() {
    let models = super::provider_registry::curated_model_ids(LlmProvider::Ollama);
    assert!(!models.is_empty(), "Ollama should have curated models");
}

#[test]
fn curated_model_ids_never_returns_wrong_values() {
    for provider in [
        LlmProvider::OpenAI,
        LlmProvider::OpenRouter,
        LlmProvider::EURouter,
        LlmProvider::Neuralwatt,
        LlmProvider::OpenCodeGo,
        LlmProvider::OpenCode,
        LlmProvider::Ollama,
    ] {
        let models = super::provider_registry::curated_model_ids(provider);
        assert!(!models.is_empty(), "{provider:?} should have models");
        for model in models {
            assert_ne!(*model, "xyzzy", "{provider:?} has placeholder model");
            assert!(!model.is_empty(), "{provider:?} has empty model");
        }
    }
}

#[test]
fn curated_model_ids_for_all_providers_are_non_empty() {
    let providers = [
        LlmProvider::OpenAI,
        LlmProvider::OpenRouter,
        LlmProvider::EURouter,
        LlmProvider::Neuralwatt,
        LlmProvider::OpenCodeGo,
        LlmProvider::OpenCode,
        LlmProvider::Ollama,
    ];

    for provider in providers {
        let models = super::provider_registry::curated_model_ids(provider);
        assert!(
            !models.is_empty(),
            "{provider:?} should have curated models"
        );
    }
}

// ===========================================================================
// Prompts: default_prompt — kills delete ! replacement
// ===========================================================================

#[test]
fn default_prompt_returns_ok_for_script() {
    let result = super::prompts::default_prompt(DocumentKind::Script);
    assert!(result.is_ok(), "Script prompt should exist: {result:?}");
    let prompt = result.unwrap();
    assert!(!prompt.is_empty(), "Script prompt should not be empty");
}

#[test]
fn default_prompt_returns_ok_for_schedule() {
    let result = super::prompts::default_prompt(DocumentKind::Schedule);
    assert!(result.is_ok(), "Schedule prompt should exist: {result:?}");
    let prompt = result.unwrap();
    assert!(!prompt.is_empty(), "Schedule prompt should not be empty");
}

#[test]
fn default_prompt_contains_relevant_instructions() {
    let script_prompt = super::prompts::default_prompt(DocumentKind::Script).unwrap();
    assert!(
        script_prompt.to_lowercase().contains("scene")
            || script_prompt.to_lowercase().contains("script"),
        "Script prompt should mention scenes or script"
    );

    let schedule_prompt = super::prompts::default_prompt(DocumentKind::Schedule).unwrap();
    assert!(
        schedule_prompt.to_lowercase().contains("schedule")
            || schedule_prompt.to_lowercase().contains("csv"),
        "Schedule prompt should mention schedule or csv"
    );
}

#[test]
fn default_prompts_returns_both_document_kinds() {
    // Issue #471: the single-source defaults endpoint seeds both prompt
    // fields; the per-kind accessor must agree with the batch read so the
    // wire never drifts from the worker seeding.
    let defaults = super::prompts::default_prompts().unwrap();
    assert!(
        !defaults.script.trim().is_empty(),
        "script default must exist"
    );
    assert!(
        !defaults.schedule.trim().is_empty(),
        "schedule default must exist"
    );
    assert_eq!(
        defaults.script,
        super::prompts::default_prompt(DocumentKind::Script).unwrap()
    );
    assert_eq!(
        defaults.schedule,
        super::prompts::default_prompt(DocumentKind::Schedule).unwrap()
    );
}

/// Issue #607: an outline-style block (heading + day marker, no body) used to
/// be answered with a boilerplate sentence about its own emptiness, which the
/// preview appends verbatim to the row label. The fix is the prompt: such a
/// block gets empty lists and a NULL `summary`, and `summary` never carries
/// meta-information about the extraction itself. These two assertions pin the
/// instruction so the wording cannot silently regress into "say so".
///
/// Reads the **embedded** prompt file, not `default_prompt()`: the served
/// default is overridable per deployment (`AI_IMPORT_DEFAULT_PROMPTS_PATH`),
/// and a stored prompt with different wording must not fail this test — the
/// regression guard is about the file this PR edits.
#[test]
fn script_prompt_leaves_summary_empty_for_an_outline_style_block() {
    let embedded: toml::Value = toml::from_str(super::prompts::EMBEDDED_PROMPT_FILE)
        .expect("embedded prompts parse as TOML");
    let prompt = embedded
        .get("script")
        .and_then(|entry| entry.get("text"))
        .and_then(toml::Value::as_str)
        .expect("the embedded prompt file must carry a [script] text")
        .to_lowercase();

    assert!(
        !prompt.contains("say so in"),
        "the prompt must not ask the model to comment in `summary` (issue #607)"
    );

    let outline_rule = prompt
        .split("outline-style block")
        .nth(1)
        .and_then(|rest| rest.split("correct answer").next())
        .unwrap_or_else(|| {
            panic!("the script prompt must keep its outline-style rule (issue #607): {prompt}")
        });
    assert!(
        outline_rule.contains("summary") && outline_rule.contains("null"),
        "the outline rule must leave `summary` null instead of describing the block: \
         {outline_rule}"
    );
}

// ===========================================================================
// Embedded script prompt: marker and uncertainty-field rules (issue #826)
// ===========================================================================

/// The embedded `[script]` prompt text, lowercased.
///
/// Reads `EMBEDDED_PROMPT_FILE` and not `default_prompt()` for the same reason
/// the outline-style test below does: the served default is overridable per
/// deployment (`AI_IMPORT_DEFAULT_PROMPTS_PATH`), and a stored prompt with
/// different wording must not fail a regression guard about the file this PR
/// edits.
fn embedded_script_prompt() -> String {
    let embedded: toml::Value = toml::from_str(super::prompts::EMBEDDED_PROMPT_FILE)
        .expect("embedded prompts parse as TOML");
    embedded
        .get("script")
        .and_then(|entry| entry.get("text"))
        .and_then(toml::Value::as_str)
        .expect("the embedded prompt file must carry a [script] text")
        .to_lowercase()
}

/// The body of one `<element>…</element>` block of the script prompt,
/// lowercased.
///
/// Scoping an assertion to its element is what makes it mean something: terms
/// like `extra` or `uncertainty` occur in several rules, so a whole-prompt
/// `contains` would stay green after the rule under test was moved out of the
/// element that owns it.
fn script_prompt_element(prompt: &str, element: &str) -> String {
    let open = format!("<{element}>");
    let close = format!("</{element}>");
    prompt
        .split_once(&open)
        .and_then(|(_, rest)| rest.split_once(&close))
        .map(|(body, _)| body.to_owned())
        .unwrap_or_else(|| panic!("the script prompt must keep a {open} element: {prompt}"))
}

/// Issue #826 (rule 1): `(OT)` is "Off-Text" — a figure without dialogue, i.e.
/// a background performer — so it is an `extra` signal like `Statist`/
/// `Komparse`, not an ambiguity the reviewer has to tick. The live job this
/// issue comes from answered `"OP-PERSONAL is marked as (OT) … may indicate
/// extra or guest role"`, i.e. the model invented an uncertainty because the
/// prompt never named the marker.
///
/// Follow-up (the same live import, second reading): #826 still called a figure
/// that stands under `Darsteller` AND carries an inline `(OT)` a genuine
/// conflict, so the section won and the figure fell back to `main_cast` behind
/// a blocking uncertainty. An inline marker attached to the NAME now outranks
/// the section — `(OT)` is always `extra`, never hedged, never `main_cast`. A
/// name WITHOUT a marker keeps following its section, so the grounded default
/// survives where the document states nothing about the figure itself.
#[test]
fn script_prompt_classifies_ot_markers_as_extras_without_an_uncertainty() {
    let prompt = embedded_script_prompt();
    let characters = script_prompt_element(&prompt, "characters");

    assert!(
        characters.contains("off-text"),
        "the characters rule must name the `OT` reading (`Off-Text`), got: {characters}"
    );
    assert!(
        characters.contains("(ot)") && characters.contains("extra"),
        "`(OT)` must be listed as an `extra` signal: {characters}"
    );
    assert!(
        characters.contains("off-ton"),
        "the prompt must state which reading this pipeline uses against the \
         off-screen-voice homonym `Off-Ton`: {characters}"
    );
    assert!(
        characters.contains("attached to the name outranks the section")
            && characters.contains("no fallback to `main_cast`"),
        "an inline `(OT)` must outrank the section and never fall back to \
         `main_cast`: {characters}"
    );
    assert!(
        characters.contains("\"may indicate\""),
        "the rule must name the hedged wording it forbids (the live answer \
         said \"may indicate extra or guest role\"): {characters}"
    );
    assert!(
        !characters.contains("and marked \"(ot)\""),
        "a `Darsteller` figure with an inline `(OT)` must no longer be listed as \
         a conflict — that reading demoted the marker to a hint: {characters}"
    );
    assert!(
        characters.contains("a name with no inline marker follows its section"),
        "the section must stay authoritative for a name the document does not \
         mark: {characters}"
    );
}

/// Issue #826 (rule 2): an episode designation is a fixed number — everything
/// after the `/` in `Ep.: <n>/<suffix>` is a scene/page index inside episode
/// `<n>`. Real page headers glue the fields together
/// (`Block: 098/Ep.: 294`), and the deterministic `episode_marker` scan already
/// reads only the leading digits; the prompt now says so, so the model stops
/// treating `/15` vs `/16` as two candidate episodes.
#[test]
fn script_prompt_ignores_the_suffix_after_the_episode_number() {
    let prompt = embedded_script_prompt();
    let episode = script_prompt_element(&prompt, "episode");

    assert!(
        episode.contains("ep.: 292/15") && episode.contains("ep.: 292/16"),
        "the episode rule must show the suffix form it resolves: {episode}"
    );
    assert!(
        episode.contains("episode 292"),
        "both suffix variants must be named as episode 292: {episode}"
    );
    assert!(
        episode.contains("block: 098/ep.: 294"),
        "the glued page-header shape (`Block: 098/Ep.: 294`) must be covered: {episode}"
    );
    assert!(
        episode.contains("leading number"),
        "the rule must say to read the leading number only: {episode}"
    );
    assert!(
        episode.contains("never a reason for an uncertainty"),
        "a dissenting suffix must not become an uncertainty: {episode}"
    );
}

/// Issue #827: the page header states the production BLOCK, and the import now
/// publishes it next to the episode. The deterministic `Block:` scan is the
/// primary source (zero tokens); this rule is the fallback for a header shape
/// the scan does not recognize, so a model that did read a marker has a field
/// to put it in (`ScriptContextSchema.block_number`) instead of inventing an
/// uncertainty about it.
#[test]
fn script_prompt_reads_the_block_the_page_header_states() {
    let prompt = embedded_script_prompt();
    let block = script_prompt_element(&prompt, "block");

    assert!(
        block.contains("`block: 2`") && block.contains("`block 2`"),
        "the block rule must name both observed header shapes: {block}"
    );
    assert!(
        block.contains("`block: 098/ep.: 294`"),
        "the glued page-header shape must be covered: {block}"
    );
    assert!(
        block.contains("leading digits"),
        "the rule must say to read the leading digits only: {block}"
    );
    assert!(
        block.contains("block_number") && block.contains("null"),
        "the rule must name the field and its null answer: {block}"
    );
    assert!(
        block.contains("never report an uncertainty"),
        "a missing block marker must not become an uncertainty: {block}"
    );
}

/// Issue #826 (rule 3): one canonical `field` name per uncertainty concept.
///
/// The preview renders the model's `field` string verbatim and the #663
/// acknowledgement keys on `(scene_index, field)`, so `category`,
/// `characters.category`, `character_category` and `role_type` for one concept
/// made a single doubt look like four (28 blocking entries on 8 pairs in the
/// reported job). `characters` is the canonical name for the cast concept, and
/// it is the SAME string the server's own #695 conflict scan emits — otherwise
/// a model doubt and a detected conflict for one figure would still be two keys.
#[test]
fn script_prompt_names_one_canonical_uncertainty_field_per_concept() {
    let prompt = embedded_script_prompt();
    let uncertainties = script_prompt_element(&prompt, "uncertainties");

    for field in [
        "\"characters\"",
        "\"episode\"",
        "\"location\"",
        "\"mood\"",
        "\"outfits\"",
    ] {
        assert!(
            uncertainties.contains(field),
            "the canonical field vocabulary must name {field}: {uncertainties}"
        );
    }
    assert!(
        uncertainties.contains("nested path") && uncertainties.contains("\"characters.category\""),
        "nested paths must be forbidden by name: {uncertainties}"
    );
    assert!(
        uncertainties.contains("(scene_index, field)"),
        "the rule must state WHY the name matters (the acknowledgement key): \
         {uncertainties}"
    );

    let characters = script_prompt_element(&prompt, "characters");
    assert!(
        characters.contains("field \"characters\""),
        "the cast-classification uncertainty must use the canonical name: {characters}"
    );
    assert!(
        !characters.contains("field \"category\""),
        "the old synonym must be gone, not merely supplemented: {characters}"
    );

    // The prompt and the server must agree on the ONE string (issue #826).
    assert_eq!(
        breakdown_core::ai::UNCERTAINTY_FIELD_CHARACTERS,
        "characters"
    );
}

// ===========================================================================
// Provider URLs: base_url consistency
// ===========================================================================

#[test]
fn base_url_for_each_provider_is_unique() {
    let urls: Vec<_> = [
        LlmProvider::OpenAI,
        LlmProvider::OpenRouter,
        LlmProvider::EURouter,
        LlmProvider::Neuralwatt,
        LlmProvider::OpenCodeGo,
        LlmProvider::OpenCode,
        LlmProvider::Ollama,
    ]
    .iter()
    .map(|&p| CuratedProviderUrls::base_url(p))
    .collect();

    // All URLs should be unique
    for i in 0..urls.len() {
        for j in (i + 1)..urls.len() {
            assert_ne!(
                urls[i], urls[j],
                "URLs for different providers should be unique: {} vs {}",
                urls[i], urls[j]
            );
        }
    }
}

// ===========================================================================
// Provider info
// ===========================================================================

#[test]
fn list_providers_returns_all_curated_providers() {
    let providers = super::provider_registry::list_providers();
    assert_eq!(providers.len(), 8, "should have 8 curated providers");
}

#[test]
fn resolve_provider_accepts_gemini_and_google_alias() {
    assert_eq!(
        super::provider_registry::resolve_provider("gemini"),
        Some(LlmProvider::Gemini)
    );
    assert_eq!(
        super::provider_registry::resolve_provider("google"),
        Some(LlmProvider::Gemini)
    );
}

#[test]
fn resolve_provider_works_for_known_names() {
    assert!(super::provider_registry::resolve_provider("openai").is_some());
    assert!(super::provider_registry::resolve_provider("openrouter").is_some());
    assert!(super::provider_registry::resolve_provider("ollama").is_some());
    assert!(super::provider_registry::resolve_provider("unknown").is_none());
}
