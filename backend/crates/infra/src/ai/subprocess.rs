// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Bounded Poppler subprocess plumbing shared by the document-structure
//! adapters (ADR-041 `D1`, issue #958).
//!
//! Both adapters (`LegacyPdfToTextAdapter`, `SpatialPdfExtractor`) drive a
//! Poppler CLI over **stdin/stdout**: the PDF never touches the filesystem, so
//! no temporary document is persisted, no path is ever built from request
//! input, and there is nothing to clean up after a crash. The hygiene rules
//! below are the reason this lives in one place instead of being copied per
//! adapter:
//!
//! * the child is killed **and reaped** on every error and timeout path, so a
//!   failed render cannot leak a zombie or a spinning `pdftocairo`;
//! * the child is also killed if the caller **cancels** the future (a task
//!   aborted at shutdown drops the handle before any error branch can run), so
//!   Poppler never keeps consuming a core for a caller that stopped waiting;
//! * stdin is written while stdout is drained (`tokio::join!`) — a one-sided
//!   write of a large PDF deadlocks against a full pipe buffer;
//! * the output is read through a `take(max + 1)` limiter, so an adversarially
//!   large document cannot allocate unbounded memory before the size check;
//! * the whole exchange runs under `tokio::time::timeout`, and a child that
//!   outlives it is reaped before the error propagates.

use std::process::Stdio;
use std::time::Duration;

use breakdown_core::error::DomainError;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::process::{Child, Command};

/// Best-effort kill + reap of a spawned child. Every error path after
/// `spawn()` routes through this so repeated failures cannot leave processes
/// running. Cleanup failures are logged, never propagated — the original error
/// is what matters.
async fn reap_child(child: &mut Child, program: &str, context: &'static str) {
    if let Err(error) = child.kill().await {
        tracing::warn!(%error, program, context, "failed to kill document tool");
    }
    if let Err(error) = child.wait().await {
        tracing::warn!(%error, program, context, "failed to reap document tool");
    }
}

/// Run one Poppler CLI with `stdin_bytes` on stdin and bounded output.
///
/// `program` is also the identity used in error messages, so the operator can
/// tell a `pdftotext` failure from a `pdftocairo` one without a trace.
pub(crate) async fn run_bounded(
    program: &'static str,
    args: &[&str],
    stdin_bytes: &[u8],
    max_output_bytes: usize,
    timeout: Duration,
) -> Result<Vec<u8>, DomainError> {
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        // Cancellation fallback: if the caller drops this future (worker
        // shutdown, task abort) neither `reap_child` nor `child.wait()` ever
        // runs, and Tokio leaves a running child alive by default. The explicit
        // wait/reap below still owns the normal and error paths, so this only
        // adds the case that has no code path left to run.
        .kill_on_drop(true)
        .spawn()
        .map_err(|error| DomainError::validation(format!("could not start {program}: {error}")))?;

    let Some(mut stdin) = child.stdin.take() else {
        reap_child(&mut child, program, "stdin missing").await;
        return Err(DomainError::validation(format!(
            "{program} stdin was not available"
        )));
    };
    let Some(stdout) = child.stdout.take() else {
        reap_child(&mut child, program, "stdout missing").await;
        return Err(DomainError::validation(format!(
            "{program} stdout was not available"
        )));
    };
    let read_limit = max_output_bytes.saturating_add(1);

    let finished = async {
        let write = async move {
            stdin.write_all(stdin_bytes).await?;
            stdin.shutdown().await
        };
        let mut output = Vec::new();
        let mut limited = stdout.take(read_limit as u64);
        let read = limited.read_to_end(&mut output);
        let (written, read_result) = tokio::join!(write, read);
        if let Err(error) = written
            && error.kind() != std::io::ErrorKind::BrokenPipe
        {
            reap_child(&mut child, program, "stdin write failed").await;
            return Err(DomainError::validation(format!(
                "could not provide the document to {program}: {error}"
            )));
        }
        if let Err(error) = read_result {
            reap_child(&mut child, program, "stdout read failed").await;
            return Err(DomainError::validation(format!(
                "could not read {program} output: {error}"
            )));
        }
        if output.len() > max_output_bytes {
            reap_child(&mut child, program, "output oversized").await;
            return Err(DomainError::validation(format!(
                "{program} output exceeds the configured bound"
            )));
        }
        let status = child.wait().await.map_err(|error| {
            DomainError::validation(format!("could not reap {program} process: {error}"))
        })?;
        Ok::<(std::process::ExitStatus, Vec<u8>), DomainError>((status, output))
    };

    let (status, output) = match tokio::time::timeout(timeout, finished).await {
        Ok(result) => result?,
        Err(_elapsed) => {
            reap_child(&mut child, program, "timed out").await;
            return Err(DomainError::validation(format!(
                "{program} did not finish within {} seconds",
                timeout.as_secs()
            )));
        }
    };

    if !status.success() {
        return Err(DomainError::validation(format!(
            "{program} failed with status {status}"
        )));
    }
    Ok(output)
}

/// Render exactly one page of a PDF to PNG, bounded by `max_bytes` and
/// `timeout`.
///
/// `pdftocairo` (not `pdftoppm`) is the streaming renderer: `pdftoppm` always
/// writes `<prefix>.png` to the filesystem, so streaming from it would mean
/// inventing a temporary path — a file to clean up and one more thing that can
/// go wrong mid-render. `pdftocairo` writes the single page to stdout with the
/// `-` prefix, keeping the same stdin/stdout discipline as `pdftotext`. Both
/// ship in `poppler-utils`, which the runtime image already installs.
pub(crate) async fn render_page_png(
    pdf_bytes: &[u8],
    page_number: u32,
    target_dpi: u16,
    max_output_bytes: usize,
    timeout: Duration,
) -> Result<Vec<u8>, DomainError> {
    if page_number == 0 {
        return Err(DomainError::validation(
            "page numbers are 1-based; page 0 cannot be rendered",
        ));
    }
    let dpi = target_dpi.to_string();
    let first = page_number.to_string();
    let last = page_number.to_string();
    let png = run_bounded(
        "pdftocairo",
        &[
            "-png",
            "-r",
            &dpi,
            "-f",
            &first,
            "-l",
            &last,
            "-singlefile",
            "-",
            "-",
        ],
        pdf_bytes,
        max_output_bytes,
        timeout,
    )
    .await?;
    // A successful `pdftocairo` always emits the PNG signature; anything else
    // means the page does not exist (a page count from a stale document) or the
    // tool wrote a diagnostic where the image belongs.
    const PNG_SIGNATURE: [u8; 8] = [0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a];
    if !png.starts_with(&PNG_SIGNATURE) {
        return Err(DomainError::validation(format!(
            "pdftocairo did not return a PNG image for page {page_number}"
        )));
    }
    Ok(png)
}

#[cfg(test)]
#[path = "subprocess_tests.rs"]
mod subprocess_tests;
