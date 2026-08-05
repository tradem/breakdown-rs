// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

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
        let operator = Operator::new(builder)
            .map_err(|error| DomainError::ServiceUnavailable(format!("GDrive adapter: {error}")))?
            .finish();
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
            return Err(DomainError::ValidationError(format!(
                "GDrive document exceeds the configured {} byte limit",
                self.max_document_bytes
            )));
        }
        let bytes = self
            .operator
            .read_with(handle)
            // Cap the buffered bytes: reject oversized documents after at most
            // max_document_bytes + 1 bytes instead of downloading the whole file.
            .range(0..=self.max_document_bytes)
            .await
            .map_err(map_opendal_error)?
            .to_vec();
        if bytes.len() as u64 > self.max_document_bytes {
            return Err(DomainError::ValidationError(
                "GDrive document exceeded the configured byte limit while reading".to_owned(),
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
        return Err(DomainError::ValidationError(
            "invalid GDrive document handle".to_owned(),
        ));
    }
    Ok(())
}

fn is_supported_document(path: &str) -> bool {
    let lower = path.to_ascii_lowercase();
    lower.ends_with(".pdf") || lower.ends_with(".csv")
}

fn map_opendal_error(error: opendal::Error) -> DomainError {
    if error.is_temporary() {
        DomainError::ServiceUnavailable("temporary GDrive storage failure".to_owned())
    } else if error.kind() == opendal::ErrorKind::NotFound {
        DomainError::NotFound("GDrive document not found".to_owned())
    } else {
        DomainError::ValidationError("GDrive document operation failed".to_owned())
    }
}
