<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Proposal: Projector dead-letter + health signal (issue #37)

## Summary

A permanently unprocessable event (e.g. a Postgres FK violation 23503 from a
command that referenced a non-existent character) currently loops the projector
forever: worker retries 5×, epoch fails, supervisor restarts, checkpoint never
advances, category is stalled with only `tracing::error!` lines as a trace.
#404 shipped a log-only skip for four *known* 23505 constraints; this change
completes the #37 target state from the cross-aggregate invariant doctrine:
**classification + durable dead-letter + checkpoint advance + health signal**.

## Change

1. **kameo_es processor patch** (`.patches/kameo_es`, already a path dep):
   after the worker's in-loop retry budget (5×) is exhausted on one event,
   classify the final error. **Permanent** (SQLSTATE class 23/22, event
   deserialization failures, parse failures) → dead-letter path. **Transient**
   (connection, Sierra/Redis, pool, serialization-failure 40001, deadlock
   40P01) → unchanged propagate/restart behavior.
2. **Dead-letter path**: in one transaction on the pooled connection, (a)
   upsert an idempotent row into a new `projection_dead_letter` table and (b)
   advance the projector's `sierradb_event_checkpoints` checkpoint past the
   event; update in-memory handled/flushed maps; continue with the next event
   (no restart, no stall). Log `tracing::error!` with issue #37 marker.
3. **Classification seam**: new kameo_es trait `EventErrorClassify`
   (`is_permanent_event_error`) implemented for `sqlx::Error` (all repo
   projector handlers use `H::Error = sqlx::Error`); unknown error types
   default to transient (conservative — old behavior).
4. **Infra health signal**: `crates/infra/src/projectors/health.rs` —
   `ProjectorHealthRepository` reading (a) dead-letter entries and (b)
   per-projection checkpoint progress, as the programmatic operator surface.
   Documented `psql` query in `docs/operations/runbooks.md` so an operator can
   detect a stuck projector without grepping logs. (HTTP endpoint intentionally
   deferred — no ops-admin authorization surface exists yet; follow-up issue.)

## Non-goals

- No HTTP ops endpoint (needs a new authorization capability — follow-up).
- No physical cleanup of dead-lettered event streams in SierraDB (optional,
  documented in runbooks; not automated).
- No change to the #404 savepoint-skip for the four known constraints — it
  stays (finer-grained: keeps the authoritative projection row); the DLQ
  catches everything the handler-level skip does not handle.

## Validation

- Unit tests: classification matrix (permanent vs transient per SQLSTATE /
  variant) in the patched crate.
- Tier-4 integration test (testcontainers): costume assigned to a never-created
  character → 23503 → DLQ row present, checkpoint advanced past the event,
  projection continues (trailing event of the stream still processed).
- `cargo check --workspace`, `cargo test -p infra -p kameo_es`, clippy clean.
