// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Where an AI-import apply's Postgres time goes (issue #900, measurement M1).
//!
//! An apply issues one `reserve` and one `insert` per mapped aggregate through
//! [`crate::ai::mapping::PgAiImportMappingRepository`], and each of those is a
//! `pool.acquire()` followed by a single statement. Splitting the two is what
//! tells **"the write is slow"** apart from **"the write waited for a
//! connection"** — the process shares one pool of 20 with 16–18 projectors and
//! sagas, and an apply manufactures the very projection backlog those
//! projectors are writing, so the two explanations predict very different
//! numbers.
//!
//! Read as a **snapshot delta**: [`MAPPING_WRITES`] is process-wide, so
//! [`ApplyWorker`] snapshots it before and after the row phase and logs the
//! difference in the row-phase summary (`workers.rs`). The synthesis is sound
//! because the mapping table has exactly one writer in a running process — this
//! repository (the projectors only *read* it, and the dev-reset tooling does not
//! run during an apply), so the delta is that run's own cost. Two previews
//! applying concurrently would share the delta; the separate `reserve_ops` /
//! `insert_ops` counters keep that visible, because each preview's ops can be
//! checked against its own plan.
//!
//! Per-call percentiles need no histogram here: every write also logs
//! `histogram.mapping_acquire_duration` / `histogram.mapping_statement_duration`
//! (the same shape the event store uses for `append_emappend_duration`), so
//! p50/p95 come from the log lines while the sums come from the counters.
//!
//! [`ApplyWorker`]: crate::ai::workers::ApplyWorker

use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

/// Which mapped write a measurement belongs to. The two calls have different
/// cost profiles (`reserve` is insert-if-absent, `insert` is a conditional
/// update), so they are never summed into one figure without the split.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum MappingWriteOp {
    Reserve,
    Insert,
}

impl MappingWriteOp {
    /// Stable log value — the field a log query groups by.
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::Reserve => "reserve",
            Self::Insert => "insert",
        }
    }
}

/// Absolute counter values. Subtract two snapshots ([`Self::since`]) for one
/// run's share.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct MappingWriteSnapshot {
    pub(crate) reserve_ops: u64,
    pub(crate) insert_ops: u64,
    /// Time spent waiting for a pooled connection, summed over every write.
    pub(crate) acquire: Duration,
    /// Time the statement itself took, summed over every write.
    pub(crate) statement: Duration,
    /// The pool's configured/leased size **at the latest observation** — a
    /// gauge, never a sum.
    pub(crate) pool_size: u32,
    /// Idle connections **at the latest observation** — a gauge, never a sum.
    pub(crate) pool_num_idle: usize,
}

impl MappingWriteSnapshot {
    /// This snapshot's share of what happened since `earlier`: ops and
    /// durations are differences, the pool gauges are the *latest* observation
    /// (a gauge has no meaningful delta; `size - num_idle` in flight is what a
    /// reader is after, and that only exists in a single instant).
    pub(crate) fn since(&self, earlier: Self) -> Self {
        Self {
            reserve_ops: self.reserve_ops.saturating_sub(earlier.reserve_ops),
            insert_ops: self.insert_ops.saturating_sub(earlier.insert_ops),
            acquire: self.acquire.saturating_sub(earlier.acquire),
            statement: self.statement.saturating_sub(earlier.statement),
            pool_size: self.pool_size,
            pool_num_idle: self.pool_num_idle,
        }
    }
}

/// The process-wide counters behind [`MAPPING_WRITES`].
///
/// One instance per process is the intended use, but the type is a plain value
/// so tests can exercise it without touching shared state (a test that used the
/// global would race every other test in this binary).
#[derive(Debug, Default)]
pub(crate) struct MappingWriteCounters {
    reserve_ops: AtomicU64,
    insert_ops: AtomicU64,
    acquire_nanos: AtomicU64,
    statement_nanos: AtomicU64,
    pool_size: AtomicU64,
    pool_num_idle: AtomicU64,
}

impl MappingWriteCounters {
    pub(crate) const fn new() -> Self {
        Self {
            reserve_ops: AtomicU64::new(0),
            insert_ops: AtomicU64::new(0),
            acquire_nanos: AtomicU64::new(0),
            statement_nanos: AtomicU64::new(0),
            pool_size: AtomicU64::new(0),
            pool_num_idle: AtomicU64::new(0),
        }
    }

    /// Record one finished write: which call, how long the connection wait was,
    /// how long the statement took, and the pool's state in that instant.
    ///
    /// `Relaxed` is enough for all of them: no counter gates another memory
    /// location, and a reader only needs each value to be a real observation
    /// (a torn *set* of counters is acceptable — the summary is a diagnostic,
    /// not a transaction).
    pub(crate) fn record(
        &self,
        op: MappingWriteOp,
        acquire: Duration,
        statement: Duration,
        pool_size: u32,
        pool_num_idle: usize,
    ) {
        match op {
            MappingWriteOp::Reserve => {
                self.reserve_ops.fetch_add(1, Ordering::Relaxed);
            }
            MappingWriteOp::Insert => {
                self.insert_ops.fetch_add(1, Ordering::Relaxed);
            }
        }
        // Saturating rather than wrapping: a run long enough to overflow a
        // nanosecond counter is impossible, and a wrapped diagnostic would lie.
        let acquire_nanos = u64::try_from(acquire.as_nanos()).unwrap_or(u64::MAX);
        let statement_nanos = u64::try_from(statement.as_nanos()).unwrap_or(u64::MAX);
        self.acquire_nanos
            .fetch_add(acquire_nanos, Ordering::Relaxed);
        self.statement_nanos
            .fetch_add(statement_nanos, Ordering::Relaxed);
        self.pool_size
            .store(u64::from(pool_size), Ordering::Relaxed);
        self.pool_num_idle.store(
            u64::try_from(pool_num_idle).unwrap_or(u64::MAX),
            Ordering::Relaxed,
        );
    }

    pub(crate) fn snapshot(&self) -> MappingWriteSnapshot {
        MappingWriteSnapshot {
            reserve_ops: self.reserve_ops.load(Ordering::Relaxed),
            insert_ops: self.insert_ops.load(Ordering::Relaxed),
            acquire: Duration::from_nanos(self.acquire_nanos.load(Ordering::Relaxed)),
            statement: Duration::from_nanos(self.statement_nanos.load(Ordering::Relaxed)),
            pool_size: u32::try_from(self.pool_size.load(Ordering::Relaxed)).unwrap_or(u32::MAX),
            pool_num_idle: usize::try_from(self.pool_num_idle.load(Ordering::Relaxed))
                .unwrap_or(usize::MAX),
        }
    }
}

/// The process-wide accumulator every mapping write feeds (see the module docs
/// for why a process-wide counter is the run's own number here).
pub(crate) static MAPPING_WRITES: MappingWriteCounters = MappingWriteCounters::new();

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counters_keep_the_two_calls_apart_and_sum_their_durations() {
        let counters = MappingWriteCounters::new();
        counters.record(
            MappingWriteOp::Reserve,
            Duration::from_millis(3),
            Duration::from_millis(1),
            20,
            4,
        );
        counters.record(
            MappingWriteOp::Insert,
            Duration::from_millis(5),
            Duration::from_micros(340),
            20,
            2,
        );

        let snapshot = counters.snapshot();
        assert_eq!(snapshot.reserve_ops, 1);
        assert_eq!(snapshot.insert_ops, 1);
        assert_eq!(snapshot.acquire, Duration::from_millis(8));
        assert_eq!(snapshot.statement, Duration::from_micros(1_340));
        // Gauges: the latest observation wins, never a sum.
        assert_eq!(snapshot.pool_size, 20);
        assert_eq!(snapshot.pool_num_idle, 2);
    }

    #[test]
    fn since_yields_only_the_second_windows_share() {
        let counters = MappingWriteCounters::new();
        counters.record(
            MappingWriteOp::Reserve,
            Duration::from_millis(10),
            Duration::from_millis(10),
            20,
            0,
        );
        let before = counters.snapshot();
        counters.record(
            MappingWriteOp::Insert,
            Duration::from_millis(2),
            Duration::from_millis(1),
            20,
            7,
        );

        let delta = counters.snapshot().since(before);
        assert_eq!(delta.reserve_ops, 0, "a reserve outside the window");
        assert_eq!(delta.insert_ops, 1);
        assert_eq!(delta.acquire, Duration::from_millis(2));
        assert_eq!(delta.statement, Duration::from_millis(1));
        // The gauges are the *current* instant, not a difference — a negative
        // idle count would be nonsense.
        assert_eq!(delta.pool_size, 20);
        assert_eq!(delta.pool_num_idle, 7);
    }

    #[test]
    fn since_never_wraps_when_the_window_is_empty() {
        let counters = MappingWriteCounters::new();
        let before = counters.snapshot();
        counters.record(MappingWriteOp::Insert, Duration::ZERO, Duration::ZERO, 1, 0);

        // An empty window (an apply whose rows were all cache-served) must
        // report zeros, not a wrapped huge number.
        assert_eq!(before.since(before), before);
        assert_eq!(before.reserve_ops, 0);
        assert_eq!(before.acquire, Duration::ZERO);
    }
}
