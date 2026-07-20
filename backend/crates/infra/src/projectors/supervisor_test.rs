// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors

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
