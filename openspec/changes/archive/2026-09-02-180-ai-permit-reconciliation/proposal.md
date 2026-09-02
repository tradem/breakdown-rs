<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gpt-5.6-luna (pi) -->
<!-- Co-authored-by: longcat-2.0-free (opencode) -->

# Proposal: AI Import Permit Reconciliation and Atomic Claim (Issue #180)

## Context

Issue #180 asked for durable leases and recovery for AI import concurrency. The
leases themselves were delivered by issues #177 (job-level worker leases) and
#178 (cancellation-safe permits). What remains is the **reconciliation gap**:
when a worker crashes mid-job and a new worker reclaims the job, the old
worker's `concurrency_permit` row survives until its lease expires. The global
and per-user counters therefore stay inflated — capacity is lost for up to
`AI_IMPORT_LEASE_SECS` (default 900s) even though the job is already running
on a healthy worker.

A second gap is ordering. Capacity used to be acquired *before* the job was
claimed, which means acquiring before the owning user is known — the slot could
only be charged to a synthetic per-worker identity, so
`AI_IMPORT_MAX_CONCURRENT_JOBS_PER_USER` would never bind.

## Scope

This change delivers the three remaining acceptance criteria of #180:

1. **Recovery decrements counters exactly once**: a reclaimed job's orphaned
   permit is released by the reclaiming worker, in the same statement as the
   claim, rather than by the slow lease-expiry sweep.
2. **Claim, then acquire**: the job is claimed first so the permit can be
   charged to the job's own `user_id`, and the orphan is freed before the
   acquisition so a reclaiming worker is not refused the slot the dead worker
   still holds.
3. **Integration tests**: deterministic tests for the full crash-recovery
   path — worker termination, job reclaim, and counter reconciliation.

## Affected Files

- `backend/crates/core/src/ai/ports.rs` — four **defaulted** additions to
  `AiImportQueue`: `claim_next_reconciling`, `claim_next_kind_reconciling`,
  `attach_permit`, `release_claim`.
- `backend/crates/infra/src/ai/queue.rs` — Postgres implementations. The
  reconciling claims release the orphan as data-modifying CTEs of one
  statement; the legacy `claim_next` / `claim_next_kind` also clear
  `permit_id` so every claim path establishes the same invariant.
- `backend/crates/infra/src/ai/workers.rs` — `run_once_with_permit` on
  `ScriptImportWorker` / `ScheduleImportWorker`, built on the shared
  `acquire_for_claim` / `release_permit_logging_errors` helpers.
- `backend/crates/infra/migrations/20260811000000_ai_import_claim_with_permit.up.sql`
  — nullable `permit_id UUID` on `ai_import_job`.
- `backend/crates/integration-tests/tests/ai_import_permit_reconciliation.rs`
  — six tests against a real Postgres.

`pg_concurrency.rs` and `runtime.rs` are **not** modified: the permit
primitive and `AiWorkerRuntime` are unchanged by this design.

## Design

### 1. Job-permit link via `permit_id`

A nullable `permit_id UUID` column on `ai_import_job` records which
concurrency permit owns the current claim. No FK: the referenced permit may
already have been freed by the lease sweep in `try_acquire_as`, and an FK
would turn that ordinary race into a constraint violation.

### 2. Reconciling claim

`claim_next_reconciling` (and its kind-filtered twin) claims the next runnable
job and deletes the orphaned permit in **one statement**, as data-modifying
CTEs:

```sql
WITH next_job AS (
    SELECT id, permit_id AS orphan_permit_id
    FROM ai_import.ai_import_job
    WHERE <runnable predicate>
    ORDER BY created_at, id
    FOR UPDATE SKIP LOCKED LIMIT 1
),
claim AS (
    UPDATE ai_import.ai_import_job AS job
    SET status = 'running', worker_id = $1, permit_id = NULL,
        lease_expires_at = now() + make_interval(secs => $2), updated_at = now()
    FROM next_job WHERE job.id = next_job.id
    RETURNING job.*, next_job.orphan_permit_id
),
released AS (
    DELETE FROM ai_import.concurrency_permit
    WHERE id = (SELECT orphan_permit_id FROM claim)
    RETURNING id
)
SELECT claim.*, (SELECT id FROM released) AS released_permit_id FROM claim
```

All three writes share one snapshot and one implicit transaction, so the job
is never observed as reclaimed while the orphan is still counted.

> **Implementation note.** The first attempt expressed the release as
> `LEFT JOIN LATERAL (DELETE ... RETURNING id)`. That is not valid PostgreSQL —
> DML is permitted only in a `WITH` CTE — and every call failed at runtime with
> a syntax error, surfaced as an opaque `ServiceUnavailable` because
> `map_sqlx_error` deliberately redacts SQL detail (CWE-209). This was the
> defect that stalled the previous session.

### 3. Claim, then acquire

Capacity is acquired **after** the claim, and linked back with
`attach_permit`. Two properties depend on this order:

* **Correct per-user attribution.** The permit is charged to the job's own
  `user_id`. Acquiring first would mean acquiring before the owning user is
  known — the slot could only be charged to a synthetic per-worker identity,
  and `AI_IMPORT_MAX_CONCURRENT_JOBS_PER_USER` would never bind.
* **No self-inflicted deadlock.** The orphan is freed by the claim, before the
  acquisition. In the reverse order, a reclaiming worker at a saturated ceiling
  would be refused the very slot the dead worker is still holding, and the job
  could never make progress.

The window between claim and acquisition is covered by the job lease: a worker
that dies there leaves a `running` job that the reclaim predicate recovers, and
no permit to leak.

When the ceiling is saturated the claim is handed back with `release_claim`,
which resets the job to `pending` **without** incrementing `retries` — the job
never ran, so a full ceiling must not be able to walk a valid job to
`dead_letter`.

`attach_permit` and `release_claim` are owner-fenced like every other
worker-originated write: a displaced worker gets `Conflict` rather than
overwriting the new owner's link (which would make a later reclaim delete a
*live* permit).

### 4. Port defaults

All new `AiImportQueue` methods have default implementations — claim normally,
report no orphan, no-op — so in-memory and test queues, which have neither a
permit link nor a lease, need no change. This keeps the trait addition
non-breaking.

### 5. Tests

`crates/integration-tests/tests/ai_import_permit_reconciliation.rs`, six tests
against a real Postgres:

1. `reclaim_releases_the_orphaned_permit_exactly_once` — the global counter
   returns to one live permit, not two.
2. `reclaim_of_an_already_freed_orphan_does_not_double_decrement` — an orphan
   already freed by the lease sweep is a no-op, never a second decrement.
3. `reclaim_reconciles_the_owning_users_counter` — the permit is charged to
   `job.user_id`, the per-user ceiling binds, and the recovered slot is
   genuinely usable again.
4. `no_claimable_job_means_no_permit_is_released` — a live lease releases
   nothing.
5. `a_returned_claim_is_runnable_again_and_not_charged_a_retry`.
6. `lifecycle_writes_are_owner_fenced`.

The tests expire only the **job** lease, never the permit lease: expiring the
permit would let `try_acquire_as`'s own sweep free the orphan, and the tests
would pass while asserting nothing about the code under test. Expiry is always
written into the past, never slept out.

## Version Bumps

| Crate | Previous | New | Bump type | Reason |
|---|---|---|---|---|
| `core` | 0.7.0 | 0.7.0 | none | New `AiImportQueue` methods are additive **and defaulted**; 0.7.0 is still unreleased, so the entry folds into it |
| `infra` | 0.11.0 | 0.12.0 | MINOR | New public queue API + `permit_id` column and migration |
| `api` | 0.6.0 | 0.6.1 | PATCH | Re-pin to `infra` 0.12.0; no public API change |

## Risks

- **Migration downtime**: adding a nullable UUID column is a metadata-only
  change in Postgres 16; no table rewrite.
- **Unwired workers**: `run_once_with_permit` has no production caller yet —
  no worker loop exists, and `main.rs` has no `with_graceful_shutdown` to hang
  one off. Wiring is owned by **#214**, which also covers the `PermitReclaimer`
  shutdown ordering the loop would need. Deliberately out of scope here: adding
  a worker loop without that ordering would either hang shutdown on a live
  channel sender or silently downgrade reclaims to lease-only (AGENTS.md §6).
