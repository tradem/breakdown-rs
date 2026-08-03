// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: gpt-5.6-luna (opencode-go)

use std::fmt;
use std::sync::Arc;

use async_trait::async_trait;
use breakdown_core::error::DomainError;
use breakdown_core::photo::ports::PhotoStorage;
use breakdown_core::photo::views::PhotoBytes;
use breakdown_core::shared::{PhotoId, PhotoVariant};
use chrono::{DateTime, Utc};
use futures::StreamExt;
use opendal::Operator;
use tokio::sync::Mutex;
use tracing::warn;
use zeroize::Zeroizing;

/// Resolves the SSE-C customer key for photo storage on demand.
///
/// Resolution is deliberately retried on every call: a failed resolution is
/// never cached, so the adapter recovers automatically once the key source
/// (Vault) becomes reachable again — no API restart required.
#[async_trait]
pub trait PhotoStorageKeySource: Send + Sync + fmt::Debug {
    async fn resolve(&self) -> Result<Zeroizing<Vec<u8>>, DomainError>;
}

/// Key source used by the fail-closed `unavailable` adapter and as a
/// never-reached placeholder for pre-configured (test) operators.
#[derive(Debug)]
struct NoKeySource;

#[async_trait]
impl PhotoStorageKeySource for NoKeySource {
    async fn resolve(&self) -> Result<Zeroizing<Vec<u8>>, DomainError> {
        Err(DomainError::ServiceUnavailable(
            "photo storage is not configured with a key source".to_owned(),
        ))
    }
}

/// Shared lazy state: caches the SSE-C operator and re-resolves the key on
/// demand, so a Vault outage at boot does not permanently disable storage.
struct RecoverableInner {
    /// Cached SSE-C operator; `None` until the first successful key
    /// resolution. A failed resolution is never cached.
    op: Mutex<Option<Operator>>,
    key_source: Arc<dyn PhotoStorageKeySource>,
}

/// OpenDAL-backed photo storage adapter configured against an S3-compatible
/// backend (Garage).
///
/// Key layout (adapter-internal, never exposed via the port):
/// `{photo_id}/{variant}` — flat prefix-less key space.
#[derive(Clone)]
pub struct OpenDalPhotoStorage {
    inner: Arc<RecoverableInner>,
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
            .field("configured", &self.is_configured())
            .finish_non_exhaustive()
    }
}

impl OpenDalPhotoStorage {
    /// Build a new storage adapter from an already-configured OpenDAL operator.
    ///
    /// This constructor is available only to the integration-test feature. The
    /// operator MUST be configured with the S3 service, a valid bucket, access
    /// key, secret key, and the matching SSE-C customer key.
    #[cfg(feature = "test-support")]
    pub fn new(op: Operator) -> Self {
        Self {
            inner: Arc::new(RecoverableInner {
                op: Mutex::new(Some(op)),
                key_source: Arc::new(NoKeySource),
            }),
            bucket: None,
            unavailable_reason: None,
        }
    }

    /// Build a new storage adapter with an explicit bucket name.
    #[cfg(feature = "test-support")]
    pub fn with_bucket(op: Operator, bucket: String) -> Self {
        Self {
            inner: Arc::new(RecoverableInner {
                op: Mutex::new(Some(op)),
                key_source: Arc::new(NoKeySource),
            }),
            bucket: Some(bucket),
            unavailable_reason: None,
        }
    }

    /// Construct an adapter that fails closed until the next successful boot.
    pub fn unavailable(reason: impl Into<String>) -> Self {
        Self {
            inner: Arc::new(RecoverableInner {
                op: Mutex::new(None),
                key_source: Arc::new(NoKeySource),
            }),
            bucket: None,
            unavailable_reason: Some(reason.into()),
        }
    }

    /// Construct a recoverable adapter that resolves the SSE-C customer key
    /// lazily via `key_source` on first use and re-resolves it on demand
    /// after a failure. A Vault outage at boot therefore disables photo
    /// operations (fail-closed, HTTP 503) only until Vault becomes reachable
    /// again — no API restart required.
    pub fn recoverable(key_source: Arc<dyn PhotoStorageKeySource>) -> Self {
        Self {
            inner: Arc::new(RecoverableInner {
                op: Mutex::new(None),
                key_source,
            }),
            bucket: None,
            unavailable_reason: None,
        }
    }

    /// Whether an SSE-C operator has been successfully constructed and cached.
    fn is_configured(&self) -> bool {
        self.inner
            .op
            .try_lock()
            .map(|guard| guard.is_some())
            .unwrap_or(false)
    }

    /// Return the cached SSE-C operator, or resolve the customer key and
    /// construct one on demand. Resolution failures are **not** cached, so
    /// the next call retries automatically once the key source recovers.
    async fn operator(&self) -> Result<Operator, DomainError> {
        if let Some(op) = self.inner.op.lock().await.as_ref() {
            return Ok(op.clone());
        }

        let key = self.inner.key_source.resolve().await.map_err(|e| {
            // Prefer the boot-time fail-closed reason when present.
            match &self.unavailable_reason {
                Some(reason) => DomainError::ServiceUnavailable(reason.clone()),
                None => e,
            }
        })?;
        let op = Self::build_operator(key.as_slice())?;

        let mut guard = self.inner.op.lock().await;
        if let Some(existing) = guard.as_ref() {
            // Another caller won the resolution race; reuse its operator.
            return Ok(existing.clone());
        }
        *guard = Some(op.clone());
        Ok(op)
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
        let op = Self::build_operator(customer_key)?;
        let bucket = std::env::var("S3_BUCKET").unwrap_or_else(|_| "costume-photos".into());
        Ok(Self {
            inner: Arc::new(RecoverableInner {
                op: Mutex::new(Some(op)),
                key_source: Arc::new(NoKeySource),
            }),
            bucket: Some(bucket),
            unavailable_reason: None,
        })
    }

    /// Build the SSE-C OpenDAL operator from environment variables and a
    /// customer key. Fail-closed by construction: this is the only path that
    /// ever creates a photo operator, and it always sets the AES256 SSE-C
    /// customer key — never plaintext or SSE-S3.
    fn build_operator(customer_key: &[u8]) -> Result<Operator, DomainError> {
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
            customer_key,
        )
        .map_err(|e| DomainError::ValidationError(format!("Failed to configure S3: {e}")))?;

        let op = Operator::new(builder)
            .map_err(|e| {
                DomainError::ValidationError(format!("Failed to create S3 operator: {e}"))
            })?
            .finish();
        Ok(op)
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
        match self.operator().await?.stat(&key).await {
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
        self.operator()
            .await?
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
        let op = self.operator().await?;
        let meta = op.stat(&key).await.map_err(|e| {
            if e.to_string().contains("Not Found") || e.to_string().contains("ObjectNotExist") {
                DomainError::NotFound(format!("Photo {id:?} variant {variant:?}"))
            } else {
                DomainError::ValidationError(format!("Failed to stat object {key}: {e}"))
            }
        })?;
        let buf = op.read(&key).await.map_err(|e| {
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
        let op = self.operator().await?;
        // Delete all three variants individually.
        for variant in &[
            PhotoVariant::Original,
            PhotoVariant::Thumb,
            PhotoVariant::Medium,
        ] {
            let key = Self::object_key(id, *variant);
            let _ = op.delete(&key).await; // Ignore errors for already-absent keys
        }
        Ok(())
    }

    async fn list(&self) -> Result<Vec<PhotoId>, DomainError> {
        let mut photo_ids = Vec::new();
        let mut lister = self
            .operator()
            .await?
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

#[cfg(test)]
mod tests {
    use super::{OpenDalPhotoStorage, PhotoStorageKeySource};
    use breakdown_core::error::DomainError;
    use breakdown_core::photo::ports::PhotoStorage;
    use breakdown_core::shared::{PhotoId, PhotoVariant};
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use tokio::sync::Mutex;
    use zeroize::Zeroizing;

    /// Serializes tests that mutate the process-global `S3_*` env vars.
    static ENV_LOCK: Mutex<()> = Mutex::const_new(());

    /// Fake key source: fails with `ServiceUnavailable` for the first
    /// `failures` calls, then returns a fixed 32-byte SSE-C key.
    #[derive(Debug)]
    struct FlakyKeySource {
        failures: usize,
        calls: AtomicUsize,
    }

    #[async_trait::async_trait]
    impl PhotoStorageKeySource for FlakyKeySource {
        async fn resolve(&self) -> Result<Zeroizing<Vec<u8>>, DomainError> {
            let call = self.calls.fetch_add(1, Ordering::SeqCst);
            if call < self.failures {
                Err(DomainError::ServiceUnavailable("vault down".into()))
            } else {
                Ok(Zeroizing::new(vec![0x42; 32]))
            }
        }
    }

    #[tokio::test]
    #[allow(unsafe_code)] // test-only env seeding for the recovery test
    async fn storage_recovers_after_key_source_becomes_available() {
        let _guard = ENV_LOCK.lock().await;
        // SAFETY: process-global env is only touched inside this test, and
        // ENV_LOCK serializes it against the other env-mutating test.
        unsafe {
            std::env::set_var("S3_ENDPOINT", "http://127.0.0.1:9");
            std::env::set_var("S3_ACCESS_KEY", "test-key");
            std::env::set_var("S3_SECRET_KEY", "test-secret");
            std::env::set_var("S3_BUCKET", "test-bucket");
        }

        let key_source = Arc::new(FlakyKeySource {
            failures: 2,
            calls: AtomicUsize::new(0),
        });
        let storage = OpenDalPhotoStorage::recoverable(key_source.clone());
        let id = PhotoId::new();

        // Fail closed (503) while the key source is unavailable. The operator
        // is never constructed, so no storage op succeeds.
        let err = storage
            .store(
                id,
                PhotoVariant::Original,
                b"x".to_vec(),
                "image/jpeg".into(),
            )
            .await
            .unwrap_err();
        assert!(matches!(err, DomainError::ServiceUnavailable(_)));
        assert!(!storage.is_configured());

        let err = storage
            .store(
                id,
                PhotoVariant::Original,
                b"x".to_vec(),
                "image/jpeg".into(),
            )
            .await
            .unwrap_err();
        assert!(matches!(err, DomainError::ServiceUnavailable(_)));

        // The key source recovers: the SSE-C operator is now built (S3
        // connects lazily, so the build itself succeeds) and cached. The op
        // fails at the network layer (unroutable endpoint), not at key
        // resolution — the Vault outage no longer blocks storage.
        let err = storage
            .store(
                id,
                PhotoVariant::Original,
                b"x".to_vec(),
                "image/jpeg".into(),
            )
            .await
            .unwrap_err();
        assert!(
            !matches!(err, DomainError::ServiceUnavailable(_)),
            "key resolution must have recovered"
        );
        assert!(storage.is_configured(), "operator cached after recovery");

        // The cached operator is reused: exactly 2 failed + 1 successful
        // resolution happened, and no further key resolution is attempted.
        assert_eq!(key_source.calls.load(Ordering::SeqCst), 3);
    }

    #[tokio::test]
    async fn unavailable_storage_fails_closed_without_key_source() {
        let storage = OpenDalPhotoStorage::unavailable("vault unreachable");
        let err = storage
            .store(
                PhotoId::new(),
                PhotoVariant::Original,
                b"x".to_vec(),
                "image/jpeg".into(),
            )
            .await
            .unwrap_err();
        assert!(matches!(err, DomainError::ServiceUnavailable(_)));
        assert!(!storage.is_configured());
    }
}
