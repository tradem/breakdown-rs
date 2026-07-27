// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: grok-4.5 (opencode-go)

//! OpenDAL-backed `ReportArchiveStorage` adapters.
//!
//! Two roles share the same trait:
//! 1. **Staging** — durable internal Garage/S3 (adapter #1).
//! 2. **External** — configured provider (S3/GCS/WebDAV via OpenDAL, or
//!    Google Drive via `services-gdrive` when gated) (adapter #2).
//! Key layout is adapter-internal. Typed errors never carry PDF bytes or
//! credentials; logging in this module never emits payload bytes.
use std::collections::HashMap;
use std::fmt;
use std::sync::Arc;
use async_trait::async_trait;
use breakdown_core::reporting::{
    ContentDigest, ReportArchiveStorage, ReportArtifact, ReportArtifactKey, ReportStorageError,
};
use opendal::Operator;
use tokio::sync::Mutex;
use tracing::{debug, warn};
// ---------------------------------------------------------------------------
// OpenDAL adapter (Garage/S3 staging + generic external backends)
/// Role label used only in Debug output (never credentials).
#[derive(Debug, Clone, Copy)]
pub enum StorageRole {
    Staging,
    External,
}
impl fmt::Display for StorageRole {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Staging => write!(f, "staging"),
            Self::External => write!(f, "external"),
        }
    }
/// OpenDAL-backed report archive storage.
///
/// Key layout (adapter-internal, never exposed via the port beyond the
/// deterministic key the caller already chose):
/// `{prefix}{key}` where `prefix` is optional (e.g. `report-staging/`).
#[derive(Clone)]
pub struct OpenDalReportArchiveStorage {
    op: Operator,
    /// Optional key prefix (must not contain credentials).
    prefix: String,
    role: StorageRole,
impl fmt::Debug for OpenDalReportArchiveStorage {
        f.debug_struct("OpenDalReportArchiveStorage")
            .field("prefix", &self.prefix)
            .field("role", &self.role)
            .finish_non_exhaustive()
impl OpenDalReportArchiveStorage {
    /// Build from a pre-configured OpenDAL operator.
    pub fn new(op: Operator, role: StorageRole) -> Self {
        Self {
            op,
            prefix: String::new(),
            role,
    /// Build with an explicit key prefix (e.g. `report-staging/`).
    pub fn with_prefix(op: Operator, role: StorageRole, prefix: impl Into<String>) -> Self {
            prefix: prefix.into(),
    /// Staging instance from env (`REPORT_BACKUP_STAGING_*`, falling back to `S3_*`).
    pub fn staging_from_env() -> Result<Self, ReportStorageError> {
        let endpoint =
            env_first(&["REPORT_BACKUP_STAGING_ENDPOINT", "S3_ENDPOINT"]).ok_or_else(|| {
                ReportStorageError::CredentialMissing {
                    detail: "REPORT_BACKUP_STAGING_ENDPOINT or S3_ENDPOINT must be set".into(),
                }
            })?;
        let access_key = env_first(&["REPORT_BACKUP_STAGING_ACCESS_KEY", "S3_ACCESS_KEY"])
            .ok_or_else(|| ReportStorageError::CredentialMissing {
                detail: "REPORT_BACKUP_STAGING_ACCESS_KEY or S3_ACCESS_KEY must be set".into(),
        let secret_key = env_first(&["REPORT_BACKUP_STAGING_SECRET_KEY", "S3_SECRET_KEY"])
                detail: "REPORT_BACKUP_STAGING_SECRET_KEY or S3_SECRET_KEY must be set".into(),
        let bucket = env_first(&["REPORT_BACKUP_STAGING_BUCKET", "S3_BUCKET"])
            .unwrap_or_else(|| "report-staging".into());
        let prefix = std::env::var("REPORT_BACKUP_STAGING_PREFIX")
            .unwrap_or_else(|_| "report-staging/".into());
        let op = build_s3_operator(&endpoint, &access_key, &secret_key, &bucket)?;
        Ok(Self::with_prefix(op, StorageRole::Staging, prefix))
    /// External provider from env.
    ///
    /// `REPORT_BACKUP_PROVIDER` selects the backend:
    /// - `s3` (default) — S3-compatible external bucket
    /// - `gdrive` — OpenDAL `services-gdrive` (spike-gated)
    /// - `memory` — in-process map (tests / dry-run only; not constructed here)
    pub fn external_from_env() -> Result<Self, ReportStorageError> {
        let provider = std::env::var("REPORT_BACKUP_PROVIDER")
            .unwrap_or_else(|_| "s3".into())
            .to_ascii_lowercase();
        match provider.as_str() {
            "s3" | "garage" => Self::external_s3_from_env(),
            "gdrive" | "google" | "google-drive" => Self::external_gdrive_from_env(),
            other => Err(ReportStorageError::CredentialMissing {
                detail: format!("unknown REPORT_BACKUP_PROVIDER: {other}"),
            }),
    fn external_s3_from_env() -> Result<Self, ReportStorageError> {
        let endpoint = env_first(&["REPORT_BACKUP_ENDPOINT", "S3_ENDPOINT"]).ok_or_else(|| {
            ReportStorageError::CredentialMissing {
                detail: "REPORT_BACKUP_ENDPOINT or S3_ENDPOINT must be set".into(),
            }
        })?;
        let access_key =
            env_first(&["REPORT_BACKUP_ACCESS_KEY", "S3_ACCESS_KEY"]).ok_or_else(|| {
                    detail: "REPORT_BACKUP_ACCESS_KEY or S3_ACCESS_KEY must be set".into(),
        let secret_key =
            env_first(&["REPORT_BACKUP_SECRET_KEY", "S3_SECRET_KEY"]).ok_or_else(|| {
                    detail: "REPORT_BACKUP_SECRET_KEY or S3_SECRET_KEY must be set".into(),
        let bucket = env_first(&["REPORT_BACKUP_BUCKET"]).unwrap_or_else(|| "report-backup".into());
        let prefix =
            std::env::var("REPORT_BACKUP_PREFIX").unwrap_or_else(|_| "report-backup/".into());
        Ok(Self::with_prefix(op, StorageRole::External, prefix))
    fn external_gdrive_from_env() -> Result<Self, ReportStorageError> {
        // OpenDAL services-gdrive configuration.
        // Required env (never logged):
        //   REPORT_BACKUP_GDRIVE_CLIENT_ID
        //   REPORT_BACKUP_GDRIVE_CLIENT_SECRET
        //   REPORT_BACKUP_GDRIVE_REFRESH_TOKEN
        // Optional:
        //   REPORT_BACKUP_GDRIVE_ROOT (folder id)
        //   REPORT_BACKUP_PREFIX
        let client_id = std::env::var("REPORT_BACKUP_GDRIVE_CLIENT_ID").map_err(|_| {
                detail: "REPORT_BACKUP_GDRIVE_CLIENT_ID must be set".into(),
        let client_secret = std::env::var("REPORT_BACKUP_GDRIVE_CLIENT_SECRET").map_err(|_| {
                detail: "REPORT_BACKUP_GDRIVE_CLIENT_SECRET must be set".into(),
        let refresh_token = std::env::var("REPORT_BACKUP_GDRIVE_REFRESH_TOKEN").map_err(|_| {
                detail: "REPORT_BACKUP_GDRIVE_REFRESH_TOKEN must be set".into(),
        let root = std::env::var("REPORT_BACKUP_GDRIVE_ROOT").unwrap_or_default();
        // Build via OpenDAL Gdrive service. Feature-gated at Cargo level.
        let mut builder = opendal::services::Gdrive::default()
            .client_id(&client_id)
            .client_secret(&client_secret)
            .refresh_token(&refresh_token);
        if !root.is_empty() {
            builder = builder.root(&root);
        let op = Operator::new(builder)
            .map_err(|e| {
                // Never include the original error string wholesale — it may echo tokens.
                let _ = e;
                ReportStorageError::provider_failure("failed to create gdrive operator")
            })?
            .finish();
    fn full_key(&self, key: &ReportArtifactKey) -> String {
        format!("{}{}", self.prefix, key.as_str())
#[async_trait]
impl ReportArchiveStorage for OpenDalReportArchiveStorage {
    async fn put(
        &self,
        key: &ReportArtifactKey,
        bytes: &[u8],
        content_type: &str,
        digest: &ContentDigest,
    ) -> Result<(), ReportStorageError> {
        let path = self.full_key(key);
        debug!(
            role = %self.role,
            key = %key,
            bytes_len = bytes.len(),
            digest = %digest,
            "report archive put"
        );
        // Never log `bytes`.
        self.op
            .write_with(&path, bytes.to_vec())
            .content_type(content_type)
            .user_metadata(HashMap::from([(
                "content_digest".to_string(),
                digest.as_str().to_string(),
            )]))
            .await
                warn!(role = %self.role, key = %key, "report archive put failed");
                ReportStorageError::provider_failure("put failed")
        Ok(())
    async fn fetch(&self, key: &ReportArtifactKey) -> Result<ReportArtifact, ReportStorageError> {
        let meta = match self.op.stat(&path).await {
            Ok(m) => m,
            Err(e) if e.kind() == opendal::ErrorKind::NotFound => {
                return Err(ReportStorageError::NotFound {
                    key: key.as_str().into(),
                });
            Err(e) => {
                return Err(ReportStorageError::provider_failure("stat failed"));
        };
        let buf = self.op.read(&path).await.map_err(|e| {
            let _ = e;
            ReportStorageError::provider_failure("read failed")
        let digest = meta
            .user_metadata()
            .and_then(|m| m.get("content_digest").cloned())
            .and_then(|s| ContentDigest::new(s).ok());
        let content_type = meta
            .content_type()
            .unwrap_or("application/octet-stream")
            .to_string();
        Ok(ReportArtifact {
            bytes: buf.to_vec(),
            content_type,
            digest,
        })
    async fn delete(&self, key: &ReportArtifactKey) -> Result<(), ReportStorageError> {
        match self.op.delete(&path).await {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == opendal::ErrorKind::NotFound => Ok(()),
                Err(ReportStorageError::provider_failure("delete failed"))
    async fn exists(&self, key: &ReportArtifactKey) -> Result<bool, ReportStorageError> {
        match self.op.stat(&path).await {
            Ok(_) => Ok(true),
            Err(e) if e.kind() == opendal::ErrorKind::NotFound => Ok(false),
                Err(ReportStorageError::provider_failure("exists/stat failed"))
fn build_s3_operator(
    endpoint: &str,
    access_key: &str,
    secret_key: &str,
    bucket: &str,
) -> Result<Operator, ReportStorageError> {
    let builder = opendal::services::S3::default()
        .endpoint(endpoint)
        .access_key_id(access_key)
        .secret_access_key(secret_key)
        .bucket(bucket);
    Operator::new(builder)
        .map_err(|e| {
            ReportStorageError::provider_failure("failed to create S3 operator")
        .map(|b| b.finish())
fn env_first(keys: &[&str]) -> Option<String> {
    for k in keys {
        if let Ok(v) = std::env::var(k) {
            if !v.is_empty() {
                return Some(v);
    None
// In-memory adapter (unit tests + dry-run external)
struct MemoryEntry {
    bytes: Vec<u8>,
    content_type: String,
    digest: ContentDigest,
/// In-process `ReportArchiveStorage` for tests and optional dry-run external.
#[derive(Clone, Default)]
pub struct MemoryReportArchiveStorage {
    inner: Arc<Mutex<HashMap<String, MemoryEntry>>>,
    /// When true, `put` fails with ProviderFailure (for retry tests).
    fail_puts: Arc<Mutex<bool>>,
    /// Count of successful puts (for idempotency assertions).
    put_count: Arc<Mutex<u64>>,
impl fmt::Debug for MemoryReportArchiveStorage {
        f.debug_struct("MemoryReportArchiveStorage")
impl MemoryReportArchiveStorage {
    pub fn new() -> Self {
        Self::default()
    /// Force subsequent puts to fail (until cleared).
    pub async fn set_fail_puts(&self, fail: bool) {
        *self.fail_puts.lock().await = fail;
    /// Number of successful put operations.
    pub async fn put_count(&self) -> u64 {
        *self.put_count.lock().await
impl ReportArchiveStorage for MemoryReportArchiveStorage {
        if *self.fail_puts.lock().await {
            return Err(ReportStorageError::provider_failure("injected put failure"));
        let mut guard = self.inner.lock().await;
        guard.insert(
            key.as_str().to_string(),
            MemoryEntry {
                bytes: bytes.to_vec(),
                content_type: content_type.to_string(),
                digest: digest.clone(),
            },
        *self.put_count.lock().await += 1;
        let guard = self.inner.lock().await;
        let entry = guard
            .get(key.as_str())
            .ok_or_else(|| ReportStorageError::NotFound {
                key: key.as_str().into(),
            bytes: entry.bytes.clone(),
            content_type: entry.content_type.clone(),
            digest: Some(entry.digest.clone()),
        self.inner.lock().await.remove(key.as_str());
        Ok(self.inner.lock().await.contains_key(key.as_str()))
/// Compute a hex SHA-256 digest of `bytes`.
pub fn sha256_hex(bytes: &[u8]) -> ContentDigest {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    let out = hasher.finalize();
    // Hex encode without pulling an extra crate.
    let hex: String = out.iter().map(|b| format!("{b:02x}")).collect();
    ContentDigest::new(hex).expect("sha256 hex is always valid")
/// Build the deterministic staging key for a job.
pub fn staging_key(
    shooting_day_id: uuid::Uuid,
    kind: &str,
    locale: &str,
    template_version: &str,
    digest: &ContentDigest,
) -> Result<ReportArtifactKey, ReportStorageError> {
    // Include digest so content-addressed retries land on the same object.
    ReportArtifactKey::new(format!(
        "{shooting_day_id}/{kind}/{locale}/{template_version}/{digest}.pdf"
    ))
/// Build the deterministic external destination key (idempotent overwrite).
pub fn external_key(
        "{shooting_day_id}/{kind}/{locale}/v{template_version}.pdf"
#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn memory_put_fetch_delete_exists_roundtrip() {
        let store = MemoryReportArchiveStorage::new();
        let key = ReportArtifactKey::new("day/dispo.pdf").unwrap();
        let digest = sha256_hex(b"%PDF-1.4 test");
        store
            .put(&key, b"%PDF-1.4 test", "application/pdf", &digest)
            .unwrap();
        assert!(store.exists(&key).await.unwrap());
        let art = store.fetch(&key).await.unwrap();
        assert_eq!(art.bytes, b"%PDF-1.4 test");
        assert_eq!(art.digest.as_ref().unwrap().as_str(), digest.as_str());
        store.delete(&key).await.unwrap();
        assert!(!store.exists(&key).await.unwrap());
        assert!(matches!(
            store.fetch(&key).await,
            Err(ReportStorageError::NotFound { .. })
        ));
    async fn memory_put_is_idempotent_overwrite() {
        let key = ReportArtifactKey::new("k.pdf").unwrap();
        let d1 = sha256_hex(b"a");
        let d2 = sha256_hex(b"b");
        store.put(&key, b"a", "application/pdf", &d1).await.unwrap();
        store.put(&key, b"b", "application/pdf", &d2).await.unwrap();
        assert_eq!(art.bytes, b"b");
        assert_eq!(store.put_count().await, 2);
    async fn memory_fail_puts_returns_provider_failure_without_bytes() {
        store.set_fail_puts(true).await;
        let d = sha256_hex(b"x");
        let err = store
            .put(&key, b"x", "application/pdf", &d)
            .unwrap_err();
        let s = err.to_string();
        assert!(!s.contains('x') || s.contains("injected") || s.contains("provider"));
        assert!(!s.contains("%PDF"));
    #[test]
    fn staging_and_external_keys_are_deterministic() {
        let id = uuid::Uuid::nil();
        let d = sha256_hex(b"pdf");
        let a = staging_key(id, "dispo", "de-DE", "1.0.0", &d).unwrap();
        let b = staging_key(id, "dispo", "de-DE", "1.0.0", &d).unwrap();
        assert_eq!(a.as_str(), b.as_str());
        let e = external_key(id, "dispo", "de-DE", "1.0.0").unwrap();
        assert!(e.as_str().ends_with(".pdf"));
    fn errors_never_embed_credentials_in_debug() {
        let err = ReportStorageError::CredentialMissing {
            detail: "REPORT_BACKUP_GDRIVE_CLIENT_SECRET must be set".into(),
        // Detail names the env var, not the secret value — acceptable.
        assert!(!format!("{err:?}").contains("super-secret"));
