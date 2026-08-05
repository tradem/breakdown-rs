// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use std::process::Stdio;
use std::time::Duration;

use breakdown_core::error::DomainError;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::process::Command;

/// Bounded `pdftotext` subprocess adapter. PDF bytes are sent through stdin so
/// no temporary document is persisted by this adapter.
pub struct PdfTextExtractor {
    pub max_output_bytes: usize,
    pub timeout: Duration,
}

impl PdfTextExtractor {
    pub const fn new(max_output_bytes: usize, timeout: Duration) -> Self {
        Self {
            max_output_bytes,
            timeout,
        }
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
            // stderr is never drained; piping it would let pdftotext block
            // once the pipe buffer fills (same deadlock hazard as the
            // stdin/stdout interleave below).
            .stderr(Stdio::null())
            .spawn()
            .map_err(|error| {
                DomainError::ValidationError(format!("could not start pdftotext: {error}"))
            })?;

        let mut stdin = child.stdin.take().ok_or_else(|| {
            DomainError::ValidationError("pdftotext stdin was not available".to_owned())
        })?;
        let stdout = child.stdout.take().ok_or_else(|| {
            DomainError::ValidationError("pdftotext stdout was not available".to_owned())
        })?;
        let read_limit = self.max_output_bytes.saturating_add(1);

        let finished = async {
            // Write stdin and drain stdout CONCURRENTLY: a serial
            // write-all-then-read interleave deadlocks once pdftotext's stdout
            // pipe buffer (~64 KiB) fills while it still consumes stdin.
            let write = async move {
                stdin.write_all(pdf_bytes).await?;
                stdin.shutdown().await
            };
            let mut output = Vec::new();
            let mut limited = stdout.take(read_limit as u64);
            let read = limited.read_to_end(&mut output);
            let (written, read_result) = tokio::join!(write, read);
            if let Err(error) = written {
                // A broken stdin pipe is expected when pdftotext stops early.
                if error.kind() != std::io::ErrorKind::BrokenPipe {
                    return Err(DomainError::ValidationError(format!(
                        "could not provide PDF to pdftotext: {error}"
                    )));
                }
            }
            read_result.map_err(|error| {
                DomainError::ValidationError(format!("could not read pdftotext output: {error}"))
            })?;
            let status = child.wait().await.map_err(|error| {
                DomainError::ValidationError(format!("could not reap pdftotext process: {error}"))
            })?;
            Ok::<(std::process::ExitStatus, Vec<u8>), DomainError>((status, output))
        };

        let (status, output) = match tokio::time::timeout(self.timeout, finished).await {
            Ok(result) => result?,
            Err(_elapsed) => {
                // A stalled pdftotext must not hold the concurrency permit
                // forever; kill and reap it, then fail deterministically.
                if let Err(error) = child.kill().await {
                    tracing::warn!(%error, "failed to kill timed-out pdftotext process");
                }
                if let Err(error) = child.wait().await {
                    tracing::warn!(%error, "failed to reap timed-out pdftotext process");
                }
                return Err(DomainError::ValidationError(format!(
                    "pdftotext did not finish within {} seconds",
                    self.timeout.as_secs()
                )));
            }
        };

        if output.len() > self.max_output_bytes {
            return Err(DomainError::ValidationError(
                "pdftotext output exceeds the configured bound".to_owned(),
            ));
        }
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
