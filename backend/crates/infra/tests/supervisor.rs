// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024 Breakdown RS Contributors
// Co-authored-by: glm-5.2 (neuralwatt)

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stdout,
    clippy::print_stderr,
    clippy::dbg_macro
)]
use infra::projectors::supervisor::{
    BACKOFF_BASE_MS, BACKOFF_MAX_DELAY_MS, BackoffConfig, MAX_ATTEMPTS, compute_backoff,
    run_with_restart_with_config,
};
use std::future::Future;
use std::pin::Pin;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

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
        assert!(
            delay_ms >= (*exp_base * 3) / 4,
            "attempt {attempt}: delay {delay_ms}ms below 75 % of expected base {exp_base}ms"
        );
        assert!(
            delay_ms <= (exp_base * 5).div_ceil(4),
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

/// Two failures then success must reset the consecutive-failure counter.
/// Uses `test_profile` backoff so the epoch restarts happen in milliseconds.
#[tokio::test]
async fn error_triggers_restart_then_success_resets_counter() {
    let (_data, count, closure) =
        make_controlled(vec![Outcome::Fail, Outcome::Fail, Outcome::Succeed]);

    let handle = run_with_restart_with_config("err_test", closure, BackoffConfig::test_profile())
        .await
        .unwrap();

    // With 1 ms base / 5 ms cap backoff, three epochs complete well within 1 s.
    tokio::time::timeout(Duration::from_secs(1), async {
        // Wait until at least 3 epochs have run.
        loop {
            if count.load(Ordering::SeqCst) >= 3 {
                return;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .expect("restart counter never reached 3");
    assert!(count.load(Ordering::SeqCst) >= 3);

    handle.abort();
    let _ = handle.await;
}

/// Feed more failures than `max_attempts`; the loop must stop on its own
/// (budget exhausted). With `test_profile` this completes in milliseconds
/// instead of ~3 minutes of real production backoff.
#[tokio::test]
async fn budget_exhaustion_stops_loop() {
    let (_data, count, closure) = make_controlled(vec![Outcome::Fail; MAX_ATTEMPTS + 5]);

    let handle =
        run_with_restart_with_config("budget_test", closure, BackoffConfig::test_profile())
            .await
            .unwrap();

    tokio::time::timeout(Duration::from_secs(2), handle)
        .await
        .expect("budget exhaustion timed out")
        .expect("supervisor task panicked");
    assert!(count.load(Ordering::SeqCst) >= MAX_ATTEMPTS);
}

/// A panicking epoch is caught and retried, then success resets the counter.
#[tokio::test]
async fn panic_is_caught_and_retried() {
    let (_data, count, closure) = make_controlled(vec![Outcome::Panic, Outcome::Succeed]);

    let handle = run_with_restart_with_config("panic_test", closure, BackoffConfig::test_profile())
        .await
        .unwrap();

    tokio::time::timeout(Duration::from_secs(1), async {
        loop {
            if count.load(Ordering::SeqCst) >= 2 {
                return;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .expect("panic retry counter never reached 2");
    assert!(count.load(Ordering::SeqCst) >= 2);

    handle.abort();
    let _ = handle.await;
}
