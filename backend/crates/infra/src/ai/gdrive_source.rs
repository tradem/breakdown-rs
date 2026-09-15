// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)

use std::sync::Arc;

use async_trait::async_trait;
use breakdown_core::error::DomainError;
use breakdown_core::settings::ports::{CredentialVault, VaultBinding};
use futures::TryStreamExt;
use opendal::Operator;
use uuid::Uuid;

use super::preview_store::AiDocumentSource;

/// Metadata for one externally stored fixture document. It contains no bytes
/// and is therefore safe to use for selection/logging.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GDriveDocument {
    pub handle: String,
    pub name: String,
}

/// Read-only GDrive source for AI import documents. Credentials are fetched
/// through the existing Vault binding and never stored on this struct.
#[derive(Clone)]
pub struct GDriveDocumentSource {
    operator: Arc<Operator>,
    max_document_bytes: u64,
}

impl GDriveDocumentSource {
    pub async fn from_vault(
        vault: &dyn CredentialVault,
        settings_id: Uuid,
        binding: &VaultBinding,
        max_document_bytes: u64,
    ) -> Result<Self, DomainError> {
        let bundle = vault
            .fetch_gdrive(settings_id, &binding.vault_key_id)
            .await?;
        let mut builder = opendal::services::Gdrive::default()
            .client_id(bundle.client_id())
            .client_secret(bundle.client_secret())
            .refresh_token(bundle.refresh_token());
        if let Some(root) = bundle.root_folder_id() {
            builder = builder.root(root);
        }
        let operator = Operator::new(builder).map_err(|error| {
            DomainError::service_unavailable(format!("GDrive adapter: {error}"))
        })?;
        Ok(Self {
            operator: Arc::new(operator),
            max_document_bytes,
        })
    }

    pub async fn list_documents(&self) -> Result<Vec<GDriveDocument>, DomainError> {
        // Bound the listing: a Drive folder can hold an unbounded number of
        // files, and draining the whole lister would produce an unbounded Vec
        // plus unbounded round trips. Stop at a fixed maximum.
        const MAX_LISTED: usize = 1000;
        let mut lister = self.operator.lister("").await.map_err(map_opendal_error)?;
        let mut documents = Vec::new();
        while documents.len() < MAX_LISTED {
            let entry = match lister.try_next().await.map_err(map_opendal_error)? {
                Some(entry) => entry,
                None => break,
            };
            let path = entry.path().to_owned();
            if is_supported_document(&path) {
                let name = path.rsplit('/').next().unwrap_or(&path).to_owned();
                documents.push(GDriveDocument { handle: path, name });
            }
        }
        documents.sort_by(|left, right| left.handle.cmp(&right.handle));
        Ok(documents)
    }

    async fn read_bounded(&self, handle: &str) -> Result<Vec<u8>, DomainError> {
        validate_handle(handle)?;
        let metadata = self
            .operator
            .stat(handle)
            .await
            .map_err(map_opendal_error)?;
        if metadata.content_length() > self.max_document_bytes {
            return Err(DomainError::validation(format!(
                "GDrive document exceeds the configured {} byte limit",
                self.max_document_bytes
            )));
        }
        // The `stat` above already rejects oversized documents before any
        // bytes are buffered, so a plain read is bounded. A `read_with`
        // `.range(0..=max)` is NOT safe on GDrive: requesting a range end
        // beyond EOF makes OpenDAL fail with "reader got too little data".
        let bytes = self
            .operator
            .read(handle)
            .await
            .map_err(map_opendal_error)?
            .to_vec();
        if bytes.len() as u64 > self.max_document_bytes {
            return Err(DomainError::validation(
                "GDrive document exceeded the configured byte limit while reading",
            ));
        }
        Ok(bytes)
    }
}

#[async_trait]
impl AiDocumentSource for GDriveDocumentSource {
    async fn load(&self, handle: &str) -> Result<Vec<u8>, DomainError> {
        self.read_bounded(handle).await
    }
}

fn validate_handle(handle: &str) -> Result<(), DomainError> {
    if handle.trim().is_empty()
        || handle.starts_with('/')
        || handle.split('/').any(|part| part == "..")
    {
        return Err(DomainError::validation("invalid GDrive document handle"));
    }
    Ok(())
}

fn is_supported_document(path: &str) -> bool {
    let lower = path.to_ascii_lowercase();
    lower.ends_with(".pdf") || lower.ends_with(".csv")
}

fn map_opendal_error(error: opendal::Error) -> DomainError {
    // Diagnostics WITHOUT secrets: opendal's full `Display` embeds the
    // request context, whose URI carries the OAuth `client_secret` and
    // `refresh_token` query parameters for the token endpoint — those must
    // never land in logs or job failure records (monorepo secrets rule).
    // Only the secret-free parts are carried through: the error kind plus
    // the sanitized message, which holds the upstream response body (e.g.
    // Google's `{"error": "invalid_grant"}` from an expired refresh token
    // — see the GDrive CI red on 2026-09-15). The message is untrusted
    // upstream content that lands in worker logs and the persisted
    // `last_error` (surfaced by the AI job API), so it is bounded and
    // credential-scanned before inclusion, mirroring
    // `sanitize_error_detail` (core/reporting) and `truncate_error`
    // (infra/reporting).
    let detail = sanitize_error_detail(format!("{} — {}", error.kind(), error.message()));
    if error.is_temporary() {
        DomainError::service_unavailable(format!("temporary GDrive storage failure: {detail}"))
    } else if error.kind() == opendal::ErrorKind::NotFound {
        DomainError::not_found("gdrive-document")
    } else {
        DomainError::validation(format!("GDrive document operation failed: {detail}"))
    }
}

/// Strip credential-ish content and bound length so the upstream error body
/// stays log-safe and persisted-`last_error`-safe (same discipline as
/// `sanitize_error_detail` in core/reporting/storage.rs). `char`-based
/// truncation so the bound never splits a multi-byte UTF-8 boundary.
fn sanitize_error_detail(mut detail: String) -> String {
    const MAX_CHARS: usize = 256;
    if detail.chars().count() > MAX_CHARS {
        detail = detail.chars().take(MAX_CHARS).collect::<String>();
        detail.push('…');
    }
    // Redact wholesale if a credential-ish token slipped into the message —
    // covers OpenDAL echoing a URL fragment or a provider body containing
    // token/secret material (the request context with the actual OAuth
    // parameters is already excluded in map_opendal_error).
    let lower = detail.to_ascii_lowercase();
    for needle in ["secret", "password", "token", "bearer ", "akia"] {
        if lower.contains(needle) {
            return "redacted upstream error".into();
        }
    }
    detail
}

#[cfg(test)]
mod tests {
    use super::sanitize_error_detail;

    // White-box tests for the mutation-sensitive sanitizer: bounding is
    // `char`-based (never splits UTF-8), credential-ish needles redact the
    // whole detail, and the benign upstream body of the issue-#423-class
    // failure (`invalid_grant`) survives for diagnosability.

    #[test]
    fn benign_upstream_body_survives() {
        let detail = sanitize_error_detail(
            "Unexpected — {\n  \"error\": \"invalid_grant\",\n  \"error_description\": \"Bad Request\"\n}".to_string(),
        );
        assert!(detail.contains("invalid_grant"));
    }

    #[test]
    fn long_details_are_char_bounded() {
        // 200 multi-byte chars (600 bytes) → 256 chars + ellipsis, valid UTF-8.
        let detail = sanitize_error_detail("é".repeat(300));
        assert_eq!(detail.chars().count(), 257); // 256 + '…'
    }

    #[test]
    fn credential_ish_content_is_redacted_wholesale() {
        for leaky in [
            "status 401, client_secret=GOCSPX-abcd",
            "refresh_token=1//04abc…",
            "Authorization: Bearer ya29.xyz",
            "aws access key akia lower-case redaction check",
            "entered password hunter2",
        ] {
            assert_eq!(
                sanitize_error_detail(leaky.to_string()),
                "redacted upstream error"
            );
        }
    }

    #[test]
    fn plain_kind_only_detail_is_kept() {
        assert_eq!(
            sanitize_error_detail("Unexpected".to_string()),
            "Unexpected"
        );
    }
}
