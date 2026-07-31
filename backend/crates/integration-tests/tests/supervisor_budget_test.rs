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
//! Exercises the real `run_with_restart_with_config` supervisor with a
//! `BackoffConfig` tuned for a small `max_attempts` and millisecond backoff.
//!
//! Previously this file duplicated the entire `supervisor_loop` (~80 lines)
//! to inject test constants — that copy-paste drifted from production and
//! was a maintenance hazard. It now drives the same production code path
//! via `run_with_restart_with_config` + `BackoffConfig`.

mod fixtures;

use std::future::Future;
use std::pin::Pin;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::Result;

use infra::projectors::supervisor::{BackoffConfig, run_with_restart_with_config};

/// Test backoff profile: small budget, millisecond delays.
fn test_config(max_attempts: usize) -> BackoffConfig {
    BackoffConfig {
        base_ms: 1,
        max_delay: Duration::from_millis(5),
        max_attempts,
        reset_window: Duration::from_secs(60),
    }
}

/// Outcome each epoch returns.
#[derive(Clone)]
enum Outcome {
    Fail,
    #[allow(dead_code)]
    Succeed,
}

/// Closure type for the controlled epoch test.
type EpochClosure =
    Box<dyn Fn() -> Pin<Box<dyn Future<Output = anyhow::Result<()>> + Send>> + Send>;

/// Build a controlled closure that returns planned outcomes epoch-by-epoch.
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
            let count = Arc::clone(&count_in);
            Box::pin(async move {
                count.fetch_add(1, Ordering::SeqCst);
                let mut guard = data.lock().unwrap_or_else(|e| e.into_inner());
                if let Some(val) = guard.first().cloned() {
                    guard.remove(0);
                    match val {
                        Outcome::Fail => anyhow::bail!("epoch failure"),
                        Outcome::Succeed => Ok(()),
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
async fn budget_exhaustion_stops_loop_fast() -> Result<()> {
    let max_attempts = 3;
    let (_data, count, closure) = make_controlled(vec![Outcome::Fail; max_attempts + 2]);

    let handle = run_with_restart_with_config("budget_test", closure, test_config(max_attempts))
        .await
        .unwrap();

    let result = tokio::time::timeout(Duration::from_secs(2), handle).await;

    assert!(
        result.is_ok(),
        "supervisor loop did not stop after budget exhaustion within 2 s"
    );
    let _ = result.unwrap();

    assert!(
        count.load(Ordering::SeqCst) >= max_attempts,
        "expected ≥ {} epochs, got {}",
        max_attempts,
        count.load(Ordering::SeqCst)
    );

    Ok(())
}
