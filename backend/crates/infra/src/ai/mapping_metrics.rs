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

use std::cell::Cell;
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
/// A plain `Cell<MappingWriteSnapshot>` is enough because the accumulator is
/// scoped to one task and Tokio polls a task on exactly one thread at a time
/// (all rows of one apply are awaited in the same task), so no counter is ever
/// read and written concurrently — no atomics, no torn reads.
impl MappingWriteSnapshot {
    /// Record one finished write: which call, how long the connection wait was,
    /// how long the statement took, and the pool's state in that instant.
    pub(crate) fn record(
        &mut self,
        op: MappingWriteOp,
        acquire: Duration,
        statement: Duration,
        pool_size: u32,
        pool_num_idle: usize,
    ) {
        match op {
            MappingWriteOp::Reserve => {
                self.reserve_ops = self.reserve_ops.saturating_add(1);
            }
            MappingWriteOp::Insert => {
                self.insert_ops = self.insert_ops.saturating_add(1);
            }
        }
        self.acquire = self.acquire.saturating_add(acquire);
        self.statement = self.statement.saturating_add(statement);
        // Gauges: the latest observation wins, never a sum.
        self.pool_size = pool_size;
        self.pool_num_idle = pool_num_idle;
    }
}

tokio::task_local! {
    static MAPPING_WRITES: Cell<MappingWriteSnapshot>;
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
        .try_with(|slot| {
            let mut snapshot = slot.get();
            snapshot.record(op, acquire, statement, pool_size, pool_num_idle);
            slot.set(snapshot);
        })
        .unwrap_or(());
}

/// Run `future` with fresh task-local counters and return both its output and
/// the run's own [`MappingWriteSnapshot`].
pub(crate) async fn scope_mapping_writes<F, T>(future: F) -> (T, MappingWriteSnapshot)
where
    F: std::future::Future<Output = T>,
{
    MAPPING_WRITES
        .scope(Cell::new(MappingWriteSnapshot::default()), async move {
            let output = future.await;
            let snapshot = MAPPING_WRITES.try_with(Cell::get).unwrap_or_default();
            (output, snapshot)
        })
        .await
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The snapshot lives in a `Cell`, which is `!Sync` — this pins the one
    /// property that makes that safe here: the scoped future stays `Send`, so
    /// `crates/api/src/apply_runner.rs` can keep spawning it in a `JoinSet`.
    #[allow(dead_code)] // Compile-time assertion only.
    fn assert_scope_future_is_send<T: Send>(_: T) {}

    #[test]
    fn counters_keep_the_two_calls_apart_and_sum_their_durations() {
        let mut snapshot = MappingWriteSnapshot::default();
        snapshot.record(
            MappingWriteOp::Reserve,
            Duration::from_millis(3),
            Duration::from_millis(1),
            20,
            4,
        );
        snapshot.record(
            MappingWriteOp::Insert,
            Duration::from_millis(5),
            Duration::from_micros(340),
            20,
            2,
        );

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
        assert_scope_future_is_send(scope_mapping_writes(async {}));

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
