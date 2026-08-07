// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: glm-5.2 (neuralwatt)

//! Durable AI import payload storage backed by OpenDAL/S3 (Garage).
//!
//! Stores source documents (PDFs, CSVs) and preview payloads (JSON) durably
//! so that pending jobs can resume after an API restart and succeeded jobs
//! can continue serving previews.
//!
//! Key layout (adapter-internal, never exposed via the port):
//! - Source documents: `ai-import/{job_id}/source`
//! - Preview payloads: `ai-import/{job_id}/preview`

// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: mimo-v2.5 (opencode-go)

use std::path::Path;
use std::sync::Arc;

use async_trait::async_trait;
use breakdown_core::ai::AiImportJobId;
use breakdown_core::error::DomainError;
use opendal::Operator;
use tokio::sync::Mutex;
use tracing::{debug, warn};

use super::preview_store::{AiDocumentSource, AiDocumentStore, AiPreviewStore};

/// OpenDAL-backed AI payload storage adapter.
///
/// Stores source documents and preview payloads in an S3-compatible backend
/// (Garage). Unlike photo storage, AI payloads don't contain PII and don't
/// require SSE-C encryption.
#[derive(Clone)]
pub struct OpenDalAiPayloadStorage {
    inner: Arc<StorageInner>,
}

#[derive(Debug)]
struct StorageInner {
    /// Cached OpenDAL operator; `None` until the first successful construction.
    op: Mutex<Option<Operator>>,
    /// S3 endpoint URL.
    endpoint: String,
    /// S3 access key.
    access_key: String,
    /// S3 secret key.
    secret_key: String,
    /// S3 bucket name.
    bucket: String,
    /// Optional TLS root certificate path.
    root_cert: Option<String>,
}

impl std::fmt::Debug for OpenDalAiPayloadStorage {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("OpenDalAiPayloadStorage")
            .field("bucket", &self.inner.bucket)
            .finish_non_exhaustive()
    }
}

impl OpenDalAiPayloadStorage {
    /// Build a new storage adapter from environment variables.
    ///
    /// # Environment Variables
    ///
    /// - `AI_PAYLOAD_S3_ENDPOINT` — S3 API endpoint (e.g. `http://garage:3900`)
    /// - `AI_PAYLOAD_S3_ACCESS_KEY` — S3 access key
    /// - `AI_PAYLOAD_S3_SECRET_KEY` — S3 secret key
    /// - `AI_PAYLOAD_S3_BUCKET` — bucket name (default: `ai-import-payloads`)
    /// - `AI_PAYLOAD_S3_TLS_ROOT_CERT` — optional PEM path of the pinned root CA
    ///
    /// Returns `None` if required environment variables are not set.
    pub fn from_env() -> Option<Self> {
        let endpoint = std::env::var("AI_PAYLOAD_S3_ENDPOINT").ok()?;
        let access_key = std::env::var("AI_PAYLOAD_S3_ACCESS_KEY").ok()?;
        let secret_key = std::env::var("AI_PAYLOAD_S3_SECRET_KEY").ok()?;
        let bucket = std::env::var("AI_PAYLOAD_S3_BUCKET")
            .unwrap_or_else(|_| "ai-import-payloads".to_string());
        let root_cert = std::env::var("AI_PAYLOAD_S3_TLS_ROOT_CERT").ok();

        Some(Self {
            inner: Arc::new(StorageInner {
                op: Mutex::new(None),
                endpoint,
                access_key,
                secret_key,
                bucket,
                root_cert,
            }),
        })
    }

    /// Build a new storage adapter with explicit configuration.
    #[cfg(any(test, feature = "test-support"))]
    pub fn new(
        endpoint: String,
        access_key: String,
        secret_key: String,
        bucket: String,
        root_cert: Option<String>,
    ) -> Self {
        Self {
            inner: Arc::new(StorageInner {
                op: Mutex::new(None),
                endpoint,
                access_key,
                secret_key,
                bucket,
                root_cert,
            }),
        }
    }

    /// Return the cached operator, or construct one on demand.
    async fn operator(&self) -> Result<Operator, DomainError> {
        // Fast path: return cached operator
        {
            let guard = self.inner.op.lock().await;
            if let Some(op) = guard.as_ref() {
                return Ok(op.clone());
            }
        }

        // Slow path: construct operator
        let op = self.build_operator()?;
        let mut guard = self.inner.op.lock().await;
        *guard = Some(op.clone());
        Ok(op)
    }

    /// Build an OpenDAL S3 operator from the stored configuration.
    fn build_operator(&self) -> Result<Operator, DomainError> {
        let root_cert_path = self.inner.root_cert.as_deref().map(Path::new);
        crate::tls::s3_builder(
            &self.inner.endpoint,
            &self.inner.access_key,
            &self.inner.secret_key,
            &self.inner.bucket,
            root_cert_path,
        )
        .map_err(|e| {
            DomainError::ValidationError(format!(
                "Failed to build AI payload storage operator: {e}"
            ))
        })
    }

    /// Build the internal storage key for a source document.
    fn source_key(job_id: AiImportJobId) -> String {
        format!("ai-import/{}/source", job_id.as_uuid())
    }

    /// Build the internal storage key for a preview payload.
    fn preview_key(job_id: AiImportJobId) -> String {
        format!("ai-import/{}/preview", job_id.as_uuid())
    }
}

#[async_trait]
impl AiPreviewStore for OpenDalAiPayloadStorage {
    async fn put(&self, job_id: AiImportJobId, payload: Vec<u8>) -> Result<String, DomainError> {
        let key = Self::preview_key(job_id);
        let op = self.operator().await?;

        op.write(&key, payload)
            .await
            .map_err(|e| map_storage_error(&key, e))?;

        debug!(job_id = %job_id.as_uuid(), key = %key, "Stored AI preview payload");
        Ok(key)
    }

    async fn get(&self, handle: &str) -> Result<Option<Vec<u8>>, DomainError> {
        let op = self.operator().await?;

        match op.read(handle).await {
            Ok(data) => Ok(Some(data.to_vec())),
            Err(e) if is_not_found(&e) => Ok(None),
            Err(e) => Err(map_storage_error(handle, e)),
        }
    }

    async fn delete(&self, handle: &str) -> Result<(), DomainError> {
        let op = self.operator().await?;

        match op.delete(handle).await {
            Ok(()) => {
                debug!(key = %handle, "Deleted AI payload");
                Ok(())
            }
            Err(e) if is_not_found(&e) => {
                // Missing handle is a no-op
                Ok(())
            }
            Err(e) => Err(map_storage_error(handle, e)),
        }
    }
}

#[async_trait]
impl AiDocumentSource for OpenDalAiPayloadStorage {
    async fn load(&self, handle: &str) -> Result<Vec<u8>, DomainError> {
        let op = self.operator().await?;

        op.read(handle)
            .await
            .map(|data| data.to_vec())
            .map_err(|e| {
                if is_not_found(&e) {
                    DomainError::NotFound(format!("AI document source {handle}"))
                } else {
                    map_storage_error(handle, e)
                }
            })
    }
}

#[async_trait]
impl AiDocumentStore for OpenDalAiPayloadStorage {
    async fn put_source(
        &self,
        job_id: AiImportJobId,
        payload: Vec<u8>,
    ) -> Result<String, DomainError> {
        let key = Self::source_key(job_id);
        let op = self.operator().await?;

        op.write(&key, payload)
            .await
            .map_err(|e| map_storage_error(&key, e))?;

        debug!(job_id = %job_id.as_uuid(), key = %key, "Stored AI source document");
        Ok(key)
    }

    async fn get_source(&self, handle: &str) -> Result<Option<Vec<u8>>, DomainError> {
        let op = self.operator().await?;

        match op.read(handle).await {
            Ok(data) => Ok(Some(data.to_vec())),
            Err(e) if is_not_found(&e) => Ok(None),
            Err(e) => Err(map_storage_error(handle, e)),
        }
    }

    async fn delete_source(&self, handle: &str) -> Result<(), DomainError> {
        let op = self.operator().await?;

        match op.delete(handle).await {
            Ok(()) => {
                debug!(key = %handle, "Deleted AI source document");
                Ok(())
            }
            Err(e) if is_not_found(&e) => {
                // Missing handle is a no-op
                Ok(())
            }
            Err(e) => Err(map_storage_error(handle, e)),
        }
    }
}

/// Map an OpenDAL storage error to a domain error.
fn map_storage_error(key: &str, e: opendal::Error) -> DomainError {
    if e.is_temporary() {
        warn!(key = %key, error = %e, "Temporary AI payload storage error");
        DomainError::ServiceUnavailable(format!("AI payload storage temporarily unavailable: {e}"))
    } else {
        DomainError::ValidationError(format!("AI payload storage error for {key}: {e}"))
    }
}

/// Check if an OpenDAL error indicates a not-found condition.
///
/// OpenDAL 0.58+ maps S3 `NoSuchKey`/404 responses to `ErrorKind::NotFound`.
/// We rely exclusively on the kind classification to avoid false positives
/// from string matching unrelated error messages.
fn is_not_found(e: &opendal::Error) -> bool {
    e.kind() == opendal::ErrorKind::NotFound
}

/// Source document handle builder for the AI import queue.
pub fn source_handle_for_job(job_id: AiImportJobId) -> String {
    OpenDalAiPayloadStorage::source_key(job_id)
}

#[cfg(test)]
mod tests {
    use breakdown_core::ai::AiImportJobId;

    use super::{OpenDalAiPayloadStorage, source_handle_for_job};

    #[test]
    fn source_key_format() {
        let job_id = AiImportJobId::new();
        let key = OpenDalAiPayloadStorage::source_key(job_id);
        assert!(key.starts_with("ai-import/"));
        assert!(key.ends_with("/source"));
        assert!(key.contains(&job_id.as_uuid().to_string()));
    }

    #[test]
    fn preview_key_format() {
        let job_id = AiImportJobId::new();
        let key = OpenDalAiPayloadStorage::preview_key(job_id);
        assert!(key.starts_with("ai-import/"));
        assert!(key.ends_with("/preview"));
        assert!(key.contains(&job_id.as_uuid().to_string()));
    }

    #[test]
    fn source_handle_for_job_matches_source_key() {
        let job_id = AiImportJobId::new();
        let handle = source_handle_for_job(job_id);
        let expected = OpenDalAiPayloadStorage::source_key(job_id);
        assert_eq!(handle, expected);
    }
}
