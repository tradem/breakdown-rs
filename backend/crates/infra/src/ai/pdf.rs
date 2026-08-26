// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

use std::process::Stdio;
use std::time::Duration;

use breakdown_core::error::DomainError;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::process::Command;

#[cfg(test)]
#[path = "pdf_tests.rs"]
mod pdf_tests;

/// Bounded `pdftotext` subprocess adapter. PDF bytes are sent through stdin so
/// no temporary document is persisted by this adapter.
#[derive(Clone, Debug)]
pub struct PdfTextExtractor {
    pub max_output_bytes: usize,
    pub timeout: Duration,
}

/// Best-effort kill + reap of a spawned `pdftotext` child. Every error path
/// after `spawn()` routes through this so repeated failures cannot leave
/// processes running. Cleanup failures are logged, never propagated — the
/// original error is what matters.
async fn reap_child(child: &mut tokio::process::Child, context: &'static str) {
    if let Err(error) = child.kill().await {
        tracing::warn!(%error, context, "failed to kill pdftotext process");
    }
    if let Err(error) = child.wait().await {
        tracing::warn!(%error, context, "failed to reap pdftotext process");
    }
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
            return Err(DomainError::validation("PDF document must not be empty"));
        }
        let mut child = Command::new("pdftotext")
            .args(["-q", "-", "-"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|error| {
                DomainError::validation(format!("could not start pdftotext: {error}"))
            })?;

        // Every error path after spawn() must kill + reap the child; an early
        // return would leave pdftotext running (repeated failures accumulate
        // processes). Cleanup failures are logged, the original error is
        // preserved.
        let mut stdin = match child.stdin.take() {
            Some(stdin) => stdin,
            None => {
                reap_child(&mut child, "stdin missing").await;
                return Err(DomainError::validation("pdftotext stdin was not available"));
            }
        };
        let stdout = match child.stdout.take() {
            Some(stdout) => stdout,
            None => {
                reap_child(&mut child, "stdout missing").await;
                return Err(DomainError::validation(
                    "pdftotext stdout was not available",
                ));
            }
        };
        let read_limit = self.max_output_bytes.saturating_add(1);

        let finished = async {
            let write = async move {
                stdin.write_all(pdf_bytes).await?;
                stdin.shutdown().await
            };
            let mut output = Vec::new();
            let mut limited = stdout.take(read_limit as u64);
            let read = limited.read_to_end(&mut output);
            let (written, read_result) = tokio::join!(write, read);
            if let Err(error) = written
                && error.kind() != std::io::ErrorKind::BrokenPipe
            {
                reap_child(&mut child, "stdin write failed").await;
                return Err(DomainError::validation(format!(
                    "could not provide PDF to pdftotext: {error}"
                )));
            }
            if let Err(error) = read_result {
                reap_child(&mut child, "stdout read failed").await;
                return Err(DomainError::validation(format!(
                    "could not read pdftotext output: {error}"
                )));
            }
            if output.len() > self.max_output_bytes {
                reap_child(&mut child, "output oversized").await;
                return Err(DomainError::validation(
                    "pdftotext output exceeds the configured bound",
                ));
            }
            let status = child.wait().await.map_err(|error| {
                DomainError::validation(format!("could not reap pdftotext process: {error}"))
            })?;
            Ok::<(std::process::ExitStatus, Vec<u8>), DomainError>((status, output))
        };

        let (status, output) = match tokio::time::timeout(self.timeout, finished).await {
            Ok(result) => result?,
            Err(_elapsed) => {
                reap_child(&mut child, "timed out").await;
                return Err(DomainError::validation(format!(
                    "pdftotext did not finish within {} seconds",
                    self.timeout.as_secs()
                )));
            }
        };

        if !status.success() {
            return Err(DomainError::validation(format!(
                "pdftotext failed with status {status}"
            )));
        }
        String::from_utf8(output).map_err(|error| {
            DomainError::validation(format!("pdftotext emitted invalid UTF-8: {error}"))
        })
    }
}
