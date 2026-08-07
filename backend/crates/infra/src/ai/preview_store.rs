// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

use std::collections::HashMap;
use std::sync::Arc;

use async_trait::async_trait;
use breakdown_core::ai::AiImportJobId;
use breakdown_core::error::DomainError;
use tokio::sync::RwLock;

#[async_trait]
pub trait AiPreviewStore: Send + Sync {
    async fn put(&self, job_id: AiImportJobId, payload: Vec<u8>) -> Result<String, DomainError>;
    async fn get(&self, handle: &str) -> Result<Option<Vec<u8>>, DomainError>;
    /// Remove a stored payload. Used to clean up orphaned blobs when a
    /// duplicate upload is deduplicated after storage. Missing handles are a
    /// no-op (the caller treats removal as best-effort).
    async fn delete(&self, handle: &str) -> Result<(), DomainError>;
}

/// Store source documents (PDFs, CSVs) durably. Source documents are
/// distinct from preview payloads and must not overwrite them.
#[async_trait]
pub trait AiDocumentStore: Send + Sync {
    async fn put_source(
        &self,
        job_id: AiImportJobId,
        payload: Vec<u8>,
    ) -> Result<String, DomainError>;
    async fn get_source(&self, handle: &str) -> Result<Option<Vec<u8>>, DomainError>;
    async fn delete_source(&self, handle: &str) -> Result<(), DomainError>;
}

/// Small in-memory preview store for unit tests and local development. The
/// production composition root can replace it with an object-store adapter.
#[derive(Clone, Default, Debug)]
pub struct MemoryAiPreviewStore {
    values: Arc<RwLock<HashMap<String, Vec<u8>>>>,
}

#[async_trait]
impl AiPreviewStore for MemoryAiPreviewStore {
    async fn put(&self, job_id: AiImportJobId, payload: Vec<u8>) -> Result<String, DomainError> {
        let handle = format!("ai-preview/{}", job_id.as_uuid());
        self.values.write().await.insert(handle.clone(), payload);
        Ok(handle)
    }

    async fn get(&self, handle: &str) -> Result<Option<Vec<u8>>, DomainError> {
        Ok(self.values.read().await.get(handle).cloned())
    }

    async fn delete(&self, handle: &str) -> Result<(), DomainError> {
        self.values.write().await.remove(handle);
        Ok(())
    }
}

impl MemoryAiPreviewStore {
    /// Store a payload under an explicit handle (test helper).
    /// The production `put` derives the handle from the job id; tests
    /// sometimes need to control the handle to match a fake queue's
    /// `preview_handle` field.
    #[cfg(any(test, feature = "test-support"))]
    pub async fn put_raw_for_test(&self, handle: String, payload: Vec<u8>) {
        self.values.write().await.insert(handle, payload);
    }
}

#[async_trait]
impl AiDocumentStore for MemoryAiPreviewStore {
    async fn put_source(
        &self,
        job_id: AiImportJobId,
        payload: Vec<u8>,
    ) -> Result<String, DomainError> {
        let handle = format!("ai-source/{}", job_id.as_uuid());
        self.values.write().await.insert(handle.clone(), payload);
        Ok(handle)
    }

    async fn get_source(&self, handle: &str) -> Result<Option<Vec<u8>>, DomainError> {
        Ok(self.values.read().await.get(handle).cloned())
    }

    async fn delete_source(&self, handle: &str) -> Result<(), DomainError> {
        self.values.write().await.remove(handle);
        Ok(())
    }
}

#[async_trait]
impl AiDocumentSource for MemoryAiPreviewStore {
    async fn load(&self, handle: &str) -> Result<Vec<u8>, DomainError> {
        self.get(handle)
            .await?
            .ok_or_else(|| DomainError::NotFound(format!("AI document source {handle}")))
    }
}

#[async_trait]
pub trait AiDocumentSource: Send + Sync {
    async fn load(&self, handle: &str) -> Result<Vec<u8>, DomainError>;
}
