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

/// Null-object payload store for a composition root with AI import disabled
/// (issue #181).
///
/// The production composition root must never hold a store that *silently*
/// accepts payloads it cannot keep. `MemoryAiPreviewStore` used to fill this
/// slot, and it does exactly that: a restart drops every byte it holds, so a
/// persisted job row outlives its own payload. This adapter instead refuses
/// every operation, so any code path that reaches it fails loudly and
/// immediately.
///
/// The refusal is a `ServiceUnavailable`, not a `NotFound`: nothing was lost,
/// the capability was never configured. That distinction matters downstream —
/// a `NotFound` is what marks a job permanently non-resumable
/// ([`JobStatus::PayloadUnavailable`](breakdown_core::ai::JobStatus::PayloadUnavailable)),
/// and a deployment that merely has AI import switched off must not
/// dead-letter jobs an operator may later enable the feature for.
///
/// Unreachable in practice: `main.rs` refuses to boot with `AI_IMPORT_ENABLED`
/// set and no payload storage configured, and every AI route returns `404`
/// while the feature is off.
#[derive(Clone, Copy, Default, Debug)]
pub struct UnconfiguredAiPayloadStore;

impl UnconfiguredAiPayloadStore {
    fn unavailable(operation: &str) -> DomainError {
        DomainError::ServiceUnavailable(format!(
            "AI payload storage is not configured; cannot {operation}. \
             Set AI_PAYLOAD_S3_ENDPOINT, AI_PAYLOAD_S3_ACCESS_KEY and \
             AI_PAYLOAD_S3_SECRET_KEY."
        ))
    }
}

#[async_trait]
impl AiPreviewStore for UnconfiguredAiPayloadStore {
    async fn put(&self, _job_id: AiImportJobId, _payload: Vec<u8>) -> Result<String, DomainError> {
        Err(Self::unavailable("store a preview payload"))
    }

    async fn get(&self, _handle: &str) -> Result<Option<Vec<u8>>, DomainError> {
        Err(Self::unavailable("read a preview payload"))
    }

    async fn delete(&self, _handle: &str) -> Result<(), DomainError> {
        Err(Self::unavailable("delete a preview payload"))
    }
}

#[async_trait]
impl AiDocumentStore for UnconfiguredAiPayloadStore {
    async fn put_source(
        &self,
        _job_id: AiImportJobId,
        _payload: Vec<u8>,
    ) -> Result<String, DomainError> {
        Err(Self::unavailable("store a source document"))
    }

    async fn get_source(&self, _handle: &str) -> Result<Option<Vec<u8>>, DomainError> {
        Err(Self::unavailable("read a source document"))
    }

    async fn delete_source(&self, _handle: &str) -> Result<(), DomainError> {
        Err(Self::unavailable("delete a source document"))
    }
}

#[async_trait]
impl AiDocumentSource for UnconfiguredAiPayloadStore {
    async fn load(&self, _handle: &str) -> Result<Vec<u8>, DomainError> {
        Err(Self::unavailable("load a source document"))
    }
}
