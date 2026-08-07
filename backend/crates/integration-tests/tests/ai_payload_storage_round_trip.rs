// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
mod fixtures;

use anyhow::Result;
use breakdown_core::ai::AiImportJobId;
use fixtures::{GarageCredentials, spawn_garage};
use infra::ai::{AiDocumentStore, AiPreviewStore, OpenDalAiPayloadStorage};

/// Build an `OpenDalAiPayloadStorage` from Garage test credentials.
fn build_ai_payload_storage(creds: &GarageCredentials) -> OpenDalAiPayloadStorage {
    OpenDalAiPayloadStorage::new(
        creds.endpoint.clone(),
        creds.access_key.clone(),
        creds.secret_key.clone(),
        creds.bucket.clone(),
        None,
    )
}

/// Test that AI payloads survive a simulated restart (new storage instance, same bucket).
///
/// This verifies the core promise of Issue #174: durable storage for source documents
/// and preview payloads so that pending jobs can resume after an API restart.
#[tokio::test]
async fn ai_payload_storage_survives_simulated_restart() -> Result<()> {
    let (creds, _container) = spawn_garage().await?;

    // Create the AI payload bucket
    let storage = build_ai_payload_storage(&creds);
    // Note: In a real scenario, the bucket would be created by the provision script.
    // For this test, we use the same bucket as costume photos for simplicity.

    let job_id = AiImportJobId::new();
    let source_bytes = b"PDF content for script import".to_vec();
    let preview_bytes = b"{\"scenes\": [{\"heading\": \"INT. KITCHEN\"}]}".to_vec();

    // Phase 1: Store payloads with first storage instance
    {
        let source_handle = storage.put_source(job_id, source_bytes.clone()).await?;
        assert!(source_handle.contains(&job_id.as_uuid().to_string()));
        assert!(source_handle.ends_with("/source"));

        let preview_handle = storage.put(job_id, preview_bytes.clone()).await?;
        assert!(preview_handle.contains(&job_id.as_uuid().to_string()));
        assert!(preview_handle.ends_with("/preview"));

        // Verify both are readable
        let loaded_source = storage.get_source(&source_handle).await?.unwrap();
        assert_eq!(loaded_source, source_bytes);

        let loaded_preview = storage.get(&preview_handle).await?.unwrap();
        assert_eq!(loaded_preview, preview_bytes);
    }

    // Phase 2: Simulate restart - create new storage instance with same bucket
    {
        let storage = build_ai_payload_storage(&creds);

        // Reconstruct handles (as the queue would after restart)
        let source_handle = format!("ai-import/{}/source", job_id.as_uuid());
        let preview_handle = format!("ai-import/{}/preview", job_id.as_uuid());

        // Verify payloads are still accessible
        let loaded_source = storage.get_source(&source_handle).await?.unwrap();
        assert_eq!(
            loaded_source, source_bytes,
            "Source document should survive simulated restart"
        );

        let loaded_preview = storage.get(&preview_handle).await?.unwrap();
        assert_eq!(
            loaded_preview, preview_bytes,
            "Preview payload should survive simulated restart"
        );
    }

    Ok(())
}

/// Test that delete works correctly and missing handles are a no-op.
#[tokio::test]
async fn ai_payload_storage_delete_is_idempotent() -> Result<()> {
    let (creds, _container) = spawn_garage().await?;

    let storage = build_ai_payload_storage(&creds);
    let job_id = AiImportJobId::new();

    // Store and then delete source
    let source_handle = storage.put_source(job_id, b"test".to_vec()).await?;
    assert!(storage.get_source(&source_handle).await?.is_some());

    storage.delete_source(&source_handle).await?;
    assert!(storage.get_source(&source_handle).await?.is_none());

    // Deleting again should be a no-op (not an error)
    storage.delete_source(&source_handle).await?;

    // Store and then delete preview
    let preview_handle = storage.put(job_id, b"preview".to_vec()).await?;
    assert!(storage.get(&preview_handle).await?.is_some());

    storage.delete(&preview_handle).await?;
    assert!(storage.get(&preview_handle).await?.is_none());

    // Deleting again should be a no-op (not an error)
    storage.delete(&preview_handle).await?;

    Ok(())
}

/// Test that source and preview handles are independent.
#[tokio::test]
async fn ai_payload_storage_source_and_preview_are_independent() -> Result<()> {
    let (creds, _container) = spawn_garage().await?;

    let storage = build_ai_payload_storage(&creds);
    let job_id = AiImportJobId::new();

    let source_bytes = b"source document".to_vec();
    let preview_bytes = b"preview payload".to_vec();

    let source_handle = storage.put_source(job_id, source_bytes.clone()).await?;
    let preview_handle = storage.put(job_id, preview_bytes.clone()).await?;

    // Handles should be different
    assert_ne!(source_handle, preview_handle);

    // Deleting source should not affect preview
    storage.delete_source(&source_handle).await?;
    assert!(storage.get_source(&source_handle).await?.is_none());
    assert_eq!(storage.get(&preview_handle).await?, Some(preview_bytes));

    Ok(())
}
