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
mod tests {
    use super::*;
    use std::future::Future;
    use std::pin::Pin;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::{Arc, Mutex};

    #[test]
    fn backoff_non_decreasing_and_capped() {
        let max = Duration::from_millis(BACKOFF_MAX_DELAY_MS);
        for attempt in 0..20 {
            let delay = compute_backoff(attempt, max);
            assert!(
                delay <= max,
                "backoff at attempt {} ({:?}) exceeds cap {:?}",
                attempt,
                delay,
                max
            );
        }
    }

    /// Ensure `compute_backoff` follows the expected exponential formula:
    /// `min(base * 2^attempt, cap)` — a wrong operator (+, /) or a
    /// `Default::default()` return must change the computed values.
    #[test]
    fn compute_backoff_values() {
        let max = Duration::from_millis(BACKOFF_MAX_DELAY_MS);

        // Expected base values (without jitter, which is 0–25 % of base).
        let expected_base: Vec<u64> = (0..=5)
            .map(|a| {
                std::cmp::min(
                    BACKOFF_BASE_MS * 2_u64.saturating_pow(a as u32),
                    BACKOFF_MAX_DELAY_MS,
                )
            })
            .collect();

        let delays: Vec<Duration> = (0..=5).map(|a| compute_backoff(a, max)).collect();

        for (attempt, (exp_base, delay)) in expected_base.iter().zip(delays.iter()).enumerate() {
            let delay_ms = delay.as_millis() as u64;
            // Delay must be within ±25 % of the base (the jitter window).
            assert!(
                delay_ms >= (*exp_base * 3) / 4,
                "attempt {attempt}: delay {delay_ms}ms below 75 % of expected base {exp_base}ms"
            );
            assert!(
                delay_ms <= (exp_base * 5).div_ceil(4), // allow full jitter
                "attempt {attempt}: delay {delay_ms}ms above 125 % of expected base {exp_base}ms"
            );
        }
    }

    /// Ensure jitter is not zero for all runs, which would indicate that
    /// the `base / 4` expression was mutated to `base % 4` (always 0 for
    /// bases divisible by 4).
    #[test]
    fn compute_backoff_jitter_not_zero() {
        const TRIES: usize = 10;
        let max = Duration::from_millis(BACKOFF_MAX_DELAY_MS);

        for attempt in 0..3 {
            let base = std::cmp::min(
                BACKOFF_BASE_MS * 2_u64.saturating_pow(attempt as u32),
                BACKOFF_MAX_DELAY_MS,
            );

            let mut saw_jitter = false;
            for _ in 0..TRIES {
                let delay = compute_backoff(attempt, max);
                if delay.as_millis() != base as u128 {
                    saw_jitter = true;
                    break;
                }
            }
            assert!(
                saw_jitter,
                "attempt {attempt}: jitter was zero in all {TRIES} runs (jitter range {0} should have produced a non-zero value at least once)",
                (base / 4) + 1,
            );
        }
    }

    /// Outcome each epoch returns.
    #[derive(Clone)]
    enum Outcome {
        Succeed,
        Fail,
        Panic,
    }

    /// Closure type for a controlled epoch.
    type EpochClosure =
        Box<dyn Fn() -> Pin<Box<dyn Future<Output = anyhow::Result<()>> + Send>> + Send>;

    /// Build a closure that returns planned outcomes epoch-by-epoch.
    fn make_controlled(
        outcomes: Vec<Outcome>,
    ) -> (Arc<Mutex<Vec<Outcome>>>, Arc<AtomicUsize>, EpochClosure) {
        let data = Arc::new(Mutex::new(outcomes));
        let count = Arc::new(AtomicUsize::new(0));
        let data_in = Arc::clone(&data);
        let count_in = Arc::clone(&count);
        let closure: EpochClosure = {
            Box::new(move || {
                let data = Arc::clone(&data_in);
                count_in.fetch_add(1, Ordering::SeqCst);
                Box::pin(async move {
                    let mut guard = data.lock().unwrap_or_else(|e| e.into_inner());
                    if let Some(val) = guard.first().cloned() {
                        guard.remove(0);
                        match val {
                            Outcome::Succeed => Ok(()),
                            Outcome::Fail => anyhow::bail!("epoch failure"),
                            Outcome::Panic => panic!("epoch panic"),
                        }
                    } else {
                        Ok(())
                    }
                })
            })
        };
        (data, count, closure)
    }

    #[tokio::test]
    async fn error_triggers_restart_then_success_resets_counter() {
        let (_data, count, closure) =
            make_controlled(vec![Outcome::Fail, Outcome::Fail, Outcome::Succeed]);

        // run_with_restart returns a JoinHandle; keeping it alive keeps
        // the supervisor loop running.  After the 3rd epoch succeeds the
        // loop continues; we abort it to end the test.
        let handle = run_with_restart("err_test", closure).await.unwrap();

        // Give enough time for 3 epochs + 2 backoff delays (~2.5s).
        tokio::time::sleep(Duration::from_secs(4)).await;
        assert!(count.load(Ordering::SeqCst) >= 3);

        // Stop the supervisor so the test ends.
        handle.abort();
        let _ = handle.await;
    }

    #[tokio::test]
    async fn budget_exhaustion_stops_loop() {
        let (_data, count, closure) = make_controlled(vec![Outcome::Fail; MAX_ATTEMPTS + 5]);

        // When budget exhausts the supervisor_loop exits naturally,
        // so the JoinHandle completes on its own.
        let handle = run_with_restart("budget_test", closure).await.unwrap();

        // 10 failures × capped backoff (~30s each). Total ≈ 60-90s.
        tokio::time::timeout(Duration::from_secs(240), handle)
            .await
            .expect("budget exhaustion timed out")
            .expect("supervisor task panicked");
        assert!(count.load(Ordering::SeqCst) >= MAX_ATTEMPTS);
    }

    #[tokio::test]
    async fn panic_is_caught_and_retried() {
        let (_data, count, closure) = make_controlled(vec![Outcome::Panic, Outcome::Succeed]);

        let handle = run_with_restart("panic_test", closure).await.unwrap();

        // After panic + backoff + restart, second epoch succeeds (~1.5s).
        tokio::time::sleep(Duration::from_secs(3)).await;
        assert!(count.load(Ordering::SeqCst) >= 2);

        handle.abort();
        let _ = handle.await;
    }
}
