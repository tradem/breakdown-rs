// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use std::process::Stdio;

use breakdown_core::error::DomainError;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::process::Command;

/// Bounded `pdftotext` subprocess adapter. PDF bytes are sent through stdin so
/// no temporary document is persisted by this adapter.
pub struct PdfTextExtractor {
    pub max_output_bytes: usize,
}

impl PdfTextExtractor {
    pub const fn new(max_output_bytes: usize) -> Self {
        Self { max_output_bytes }
    }

    pub async fn extract(&self, pdf_bytes: &[u8]) -> Result<String, DomainError> {
        if pdf_bytes.is_empty() {
            return Err(DomainError::ValidationError(
                "PDF document must not be empty".to_owned(),
            ));
        }
        let mut child = Command::new("pdftotext")
            .args(["-q", "-", "-"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|error| {
                DomainError::ValidationError(format!("could not start pdftotext: {error}"))
            })?;

        let mut stdin = child.stdin.take().ok_or_else(|| {
            DomainError::ValidationError("pdftotext stdin was not available".to_owned())
        })?;
        stdin.write_all(pdf_bytes).await.map_err(|error| {
            DomainError::ValidationError(format!("could not provide PDF to pdftotext: {error}"))
        })?;
        drop(stdin);

        let stdout = child.stdout.take().ok_or_else(|| {
            DomainError::ValidationError("pdftotext stdout was not available".to_owned())
        })?;
        let mut output = Vec::new();
        let read_limit = self.max_output_bytes.saturating_add(1);
        stdout
            .take(read_limit as u64)
            .read_to_end(&mut output)
            .await
            .map_err(|error| {
                DomainError::ValidationError(format!("could not read pdftotext output: {error}"))
            })?;

        if output.len() > self.max_output_bytes {
            child.kill().await.map_err(|error| {
                DomainError::ValidationError(format!(
                    "could not stop oversized pdftotext process: {error}"
                ))
            })?;
            child.wait().await.map_err(|error| {
                DomainError::ValidationError(format!("could not reap pdftotext process: {error}"))
            })?;
            return Err(DomainError::ValidationError(
                "pdftotext output exceeds the configured bound".to_owned(),
            ));
        }

        let status = child.wait().await.map_err(|error| {
            DomainError::ValidationError(format!("could not reap pdftotext process: {error}"))
        })?;
        if !status.success() {
            return Err(DomainError::ValidationError(format!(
                "pdftotext failed with status {status}"
            )));
        }
        String::from_utf8(output).map_err(|error| {
            DomainError::ValidationError(format!("pdftotext emitted invalid UTF-8: {error}"))
        })
    }
}
