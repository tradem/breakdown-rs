// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: gpt-5.6-luna (opencode-go)

use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use tokio::sync::Notify;

/// Tracks jobs that have been claimed but have not yet reached a terminal
/// queue transition. Shutdown waits for this count to reach zero.
#[derive(Clone, Default)]
pub struct AiWorkerLifecycle {
    in_flight: Arc<AtomicUsize>,
    drained: Arc<Notify>,
}

impl AiWorkerLifecycle {
    pub fn start_job(&self) -> AiJobGuard {
        self.in_flight.fetch_add(1, Ordering::AcqRel);
        AiJobGuard {
            in_flight: Arc::clone(&self.in_flight),
            drained: Arc::clone(&self.drained),
        }
    }

    pub fn in_flight(&self) -> usize {
        self.in_flight.load(Ordering::Acquire)
    }

    /// Wait until every claimed job has dropped its guard after a terminal
    /// success, failure, or dead-letter transition.
    pub async fn drain(&self) {
        loop {
            let notified = self.drained.notified();
            if self.in_flight() == 0 {
                return;
            }
            notified.await;
        }
    }
}

pub struct AiJobGuard {
    in_flight: Arc<AtomicUsize>,
    drained: Arc<Notify>,
}

impl Drop for AiJobGuard {
    fn drop(&mut self) {
        self.in_flight.fetch_sub(1, Ordering::AcqRel);
        self.drained.notify_waiters();
    }
}
