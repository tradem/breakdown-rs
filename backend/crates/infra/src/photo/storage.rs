// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: gpt-5.6-luna (opencode-go)

use std::fmt;

use breakdown_core::error::DomainError;
use breakdown_core::photo::ports::PhotoStorage;
use breakdown_core::photo::views::PhotoBytes;
use breakdown_core::shared::{PhotoId, PhotoVariant};
use chrono::{DateTime, Utc};
use futures::StreamExt;
use opendal::Operator;
use tracing::warn;

/// OpenDAL-backed photo storage adapter configured against an S3-compatible
/// backend (Garage).
///
/// Key layout (adapter-internal, never exposed via the port):
/// `{photo_id}/{variant}` — flat prefix-less key space.
#[derive(Clone)]
pub struct OpenDalPhotoStorage {
    /// OpenDAL operator (S3-compatible backend), absent when Vault was
    /// unavailable during API boot.
    op: Option<Operator>,
    /// Optional bucket override; when `None` the operator's configured bucket
    /// is used.
    bucket: Option<String>,
    /// Redacted reason for the fail-closed unavailable state.
    unavailable_reason: Option<String>,
}

impl fmt::Debug for OpenDalPhotoStorage {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("OpenDalPhotoStorage")
            .field("bucket", &self.bucket)
            .field("configured", &self.op.is_some())
            .finish_non_exhaustive()
    }
}

impl OpenDalPhotoStorage {
    /// Build a new storage adapter from an already-configured OpenDAL operator.
    ///
    /// The operator MUST be configured with the S3 service, a valid bucket,
    /// access key, secret key, and the matching SSE-C customer key. Production
    /// code uses `from_env_with_customer_key`; this constructor is a test seam
    /// for an already-configured operator.
    pub fn new(op: Operator) -> Self {
        Self {
            op: Some(op),
            bucket: None,
            unavailable_reason: None,
        }
    }

    /// Build a new storage adapter with an explicit bucket name.
    pub fn with_bucket(op: Operator, bucket: String) -> Self {
        Self {
            op: Some(op),
            bucket: Some(bucket),
            unavailable_reason: None,
        }
    }

    /// Construct an adapter that fails closed until the next successful boot.
    pub fn unavailable(reason: impl Into<String>) -> Self {
        Self {
            op: None,
            bucket: None,
            unavailable_reason: Some(reason.into()),
        }
    }

    /// Build from environment variables and a Vault-derived SSE-C key:
    /// - `S3_ENDPOINT` — Garage S3 API endpoint (e.g. `http://garage:3900`,
    ///   or `https://caddy:9443` with the Caddy TLS front, ADR-024)
    /// - `S3_ACCESS_KEY` — Garage access key
    /// - `S3_SECRET_KEY` — Garage secret key
    /// - `S3_BUCKET` — bucket name (default: `costume-photos`)
    /// - `S3_TLS_ROOT_CERT` — optional PEM path of the pinned root CA (the
    ///   internal step-ca root, ADR-024) for `https://` endpoints
    pub fn from_env_with_customer_key(customer_key: &[u8]) -> Result<Self, DomainError> {
        if customer_key.len() != 32 {
            return Err(DomainError::ValidationError(
                "photo SSE-C key must be exactly 32 bytes".into(),
            ));
        }
        let endpoint = std::env::var("S3_ENDPOINT")
            .map_err(|_| DomainError::ValidationError("S3_ENDPOINT must be set".into()))?;
        let access_key = std::env::var("S3_ACCESS_KEY")
            .map_err(|_| DomainError::ValidationError("S3_ACCESS_KEY must be set".into()))?;
        let secret_key = std::env::var("S3_SECRET_KEY")
            .map_err(|_| DomainError::ValidationError("S3_SECRET_KEY must be set".into()))?;
        let bucket = std::env::var("S3_BUCKET").unwrap_or_else(|_| "costume-photos".into());
        let root_cert = crate::tls::root_cert_from_env("S3_TLS_ROOT_CERT")
            .map_err(|e| DomainError::ValidationError(format!("Invalid S3_TLS_ROOT_CERT: {e}")))?;

        let builder = crate::tls::s3_builder_with_customer_key(
            &endpoint,
            &access_key,
            &secret_key,
            &bucket,
            root_cert.as_deref(),
            Some(customer_key),
        )
        .map_err(|e| DomainError::ValidationError(format!("Failed to configure S3: {e}")))?;

        let op = Operator::new(builder)
            .map_err(|e| {
                DomainError::ValidationError(format!("Failed to create S3 operator: {e}"))
            })?
            .finish();

        Ok(Self {
            op: Some(op),
            bucket: Some(bucket),
            unavailable_reason: None,
        })
    }

    fn operator(&self) -> Result<&Operator, DomainError> {
        self.op.as_ref().ok_or_else(|| {
            DomainError::ServiceUnavailable(
                self.unavailable_reason
                    .as_deref()
                    .unwrap_or("photo storage is unavailable")
                    .to_owned(),
            )
        })
    }

    /// Fetch the `stored_at` timestamp from user metadata for a given photo variant.
    ///
    /// Returns `Ok(None)` if the object doesn't exist or has no `stored_at` metadata
    /// (e.g. pre-existing objects stored before this feature was added).
    /// Logs a warning for existing objects without metadata.
    pub async fn fetch_stored_at(
        &self,
        id: PhotoId,
        variant: PhotoVariant,
    ) -> Result<Option<DateTime<Utc>>, DomainError> {
        let key = Self::object_key(id, variant);
        match self.operator()?.stat(&key).await {
            Ok(meta) => {
                if let Some(metadata_map) = meta.user_metadata() {
                    if let Some(stored_at_str) = metadata_map.get("stored_at") {
                        match DateTime::parse_from_rfc3339(stored_at_str) {
                            Ok(dt) => Ok(Some(dt.with_timezone(&Utc))),
                            Err(e) => {
                                warn!("Failed to parse stored_at metadata for {key}: {e}");
                                Ok(None)
                            }
                        }
                    } else {
                        warn!("No stored_at metadata on object {key}");
                        Ok(None)
                    }
                } else {
                    warn!("No user metadata on object {key}");
                    Ok(None)
                }
            }
            Err(e) => {
                if e.to_string().contains("Not Found") || e.to_string().contains("ObjectNotExist") {
                    Ok(None)
                } else {
                    Err(DomainError::ValidationError(format!(
                        "Failed to stat object {key}: {e}"
                    )))
                }
            }
        }
    }

    /// Build the internal storage key for a photo variant.
    fn object_key(id: PhotoId, variant: PhotoVariant) -> String {
        format!("{}/{}", id.0, variant.as_str())
    }
}

#[async_trait::async_trait]
impl PhotoStorage for OpenDalPhotoStorage {
    async fn store(
        &self,
        id: PhotoId,
        variant: PhotoVariant,
        bytes: Vec<u8>,
        content_type: String,
    ) -> Result<(), DomainError> {
        let key = Self::object_key(id, variant);
        self.operator()?
            .write_with(&key, bytes)
            .content_type(&content_type)
            .user_metadata([("stored_at".to_string(), Utc::now().to_rfc3339())])
            .await
            .map_err(|e| {
                DomainError::ValidationError(format!("Failed to store object {key}: {e}"))
            })?;
        Ok(())
    }

    async fn fetch(&self, id: PhotoId, variant: PhotoVariant) -> Result<PhotoBytes, DomainError> {
        let key = Self::object_key(id, variant);
        let meta = self.operator()?.stat(&key).await.map_err(|e| {
            if e.to_string().contains("Not Found") || e.to_string().contains("ObjectNotExist") {
                DomainError::NotFound(format!("Photo {id:?} variant {variant:?}"))
            } else {
                DomainError::ValidationError(format!("Failed to stat object {key}: {e}"))
            }
        })?;
        let buf = self.operator()?.read(&key).await.map_err(|e| {
            DomainError::ValidationError(format!("Failed to read object {key}: {e}"))
        })?;
        let content_type = meta
            .content_type()
            .unwrap_or("application/octet-stream")
            .to_string();
        let etag = meta.etag().map(|s| s.to_string());
        Ok(PhotoBytes {
            bytes: buf.to_vec(),
            content_type,
            size_bytes: meta.content_length() as u64,
            etag,
        })
    }

    async fn delete_all(&self, id: PhotoId) -> Result<(), DomainError> {
        // Delete all three variants individually.
        for variant in &[
            PhotoVariant::Original,
            PhotoVariant::Thumb,
            PhotoVariant::Medium,
        ] {
            let key = Self::object_key(id, *variant);
            let _ = self.operator()?.delete(&key).await; // Ignore errors for already-absent keys
        }
        Ok(())
    }

    async fn list(&self) -> Result<Vec<PhotoId>, DomainError> {
        let mut photo_ids = Vec::new();
        let mut lister = self
            .operator()?
            .lister_with("")
            .limit(1000)
            .await
            .map_err(|e| DomainError::ValidationError(format!("Failed to list objects: {e}")))?;

        while let Some(entry) = lister.next().await {
            let entry = match entry {
                Ok(e) => e,
                Err(e) => {
                    return Err(DomainError::ValidationError(format!(
                        "Failed to list object entry: {e}"
                    )));
                }
            };
            let path = entry.path();
            // Key format is "{photo_id}/{variant}". Extract the photo_id prefix.
            if let Some(id_str) = path.split('/').next()
                && let Ok(u) = uuid::Uuid::parse_str(id_str)
            {
                photo_ids.push(PhotoId::from_uuid(u));
            }
        }

        photo_ids.sort();
        photo_ids.dedup();
        Ok(photo_ids)
    }
}
