// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Process-wide append counters (issue #900, measurement M2).
//!
//! The apply worker needs two numbers it cannot derive from its own dispatch
//! count: **how many `EMAPPEND` calls one run issues** (a command may append
//! once and still land more than one event, and a *conflict retry* appends a
//! second time for the same command) and **how many of them answer `WRONGVER`**.
//! Both facts only exist at the store boundary, which is here.
//!
//! Read as a **snapshot delta**: take [`append_metrics`] before and after a
//! phase and subtract. The counters are process-wide because an append happens
//! inside an actor's own task — the dispatcher's task is gone by then, so a
//! task-local or a per-call handle cannot reach it, and threading a counter
//! through this message would change the public `Execute` surface for a
//! measurement. The consequence is explicit: a delta over a window includes
//! **every** append of the process in that window, not only one run's. On a
//! quiescent instance that is the run; with unrelated traffic it is an upper
//! bound. Do not present it as an exact per-run count.
//!
//! The per-append timing already exists (`histogram.append_emappend_duration`)
//! and the conflict path logs `write conflict` at debug — these counters are the
//! aggregate a run can print about itself, nothing more.

use std::sync::atomic::{AtomicU64, Ordering};

static APPEND_ATTEMPTS: AtomicU64 = AtomicU64::new(0);
static APPENDED_EVENTS: AtomicU64 = AtomicU64::new(0);
static VERSION_CONFLICTS: AtomicU64 = AtomicU64::new(0);

/// Absolute counter values; subtract two readings for one window's share.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct AppendMetrics {
    /// `EMAPPEND` calls issued, conflict retries included.
    pub append_attempts: u64,
    /// Events carried by those appends, summed (one append may carry several).
    pub appended_events: u64,
    /// Appends answered with `WRONGVER` — each one costs a resync and a retry.
    pub version_conflicts: u64,
}

impl AppendMetrics {
    /// This reading's share of what happened since `earlier`, saturating at
    /// zero rather than wrapping (a diagnostic must never report a huge negative).
    pub fn since(self, earlier: Self) -> Self {
        Self {
            append_attempts: self.append_attempts.saturating_sub(earlier.append_attempts),
            appended_events: self.appended_events.saturating_sub(earlier.appended_events),
            version_conflicts: self
                .version_conflicts
                .saturating_sub(earlier.version_conflicts),
        }
    }
}

/// Read the current counters.
pub fn append_metrics() -> AppendMetrics {
    AppendMetrics {
        append_attempts: APPEND_ATTEMPTS.load(Ordering::Relaxed),
        appended_events: APPENDED_EVENTS.load(Ordering::Relaxed),
        version_conflicts: VERSION_CONFLICTS.load(Ordering::Relaxed),
    }
}

/// Record one `EMAPPEND` call carrying `events` events.
///
/// `Relaxed` on purpose: no counter gates another memory location, and a reader
/// only needs each value to be a real observation. A slightly torn *set* of
/// counters is acceptable for a diagnostic.
pub(crate) fn record_append(events: usize) {
    APPEND_ATTEMPTS.fetch_add(1, Ordering::Relaxed);
    APPENDED_EVENTS.fetch_add(u64::try_from(events).unwrap_or(u64::MAX), Ordering::Relaxed);
}

/// Record one append that answered `WRONGVER` (the store rejected the expected
/// version), i.e. one resync-and-retry the caller pays for.
pub(crate) fn record_version_conflict() {
    VERSION_CONFLICTS.fetch_add(1, Ordering::Relaxed);
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The counters are process-wide statics that other tests in this crate also
    /// touch, so every assertion is written as a *delta* — a test that asserted
    /// absolute values would race the rest of the suite.
    #[test]
    fn appended_events_are_summed_not_counted_as_one() {
        let before = append_metrics();
        record_append(1);
        record_append(3);

        let delta = append_metrics().since(before);
        assert_eq!(delta.append_attempts, 2);
        assert_eq!(delta.appended_events, 4);
    }

    #[test]
    fn version_conflicts_are_counted_separately_from_attempts() {
        let before = append_metrics();
        record_append(1);
        record_version_conflict();
        record_append(1);

        let delta = append_metrics().since(before);
        assert_eq!(delta.append_attempts, 2);
        // A conflict is a rejected append, NOT a successful one: it must not
        // inflate the event count.
        assert_eq!(delta.appended_events, 2);
        assert_eq!(delta.version_conflicts, 1);
    }

    #[test]
    fn since_never_wraps_when_the_window_is_empty() {
        record_append(1);
        let later = append_metrics();

        // Reading "later" *before* "later" is zero, never a wrapped u64::MAX.
        assert_eq!(later.since(later), AppendMetrics::default());
    }
}
