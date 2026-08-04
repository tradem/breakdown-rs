// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

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
}

/// Small in-memory preview store for unit tests and local development. The
/// production composition root can replace it with an object-store adapter.
#[derive(Clone, Default)]
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
}

#[async_trait]
pub trait AiDocumentSource: Send + Sync {
    async fn load(&self, handle: &str) -> Result<Vec<u8>, DomainError>;
}
