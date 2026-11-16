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
//! The accumulator is a **task-local**, not a process-wide static: every write
//! of one apply runs inside [`scope_mapping_writes`], so the snapshot a run
//! reads back is exactly its own. The API's apply runner executes up to four
//! script/schedule applies concurrently (`APPLY_MAX_CONCURRENCY` in
//! `crates/api/src/apply_runner.rs`), and all rows of one script apply are
//! awaited inside the same Tokio task (a `try_join_all` under sequential
//! `.await`s, no `tokio::spawn` per row), so the task boundary is the run
//! boundary — concurrent runs cannot mix their ops, durations or pool gauges,
//! and a re-apply served entirely from `CachedMappings` starts from zeros
//! instead of inheriting an earlier run's leftovers.
//!
//! Per-call percentiles need no histogram here: every write also logs
//! `histogram.mapping_acquire_duration` / `histogram.mapping_statement_duration`
//! (the same shape the event store uses for `append_emappend_duration`), so
//! p50/p95 come from the log lines while the sums come from the counters.

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

/// One run's absolute counter values. Ops and durations are sums, the pool
/// fields are gauges (the latest observation, never a sum).
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

/// The counters of one apply run (see [`scope_mapping_writes`]).
///
/// Atomics keep the reader side trivial and the type a plain value, so tests
/// can exercise it without touching shared state.
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

tokio::task_local! {
    static MAPPING_WRITES: MappingWriteCounters;
}

/// Feed the current script-apply task's counters, if inside
/// [`scope_mapping_writes`]. Calls outside a scoped script apply (such as
/// `ScheduleApplyWorker` or standalone repository tests) are a no-op here
/// and still emit their per-write log line.
pub(crate) fn record_mapping_write(
    op: MappingWriteOp,
    acquire: Duration,
    statement: Duration,
    pool_size: u32,
    pool_num_idle: usize,
) {
    let () = MAPPING_WRITES
        .try_with(|counters| {
            counters.record(op, acquire, statement, pool_size, pool_num_idle);
        })
        .unwrap_or(());
}

/// Run `future` with fresh task-local [`MappingWriteCounters`] and return
/// both its output and the run's own [`MappingWriteSnapshot`].
pub(crate) async fn scope_mapping_writes<F, T>(future: F) -> (T, MappingWriteSnapshot)
where
    F: std::future::Future<Output = T>,
{
    MAPPING_WRITES
        .scope(MappingWriteCounters::new(), async move {
            let output = future.await;
            let snapshot = MAPPING_WRITES
                .try_with(MappingWriteCounters::snapshot)
                .unwrap_or_default();
            (output, snapshot)
        })
        .await
}

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
        // The log value the field is grouped by.
        assert_eq!(MappingWriteOp::Reserve.as_str(), "reserve");
        assert_eq!(MappingWriteOp::Insert.as_str(), "insert");
    }

    #[tokio::test]
    async fn scope_isolates_concurrent_runs_and_starts_empty() {
        // Outside any scope a write is a no-op, not a panic and not a leak
        // into whichever run happens to be scoped next.
        record_mapping_write(
            MappingWriteOp::Insert,
            Duration::from_millis(100),
            Duration::from_millis(100),
            7,
            0,
        );

        // Two runs interleaved on one task: the boundary a real apply relies on
        // is the scope, not the task's call sequence.
        let (((), a), ((), b)) = tokio::join!(
            scope_mapping_writes(async {
                record_mapping_write(
                    MappingWriteOp::Reserve,
                    Duration::from_millis(4),
                    Duration::from_millis(1),
                    20,
                    0,
                );
                tokio::task::yield_now().await;
                record_mapping_write(
                    MappingWriteOp::Insert,
                    Duration::from_millis(6),
                    Duration::from_millis(2),
                    20,
                    5,
                );
            }),
            // A re-apply served entirely from the cache: it must report zeros,
            // not the neighbouring run's numbers.
            scope_mapping_writes(async {
                tokio::task::yield_now().await;
            })
        );

        assert_eq!(a.reserve_ops, 1);
        assert_eq!(a.insert_ops, 1);
        assert_eq!(a.acquire, Duration::from_millis(10));
        assert_eq!(a.statement, Duration::from_millis(3));
        assert_eq!(a.pool_size, 20);
        assert_eq!(a.pool_num_idle, 5);

        assert_eq!(b, MappingWriteSnapshot::default());
    }
}
