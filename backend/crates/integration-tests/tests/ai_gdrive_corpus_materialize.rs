// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Materialise the GDrive Golden Corpus into a local directory (ADR-041 `D8`,
//! issue #959).
//!
//! The broadcast scripts and shooting schedules of the evaluation corpus are
//! confidential third-party IP: they live in the GDrive fixture folder that the
//! nightly workflow reads and must never enter Git. This test copies them into
//! `AI_EVAL_CORPUS_DIR` so the *same* assertions run locally and in CI:
//!
//! ```text
//! cd backend
//! # once, with the GDrive credentials in the environment (or the CI secrets):
//! AI_EVAL_CORPUS_DIR=$PWD/target/eval-corpus \
//!   cargo test -p integration-tests --test ai_gdrive_corpus_materialize -- --nocapture
//! # then, exactly the command CI runs:
//! AI_EVAL_CORPUS_DIR=$PWD/target/eval-corpus \
//!   cargo test -p infra --test ai_document_eval_corpus -- --nocapture
//! ```
//!
//! Without `GDRIVE_CLIENT_ID` the test returns `Ok(())` immediately, matching
//! [`ai_gdrive_fixture_test`](super::ai_gdrive_fixture_test): a missing
//! credential must skip, not fail, because CI only exposes the secrets to
//! trusted contexts. With the credential set, an unusable configuration is a
//! hard error — a "materialised" corpus that silently skipped would turn the
//! corpus gate into a no-op.
//!
//! What it does **not** do: it never deletes a file from the target directory
//! and never invents an expectation. Which documents exist and how many scenes
//! each must produce is stated in `config/ai_eval_corpus.tsv`; this test only
//! fetches the bytes.

// The whole point of this test is to be *visible* in a CI log (`--nocapture`):
// it reports every document it wrote. Same opt-in as the corpus harness itself.
#![allow(clippy::print_stderr)]

mod fixtures;

use std::env;
use std::path::{Path, PathBuf};

use anyhow::{Result, anyhow};
use breakdown_core::ai::sanitize_source_file_name;
use breakdown_core::settings::ports::{CredentialVault, GDriveCredentialBundle};
use infra::ai::{AiDocumentSource, GDriveDocument, GDriveDocumentSource};
use uuid::Uuid;

/// The directory the corpus is materialised into: `AI_EVAL_CORPUS_DIR`.
const CORPUS_ENV: &str = "AI_EVAL_CORPUS_DIR";

/// Default target when the variable is unset: inside the (gitignored) build
/// directory, so a local run cannot commit confidential IP by accident.
const DEFAULT_DIRECTORY: &str = "target/eval-corpus";

#[tokio::test]
async fn the_gdrive_corpus_can_be_materialised_for_the_eval_harness() -> Result<()> {
    let Some(client_id) = env::var("GDRIVE_CLIENT_ID").ok().filter(|v| !v.is_empty()) else {
        eprintln!("skipped: GDRIVE_CLIENT_ID is unset (the corpus lives in GDrive, never in Git)");
        return Ok(());
    };
    let client_secret = env::var("GDRIVE_CLIENT_SECRET")
        .map_err(|_| anyhow!("GDRIVE_CLIENT_SECRET is required when the corpus is fetched"))?;
    let refresh_token = env::var("GDRIVE_REFRESH_TOKEN")
        .map_err(|_| anyhow!("GDRIVE_REFRESH_TOKEN is required when the corpus is fetched"))?;
    let root = env::var("GDRIVE_ROOT")
        .map_err(|_| anyhow!("GDRIVE_ROOT is required when the corpus is fetched"))?;
    let directory =
        env::var_os(CORPUS_ENV).map_or_else(|| PathBuf::from(DEFAULT_DIRECTORY), PathBuf::from);
    std::fs::create_dir_all(&directory).map_err(|error| {
        anyhow!(
            "could not create the corpus directory {}: {error}",
            directory.display()
        )
    })?;

    let vault = fixtures::spawn_vault().await?;
    let client = vault.client();
    let settings_id = Uuid::now_v7();
    let bundle =
        GDriveCredentialBundle::try_new(client_id, client_secret, refresh_token, Some(root))?;
    let binding = client.store_gdrive(settings_id, bundle).await?;
    let max_document_bytes = breakdown_core::ai::AiImportBounds::default().max_document_bytes;
    let source =
        GDriveDocumentSource::from_vault(&client, settings_id, &binding, max_document_bytes)
            .await?;

    let documents = source.list_documents().await?;
    let mut written: Vec<String> = Vec::new();
    for document in documents {
        let target = corpus_path(&directory, &document)?;
        let bytes = source.load(&document.handle).await?;
        if bytes.is_empty() {
            return Err(anyhow!("GDrive corpus document {} is empty", document.name));
        }
        if !bytes.starts_with(b"%PDF") {
            return Err(anyhow!(
                "GDrive corpus document {} is not a PDF",
                document.name
            ));
        }
        std::fs::write(&target, &bytes).map_err(|error| {
            anyhow!(
                "could not write {} ({} bytes): {error}",
                target.display(),
                bytes.len()
            )
        })?;
        written.push(document.name.clone());
        eprintln!("wrote {} ({} bytes)", target.display(), bytes.len());
    }
    client.destroy(settings_id, &binding.vault_key_id).await?;

    // A corpus fetch that wrote nothing is a configuration error, not a pass: the
    // eval harness would then skip every document while CI stayed green.
    if written.is_empty() {
        return Err(anyhow!(
            "GDRIVE_ROOT contained no document — {} stays empty",
            directory.display()
        ));
    }
    written.sort();
    eprintln!(
        "materialised {} document(s) into {}: {}",
        written.len(),
        directory.display(),
        written.join(", ")
    );
    Ok(())
}

/// Where one GDrive document is written: `directory/<sanitized basename>`.
///
/// The name comes from Drive, i.e. from outside the trust boundary, so it is
/// normalised with the same rules the upload path uses — basename only, control
/// characters dropped, whitespace collapsed, length capped. That is what keeps a
/// hostile name (`../../etc/cron.d/x`) inside the corpus directory. A name that
/// is not a PDF is skipped by returning an error the caller reports, because the
/// corpus is defined as the PDFs of the folder.
fn corpus_path(directory: &Path, document: &GDriveDocument) -> Result<PathBuf> {
    let name = sanitize_source_file_name(&document.name)
        .ok_or_else(|| anyhow!("GDrive document {:?} has no usable name", document.name))?;
    if !name.to_ascii_lowercase().ends_with(".pdf") {
        return Err(anyhow!("GDrive document {name:?} is not a PDF"));
    }
    Ok(directory.join(name))
}
