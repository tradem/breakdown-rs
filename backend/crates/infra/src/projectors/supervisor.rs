// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors

//! In-process supervisor for projector subscription loops.
//!
//! Wraps a per-epoch subscription + `stream.run()` body in a restart loop with
//! exponential backoff, jitter, bounded retry budget, and structured tracing.

use std::future::Future;
use std::time::{Duration, Instant};

use anyhow::Result;
use tokio::time::sleep;

/// Base delay for exponential backoff (milliseconds).
pub const BACKOFF_BASE_MS: u64 = 500;

/// Maximum backoff delay (milliseconds).
pub const BACKOFF_MAX_DELAY_MS: u64 = 30_000;

/// Maximum consecutive failures before the projector gives up.
pub const MAX_ATTEMPTS: usize = 10;

/// Duration a successful epoch must run before the consecutive-failure
/// counter is reset on the next failure.
pub const RESET_WINDOW_SECS: u64 = 300;

// ── helpers ──────────────────────────────────────────────────────────

/// Compute the delay for a given attempt (0-indexed) with exponential
/// backoff, cap, and random jitter.
pub(super) fn compute_backoff(attempt: usize, max: Duration) -> Duration {
    let base = std::cmp::min(
        BACKOFF_BASE_MS * 2_u64.saturating_pow(attempt as u32),
        max.as_millis() as u64,
    );
    let jitter: u64 = fastrand::u64(0..=base / 4); // up to 25 % of base
    let total = base.saturating_add(jitter).min(max.as_millis() as u64);
    Duration::from_millis(total)
}

// ── public API ───────────────────────────────────────────────────────

/// Spawn a supervised projector subscription loop.
///
/// The supplied closure `make_epoch` builds the SierraDB subscription +
/// calls `stream.run()`.  On `Err` or panic the loop restarts from the
/// projector's checkpoint after an exponential-backoff delay, up to
/// [`MAX_ATTEMPTS`] consecutive failures.
///
/// Returns a [`JoinHandle`] that completes when the supervisor loop
/// exits — either because budget exhaustion was reached or because the
/// handle is aborted.
pub async fn run_with_restart<F, Fut>(
    category: &'static str,
    make_epoch: F,
) -> Result<tokio::task::JoinHandle<()>>
where
    F: Fn() -> Fut + Send + 'static,
    Fut: Future<Output = anyhow::Result<()>> + Send + 'static,
{
    let handle = tokio::spawn(supervisor_loop(category, make_epoch));
    Ok(handle)
}

async fn supervisor_loop<F, Fut>(category: &'static str, make_epoch: F)
where
    F: Fn() -> Fut + Send + 'static,
    Fut: Future<Output = anyhow::Result<()>> + Send + 'static,
{
    let mut consecutive_failures: usize = 0;
    let mut long_success_occurred: bool = false;

    loop {
        tracing::info!(
            projector.category = category,
            "starting projector subscription stream"
        );

        let started_at = Instant::now();
        let epoch_fut = make_epoch();

        // tokio::spawn catches panics via JoinError — panics are
        // treated as failures and follow the same backoff path.
        let handle = tokio::spawn(epoch_fut);

        match handle.await {
            // Epoch completed successfully.
            Ok(Ok(())) => {
                if started_at.elapsed() >= Duration::from_secs(RESET_WINDOW_SECS) {
                    long_success_occurred = true;
                }
                consecutive_failures = 0;
                continue; // next epoch
            }

            // stream.run() returned an error.
            Ok(Err(err)) => {
                if long_success_occurred {
                    long_success_occurred = false;
                    consecutive_failures = 0;
                }
                consecutive_failures += 1;

                if consecutive_failures >= MAX_ATTEMPTS {
                    tracing::error!(
                        projector.category = category,
                        error = %err,
                        "projector subscription budget exhausted, stopping"
                    );
                    return;
                }

                let delay = compute_backoff(
                    consecutive_failures,
                    Duration::from_millis(BACKOFF_MAX_DELAY_MS),
                );
                tracing::warn!(
                    projector.category = category,
                    attempt = consecutive_failures,
                    delay_ms = delay.as_millis(),
                    error = %err,
                    "restarting projector subscription after error"
                );
                sleep(delay).await;
            }

            // Task panicked — caught via JoinError.
            Err(join_err) => {
                let payload = join_err.to_string();
                if long_success_occurred {
                    long_success_occurred = false;
                    consecutive_failures = 0;
                }
                consecutive_failures += 1;

                if consecutive_failures >= MAX_ATTEMPTS {
                    tracing::error!(
                        projector.category = category,
                        error = %payload,
                        "projector subscription budget exhausted after panic, stopping"
                    );
                    return;
                }

                let delay = compute_backoff(
                    consecutive_failures,
                    Duration::from_millis(BACKOFF_MAX_DELAY_MS),
                );
                tracing::warn!(
                    projector.category = category,
                    attempt = consecutive_failures,
                    delay_ms = delay.as_millis(),
                    error = %payload,
                    "restarting projector subscription after panic"
                );
                sleep(delay).await;
            }
        }
    }
}

#[cfg(test)]
#[path = "supervisor_test.rs"]
mod tests;
