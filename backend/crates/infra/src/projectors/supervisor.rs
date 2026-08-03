// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: glm-5.2 (neuralwatt)

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

/// Tunable backoff parameters for [`run_with_restart`].
///
/// Production code uses [`BackoffConfig::default`] (slow exponential
/// backoff up to 30 s).  Tests use [`BackoffConfig::test_profile`] so a
/// 10-attempt budget exhaustion completes in milliseconds instead of
/// minutes — without duplicating the supervisor loop.
#[derive(Clone, Copy, Debug)]
pub struct BackoffConfig {
    /// Base delay in milliseconds; the `attempt`-th retry waits roughly
    /// `base_ms * 2^attempt` (capped at `max_delay`), plus jitter.
    pub base_ms: u64,
    /// Upper bound for a single backoff delay.
    pub max_delay: Duration,
    /// Consecutive failures before the supervisor gives up and the loop exits.
    pub max_attempts: usize,
    /// How long a successful epoch must run before the next failure resets the
    /// consecutive-failure counter.
    pub reset_window: Duration,
}

impl Default for BackoffConfig {
    fn default() -> Self {
        Self {
            base_ms: BACKOFF_BASE_MS,
            max_delay: Duration::from_millis(BACKOFF_MAX_DELAY_MS),
            max_attempts: MAX_ATTEMPTS,
            reset_window: Duration::from_secs(RESET_WINDOW_SECS),
        }
    }
}

impl BackoffConfig {
    /// Fast profile for unit/integration tests — tiny delays so a multi-attempt
    /// budget exhaustion completes in milliseconds instead of ~3 minutes.
    /// **Never use in production** — production supervisor loops must use
    /// [`BackoffConfig::default`].
    #[doc(hidden)]
    pub fn test_profile() -> Self {
        Self {
            base_ms: 1,
            max_delay: Duration::from_millis(5),
            max_attempts: MAX_ATTEMPTS,
            reset_window: Duration::from_secs(60),
        }
    }

    /// Compute the delay for a given 0-indexed attempt with exponential
    /// backoff, cap, and random jitter.
    pub fn compute_backoff(&self, attempt: usize) -> Duration {
        let base = std::cmp::min(
            self.base_ms * 2_u64.saturating_pow(attempt as u32),
            self.max_delay.as_millis() as u64,
        );
        let jitter: u64 = fastrand::u64(0..=base / 4);
        let total = base
            .saturating_add(jitter)
            .min(self.max_delay.as_millis() as u64);
        Duration::from_millis(total)
    }
}

/// Compute the delay for a given attempt (0-indexed) with exponential
/// backoff, cap, and random jitter, using production defaults.
///
/// Kept `pub` for direct formula unit tests. Runtime callers should go
/// through [`BackoffConfig::compute_backoff`] so their config is honoured.
pub fn compute_backoff(attempt: usize, max: Duration) -> Duration {
    BackoffConfig::default()
        .with_max_delay(max)
        .compute_backoff(attempt)
}

impl BackoffConfig {
    /// Builder helper used by the free-standing [`compute_backoff`] shim.
    fn with_max_delay(mut self, max: Duration) -> Self {
        self.max_delay = max;
        self
    }
}

/// Spawn a supervised projector subscription loop with production backoff.
///
/// The supplied closure `make_epoch` builds the SierraDB subscription +
/// calls `stream.run()`.  On `Err` or panic the loop restarts from the
/// projector's checkpoint after an exponential-backoff delay, up to
/// [`MAX_ATTEMPTS`] consecutive failures.
///
/// Returns a [`tokio::task::JoinHandle`] that completes when the supervisor
/// loop exits — either because the budget was exhausted or because the
/// handle is aborted.
pub async fn run_with_restart<F, Fut>(
    category: &'static str,
    make_epoch: F,
) -> Result<tokio::task::JoinHandle<()>>
where
    F: Fn() -> Fut + Send + 'static,
    Fut: Future<Output = anyhow::Result<()>> + Send + 'static,
{
    run_with_restart_with_config(category, make_epoch, BackoffConfig::default()).await
}

/// Like [`run_with_restart`] but with an explicit [`BackoffConfig`], so tests
/// can run with millisecond backoff instead of the production 30 s cap.
pub async fn run_with_restart_with_config<F, Fut>(
    category: &'static str,
    make_epoch: F,
    config: BackoffConfig,
) -> Result<tokio::task::JoinHandle<()>>
where
    F: Fn() -> Fut + Send + 'static,
    Fut: Future<Output = anyhow::Result<()>> + Send + 'static,
{
    let handle = tokio::spawn(supervisor_loop(category, make_epoch, config));
    Ok(handle)
}

async fn supervisor_loop<F, Fut>(category: &'static str, make_epoch: F, config: BackoffConfig)
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

        let handle = tokio::spawn(epoch_fut);

        match handle.await {
            Ok(Ok(())) => {
                if started_at.elapsed() >= config.reset_window {
                    long_success_occurred = true;
                }
                consecutive_failures = 0;
                continue;
            }

            Ok(Err(err)) => {
                if long_success_occurred {
                    long_success_occurred = false;
                    consecutive_failures = 0;
                }
                consecutive_failures += 1;

                if consecutive_failures >= config.max_attempts {
                    tracing::error!(
                        projector.category = category,
                        error = %err,
                        "projector subscription budget exhausted, stopping"
                    );
                    return;
                }

                let delay = config.compute_backoff(consecutive_failures);
                tracing::warn!(
                    projector.category = category,
                    attempt = consecutive_failures,
                    delay_ms = delay.as_millis(),
                    error = %err,
                    "restarting projector subscription after error"
                );
                sleep(delay).await;
            }

            Err(join_err) => {
                let payload = join_err.to_string();
                if long_success_occurred {
                    long_success_occurred = false;
                    consecutive_failures = 0;
                }
                consecutive_failures += 1;

                if consecutive_failures >= config.max_attempts {
                    tracing::error!(
                        projector.category = category,
                        error = %payload,
                        "projector subscription budget exhausted after panic, stopping"
                    );
                    return;
                }

                let delay = config.compute_backoff(consecutive_failures);
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
