// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

//! Live GDrive fixture smoke test.
//!
//! The test is intentionally a no-op when the existing GDrive CI/local
//! variables are absent, so fork PRs and ordinary unit-test runs never need
//! external credentials.

mod fixtures;

use std::env;

use anyhow::{Result, anyhow};
use breakdown_core::settings::ports::{CredentialVault, GDriveCredentialBundle};
use infra::ai::{AiDocumentSource, GDriveDocumentSource};
use uuid::Uuid;

#[tokio::test]
async fn existing_gdrive_folder_is_readable_through_test_vault() -> Result<()> {
    let Some(client_id) = env::var("GDRIVE_CLIENT_ID").ok().filter(|v| !v.is_empty()) else {
        return Ok(());
    };
    let client_secret = env::var("GDRIVE_CLIENT_SECRET").map_err(|_| {
        anyhow!("GDRIVE_CLIENT_SECRET is required when live GDrive testing is enabled")
    })?;
    let refresh_token = env::var("GDRIVE_REFRESH_TOKEN").map_err(|_| {
        anyhow!("GDRIVE_REFRESH_TOKEN is required when live GDrive testing is enabled")
    })?;
    let root = env::var("GDRIVE_ROOT")
        .map_err(|_| anyhow!("GDRIVE_ROOT is required when live GDrive testing is enabled"))?;

    // Note: GDRIVE_ROOT is passed to OpenDAL's `services-gdrive` builder as its
    // `root` setting, which resolves the folder by NAME/path (e.g.
    // "breakdown-rs-test" or "parent/sub") — a Drive folder ID (e.g.
    // 1IcJDk--K8HTi2pQoIO7RGdyO6ANgeDwy) will NOT resolve and the listing
    // returns zero documents.

    let vault = fixtures::spawn_vault().await?;
    let client = vault.client();
    let settings_id = Uuid::now_v7();
    let bundle =
        GDriveCredentialBundle::try_new(client_id, client_secret, refresh_token, Some(root))?;
    let binding = client.store_gdrive(settings_id, bundle).await?;
    let source =
        GDriveDocumentSource::from_vault(&client, settings_id, &binding, 20 * 1024 * 1024).await?;
    let documents = source.list_documents().await?;
    let pdfs: Vec<_> = documents
        .iter()
        .filter(|document| document.name.to_ascii_lowercase().ends_with(".pdf"))
        .collect();
    if pdfs.len() < 3 {
        return Err(anyhow!(
            "expected at least three PDF fixtures in GDRIVE_ROOT, found {}",
            pdfs.len()
        ));
    }
    for document in pdfs.iter().take(3) {
        let bytes = source.load(&document.handle).await?;
        if bytes.is_empty() {
            return Err(anyhow!("GDrive fixture {} is empty", document.name));
        }
        if !bytes.starts_with(b"%PDF") {
            return Err(anyhow!("GDrive fixture {} is not a PDF", document.name));
        }
    }
    client.destroy(settings_id, &binding.vault_key_id).await?;
    Ok(())
}
