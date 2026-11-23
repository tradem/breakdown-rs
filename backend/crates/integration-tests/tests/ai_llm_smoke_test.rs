// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Live smoke tests for the AI document-ingestion LLM path.
//!
//! This is the "nightly reads our documents with the LLM" check: it calls the
//! real configured provider (variable `AI_LLM_PROVIDER`, model `AI_LLM_MODEL`,
//! API key from secret `AI_LLM_API_KEY`) and asserts the response decodes as a
//! `ScriptContext`.
//!
//! Two levels, deliberately:
//!
//! 1. [`llm_reads_a_document_and_returns_script_context`] — a small canary. It
//!    isolates the wire contract (transport, `response_format` schema, decode)
//!    from everything document-shaped, so a red nightly says where to look.
//! 2. [`llm_reads_every_gdrive_script_fixture`] — the production path on the
//!    production documents: load the fixture PDF from GDrive, extract its text
//!    with the same `pdftotext` adapter and the same `-layout` invocation
//!    production uses, chunk it with the same deterministic splitter, and send
//!    two representative chunks per document through the **production prompt**
//!    at the **production output budget**: chunk 0 (the first request a fresh
//!    import ever makes — measured on `292.pdf`: 4 154 bytes, 40 chunks) and the
//!    document's LARGEST chunk (21 635 bytes on the same file — the worst case
//!    for the output ceiling).
//!
//! Level 2 exists because level 1 was the whole signal until 2026-11-20, and it
//! was wrong in three ways at once (see the incident note below): it sent a
//! hard-coded three-line prompt instead of the configured one, it sent a toy
//! three-scene snippet instead of a real screenplay page, and it was silently
//! green when the key was absent. All three gaps made a dead-lettering provider
//! answer look like a passing nightly.
//!
//! **Incident 2026-11-20.** A real import died with
//! `validation failed: LLM response contained no content`: the provider answered
//! `200` with `choices[0].message.content == null`, which the client classified
//! as a permanent *validation* failure — zero in-attempt retries, immediate dead
//! letter, no `tracing` line, no `finish_reason`/`usage`/request-id recorded, and
//! no breaker signal (so the provider surface still showed "healthy"). The unit
//! tests in `infra::ai::client` now pin that decision; these live tests are what
//! makes the class reproducible against a real provider.
//!
//! Both tests skip themselves when their secrets are unset, so local developers
//! and CI without the secrets are not blocked — but a skip is logged at WARN with
//! the missing variable, so a nightly that checks nothing says so.

mod fixtures;

use std::env;
use std::time::Duration;

use anyhow::{Context, Result, anyhow};
use breakdown_core::ai::{
    AiImportBounds, DocumentKind, DraftScene, LlmChatRequest, LlmClient, LlmProvider,
    RejectedOutfitReason, SceneChunk, ScriptContext, character_identity, extract_scenes,
    verify_draft_outfits,
};
use breakdown_core::settings::ports::{CredentialVault, GDriveCredentialBundle};
use infra::ai::{
    AiDocumentSource, GDriveDocument, GDriveDocumentSource, LegacyPdfToTextAdapter,
    OpenAiCompatibleChatClient, default_prompt,
};
use uuid::Uuid;

/// Deployment defaults when the nightly variables are unset: the provider and
/// assistant model the dev/prod AI configuration currently uses. The model is
/// the curated eurouter recommendation since issue #950 (`mistral-large-4`
/// declares `reasoning_effort`, its predecessor did not).
const DEFAULT_PROVIDER: &str = "eurouter";
const DEFAULT_MODEL: &str = "mistral-large-4";

/// Per-request provider timeout, mirroring `AI_IMPORT_REQUEST_TIMEOUT_SECS`'s
/// default. A live call slower than this is a finding, not a flake.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(120);

/// Budget for the `pdftotext` subprocess: the production adapter default.
const PDF_EXTRACT_TIMEOUT: Duration = Duration::from_secs(60);

/// The production documents the nightly MUST read.
///
/// Declared rather than discovered: these are the scripts the pipeline exists
/// for, and a missing one is a red nightly with the available names in the
/// message — not a silent narrowing of the check to whatever happens to be
/// there. `292.pdf` is the document of the 2026-11-20 incident; `294.pdf` is the
/// ARD "SCRIPT REPORT" layout whose scene index column the splitter has to merge.
const REQUIRED_SCRIPTS: [&str; 5] = [
    "292.pdf",
    "293.pdf",
    "294.pdf",
    "Drehbuch_1.pdf",
    "Drehbuch_2.pdf",
];

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

/// The live provider triple, resolved once per test.
struct LiveLlm {
    api_key: String,
    provider: LlmProvider,
    model: String,
}

/// Resolve the provider/model/key, or `Ok(None)` when no key is configured (the
/// documented skip).
fn live_llm() -> Result<Option<LiveLlm>> {
    let Some(api_key) = env_non_empty("AI_LLM_API_KEY") else {
        return Ok(None);
    };
    let provider_key =
        env_non_empty("AI_LLM_PROVIDER").unwrap_or_else(|| DEFAULT_PROVIDER.to_owned());
    let model = env_non_empty("AI_LLM_MODEL").unwrap_or_else(|| DEFAULT_MODEL.to_owned());
    let provider = provider_from_key(&provider_key)
        .with_context(|| format!("invalid AI_LLM_PROVIDER {provider_key}"))?;
    Ok(Some(LiveLlm {
        api_key,
        provider,
        model,
    }))
}

/// The GDrive fixture credentials.
struct LiveGDrive {
    client_id: String,
    client_secret: String,
    refresh_token: String,
    root: String,
}

/// Resolve the GDrive fixture credentials, or `Ok(None)` when they are not
/// configured (the documented skip). A *partially* configured set is an error:
/// silently treating a typo'd secret as "not configured" is how a nightly check
/// stops checking anything.
fn live_gdrive() -> Result<Option<LiveGDrive>> {
    let Some(client_id) = env_non_empty("GDRIVE_CLIENT_ID") else {
        return Ok(None);
    };
    Ok(Some(LiveGDrive {
        client_id,
        client_secret: env::var("GDRIVE_CLIENT_SECRET")
            .context("GDRIVE_CLIENT_SECRET is required when the GDrive check is enabled")?,
        refresh_token: env::var("GDRIVE_REFRESH_TOKEN")
            .context("GDRIVE_REFRESH_TOKEN is required when the GDrive check is enabled")?,
        root: env::var("GDRIVE_ROOT")
            .context("GDRIVE_ROOT is required when the GDrive check is enabled")?,
    }))
}

/// Install the captured-output subscriber these live tests log through.
///
/// `tracing`, never `println!`/`eprintln!` — both are clippy-denied repo-wide.
/// A second installation in the same test binary is a harmless no-op, so both
/// tests call this before their first log line instead of sharing a guard.
fn init_logging() {
    let _installed = tracing_subscriber::fmt()
        .with_test_writer()
        .with_max_level(tracing::Level::INFO)
        .try_init();
}

const SMALL_SCRIPT: &str = r#"1. INT. KITCHEN - DAY
Rafael steht am Herd. Elias kommt herein.

2. EXT. HOSPITAL PARK - NIGHT
Karin und Ilja gehen über den Parkplatz.

3. INT. OFFICE - DAY
Marc liest eine Patientenakte."#;

/// How much of the model's answer must carry extracted content.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Coverage {
    /// Every returned scene (the toy canary: three hand-written scene bodies all
    /// have readable fields, so a null-heavy answer is a real signal).
    EveryScene,
    /// Only that the answer contains extraction at all. The real-document halves
    /// legitimately contain heading-only scene stubs (a numbered index entry
    /// whose body is empty), and demanding content from those made the check
    /// fail on a correct answer — the same trap the summary assertion fell into
    /// (nightly runs Aug 7-11, 2026).
    AtLeastOneScene,
}

/// Does this scene carry at least one extracted field?
fn scene_has_content(scene: &DraftScene) -> bool {
    scene.scene_number.is_some()
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
        || !scene.characters.is_empty()
}

/// The answer must contain a decodable scene, and content at the requested
/// [`Coverage`].
fn scenes_carry_content(document: &str, context: &ScriptContext, coverage: Coverage) -> Result<()> {
    if context.scenes.is_empty() {
        return Err(anyhow!(
            "{document}: LLM returned a ScriptContext without scenes"
        ));
    }
    let empty: Vec<&str> = context
        .scenes
        .iter()
        .filter(|scene| !scene_has_content(scene))
        .map(|scene| scene.draft_ref.as_str())
        .collect();
    match coverage {
        Coverage::EveryScene => {
            if !empty.is_empty() {
                return Err(anyhow!(
                    "{document}: scenes {empty:?} carry no extracted content"
                ));
            }
            Ok(())
        }
        Coverage::AtLeastOneScene => {
            if empty.len() == context.scenes.len() {
                return Err(anyhow!(
                    "{document}: none of the {} returned scenes carries extracted content",
                    context.scenes.len()
                ));
            }
            Ok(())
        }
    }
}

/// Level 1: the wire contract, with the **production prompt**.
///
/// The prompt matters: the nightly sent a hard-coded three-liner until
/// 2026-11-20, so the configured prompt — the one that carries the strict
/// `draft_ref`/`characters`/`outfits` instructions — never met a live provider.
#[tokio::test]
async fn llm_reads_a_document_and_returns_script_context() -> Result<()> {
    init_logging();
    let Some(live) = live_llm()? else {
        tracing::warn!(
            "AI_LLM_API_KEY not configured — live LLM smoke SKIPPED (this test asserted nothing)"
        );
        return Ok(());
    };
    let provider = live.provider;
    let prompt = default_prompt(DocumentKind::Script).context("production script prompt")?;
    let client = OpenAiCompatibleChatClient::new(provider, live.api_key, REQUEST_TIMEOUT).await?;
    let outcome = client
        .chat_constrained(LlmChatRequest {
            provider,
            model: live.model.clone(),
            prompt,
            source_text: SMALL_SCRIPT.to_owned(),
            // Production parity: the per-request output-token ceiling is
            // `AiImportBounds::default().max_tokens_per_req` (8_192). A smaller
            // nightly budget truncated the JSON mid-object (finish_reason
            // "length", nightly 2026-08-13); the client now grows the budget on
            // truncation, but the smoke test should exercise the production
            // budget rather than the retry path.
            max_tokens: AiImportBounds::default().max_tokens_per_req,
            response_schema: None,
            reasoning_effort: None,
        })
        .await
        .context("live LLM call failed")?;
    // Issue #675: log the recorded usage so nightly runs surface real
    // token/energy telemetry from the live provider.
    tracing::info!(
        provider = %provider.as_str(),
        model = %live.model,
        tokens_in = outcome.usage.tokens_in,
        tokens_out = outcome.usage.tokens_out,
        cached_tokens_in = outcome.usage.cached_tokens_in,
        energy_millijoules = outcome.usage.energy_millijoules,
        "llm smoke usage"
    );
    scenes_carry_content("small script", &outcome.output, Coverage::EveryScene)
}

/// Everything one fixture extraction needs, so [`extract_one_script`] stays a
/// one-argument call instead of an eight-parameter one.
struct LiveExtraction<'a> {
    client: &'a OpenAiCompatibleChatClient,
    source: &'a GDriveDocumentSource,
    extractor: &'a LegacyPdfToTextAdapter,
    documents: &'a [GDriveDocument],
    live: &'a LiveLlm,
    prompt: &'a str,
    bounds: &'a AiImportBounds,
}

/// Level 2: the production documents through the production path.
///
/// Two paid calls per fixture: chunk 0 — the first request a fresh import makes,
/// and the one the 2026-11-20 incident died on — and the document's LARGEST
/// chunk, the worst case for the output-token ceiling. Both are exactly the
/// shapes whose failure mode was "the provider spent everything it was allowed
/// and returned no content". Every failing fixture/chunk is reported together: a
/// red nightly should name all of them in one run, not one per night.
#[tokio::test]
async fn llm_reads_every_gdrive_script_fixture() -> Result<()> {
    init_logging();
    let Some(live) = live_llm()? else {
        tracing::warn!(
            "AI_LLM_API_KEY not configured — the GDrive script smoke SKIPPED (asserted nothing)"
        );
        return Ok(());
    };
    let Some(gdrive) = live_gdrive()? else {
        tracing::warn!(
            "GDRIVE_CLIENT_ID not configured — the GDrive script smoke SKIPPED (asserted nothing)"
        );
        return Ok(());
    };

    let bounds = AiImportBounds::default();
    let prompt = default_prompt(DocumentKind::Script).context("production script prompt")?;
    let client =
        OpenAiCompatibleChatClient::new(live.provider, live.api_key.clone(), REQUEST_TIMEOUT)
            .await?;
    // `-layout` is what production uses (see `LegacyPdfToTextAdapter`): the same
    // invocation must produce the same headings for the splitter, otherwise the
    // smoke measures a different pipeline than the product.
    let extractor = LegacyPdfToTextAdapter::new(
        usize::try_from(bounds.max_document_bytes).unwrap_or(usize::MAX),
        PDF_EXTRACT_TIMEOUT,
    );
    let source = gdrive_source(&gdrive, bounds.max_document_bytes).await?;
    let documents = source
        .list_documents()
        .await
        .context("listing the GDrive fixture folder")?;
    tracing::info!(documents = documents.len(), "GDrive fixture folder listed");

    let smoke = LiveExtraction {
        client: &client,
        source: &source,
        extractor: &extractor,
        documents: &documents,
        live: &live,
        prompt: &prompt,
        bounds: &bounds,
    };
    let mut failures: Vec<String> = Vec::new();
    for name in REQUIRED_SCRIPTS {
        if let Err(error) = extract_one_script(&smoke, name).await {
            tracing::error!(
                document = %name,
                error = %format!("{error:#}"),
                "live script extraction FAILED"
            );
            failures.push(format!("{name}: {error:#}"));
        }
    }
    if !failures.is_empty() {
        return Err(anyhow!(
            "{} of {} GDrive script fixtures failed live extraction:\n- {}",
            failures.len(),
            REQUIRED_SCRIPTS.len(),
            failures.join("\n- ")
        ));
    }
    Ok(())
}

/// Load one fixture document and return its production chunks.
///
/// Shared by the extraction smoke (chunk 0 + largest) and the reasoning-effort
/// probe, so both measure the SAME text: `pdftotext -layout` and the
/// deterministic splitter are the production path, and a probe that chunked
/// differently would answer a different question.
async fn load_fixture_chunks(
    source: &GDriveDocumentSource,
    extractor: &LegacyPdfToTextAdapter,
    documents: &[GDriveDocument],
    name: &str,
) -> Result<Vec<SceneChunk>> {
    let document = documents
        .iter()
        .find(|document| document.name == name)
        .ok_or_else(|| {
            let available: Vec<&str> = documents
                .iter()
                .map(|document| document.name.as_str())
                .collect();
            anyhow!("{name} not present in GDRIVE_ROOT; available documents: {available:?}")
        })?;
    let bytes = source
        .load(&document.handle)
        .await
        .with_context(|| format!("could not load {} from GDrive", document.name))?;
    let text = extractor
        .extract_layout_text(&bytes)
        .await
        .with_context(|| {
            format!(
                "pdftotext could not read {} ({} bytes)",
                document.name,
                bytes.len()
            )
        })?;
    let chunks = extract_scenes(&text);
    tracing::info!(
        document = %document.name,
        bytes = bytes.len(),
        text_chars = text.chars().count(),
        chunks = chunks.len(),
        "document chunked with the production splitter"
    );
    if chunks.is_empty() {
        return Err(anyhow!(
            "the extracted text ({} chars) contains no INT./EXT. scene heading — the \
             deterministic splitter, not the model, failed",
            text.chars().count()
        ));
    }
    Ok(chunks)
}

/// Load, extract, chunk and call one fixture document.
async fn extract_one_script(smoke: &LiveExtraction<'_>, name: &str) -> Result<()> {
    let chunks = load_fixture_chunks(smoke.source, smoke.extractor, smoke.documents, name).await?;
    let mut failures: Vec<String> = Vec::new();
    for index in chunks_to_probe(&chunks) {
        if let Err(error) = probe_chunk(smoke, name, &chunks, index).await {
            tracing::error!(
                document = %name,
                chunk = index,
                error = %format!("{error:#}"),
                "live chunk extraction FAILED"
            );
            failures.push(format!("{name} chunk {index}: {error:#}"));
        }
    }
    if failures.is_empty() {
        Ok(())
    } else {
        Err(anyhow!("{}", failures.join("; ")))
    }
}

/// The deterministic shape of one paid call: `heading + "\n" + text`.
fn source_text_of(chunk: &SceneChunk) -> String {
    format!("{}\n{}", chunk.heading, chunk.text)
}

/// Chunk 0 and the largest chunk, deduplicated.
///
/// Chunk 0 is what a fresh import sends first (and where the incident died);
/// the largest one is the worst case for the output ceiling. Both are cheap and
/// together they cover "small input, no answer" and "biggest allowed output".
fn chunks_to_probe(chunks: &[SceneChunk]) -> Vec<usize> {
    let largest = chunks
        .iter()
        .enumerate()
        .max_by_key(|(_, chunk)| source_text_of(chunk).len())
        .map(|(index, _)| index)
        .unwrap_or(0);
    let mut probes = vec![0];
    if largest != 0 {
        probes.push(largest);
    }
    probes
}

/// One paid call: the given chunk through the production prompt and budget.
async fn probe_chunk(
    smoke: &LiveExtraction<'_>,
    document: &str,
    chunks: &[SceneChunk],
    index: usize,
) -> Result<()> {
    let chunk = chunks
        .get(index)
        .ok_or_else(|| anyhow!("chunk {index} vanished from the plan"))?;
    let source_text = source_text_of(chunk);
    let outcome = smoke
        .client
        .chat_constrained(LlmChatRequest {
            provider: smoke.live.provider,
            model: smoke.live.model.clone(),
            prompt: smoke.prompt.to_owned(),
            source_text,
            max_tokens: smoke.bounds.max_tokens_per_req,
            response_schema: None,
            reasoning_effort: None,
        })
        .await
        .with_context(|| {
            format!(
                "live extraction failed ({} bytes, heading {:?})",
                chunk.heading.len() + 1 + chunk.text.len(),
                chunk.heading
            )
        })?;
    tracing::info!(
        document = %document,
        chunk = index,
        chunk_bytes = chunk.heading.len() + 1 + chunk.text.len(),
        heading = %chunk.heading,
        scenes = outcome.output.scenes.len(),
        characters = outcome
            .output
            .scenes
            .iter()
            .map(|scene| scene.characters.len())
            .sum::<usize>(),
        tokens_in = outcome.usage.tokens_in,
        tokens_out = outcome.usage.tokens_out,
        energy_millijoules = outcome.usage.energy_millijoules,
        "live script extraction"
    );
    scenes_carry_content(document, &outcome.output, Coverage::AtLeastOneScene)
}

/// Build the production GDrive source over an ephemeral Vault, exactly as the
/// composition root does (credentials stay in the vault; the operator holds
/// only the resolved token).
async fn gdrive_source(
    credentials: &LiveGDrive,
    max_document_bytes: u64,
) -> Result<GDriveDocumentSource> {
    let vault = fixtures::spawn_vault().await?;
    let client = vault.client();
    let settings_id = Uuid::now_v7();
    let bundle = GDriveCredentialBundle::try_new(
        credentials.client_id.clone(),
        credentials.client_secret.clone(),
        credentials.refresh_token.clone(),
        Some(credentials.root.clone()),
    )?;
    let binding = client.store_gdrive(settings_id, bundle).await?;
    let source =
        GDriveDocumentSource::from_vault(&client, settings_id, &binding, max_document_bytes)
            .await?;
    Ok(source)
}

// ===========================================================================
// Reasoning-effort probe (2026-11-20 output-budget investigation)
//
// This test is a MEASUREMENT, not a pass/fail check: read the logged rows. Its
// question is whether pinning the provider-side `reasoning_effort` removes the
// pathology the 2026-11-20 nightly proved — a reasoning model that spends its
// whole output ceiling before emitting one content token (`finish_reason:
// length`, `content: null`, 8_192 billable output tokens, 70-85 s of upstream
// generation for a 4 KB scene).
//
// It runs against its OWN provider/model/key (`AI_LLM_PROBE_*`), not the
// production triple: the production guard above must keep guarding what ships,
// and one provider outage already silenced two checks on 2026-11-20.
// ===========================================================================

/// Provider the probe talks to when `AI_LLM_PROBE_PROVIDER` is unset.
///
/// Neuralwatt, because it publishes the facts the experiment needs and eurouter
/// does not: `capabilities.reasoning_effort`, `reasoning.mandatory`,
/// `reasoning.default_effort`, `reasoning.supported_efforts` and
/// `limits.max_output_tokens` (checked live against `GET /v1/models`).
const DEFAULT_EFFORT_PROVIDER: &str = "neuralwatt";

/// Models probed when `AI_LLM_PROBE_MODELS` is unset.
///
/// Chosen for CONTRAST, not for speed: `glm-5.3-flash` declares
/// `reasoning.mandatory = true` with `default_effort = "max"` (the widest
/// possible gap between the provider default and `low`), `deepseek-v4.1-flash`
/// declares `reasoning.mandatory = false` with `default_effort = "high"` and
/// publishes its output ceiling. A model that honours the knob should show it
/// here; one that ignores it cannot hide, because the two models differ in what
/// they claim.
const DEFAULT_EFFORT_MODELS: [&str; 2] = ["glm-5.3-flash", "deepseek-v4.1-flash"];

/// Variants compared when `AI_LLM_PROBE_EFFORTS` is unset.
///
/// `default` sends NO `reasoning_effort` field at all — it measures the
/// provider's own default, i.e. exactly what production does today. Every other
/// entry is sent verbatim.
const DEFAULT_EFFORT_VARIANTS: [&str; 2] = ["default", "low"];

/// Output budget of one probe call.
///
/// Deliberately far above the production `AI_IMPORT_MAX_TOKENS_PER_REQ` (8_192):
/// a capped probe would report the same `tokens_out` for every variant and the
/// comparison would measure the ceiling instead of the model. It also keeps the
/// client's bounded truncation retry out of the measurement, which would
/// otherwise double the billed tokens of a capped variant.
const DEFAULT_EFFORT_MAX_TOKENS: u32 = 32_768;

/// The measured result of one paid probe call.
#[derive(Debug)]
struct EffortOutcome {
    model: String,
    variant: String,
    wall_ms: u64,
    tokens_in: u64,
    tokens_out: u64,
    scenes: usize,
    /// `tokens_out` reached the budget: the variant was cut off, so its numbers
    /// are a lower bound, not its requirement.
    capped: bool,
}

/// Read a comma-separated environment list, falling back to `default`.
fn env_list(name: &str, default: &[&str]) -> Vec<String> {
    let from_env = env::var(name).ok().map(|raw| {
        raw.split(',')
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_owned)
            .collect::<Vec<String>>()
    });
    match from_env {
        Some(values) if !values.is_empty() => values,
        _ => default.iter().map(|value| (*value).to_owned()).collect(),
    }
}

/// Treat an EMPTY value as unset.
///
/// GitHub Actions passes an undefined *optional* variable as an empty string, so
/// `env::var(name).unwrap_or(default)` silently keeps `""` instead of the
/// default. That is exactly how the nightly of 2026-11-20 ended with an empty
/// document name (`Error:  not present in GDRIVE_ROOT`) and a 4.6 s red probe.
fn non_empty(value: Option<String>) -> Option<String> {
    value.filter(|raw| !raw.trim().is_empty())
}

/// [`non_empty`] over the process environment.
fn env_non_empty(name: &str) -> Option<String> {
    non_empty(env::var(name).ok())
}

/// The fixture document the probes read unless `AI_LLM_PROBE_DOCUMENT` names
/// one: the document of the 2026-11-20 incident.
const DEFAULT_PROBE_DOCUMENT: &str = "292.pdf";

/// Resolve the probe document from the raw variable value.
///
/// A workflow variable that is declared but has no value arrives as an EMPTY
/// string, so `env::var(..).unwrap_or(default)` silently keeps `""` and the
/// probe then looks for a document called nothing instead of reading the
/// default. Pure, so the call-site mistake stays testable without touching the
/// process environment.
fn probe_document_name(raw: Option<String>) -> String {
    non_empty(raw).unwrap_or_else(|| DEFAULT_PROBE_DOCUMENT.to_owned())
}

/// Output budget of one probe call (see [`DEFAULT_EFFORT_MAX_TOKENS`]).
fn effort_probe_max_tokens() -> u32 {
    let Some(raw) = env_non_empty("AI_LLM_PROBE_MAX_TOKENS") else {
        return DEFAULT_EFFORT_MAX_TOKENS;
    };
    match raw.trim().parse::<u32>() {
        Ok(value) if value > 0 => value,
        _ => {
            tracing::warn!(
                value = %raw,
                default = DEFAULT_EFFORT_MAX_TOKENS,
                "AI_LLM_PROBE_MAX_TOKENS is not a positive integer — using the default"
            );
            DEFAULT_EFFORT_MAX_TOKENS
        }
    }
}

/// Resolve the probe credential and model list, or `Ok(None)` when unset.
fn effort_probe_llm() -> Result<Option<(LiveLlm, Vec<String>)>> {
    let Some(api_key) = env_non_empty("AI_LLM_PROBE_API_KEY") else {
        return Ok(None);
    };
    let provider_key = env_non_empty("AI_LLM_PROBE_PROVIDER")
        .unwrap_or_else(|| DEFAULT_EFFORT_PROVIDER.to_owned());
    let provider = provider_from_key(&provider_key)
        .with_context(|| format!("invalid AI_LLM_PROBE_PROVIDER {provider_key}"))?;
    let models = env_list("AI_LLM_PROBE_MODELS", &DEFAULT_EFFORT_MODELS);
    let first_model = models.first().cloned().unwrap_or_default();
    Ok(Some((
        LiveLlm {
            api_key,
            provider,
            model: first_model,
        },
        models,
    )))
}

/// Does pinning `reasoning_effort` cut the output tokens (and with them the wall
/// clock) for a production document chunk?
///
/// One fixture document, one chunk, one paid call per (model, variant) — 2×2
/// calls by default, a few cents. The table is the deliverable; the assertions
/// only refuse to let a broken wire (`400` on the unsupported parameter, or an
/// empty answer) pass as a measurement.
#[tokio::test]
async fn reasoning_effort_trades_output_tokens_for_wall_clock() -> Result<()> {
    init_logging();
    let Some((live, models)) = effort_probe_llm()? else {
        tracing::warn!(
            "AI_LLM_PROBE_API_KEY not configured — the reasoning-effort probe SKIPPED (asserted nothing)"
        );
        return Ok(());
    };
    let Some(gdrive) = live_gdrive()? else {
        tracing::warn!(
            "GDRIVE_CLIENT_ID not configured — the reasoning-effort probe SKIPPED (asserted nothing)"
        );
        return Ok(());
    };

    let variants = env_list("AI_LLM_PROBE_EFFORTS", &DEFAULT_EFFORT_VARIANTS);
    let document_name = probe_document_name(env::var("AI_LLM_PROBE_DOCUMENT").ok());
    let chunk_index = env_non_empty("AI_LLM_PROBE_CHUNK")
        .and_then(|raw| raw.trim().parse::<usize>().ok())
        .unwrap_or(0);
    let max_tokens = effort_probe_max_tokens();

    let prompt = default_prompt(DocumentKind::Script).context("production script prompt")?;
    let bounds = AiImportBounds::default();
    let extractor = LegacyPdfToTextAdapter::new(
        usize::try_from(bounds.max_document_bytes).unwrap_or(usize::MAX),
        PDF_EXTRACT_TIMEOUT,
    );
    let source = gdrive_source(&gdrive, bounds.max_document_bytes).await?;
    let documents = source
        .list_documents()
        .await
        .context("listing the GDrive fixture folder")?;
    let chunks = load_fixture_chunks(&source, &extractor, &documents, &document_name).await?;
    let chunk = chunks.get(chunk_index).ok_or_else(|| {
        anyhow!(
            "{document_name} has {} chunks, chunk {chunk_index} does not exist",
            chunks.len()
        )
    })?;
    let source_text = source_text_of(chunk);
    tracing::info!(
        provider = %live.provider.as_str(),
        document = %document_name,
        chunk = chunk_index,
        chunk_bytes = source_text.len(),
        heading = %chunk.heading,
        models = ?models,
        variants = ?variants,
        max_tokens,
        "reasoning-effort probe plan (one paid call per row)"
    );

    let client =
        OpenAiCompatibleChatClient::new(live.provider, live.api_key.clone(), REQUEST_TIMEOUT)
            .await?;
    let mut outcomes: Vec<EffortOutcome> = Vec::new();
    let mut failures: Vec<String> = Vec::new();
    for model in &models {
        for variant in &variants {
            // `default` is the sentinel for "send no field at all".
            let effort = if variant.eq_ignore_ascii_case("default") {
                None
            } else {
                Some(variant.clone())
            };
            let label = effort.clone().unwrap_or_else(|| "default".to_owned());
            let started = std::time::Instant::now();
            let result = client
                .chat_constrained(LlmChatRequest {
                    provider: live.provider,
                    model: model.clone(),
                    prompt: prompt.clone(),
                    source_text: source_text.clone(),
                    max_tokens,
                    response_schema: None,
                    reasoning_effort: effort,
                })
                .await;
            let wall_ms = u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX);
            match result {
                Ok(outcome) => {
                    let tokens_out = outcome.usage.tokens_out;
                    let scenes = outcome.output.scenes.len();
                    let capped = tokens_out >= u64::from(max_tokens);
                    tracing::info!(
                        model = %model,
                        variant = %label,
                        wall_ms,
                        tokens_in = outcome.usage.tokens_in,
                        tokens_out,
                        scenes,
                        capped,
                        "reasoning-effort row"
                    );
                    if let Err(error) = scenes_carry_content(
                        &format!("{model} / {label}"),
                        &outcome.output,
                        Coverage::AtLeastOneScene,
                    ) {
                        failures.push(format!("{model} / {label}: {error:#}"));
                    }
                    outcomes.push(EffortOutcome {
                        model: model.clone(),
                        variant: label,
                        wall_ms,
                        tokens_in: outcome.usage.tokens_in,
                        tokens_out,
                        scenes,
                        capped,
                    });
                }
                Err(error) => {
                    tracing::error!(
                        model = %model,
                        variant = %label,
                        wall_ms,
                        error = %error,
                        "reasoning-effort row FAILED"
                    );
                    failures.push(format!("{model} / {label}: {error}"));
                }
            }
        }
    }

    // The comparison line, per model: the provider default against the variant
    // that produced the fewest output tokens. The full row list rides along so a
    // doubled `tokens_in` (a client-side truncation retry) and a `capped` variant
    // are visible instead of silently skewing the ratio.
    for model in &models {
        let rows: Vec<&EffortOutcome> = outcomes
            .iter()
            .filter(|outcome| &outcome.model == model)
            .collect();
        let table = rows
            .iter()
            .map(|row| {
                format!(
                    "{}: in={} out={}{} scenes={} wall={}ms",
                    row.variant,
                    row.tokens_in,
                    row.tokens_out,
                    if row.capped { "(capped)" } else { "" },
                    row.scenes,
                    row.wall_ms
                )
            })
            .collect::<Vec<String>>()
            .join(" | ");
        let Some(baseline) = rows.iter().find(|row| row.variant == "default") else {
            tracing::info!(model = %model, %table, "reasoning-effort rows");
            continue;
        };
        let Some(cheapest) = rows.iter().min_by_key(|row| row.tokens_out) else {
            continue;
        };
        // `checked_div` yields `None` for a zero baseline instead of a panic, so
        // the ratio is simply omitted when the provider reports no usage.
        let output_ratio_pct = cheapest
            .tokens_out
            .saturating_mul(100)
            .checked_div(baseline.tokens_out);
        let wall_ratio_pct = cheapest
            .wall_ms
            .saturating_mul(100)
            .checked_div(baseline.wall_ms);
        tracing::info!(
            model = %model,
            %table,
            baseline_variant = %baseline.variant,
            baseline_tokens_out = baseline.tokens_out,
            baseline_wall_ms = baseline.wall_ms,
            cheapest_variant = %cheapest.variant,
            cheapest_tokens_out = cheapest.tokens_out,
            cheapest_wall_ms = cheapest.wall_ms,
            output_ratio_pct,
            wall_ratio_pct,
            "reasoning-effort comparison (cheapest vs provider default)"
        );
    }

    if failures.is_empty() {
        Ok(())
    } else {
        Err(anyhow!(
            "{} of {} probe calls failed:\n- {}",
            failures.len(),
            models.len() * variants.len(),
            failures.join("\n- ")
        ))
    }
}

// ===========================================================================
// Document-level quality + cost probe (2026-11-20 investigation, step 2)
//
// The single-chunk probe above answers "does the knob cut tokens?". This one
// answers the two questions that decide whether the model may ship at all:
//
//   1. QUALITY — does an extraction pass over a WHOLE script still produce a
//      grounded preview? Measured deterministically, never by an LLM judging an
//      LLM: every returned `draft_ref` must equal the heading it was given, every
//      character name must occur in the chunk text, and every outfit quote is
//      verified against the chunk with the SAME `verify_draft_outfits` the
//      production worker runs.
//   2. COST — tokens and wall clock for one document, extrapolatable to a
//      preview: 292.pdf is 40 chunks, i.e. 40 sequential paid calls, exactly the
//      shape production pays.
//
// Run it with `--test-threads=1`: two probes hitting one provider in parallel
// would distort both the wall clock and the rate-limit behaviour they measure.
// ===========================================================================

/// One full-document pass at a single effort, aggregated over its chunks.
#[derive(Debug, Default)]
struct DocumentPass {
    model: String,
    variant: String,
    chunks_sent: usize,
    chunks_failed: usize,
    /// Rows the model returned across all chunks.
    scenes_returned: usize,
    /// Rows whose `draft_ref` equals the heading they were given — the identity
    /// the whole review/apply chain keys on.
    draft_ref_exact: usize,
    scenes_with_content: usize,
    scenes_without_characters: usize,
    characters_total: usize,
    /// Names that do not occur in the chunk text at all.
    characters_ungrounded: usize,
    outfits_total: usize,
    /// `source_quote` not found in the chunk (`verify_draft_outfits`).
    outfits_ungrounded_quote: usize,
    /// Outfit names a figure the same scene does not list.
    outfits_unlisted_character: usize,
    source_chars: usize,
    tokens_in: u64,
    tokens_out: u64,
    wall_ms: u64,
}

impl DocumentPass {
    /// Fold one decoded chunk answer into the aggregate.
    fn absorb_chunk(
        &mut self,
        heading: &str,
        source_text: &str,
        context: &ScriptContext,
        tokens_in: u64,
        tokens_out: u64,
        wall_ms: u64,
    ) {
        self.chunks_sent += 1;
        self.tokens_in = self.tokens_in.saturating_add(tokens_in);
        self.tokens_out = self.tokens_out.saturating_add(tokens_out);
        self.wall_ms = self.wall_ms.saturating_add(wall_ms);
        self.source_chars = self
            .source_chars
            .saturating_add(source_text.chars().count());
        let folded_source = fold_chunk(source_text);
        let expected = heading.trim();
        for scene in &context.scenes {
            self.scenes_returned += 1;
            if scene.draft_ref.trim() == expected {
                self.draft_ref_exact += 1;
            }
            if scene_has_content(scene) {
                self.scenes_with_content += 1;
            }
            if scene.characters.is_empty() {
                self.scenes_without_characters += 1;
            }
            for character in &scene.characters {
                self.characters_total += 1;
                let identity = character_identity(&character.name);
                if !identity.is_empty() && !folded_source.contains(&identity) {
                    self.characters_ungrounded += 1;
                }
            }
            self.outfits_total += scene.outfits.len();
            // The production grounding check, run on a copy so the aggregate
            // never mutates what the next counter reads.
            let mut owned = scene.clone();
            for rejected in verify_draft_outfits(&mut owned, source_text) {
                match rejected.reason {
                    RejectedOutfitReason::UngroundedQuote => self.outfits_ungrounded_quote += 1,
                    RejectedOutfitReason::UnlistedCharacter => {
                        self.outfits_unlisted_character += 1;
                    }
                }
            }
        }
    }
}

/// Whitespace-collapsed, lowercased text, so a name the model capitalised
/// differently still counts as grounded. Core keeps its twin (`grounded_text`)
/// private, and this is a test-side diagnostic, not the production check — the
/// production one is `verify_draft_outfits` below.
fn fold_chunk(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut pending_space = false;
    for ch in text.chars() {
        if ch.is_whitespace() {
            pending_space = !out.is_empty();
            continue;
        }
        if pending_space {
            out.push(' ');
            pending_space = false;
        }
        out.extend(ch.to_lowercase());
    }
    out
}

/// Parse a "USD per million tokens" figure (`0.15`) into nano-USD per million
/// tokens — the unit the repository's pricing read model uses — so the cost
/// arithmetic stays integral. `None` for anything that is not a plain
/// non-negative decimal with at most nine fractional digits.
fn parse_nano_per_mtok(raw: &str) -> Option<u64> {
    let raw = raw.trim();
    // An empty figure is not "zero dollars" — it is a missing price, and a
    // missing price must never be mistaken for a free one.
    if raw.is_empty() {
        return None;
    }
    let (int_part, frac_part) = raw.split_once('.').unwrap_or((raw, ""));
    if frac_part.len() > 9
        || !int_part.chars().all(|c| c.is_ascii_digit())
        || !frac_part.chars().all(|c| c.is_ascii_digit())
    {
        return None;
    }
    let int: u64 = if int_part.is_empty() {
        0
    } else {
        int_part.parse().ok()?
    };
    let mut frac: u64 = 0;
    for digit in frac_part.chars() {
        frac = frac
            .checked_mul(10)?
            .checked_add(u64::from(digit.to_digit(10)?))?;
    }
    let scale = 10_u64.checked_pow(u32::try_from(9usize.checked_sub(frac_part.len())?).ok()?)?;
    int.checked_mul(1_000_000_000)?
        .checked_add(frac.checked_mul(scale)?)
}

/// Optional USD-per-million-token prices so the pass reports money instead of
/// raw tokens. Absent prices are not an error: the tokens are still reported.
fn probe_price(name: &str) -> Option<u64> {
    let raw = env_non_empty(name)?;
    let raw = raw.trim();
    match parse_nano_per_mtok(raw) {
        Some(value) => Some(value),
        None => {
            tracing::warn!(
                variable = name,
                value = %raw,
                "not a USD-per-million-token figure — the pass reports tokens without a cost"
            );
            None
        }
    }
}

/// `None` unless BOTH prices are known — a half-priced estimate is a worse
/// answer than no estimate.
fn cost_micro_usd(
    tokens_in: u64,
    tokens_out: u64,
    price_in: Option<u64>,
    price_out: Option<u64>,
) -> Option<u64> {
    let price_in = price_in?;
    let price_out = price_out?;
    let nano = (u128::from(tokens_in) * u128::from(price_in)
        + u128::from(tokens_out) * u128::from(price_out))
        / 1_000_000;
    u64::try_from(nano / 1_000).ok()
}

/// Which chunks of the document to send: `all` (the production shape) or the
/// first `N` (a cheap manual run).
///
/// Takes the raw variable value instead of reading it, so the selection is
/// testable without touching the process environment.
fn document_chunks(total: usize, raw: Option<&str>) -> Vec<usize> {
    match raw.map(str::trim) {
        Some(value) if value.eq_ignore_ascii_case("all") => (0..total).collect(),
        Some(value) => match value.parse::<usize>() {
            Ok(count) if count > 0 => (0..total.min(count)).collect(),
            _ => {
                tracing::warn!(
                    value = %value,
                    "AI_LLM_PROBE_DOC_CHUNKS is neither `all` nor a positive count — sending all chunks"
                );
                (0..total).collect()
            }
        },
        None => (0..total).collect(),
    }
}

/// One extraction pass over a whole fixture document, plus its grounding and
/// cost — the numbers that decide whether a model/effort pair may ship.
#[tokio::test]
async fn reasoning_effort_document_quality_and_cost() -> Result<()> {
    init_logging();
    let Some((live, models)) = effort_probe_llm()? else {
        tracing::warn!(
            "AI_LLM_PROBE_API_KEY not configured — the document probe SKIPPED (asserted nothing)"
        );
        return Ok(());
    };
    let Some(gdrive) = live_gdrive()? else {
        tracing::warn!(
            "GDRIVE_CLIENT_ID not configured — the document probe SKIPPED (asserted nothing)"
        );
        return Ok(());
    };

    let document_name = probe_document_name(env::var("AI_LLM_PROBE_DOCUMENT").ok());
    let model = env_non_empty("AI_LLM_PROBE_DOC_MODEL")
        .or_else(|| models.first().cloned())
        .ok_or_else(|| anyhow!("AI_LLM_PROBE_MODELS is empty — nothing to probe"))?;
    let variants = env_list("AI_LLM_PROBE_DOC_VARIANTS", &["low"]);
    let price_in = probe_price("AI_LLM_PROBE_PRICE_IN_PER_MTOK");
    let price_out = probe_price("AI_LLM_PROBE_PRICE_OUT_PER_MTOK");

    let prompt = default_prompt(DocumentKind::Script).context("production script prompt")?;
    let bounds = AiImportBounds::default();
    let extractor = LegacyPdfToTextAdapter::new(
        usize::try_from(bounds.max_document_bytes).unwrap_or(usize::MAX),
        PDF_EXTRACT_TIMEOUT,
    );
    let source = gdrive_source(&gdrive, bounds.max_document_bytes).await?;
    let documents = source
        .list_documents()
        .await
        .context("listing the GDrive fixture folder")?;
    let chunks = load_fixture_chunks(&source, &extractor, &documents, &document_name).await?;
    let indexes = document_chunks(
        chunks.len(),
        env_non_empty("AI_LLM_PROBE_DOC_CHUNKS").as_deref(),
    );
    tracing::info!(
        provider = %live.provider.as_str(),
        model = %model,
        document = %document_name,
        chunks_total = chunks.len(),
        chunks_sent = indexes.len(),
        variants = ?variants,
        max_tokens = bounds.max_tokens_per_req,
        price_in_nano_per_mtok = price_in,
        price_out_nano_per_mtok = price_out,
        "reasoning-effort document probe plan (one paid call per chunk and variant)"
    );

    let client =
        OpenAiCompatibleChatClient::new(live.provider, live.api_key.clone(), REQUEST_TIMEOUT)
            .await?;
    let mut passes: Vec<DocumentPass> = Vec::new();
    let mut failures: Vec<String> = Vec::new();
    for variant in &variants {
        let effort = if variant.eq_ignore_ascii_case("default") {
            None
        } else {
            Some(variant.clone())
        };
        let label = effort.clone().unwrap_or_else(|| "default".to_owned());
        let mut pass = DocumentPass {
            model: model.clone(),
            variant: label.clone(),
            ..DocumentPass::default()
        };
        for (position, index) in indexes.iter().enumerate() {
            let Some(chunk) = chunks.get(*index) else {
                continue;
            };
            let source_text = source_text_of(chunk);
            let started = std::time::Instant::now();
            let result = client
                .chat_constrained(LlmChatRequest {
                    provider: live.provider,
                    model: model.clone(),
                    prompt: prompt.clone(),
                    source_text: source_text.clone(),
                    max_tokens: bounds.max_tokens_per_req,
                    response_schema: None,
                    reasoning_effort: effort.clone(),
                })
                .await;
            let wall_ms = u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX);
            match result {
                Ok(outcome) => {
                    pass.absorb_chunk(
                        &chunk.heading,
                        &source_text,
                        &outcome.output,
                        outcome.usage.tokens_in,
                        outcome.usage.tokens_out,
                        wall_ms,
                    );
                    tracing::info!(
                        variant = %label,
                        chunk = index,
                        position = position + 1,
                        chunks_sent = indexes.len(),
                        scenes = outcome.output.scenes.len(),
                        tokens_in = outcome.usage.tokens_in,
                        tokens_out = outcome.usage.tokens_out,
                        wall_ms,
                        "reasoning-effort document chunk"
                    );
                }
                Err(error) => {
                    pass.chunks_failed += 1;
                    tracing::error!(
                        variant = %label,
                        chunk = index,
                        position = position + 1,
                        wall_ms,
                        error = %error,
                        "reasoning-effort document chunk FAILED"
                    );
                    failures.push(format!("{model} / {label} chunk {index}: {error}"));
                }
            }
        }

        let cost = cost_micro_usd(pass.tokens_in, pass.tokens_out, price_in, price_out);
        // Ratios are percentages of the returned rows, so they stay comparable
        // across models with different verbosity.
        let draft_ref_grounding_pct = pass
            .draft_ref_exact
            .saturating_mul(100)
            .checked_div(pass.scenes_returned);
        let character_grounding_pct = pass
            .characters_total
            .saturating_sub(pass.characters_ungrounded)
            .saturating_mul(100)
            .checked_div(pass.characters_total);
        tracing::info!(
            model = %pass.model,
            variant = %pass.variant,
            chunks_sent = pass.chunks_sent,
            chunks_failed = pass.chunks_failed,
            scenes_returned = pass.scenes_returned,
            draft_ref_exact = pass.draft_ref_exact,
            draft_ref_grounding_pct,
            scenes_with_content = pass.scenes_with_content,
            scenes_without_characters = pass.scenes_without_characters,
            characters_total = pass.characters_total,
            characters_ungrounded = pass.characters_ungrounded,
            character_grounding_pct,
            outfits_total = pass.outfits_total,
            outfits_ungrounded_quote = pass.outfits_ungrounded_quote,
            outfits_unlisted_character = pass.outfits_unlisted_character,
            source_chars = pass.source_chars,
            tokens_in = pass.tokens_in,
            tokens_out = pass.tokens_out,
            wall_ms = pass.wall_ms,
            wall_secs = pass.wall_ms / 1_000,
            cost_micro_usd = cost,
            "reasoning-effort document pass"
        );
        passes.push(pass);
    }

    // With two variants the quality/cost trade-off is one line.
    if let (Some(first), Some(second)) = (passes.first(), passes.get(1)) {
        tracing::info!(
            model = %first.model,
            a_variant = %first.variant,
            a_tokens_out = first.tokens_out,
            a_wall_ms = first.wall_ms,
            a_draft_ref_grounding_pct = first
                .draft_ref_exact
                .saturating_mul(100)
                .checked_div(first.scenes_returned),
            b_variant = %second.variant,
            b_tokens_out = second.tokens_out,
            b_wall_ms = second.wall_ms,
            b_draft_ref_grounding_pct = second
                .draft_ref_exact
                .saturating_mul(100)
                .checked_div(second.scenes_returned),
            "reasoning-effort document comparison"
        );
    }

    if failures.is_empty() {
        Ok(())
    } else {
        Err(anyhow!(
            "{} of {} document chunks failed:\n- {}",
            failures.len(),
            indexes.len() * variants.len(),
            failures.join("\n- ")
        ))
    }
}

// ===========================================================================
// The probe's own arithmetic, asserted offline.
//
// The live probe can only run in the nightly with a real key, so the parts that
// can be silently WRONG — the price parse and the cost division — are pinned
// here where every CI run sees them. A rounded-up or float-based cost figure
// would quietly misreport money in the very log line the decision is based on.
// ===========================================================================

/// The 2026-11-20 nightly failed in 4.6 s because an undefined optional workflow
/// variable arrives as an EMPTY string, not as "unset".
#[test]
fn an_empty_or_blank_setting_is_treated_as_unset() {
    assert_eq!(non_empty(None), None);
    assert_eq!(non_empty(Some(String::new())), None);
    assert_eq!(non_empty(Some("   ".to_owned())), None);
    assert_eq!(non_empty(Some("\t\n".to_owned())), None);
    // A real value is passed through untouched (no trimming of a file name).
    assert_eq!(
        non_empty(Some("292.pdf".to_owned())).as_deref(),
        Some("292.pdf")
    );
    assert_eq!(
        non_empty(Some("neuralwatt".to_owned())).as_deref(),
        Some("neuralwatt")
    );
}

#[test]
/// The call site of [`non_empty`] is what actually broke the nightly: the helper
/// was correct, but `env::var(..).unwrap_or(default)` never asked it. Testing the
/// RESOLVER keeps that mistake from coming back.
fn the_probe_document_falls_back_only_when_the_variable_carries_no_value() {
    assert_eq!(probe_document_name(None), DEFAULT_PROBE_DOCUMENT);
    assert_eq!(
        probe_document_name(Some(String::new())),
        DEFAULT_PROBE_DOCUMENT
    );
    assert_eq!(
        probe_document_name(Some("   ".to_owned())),
        DEFAULT_PROBE_DOCUMENT,
        "an undefined workflow `vars` entry arrives as an empty/blank string"
    );
    assert_eq!(probe_document_name(Some("293.pdf".to_owned())), "293.pdf");
    // The default must be a document the nightly actually requires, or the
    // fallback would name a fixture that is not there.
    assert!(
        REQUIRED_SCRIPTS.contains(&DEFAULT_PROBE_DOCUMENT),
        "the probe default must be one of the required fixtures"
    );
}

#[test]
fn nano_per_mtok_parses_plain_decimal_prices() {
    // The figures Neuralwatt publishes for the probed models.
    assert_eq!(parse_nano_per_mtok("0.15"), Some(150_000_000));
    assert_eq!(parse_nano_per_mtok("0.5"), Some(500_000_000));
    assert_eq!(parse_nano_per_mtok("1.45"), Some(1_450_000_000));
    assert_eq!(parse_nano_per_mtok("2"), Some(2_000_000_000));
    assert_eq!(parse_nano_per_mtok(" 0.15 "), Some(150_000_000));
    // Nine fractional digits is the nano-USD resolution, and one nano is the floor.
    assert_eq!(parse_nano_per_mtok("0.000000001"), Some(1));
    // Anything else is refused rather than guessed.
    assert_eq!(parse_nano_per_mtok(""), None);
    assert_eq!(parse_nano_per_mtok("   "), None);
    assert_eq!(parse_nano_per_mtok("abc"), None);
    assert_eq!(parse_nano_per_mtok("-1"), None);
    assert_eq!(parse_nano_per_mtok("0.1234567891"), None);
    assert_eq!(parse_nano_per_mtok("1.2.3"), None);
}

/// The measured `glm-5.3-flash`/`low` row of 2026-11-20: 3 822 in, 1 089 out at
/// $0.15 / $0.50 per million tokens is 1 117 µUSD — the figure that makes a
/// 40-chunk document ~$0.045.
#[test]
fn cost_reports_micro_usd_from_nano_per_million_prices() {
    assert_eq!(
        cost_micro_usd(3_822, 1_089, Some(150_000_000), Some(500_000_000)),
        Some(1_117)
    );
    // A half-known price is not an estimate — it is no estimate.
    assert_eq!(cost_micro_usd(1_000, 1_000, Some(150_000_000), None), None);
    assert_eq!(cost_micro_usd(1_000, 1_000, None, Some(500_000_000)), None);
    // Zero usage costs zero even with prices, and never divides by zero.
    assert_eq!(
        cost_micro_usd(0, 0, Some(150_000_000), Some(500_000_000)),
        Some(0)
    );
}

#[test]
fn document_chunks_defaults_to_every_chunk() {
    assert_eq!(document_chunks(3, None), vec![0, 1, 2]);
    assert_eq!(document_chunks(3, Some("all")), vec![0, 1, 2]);
    assert_eq!(document_chunks(3, Some("ALL")), vec![0, 1, 2]);
    assert_eq!(document_chunks(3, Some("2")), vec![0, 1]);
    // A count beyond the document is clamped, never an out-of-range index.
    assert_eq!(document_chunks(3, Some("99")), vec![0, 1, 2]);
    // Junk falls back to the production shape instead of sending nothing.
    assert_eq!(document_chunks(3, Some("0")), vec![0, 1, 2]);
    assert_eq!(document_chunks(3, Some("zwei")), vec![0, 1, 2]);
    assert_eq!(document_chunks(0, None), Vec::<usize>::new());
}

#[test]
fn folded_text_matches_core_character_identity_folding() {
    // `character_identity` folds case and collapses whitespace; the chunk must be
    // folded the same way or every multi-line name would count as ungrounded.
    assert_eq!(
        fold_chunk("ANNA  (30,\n Pflegerin)"),
        "anna (30, pflegerin)"
    );
    assert_eq!(character_identity("  Anna "), "anna");
    assert!(fold_chunk("INT. KÜCHE - TAG\nANNA kommt herein.").contains("anna"));
}
