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
    AiImportBounds, DocumentKind, DraftScene, LlmChatRequest, LlmClient, LlmProvider, SceneChunk,
    ScriptContext, extract_scenes,
};
use breakdown_core::settings::ports::{CredentialVault, GDriveCredentialBundle};
use infra::ai::{
    AiDocumentSource, GDriveDocument, GDriveDocumentSource, OpenAiCompatibleChatClient,
    PdfTextExtractor, default_prompt,
};
use uuid::Uuid;

/// Deployment defaults when the nightly variables are unset: the provider and
/// assistant model the dev/prod AI configuration currently uses.
const DEFAULT_PROVIDER: &str = "eurouter";
const DEFAULT_MODEL: &str = "mistral-large-3";

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
    let Some(api_key) = env::var("AI_LLM_API_KEY")
        .ok()
        .filter(|value| !value.is_empty())
    else {
        return Ok(None);
    };
    let provider_key = env::var("AI_LLM_PROVIDER").unwrap_or_else(|_| DEFAULT_PROVIDER.to_owned());
    let model = env::var("AI_LLM_MODEL").unwrap_or_else(|_| DEFAULT_MODEL.to_owned());
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
    let Some(client_id) = env::var("GDRIVE_CLIENT_ID")
        .ok()
        .filter(|value| !value.is_empty())
    else {
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
    extractor: &'a PdfTextExtractor,
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
    // `-layout` is what production uses (see `PdfTextExtractor`): the same
    // invocation must produce the same headings for the splitter, otherwise the
    // smoke measures a different pipeline than the product.
    let extractor = PdfTextExtractor::new(
        usize::try_from(bounds.max_document_bytes).unwrap_or(usize::MAX),
        PDF_EXTRACT_TIMEOUT,
    );
    let source = gdrive_source(&gdrive, bounds.max_document_bytes).await?;
    let documents = source
        .list_documents()
        .await
        .context("listing the GDrive fixture folder")?;
    tracing::info!(
        documents = documents.len(),
        root = %gdrive.root,
        "GDrive fixture folder listed"
    );

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

/// Load, extract, chunk and call one fixture document.
async fn extract_one_script(smoke: &LiveExtraction<'_>, name: &str) -> Result<()> {
    let document = smoke
        .documents
        .iter()
        .find(|document| document.name == name)
        .ok_or_else(|| {
            let available: Vec<&str> = smoke
                .documents
                .iter()
                .map(|document| document.name.as_str())
                .collect();
            anyhow!("not present in GDRIVE_ROOT; available documents: {available:?}")
        })?;
    let bytes = smoke
        .source
        .load(&document.handle)
        .await
        .with_context(|| format!("could not load {} from GDrive", document.name))?;
    let text = smoke.extractor.extract(&bytes).await.with_context(|| {
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
    let mut failures: Vec<String> = Vec::new();
    for index in chunks_to_probe(&chunks) {
        if let Err(error) = probe_chunk(smoke, &document.name, &chunks, index).await {
            tracing::error!(
                document = %document.name,
                chunk = index,
                error = %format!("{error:#}"),
                "live chunk extraction FAILED"
            );
            failures.push(format!("{} chunk {index}: {error:#}", document.name));
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
