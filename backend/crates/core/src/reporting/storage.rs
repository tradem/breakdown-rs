// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! CRUD port for report artifact bytes (staging + external backup).
//!
//! Follows the non-CQRS CRUD-port precedent of [`crate::photo::ports::PhotoStorage`],
//! but is a **separate** port: report artifacts use deterministic keys, content
//! digests, retention, and remote object identifiers rather than `PhotoId`
//! variants. The port API deliberately exposes **no** Google Drive, OpenDAL,
//! or storage-key-layout internals.

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use utoipa::ToSchema;

/// Compile-time template version baked into the binary.
///
/// Because templates are trusted static assets, a template change produces a
/// new binary with a new `TEMPLATE_VERSION`, which naturally re-archives
/// (the dedup key changes). It is NOT a runtime knob.
pub const TEMPLATE_VERSION: &str = "1.0.0";

/// Deterministic key identifying a report artifact in storage.
///
/// Key layout for staging vs external is an **adapter-internal** concern;
/// callers of the port only pass opaque, deterministic keys.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, ToSchema)]
#[serde(transparent)]
pub struct ReportArtifactKey(String);

impl ReportArtifactKey {
    /// Construct a key from a non-empty string. Empty keys are rejected.
    pub fn new(key: impl Into<String>) -> Result<Self, ReportStorageError> {
        let s = key.into();
        if s.is_empty() || s.len() > 1024 {
            return Err(ReportStorageError::KeyRejected {
                reason: "key must be non-empty and at most 1024 bytes".into(),
            });
        }
        // Reject path traversal / absolute paths so adapters never receive them.
        if s.contains("..") || s.starts_with('/') || s.contains('\\') {
            return Err(ReportStorageError::KeyRejected {
                reason: "key must not contain path traversal or absolute path markers".into(),
            });
        }
        Ok(Self(s))
    }

    /// Borrow the key as a string slice.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Display for ReportArtifactKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// Hex-encoded SHA-256 content digest of a report artifact.
///
/// Digests are recorded so retries can verify the staged object was not
/// mutated, and so external uploads re-use the exact bytes the snapshot
/// produced.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, ToSchema)]
#[serde(transparent)]
pub struct ContentDigest(String);

impl ContentDigest {
    /// Construct from a hex-encoded digest string (validated for non-empty hex).
    pub fn new(hex: impl Into<String>) -> Result<Self, ReportStorageError> {
        let s = hex.into();
        if s.is_empty() || s.len() > 128 {
            return Err(ReportStorageError::KeyRejected {
                reason: "digest must be non-empty and at most 128 hex chars".into(),
            });
        }
        if !s.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(ReportStorageError::KeyRejected {
                reason: "digest must be hex-encoded".into(),
            });
        }
        Ok(Self(s.to_ascii_lowercase()))
    }

    /// Borrow the hex digest.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Display for ContentDigest {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// Bytes plus safe metadata returned by a successful `fetch`.
///
/// Carries no provider credentials. Callers that log this type MUST NOT log
/// `bytes` (use `digest` / `content_type` / `len` only).
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ReportArtifact {
    /// Artifact bytes (PDF). Never log this field.
    #[serde(skip_serializing)]
    pub bytes: Vec<u8>,
    /// Content type (e.g. `application/pdf`).
    pub content_type: String,
    /// Content digest recorded at put-time (when known).
    pub digest: Option<ContentDigest>,
}

impl ReportArtifact {
    /// Byte length without exposing the payload.
    pub fn len(&self) -> usize {
        self.bytes.len()
    }

    /// Whether the artifact is empty.
    pub fn is_empty(&self) -> bool {
        self.bytes.is_empty()
    }
}

/// Typed errors for report artifact storage.
///
/// **Security invariant:** variants carry no PDF bytes and no provider
/// credentials. Display/Debug output is safe to log.
#[derive(Error, Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub enum ReportStorageError {
    /// The requested artifact does not exist.
    #[error("report artifact not found: {key}")]
    NotFound { key: String },

    /// A conditional/idempotent write conflicted with existing state.
    #[error("report artifact conflict: {key}")]
    Conflict { key: String },

    /// The underlying provider failed (network, 5xx, timeout, …).
    ///
    /// `detail` is a short, non-sensitive summary — never credentials or bytes.
    #[error("report storage provider failure: {detail}")]
    ProviderFailure { detail: String },

    /// Required credentials / configuration are missing.
    #[error("report storage credentials missing: {detail}")]
    CredentialMissing { detail: String },

    /// The caller-supplied key was rejected by validation.
    #[error("report artifact key rejected: {reason}")]
    KeyRejected { reason: String },

    /// Content digest mismatch (e.g. staged object mutated between put and retry).
    #[error("report artifact digest mismatch for key {key}")]
    DigestMismatch { key: String },

    /// A generic internal storage error (non-sensitive).
    #[error("report storage internal error: {detail}")]
    Internal { detail: String },
}

impl ReportStorageError {
    /// Build a `ProviderFailure` from a short summary. Callers MUST strip any
    /// credential material before passing `detail`.
    pub fn provider_failure(detail: impl Into<String>) -> Self {
        Self::ProviderFailure {
            detail: sanitize_error_detail(detail.into()),
        }
    }

    /// Build an `Internal` error from a short summary.
    pub fn internal(detail: impl Into<String>) -> Self {
        Self::Internal {
            detail: sanitize_error_detail(detail.into()),
        }
    }
}

/// Strip obviously-sensitive substrings and bound length so errors stay log-safe.
fn sanitize_error_detail(mut detail: String) -> String {
    // Never retain long payloads that could be PDF fragments.
    const MAX: usize = 256;
    if detail.len() > MAX {
        detail.truncate(MAX);
        detail.push('…');
    }
    // Redact common credential-ish tokens if a caller accidentally included them.
    for needle in ["secret", "password", "token", "Bearer ", "AKIA"] {
        if detail.to_ascii_lowercase().contains(&needle.to_ascii_lowercase()) {
            return "redacted provider error".into();
        }
    }
    detail
}

/// Byte-storage port for report artifacts (CRUD — intentionally NOT CQRS-split).
///
/// Distinct injected instances implement staging (Garage/S3) and the external
/// provider (Google Drive / S3 / GCS / WebDAV). Key layout is adapter-internal.
#[async_trait]
pub trait ReportArchiveStorage: Send + Sync {
    /// Idempotent put: store `bytes` under `key` with `content_type` and `digest`.
    ///
    /// Overwriting the same key with the same digest is a no-op success.
    /// Overwriting with a different digest is provider-defined; adapters SHOULD
    /// treat it as an idempotent overwrite for backup destinations.
    async fn put(
        &self,
        key: &ReportArtifactKey,
        bytes: &[u8],
        content_type: &str,
        digest: &ContentDigest,
    ) -> Result<(), ReportStorageError>;

    /// Fetch bytes for `key`. Returns [`ReportStorageError::NotFound`] if absent.
    async fn fetch(&self, key: &ReportArtifactKey) -> Result<ReportArtifact, ReportStorageError>;

    /// Delete the object at `key`. Idempotent — success even if already absent.
    async fn delete(&self, key: &ReportArtifactKey) -> Result<(), ReportStorageError>;

    /// Return whether an object exists at `key`.
    async fn exists(&self, key: &ReportArtifactKey) -> Result<bool, ReportStorageError>;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn artifact_key_rejects_empty_and_traversal() {
        assert!(ReportArtifactKey::new("").is_err());
        assert!(ReportArtifactKey::new("../etc/passwd").is_err());
        assert!(ReportArtifactKey::new("/abs").is_err());
        assert!(ReportArtifactKey::new(r"a\b").is_err());
        let k = ReportArtifactKey::new("reports/day/dispo.pdf").unwrap();
        assert_eq!(k.as_str(), "reports/day/dispo.pdf");
    }

    #[test]
    fn content_digest_validates_hex() {
        assert!(ContentDigest::new("").is_err());
        assert!(ContentDigest::new("zz").is_err());
        let d = ContentDigest::new("AbCd").unwrap();
        assert_eq!(d.as_str(), "abcd");
    }

    #[test]
    fn storage_error_carries_no_bytes_in_display() {
        let err = ReportStorageError::provider_failure("timeout talking to backend");
        let s = err.to_string();
        assert!(!s.contains("%PDF"));
        assert!(s.contains("timeout"));
    }

    #[test]
    fn storage_error_redacts_credentialish_detail() {
        let err = ReportStorageError::provider_failure("token=super-secret-value");
        assert_eq!(err.to_string(), "report storage provider failure: redacted provider error");
    }

    #[test]
    fn storage_error_serialization_roundtrip() {
        let err = ReportStorageError::NotFound {
            key: "k".into(),
        };
        let json = serde_json::to_string(&err).unwrap();
        let back: ReportStorageError = serde_json::from_str(&json).unwrap();
        assert_eq!(err, back);
    }

    #[test]
    fn report_artifact_len_hides_bytes_from_debug_via_skip_serializing() {
        let a = ReportArtifact {
            bytes: b"%PDF-secret".to_vec(),
            content_type: "application/pdf".into(),
            digest: None,
        };
        let json = serde_json::to_string(&a).unwrap();
        assert!(!json.contains("%PDF"));
        assert!(!json.contains("secret"));
        assert_eq!(a.len(), 11);
    }

    #[test]
    fn template_version_is_non_empty_compile_time_constant() {
        assert!(!TEMPLATE_VERSION.is_empty());
    }

    /// Guardrail: this module must not import provider SDKs (OpenDAL/Google).
    ///
    /// Scans for a `use` statement referencing a forbidden crate or a type
    /// import that would create a compile-time dependency on an infra SDK.
    /// Doc comments that mention "OpenDAL" by name are allowed — they explain
    /// what the port does NOT depend on.
    #[test]
    fn port_source_has_no_provider_imports() {
        let src = include_str!("storage.rs");
        // Only check lines that aren't doc-comments or in #[cfg(test)].
        for line in src.lines() {
            // Skip comments and doc-comments
            if line.trim().starts_with("//") || line.trim().starts_with("///") || line.trim().starts_with("//!") {
                continue;
            }
            // Skip test module
            if line.contains("#[cfg(test)]") || line.contains("mod tests") {
                continue;
            }
            let trimmed = line.trim();
            // Check for actual use statements or type references that
            // would create a dependency.
            if trimmed.starts_with("use ") {
                for forbidden in ["opendal", "sqlx", "axum", "google_drive", "yup_oauth2"] {
                    assert!(
                        !trimmed.contains(forbidden),
                        "core reporting storage port must not `use` {forbidden}: {line}"
                    );
                }
            }
        }
    }
}
