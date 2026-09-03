<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (opencode-go) -->
<!-- Co-authored-by: longcat-2.0-free (opencode) -->
<!-- Co-authored-by: hy4-preview (opencode-go) -->

# Changelog

All notable changes to the `infra` crate are documented here. Versioning
follows per-crate Semantic Versioning (ADR-020 D2); this changelog is the
crate-level companion to the release notes generated from conventional
commits (ADR-020 D5).

## [Unreleased]

### Fixed — Membership projection stores plain `role` / `state` tokens (issue #342)

- `projectors::membership` wrote `serde_json::to_string(&role)` and
  `serde_json::to_string(&state)`, so the columns contained
  `"costume_assistant"` and `"active"` — while every membership authorization
  predicate compares `m.state = 'active'` and
  `m.role IN ('costume_designer', 'wardrobe_supervisor', 'costume_assistant')`.
  **No row could ever match**, so `has_active_costume_role_in_season`,
  `has_active_report_archive_role_in_season` and
  `has_active_credential_role` always returned `false` and every photo,
  continuity-photo, PDF/JSON report, manual-archive, AI-import and credential
  handler denied every caller with `403`.
- The projector now writes the bare token (`Role::as_str` /
  `MembershipStateKind::as_str`) and `map_membership_row` parses it with
  `from_token`, rejecting unknown values loudly instead of defaulting. The
  SQL predicates are unchanged and now match.
- **No data migration:** the backend is not in production, so development
  databases are re-seeded. Rows written by the previous projector are
  rejected by `from_token` rather than mis-read.

### Added — `has_active_membership_in_series` (issue #342)

- `MembershipRepositoryImpl` implements the new series-scoped predicate: a
  single join `projection_membership → projection_block` on the indexed
  `projection_block.series_id`, filtered to `state = 'active'`. Static SQL,
  all values bound.

## [0.14.0] - 2026-08-23

### Changed — Bump MSRV to 1.98 (issue #257)

- **Breaking (MAJOR, ADR-020 D2/D3):** `rust-version` raised from `1.94` to `1.98` (workspace floor + Dockerfile builder `rust:1.98-bookworm`). Re-pinned to `breakdown_core` 0.9.0 (cascade).

## [0.13.0] - 2026-08-13

### Changed — Consume the structured `DomainError` surface (issue #230)

Adapters, projectors and sagas construct `DomainError` with the typed
registry-carrying variants instead of interpolated strings; read-model 404s
are upgraded to per-context codes (e.g. `character.not-found`). No
behavioural change beyond the error identity.

- **Breaking (cascade):** re-pinned to `breakdown_core` 0.8.0 (ADR-020 D3);
  infra bumps 0.12.0 → 0.13.0.

### Changed — Retry LLM responses truncated at the output-token budget

`OpenAiCompatibleChatClient` now inspects the provider `finish_reason`: a
response cut off at the caller's `max_tokens` ceiling (`finish_reason:
"length"`, unparseable JSON) is retried in-loop with a doubled output-token
budget, bounded by `MAX_TRUNCATION_RETRIES` (2). Previously such a response
failed permanently although a larger budget would have succeeded — this is
what broke the AI Import Nightly smoke on 2026-08-13 (`EOF while parsing an
object at line 1 column 1158`). Genuinely malformed JSON (`finish_reason:
"stop"` or absent) is still a permanent validation error: re-paying a paid
call on arbitrary malformed output is a cost risk, not a recovery. Budget
growth saturates at the `u32` ceiling, so the worst-case spend of one call
stays bounded (budgets `B, 2B, 4B` at most).

## [0.12.0] - Unreleased

### Added — Route non-CSV schedule imports through the LLM (issue #221)

- `ScheduleImportWorker` derives the extraction path from the job's persisted
  `source_format` instead of a caller-supplied `native_csv` flag: CSV stays on
  the native parser, `plain_text` goes straight to the LLM, and `pdf` is
  extracted to text with the same bounded `PdfTextExtractor` as the script
  worker before the LLM call. The flag is gone from `process`, `run_once` and
  `run_once_with_permit` — the worker loop and the processor cannot disagree
  anymore.
- New column `ai_import.ai_import_job.source_format` (NOT NULL, CHECK
  `('csv','pdf','plain_text')`). Legacy schedule rows backfill to `csv` (their
  previous routing) and script rows to `pdf`, so the claim path keeps working
  across the migration.
- **Breaking:** `ScheduleImportWorker` gains a required `extractor:
  PdfTextExtractor` field.

### Added — AI import worker loops wired through the concurrency limiter (issue #214)

The `PgAiConcurrencyLimiter` / `AiWorkerRuntime` were public API that nothing
constructed; jobs never consumed a permit and the `AI_IMPORT_MAX_CONCURRENT_JOBS_*`
ceilings were documentation only. This change adds the worker-loop side:

- New module `ai::worker_loop` with `spawn_script_import_worker` /
  `spawn_schedule_import_worker`. Each loop claims a job (reconciling orphaned
  permits via `claim_next_kind_reconciling`), resolves the job's per-user AI
  config + vaulted API key, builds the provider-matching LLM client, and routes
  the job through `AiWorkerRuntime::run_job_as` so the permit lifecycle
  (acquire → renew → release) and the `AiJobGuard` tracked for `drain()` are
  managed in one place. A saturated ceiling returns the claim unrun instead of
  acquiring first.
- `AiConfigRepositoryImpl::find_worker_config` resolves the active AI config
  (provider, model, prompt, vault reference) for a user + document kind — the
  job carries `user_id` but not a config id.
- `ScriptImportWorker` / `ScheduleImportWorker` no longer generic over the
  preview store (`S`); `previews` is now `Arc<dyn AiPreviewStore>`, which is
  what the production composition root already holds.

### Added — Per-payload cleanup state for the AI payload GC sweep (issue #206)

The sweep now records a completion mark per payload, so it makes progress
instead of re-selecting the same head of the queue on every run.

- New table `ai_import.ai_payload_cleanup`, keyed `(job_id, payload_kind)`.
  Each row records a *cleanup outcome* for one payload: a successful deletion
  **and** a not-found result (the goal state — the object is gone — holds for
  both, and a terminal job can never be re-claimed to recreate it). The row
  stores the `handle` that was targeted, the `run_id` of the sweep that
  recorded the mark, and `cleaned_at`. A job's two payloads are tracked
  independently, so a sweep that deleted the source but hit a 503 on the
  preview comes back for the preview only.
- `TERMINAL_JOBS_SQL` anti-joins the marks and selects a job only while it
  still owes a payload. Previously it returned the oldest `batch_size`
  terminal jobs unconditionally: deletions are idempotent so nothing was
  corrupted, but every run re-paid the S3 round-trips, re-counted the same
  deletions into `projection_ai_payload_gc_run`, and never advanced past the
  `LIMIT` — a job behind that parked head could outlive its retention window
  indefinitely.
- Marks are written only for deletions that actually happened. A **dry run**
  marks nothing (a mark hides the payload from every future real sweep, so
  marking in observation mode would leak exactly the objects being previewed),
  and a **failed** deletion marks nothing (so it is retried). A **not-found**
  result *is* marked: the goal state holds, and a terminal job can never be
  re-claimed to recreate the payload.
- Marks are flushed before the run-history row and before the early return on
  the first deletion error, so one failure in a batch cannot discard the marks
  its siblings earned.
- `run_gc_sweep` / `spawn_gc_scheduler` / `delete_payload` are now generic over
  `AiPreviewStore + AiDocumentStore` instead of taking the concrete
  `OpenDalAiPayloadStorage`. This is the port dependency the sweep always
  should have had, and it is what lets the partial-batch test inject a
  per-handle deletion failure — Garage accepts every malformed key and reports
  a delete of a nonexistent object as success, so the failure cannot be
  produced through the real adapter without failing the whole batch.
- New migration pair `20260813000001` (table) and `20260813000002` (partial
  index `idx_ai_import_job_retention` on `(updated_at)` covering only
  `status IN ('succeeded', 'dead_letter', 'payload_unavailable')`, built
  `CONCURRENTLY` in its own `-- no-transaction` file). The sweep previously had
  no usable index for its `updated_at` ordering; that was tolerable only while
  it re-read a parked head.

### Changed — Deterministic schedule-apply ids close the retry crash window (issue #182)

`ScheduleApplyWorker` now derives `ShootingDayId` and `SceneShootId`
deterministically from `(preview_id, draft_ref)` via SHA-256 (truncated to
128 bits, tagged with the version-7 / variant-10 bits) instead of generating
random UUIDs. A retry after a command succeeds but its mapping write fails now
re-derives the *same* id, so the aggregate's `ExpectedVersion::Empty` guard
rejects the duplicate (`VersionConflict { current }`, recovered as success by
`recover_version`). Previously the mapping projection was the only duplicate
guard, so a lost reservation row let a retry create a duplicate aggregate. The
mapping projection is preserved as the retry lookup and audit record. This is
the one documented exception to the repository UUIDv7 rule (AGENTS.md §3): a
time-based UUIDv7 cannot be derived from static inputs. Three deterministic
tests cover both crash-window paths (day + scene-shoot) and verify id stability
independent of the mapping projection.

### Added — AI import restart-recovery semantics (issue #181)

Durable payload storage (#174) made a restart survivable; this release defines
what happens when a payload is nonetheless missing, and stops cleanup from
causing that case.

- `PgAiImportQueue::mark_payload_unavailable`: owner-fenced terminal transition
  to `payload_unavailable`. `retries` is left untouched and no
  `next_attempt_at` is set — this is not an attempt that failed, it is the
  discovery that there is nothing left to attempt. Claim, lease and permit link
  are cleared like on every other terminal path, so no reclaim can resurrect
  the job. The claim predicates enumerate `pending` / `failed` /
  expired-`running`, so the new status is unclaimable by construction.
- `ScriptImportWorker` / `ScheduleImportWorker`: a payload load that fails with
  `NotFound` now terminates the job as `payload_unavailable` instead of
  consuming a retry. `ServiceUnavailable` (storage unreachable, bytes probably
  still there) stays retryable — the distinction is the whole point.
- `QueueMergeWorker`: **behaviour change.** A missing schedule preview blob was
  marked `retryable = true`, so a permanently lost payload burned the entire
  retry budget before dead-lettering. It is now terminated as
  `payload_unavailable` on the first attempt.
- **Payload GC retention fix.** The sweep matched `status IN ('succeeded',
  'failed', 'dead_letter')`, but `failed` is the *retryable* state: a job sits
  there with a backoff and is claimed again once it is due. The sweep therefore
  deleted the source document of jobs that were still scheduled to run,
  manufacturing the missing-payload case above. The sweep now matches exactly
  `succeeded`, `dead_letter` and `payload_unavailable`.
  `failed` is excluded **unconditionally**, not merely while it has retry
  budget left: the claim predicates match `status = 'failed' AND
  (next_attempt_at IS NULL OR next_attempt_at <= now())` and never consult
  `retries`, so even a budget-exhausted `failed` row is still claimable.
  Nothing leaks, because `mark_failed` dead-letters a job in the same statement
  that exhausts its budget.
- `UnconfiguredAiPayloadStore`: null-object `AiPreviewStore` / `AiDocumentStore`
  / `AiDocumentSource` that refuses every operation with `ServiceUnavailable`
  (never `NotFound`, which is the signal that permanently dead-ends a job). It
  replaces `MemoryAiPreviewStore` in the composition root when AI import is
  disabled, so a production process can no longer hold a store that accepts
  payloads and silently drops them on restart. `MemoryAiPreviewStore` remains,
  for unit tests only.
- Two new migrations extend the `status` CHECK constraint **without blocking
  writes**, split deliberately across files because sqlx wraps each migration
  in one transaction:
  `20260812000001_ai_import_payload_unavailable` adds the widened constraint
  `NOT VALID` (a fast catalog-only change) and commits, releasing the
  ACCESS EXCLUSIVE lock that `ADD CONSTRAINT` takes;
  `20260812000002_ai_import_payload_unavailable_validate` then runs
  `VALIDATE CONSTRAINT` in its own transaction — verified to take only
  `ShareUpdateExclusiveLock`, so enqueue, claim and lifecycle writes continue
  during deployment — and swaps the constraint names. Validating in the same
  file would have held the exclusive lock across the scan, defeating the point.
  The `002` down migration folds `payload_unavailable` rows into `dead_letter`
  — the closest pre-#181 state that is both terminal and unclaimable — before
  restoring the narrow constraint.

### Added — AI import permit reconciliation (issue #180)

A worker that dies mid-job leaves two leases behind: the job lease (recovered
by the reclaim predicate, #177) and the concurrency permit lease (recovered
only when it lapses, up to `AI_IMPORT_LEASE_SECS` later). The second one is
capacity consumed by a job that is already running elsewhere. This release
closes that gap.

- `AiImportQueue::claim_next_reconciling` / `claim_next_kind_reconciling`:
  claim the next runnable job **and** delete the permit orphaned by the worker
  that previously held it, as data-modifying CTEs of one statement. Returns
  `(job, released_orphan_id)`. Reconciliation is exactly-once — only the
  winner of the `FOR UPDATE SKIP LOCKED` race sees a non-null orphan id and
  the DELETE is by primary key. Both have default implementations that claim
  normally and report no orphan, so backends with no permit link (in-memory,
  test queues) need no change.
- `AiImportQueue::attach_permit`: link the acquired permit to the claim.
  Owner-fenced, so a displaced worker cannot overwrite the new owner's link
  and cause a later reclaim to delete a *live* permit.
- `AiImportQueue::release_claim`: hand a claimed job back unrun without
  charging a retry, used when the concurrency ceiling is saturated. Prevents a
  full ceiling from walking a valid job to `dead_letter`, and makes the job
  runnable immediately rather than after its lease lapses. Owner-fenced.
- `ScriptImportWorker::run_once_with_permit` /
  `ScheduleImportWorker::run_once_with_permit`: **claim, then acquire**, with
  both leases renewed for the whole run — the permit lease via
  `run_with_renewal`, the job claim via a `LeaseHeartbeat` started *before*
  the source load, so a slow document fetch cannot expire the claim underneath
  a working worker. The
  permit is charged to the job's own `user_id`, so
  `AI_IMPORT_MAX_CONCURRENT_JOBS_PER_USER` actually binds; acquiring first
  would mean acquiring before the owning user is known. The orphan is freed by
  the claim, *before* the acquisition, so a reclaiming worker is not refused
  the very slot the dead worker is still holding.
- Every claim path now clears `permit_id`, and every terminal write
  (`mark_succeeded`, `mark_failed`, `release_claim`) clears it again, so the
  link never outlives the claim it describes. This matters most on
  `mark_failed`'s retryable branch: the job stays claimable, so a stale id
  would be read by the next reclaim and deleted — freeing a permit the worker
  already released, and whose id may since belong to someone else. Otherwise a legacy reclaim would carry the dead worker's permit id
  forward and a later reconciling reclaim would delete a permit the current
  owner never attached.
- `ai_import_job` gained a nullable `permit_id UUID` column. No FK: the
  referenced permit may already have been freed by the lease sweep, and an FK
  would turn that ordinary race into a constraint violation.
- New migration `20260811000000_ai_import_claim_with_permit.{up,down}.sql`.

### Fixed — Retry-safe schedule-side scene-shoot apply (issue #179)

- `ScheduleApplyWorker` wrote its idempotency mapping only *after*
  `CreateShootingDay` / `PlanSceneShoot` succeeded. A crash (or a failing
  mapping write) in between left no mapping, so the retry minted a fresh
  `SceneShootId` and dispatched a **second** `PlanSceneShoot`. Because scene
  shoots are keyed by stream identity, the aggregate's `PairAlreadyExists`
  invariant did not catch it — the duplicate only surfaced later at the
  `uq_projection_scene_shoot_pair` constraint, i.e. after the duplicate event
  was already business truth. `resolve_day` had the identical window.
- The worker now follows a **reserve → command → confirm** protocol. The
  aggregate id is persisted as a reservation row (`aggregate_version = 0`)
  *before* the command, so every retry re-drives the *same* aggregate. Both
  commands dispatch with `ExpectedVersion::Empty`, so re-driving an
  already-appended stream returns `VersionConflict { current }` — the worker
  recovers `current` as the version the mapping needs and confirms. A conflict
  reporting version 0 (a genuinely empty stream) is **not** treated as
  recovery and propagates as an error. A still-reserved mapping no longer
  counts as applied work, so the row is re-driven rather than skipped.
- `PgAiImportMappingRepository::reserve` implements the insert-if-absent
  semantics with `ON CONFLICT ... DO UPDATE ... RETURNING` (a plain
  `DO NOTHING` returns no row on conflict, which would force a second round
  trip racing a concurrent confirm). The checked `u64 -> i64` version
  conversion is factored into `version_to_db` and shared with `insert`.

### Fixed — Cancellation-safe AI concurrency permits (issue #178)

- `AiWorkerRuntime::run_job` holds a permit across `operation().await`, which
  is a cancellation point. `Drop` cannot `.await`, so a worker cancelled during
  shutdown never ran `PgAiConcurrencyPermit::release()` and the anonymous
  `ai_import.concurrency_counter` stayed incremented forever. Because the
  increment had no owner, a leaked unit of capacity was indistinguishable from
  a busy one — later AI import jobs were refused admission until an operator
  repaired the row by hand.
- Capacity is now one owned row per permit in the new table
  `ai_import.concurrency_permit` (migration
  `20260810000001_ai_concurrency_permit`), which replaces and drops
  `concurrency_counter`. Owned rows make two reclaim paths possible:
  - **Reclaimer (fast path).** `PgAiConcurrencyLimiter::spawn_reclaimer`
    starts a background task; every permit's `Drop` pushes its id onto an
    unbounded channel (synchronous, non-blocking — the only thing `Drop` can
    do) and the task performs the `DELETE`. Task cancellation therefore returns
    capacity within milliseconds. `PermitReclaimer::shutdown` **drains** the
    queue before returning: shutdown is when workers are cancelled en masse, so
    the queue is fullest exactly when the reclaimer ends, and aborting there
    would push those reclaims back onto the 900s lease. Shutdown order:
    every sender clone must be gone before the channel closes, and permits
    hold one too — so the composition root (1) cancels **and joins** every
    task that may hold a permit, (2) drops every limiter clone, (3) awaits
    `shutdown()`. Skipping a step leaves a live sender and the call would wait
    forever; `abort()` and `Drop` remain for callers that cannot guarantee the
    ordering or cannot await.
  - **Lease (crash safety).** Each row carries `expires_at`. If the process
    dies the reclaimer dies with it, so acquisition first deletes every expired
    row and then counts. The leak is bounded by one lease window with no
    operator action; `PgAiConcurrencyPermit::renew` (interval from
    `permit_renewal_interval`, 1/3 of the window, mirroring `LeaseHeartbeat`)
    keeps legitimately long holders alive. Expiry is **irreversible**: `renew`
    is guarded by `AND expires_at > now()`, so a delayed holder cannot claw
    back a lease the limiter is already entitled to sweep and then hold
    capacity past its own deadline — it gets `Conflict` instead.
  All three paths are `DELETE ... WHERE id = $1`, so double-release is
  impossible by construction. `release()` disarms the drop hook only after a
  *confirmed* delete — its `await` is itself a cancellation point, and an early
  disarm would strand the row until the lease expired.
- `AiWorkerRuntime::run_job` renews the permit while the operation runs
  (`permit_renewal_interval`, 1/3 of the lease). A script job makes one LLM
  call per scene chunk — at defaults up to 128 calls of up to 120s — so without
  renewal the sweep would reclaim a *healthy* holder's row and admit a second
  job on top of it, over-admitting past the very ceiling the limiter enforces.
  The renewal is a `select!` loop in the operation's own task rather than a
  spawned heartbeat: it needs only a `&` borrow (no `Arc`/clone) and is
  inherently cancellation-correct, with nothing to join or abort. A `Conflict`
  aborts the operation — continuing would run on capacity the limiter has
  already handed to someone else. A transient renewal error is retried, but
  **only inside the lease the last confirmed renewal bought**: the loop tracks
  the confirmed deadline, never sleeps past it, bounds the renewal call itself
  with `timeout_at`, and aborts *before* it rather than after — otherwise a run
  of slow failures would carry the job past the point where its row becomes
  reclaimable. The state machine is unit-tested on tokio's paused clock (renews
  across five intervals, aborts on `Conflict`, survives a blip, extends the
  deadline on every confirmation, aborts before expiry under sustained slow
  failures, and never renews for a job shorter than one interval).
- New `PgAiConcurrencyPermit::deadline` exposes the lease deadline, so a holder
  can check its remaining headroom and operational tooling can surface
  "capacity at risk" without reading the table.
- All lease decisions use `clock_timestamp()`, not `now()`. `now()` is fixed at
  transaction start, and the acquisition transaction begins *before* the
  advisory-lock wait — under contention it would judge leases against a stale
  instant, missing rows that have since expired and issuing permits whose
  window silently started before the caller held the lock.
- The permit (and therefore its reclaim hook) is constructed **before**
  `tx.commit()`. `commit()` is an await point and a cancellation there is not
  benign: the COMMIT may already have reached PostgreSQL, so constructing the
  permit afterward would leave a durable row with no local owner — the exact
  leak this module removes, reintroduced at the last possible instant.
- Admission is serialised with `pg_advisory_xact_lock`: counting rows and
  inserting the new one must be atomic, and a row-level lock cannot cover a row
  that does not exist yet, so two concurrent acquisitions could otherwise both
  observe `count < limit` and over-admit.
- Both lease bounds derive from one named `LEASE_UNIT_SECS` (mirroring the
  claim-lease constants in `ai::queue`), with two compile-time assertions: the
  floor/default ordering, and that a renewal still fits strictly inside even
  the *shortest* permitted lease — so raising `RENEWALS_PER_LEASE` or lowering
  the floor cannot silently invert the relationship.
- New additive API: `PgAiConcurrencyLimiter::{spawn_reclaimer, with_lease,
  lease, try_acquire_as, in_flight}`, `PgAiConcurrencyPermit::{id, lease, renew}`,
  `AiWorkerRuntime::run_job_as`, `PermitReclaimer::{shutdown, abort}`,
  `permit_renewal_interval`, `DEFAULT_PERMIT_LEASE`,
  `PgAiConcurrencyPermit::deadline`. `try_acquire`, `release` and `run_job`
  keep their signatures; `run_job` additionally renews the lease it holds.
- Covered by `integration-tests/tests/ai_concurrency_permit_cancellation.rs`:
  a task aborted after acquisition leaves no permit row and the next job
  acquires the capacity; the lifecycle guard does not survive cancellation;
  normal completion and operation errors both release exactly once with the
  result/error preserved; an expired lease is reclaimed by the next
  acquisition; `renew` moves a live deadline forward but reports `Conflict`
  once the permit is expired or swept; `PermitReclaimer::shutdown` drains
  queued reclaims rather than discarding them; and cancelling `try_acquire`
  itself strands no permit. The last test sweeps 40 increasingly late
  cancellation points as best-effort *coverage* of the commit window, not as a
  timing assertion: the invariant it checks (capacity returns without a lease
  wait) must hold for every cancellation point, so no iteration has to land in
  a particular microsecond. Lease expiry is written into the past rather
  than slept out, keeping the suite timing-safe.

### Changed

- Re-pins `breakdown_core` to 0.7.0 (owner-fenced `AiImportQueue` lifecycle
  methods, issue #177).
- **Breaking (source):** `ScriptImportWorker::process` / `::process_text` and
  `ScheduleImportWorker::process` take the claiming `worker_id`, which they
  forward to the now owner-fenced lifecycle writes. `run_once` is unchanged
  (it already received `worker_id`).

### Added — Lease heartbeat for long AI import jobs (issue #177)

- New `ai::heartbeat` module (`LeaseHeartbeat`). A script job makes one LLM
  call per scene chunk — at defaults up to 128 calls of up to 120s, i.e. ~4.3h
  — while the lease is 900s, so the claim would lapse after roughly seven
  chunks and another worker would redo all the paid LLM work. The heartbeat
  renews the claim via the owner-fenced `mark_running` at 1/3 of the lease
  window (two spare renewals absorb a transient database blip).
- The renewal task is stopped before the terminal write and aborted on `Drop`,
  so an early `?` return cannot leak it. Because renewal is owner-fenced it can
  never resurrect a lost claim — it stops and flags `claim_lost`, and the
  script loop then aborts with `Conflict` instead of spending on an LLM call
  for a job it no longer owns.
- The heartbeat is skipped where it cannot help: native-CSV schedule parsing
  and the pure in-process merge are not long-running.
- The `claim_lost` state machine is unit-tested against a scripted queue on
  tokio's paused clock (`start_paused` + `time::advance`), so renewal ticks are
  driven instantly instead of slept out: a `Conflict` renewal flags the claim
  and stops further renewals, a transient error does neither, and `stop()`
  ends renewals before a terminal write. The tests synchronise on a renewal
  notification rather than on a `yield_now()` budget, so they cannot pass or
  fail on scheduler timing.

### Added — Owner fencing for AI import lifecycle writes (issue #177)

- `mark_running`, `mark_succeeded` and `mark_failed` fence their UPDATE on
  `status = 'running' AND worker_id = $N` and return `DomainError::Conflict`
  when no row matches. Reclaiming an expired lease means two workers can
  briefly run the same job; without the fence the displaced worker would
  overwrite the new owner's result (stale `preview_handle`, or failing a job
  another worker just completed). The rejection is logged with the job and
  worker id rather than silently swallowed.
- Because the claim is released on completion, the fence also makes a
  duplicate completion of an already-terminal job a `Conflict` instead of a
  silent overwrite.
- Worker telemetry is fenced too, via the new `record_worker_telemetry`. The
  unfenced `record_telemetry` is retained for the API apply path (terminal job,
  no claim). Both share one `TelemetryValues` conversion so their range checks
  cannot drift.
- `PgAiImportQueue` implements `lease_window()`, which is how workers obtain
  the interval for their heartbeat.

### Added — Worker leases for AI import jobs (issue #177)

- `PgAiImportQueue` now persists the claiming `worker_id` and a
  `lease_expires_at` deadline on every claim. A job whose worker crashed no
  longer stays in `running` forever: once the lease expires, `claim_next` and
  `claim_next_kind` reclaim it atomically (same `FOR UPDATE SKIP LOCKED`
  statement that flips the status), while an unexpired lease keeps a second
  worker out.
- `mark_running` doubles as a lease heartbeat; `mark_succeeded` and
  `mark_failed` release the claim (`worker_id`/`lease_expires_at` set to NULL)
  so `running` stays the only leased state.
- New builder `PgAiImportQueue::with_lease` plus accessor
  `PgAiImportQueue::lease` (MINOR, additive API).
- New environment variable `AI_IMPORT_LEASE_SECS`. An out-of-range *number* is
  clamped to the nearest bound (`30..=86400`); only an absent or unparsable
  value falls back to the `900` default.
- The three bounds derive from one named `LEASE_UNIT_SECS` constant (the
  report-archival recovery horizon) with a compile-time ordering assertion, so
  retuning the horizon cannot silently invert the range.
- Migration `20260809000001_ai_import_worker_lease` adds the two columns and
  expires pre-existing `running` rows so legacy strays become recoverable on
  the first claim. The follow-up migration
  `20260809000002_ai_import_lease_index` builds the
  `(status, lease_expires_at)` index with `CREATE INDEX CONCURRENTLY` so the
  build never blocks writes to `ai_import_job`. It is a separate,
  `-- no-transaction` migration on purpose: sqlx sends a migration file as one
  multi-statement simple query, which Postgres wraps in an implicit
  transaction, and `CONCURRENTLY` cannot run inside a transaction block.

## [0.10.0] - Unreleased

### Changed

- Re-pins `breakdown_core` to 0.6.0 (fallible `AuthorizationPolicy` checks,
  issue #175). No `infra` code change.

### Added — AI payload cleanup worker (issue #198)

- New `ai::payload_cleanup` module with periodic garbage collection for
  AI import payloads in Garage. Deletes source documents and preview
  payloads for terminal-state jobs (succeeded/failed/dead_letter) after
  a configurable grace period (default: 7 days).
- Advisory-locked sweep prevents concurrent cleanup runs.
- Dry-run mode for safe initial rollout (`AI_PAYLOAD_GC_DRY_RUN=true`).
- History table `projection_ai_payload_gc_run` tracks cleanup runs.
- New `AiPayloadGcConfig` type for cleanup configuration.
- Environment variables: `AI_PAYLOAD_GC_ENABLED`, `AI_PAYLOAD_GC_INTERVAL_SECS`,
  `AI_PAYLOAD_GC_MAX_AGE_SECS`, `AI_PAYLOAD_GC_BATCH_SIZE`, `AI_PAYLOAD_GC_DRY_RUN`.
- Re-pins `infra` to 0.10.0 (new ai::payload_cleanup module; MINOR bump).

## [0.9.0] - Unreleased

### Added — Durable AI payload storage (issue #174)

- New `ai::payload_storage` module with `OpenDalAiPayloadStorage` adapter
  that stores source documents and preview payloads in S3-compatible
  object storage (Garage). Replaces `MemoryAiPreviewStore` in production.
- New `AiDocumentStore` trait with `put_source`, `get_source`,
  `delete_source` methods for storing source documents separately from
  preview payloads.
- Source documents and preview payloads now survive API restarts: pending
  jobs can resume, retries can reload source documents, and succeeded
  jobs continue serving previews.
- Environment variables: `AI_PAYLOAD_S3_ENDPOINT`, `AI_PAYLOAD_S3_ACCESS_KEY`,
  `AI_PAYLOAD_S3_SECRET_KEY`, `AI_PAYLOAD_S3_BUCKET`, `AI_PAYLOAD_S3_TLS_ROOT_CERT`.
- Integration test `ai_payload_storage_round_trip` verifies restart-recovery
  behavior and payload lifecycle.

## [0.8.0] - Unreleased

### Added — Centralized LLM provider metadata (issue #173)

- New `ai::provider_registry` module with an exhaustive `PROVIDER_REGISTRY`
  table that maps each `LlmProvider` variant to its canonical key and
  supported aliases. Adding a provider now requires exactly one entry here
  plus a matching arm in core's `as_str` match — no other files change.
- `ai::list_providers()` returns curated provider info for the
  `/ai-import/providers` endpoint.
- `ai::resolve_provider(value)` resolves a user-supplied key or alias to
  its canonical `LlmProvider` variant.
- `ai::curated_models()` and `ai::curated_model_ids()` moved from the
  module-level `curated_models` function into the registry (re-exported
  from `ai`).
- Unit tests covering registry completeness, canonical-key resolution,
  alias resolution, unknown-value rejection, list ordering, model
  coverage, and alias-vs-key non-collision.

### Changed — AI merge worker no longer queries read-model projections (issue #172)

- `QueueMergeWorker` simplified from `QueueMergeWorker<Q, E, S, P>` to
  `QueueMergeWorker<Q, P>`: removed `EpisodeRepository` and `SceneRepository`
  generic parameters. The worker now reads an immutable `MergeInput` blob
  (schedule + pre-loaded scenes) from the preview store and calls
  `merge_from_input()` — never querying a read-model projection at runtime.
- Re-pins `breakdown_core` to 0.5.0 (consumes the new `MergeInput` type;
  under major-zero semver this is a MINOR bump, ADR-020 D2/D3).

## [0.6.0] - 2026-08-07

### Fixed — AI import telemetry: never-applied jobs have NULL edit_distance (issue #171)

- The `ai_import.ai_import_job.edit_distance` column is now **nullable**
  (migration `20260807000001_ai_import_not_applied`). Jobs that never reach
  apply are recorded with `accept_as_is = NULL` and `edit_distance = NULL`;
  an applied job accepted with zero edits keeps `edit_distance = 0` — the two
  outcomes are no longer conflated, so acceptance/edit-rate calculations can
  exclude `NotApplied` jobs.
- The script/schedule/merge workers record `TelemetryApplyState::NotApplied`
  at preview time; the apply path records `Applied { accept_as_is,
  edit_distance }` via the API edge.
- `record_telemetry` binds the apply state as `Option<bool>` / `Option<i32>`
  (NULL for `NotApplied`).

### Changed

- Re-pins `breakdown_core` to 0.4.0 (consumes the new `Telemetry`
  apply-state contract; under major-zero semver this is a MINOR bump,
  ADR-020 D2/D3).

## [0.5.0] - 2026-08-06

### Security fix — AI import provider transport (issue #170)

- Hosted AI providers (OpenAI-compatible) are now reachable over **HTTPS
  only**, and the Ollama endpoint is restricted to **local addresses**.
  Outgoing requests carry a curated redirect policy
  (`curated_provider_redirect_policy`) that blocks redirects to
  non-`https:` hosts for hosted providers and to non-local hosts for Ollama,
  preventing SSRF / credential-exfiltration via redirects.
- **DNS-rebinding guard (hosted regime):** every hosted destination is
  resolved before connecting and rejected unless **all** resolved addresses
  are globally routable — private, loopback, link-local, unique-local,
  CGNAT, multicast, documentation, the 0.0.0.0/8 "this network" range,
  the RFC 2544 benchmarking range (198.18.0.0/15), the Class E reserved
  range (240.0.0.0/4) and the deprecated site-local prefix fec0::/10 are
  blocked even when the hostname and scheme are otherwise allowed;
  IPv4-compatible IPv6 forms (`::a.b.c.d`) are classified by the IPv4 policy
  (`transport::validate_public_resolution`). The validated addresses are
  pinned for the whole request chain (initial request + same-origin
  redirects) via `ClientBuilder::resolve_to_addrs` and system proxies are
  disabled on the hosted client (they would resolve the CONNECT target
  outside the pin) (`transport::build_hosted_client`) — a rebinding attacker
  cannot point the connection at an internal service after validation.
- `OpenAiCompatibleModelCatalog::new` now builds its own HTTP client with the
  redirect policy and a fixed 30-second request deadline. **Breaking change:**
  the `new(http: reqwest::Client) -> Self` signature was replaced by
  `new() -> Result<Self, DomainError>` (under major-zero semver this is
  released as a minor bump; no in-tree caller used the old signature). A
  test seam `with_http(client)` remains for injected clients.
- `OpenAiCompatibleChatClient::new` is now **`async`** (it performs the
  resolution guard and pins the validated provider address). **Breaking
  change:** `new(provider, api_key, timeout)` must now be awaited.

### Added (additive public API)

- New `ai::transport` module with the redirect-policy constructors
  `curated_provider_redirect_policy`, `hosted_provider_redirect_policy` and
  `ollama_redirect_policy` (re-exported from `ai`).
- New `ai::transport::validate_public_resolution` (async DNS resolution
  guard for the hosted regime) and `ai::transport::build_hosted_client`
  (validated + pinned hosted client builder).

### Internal

- Follow-up refinements to the ADR-020/ADR-021 versioning rollout: projector
  `projector_version` guards, event/wire fixture contract tests and
  integration-test fixtures aligned with the released projection schema.

### Dependency updates (ADR-020 D7 bookkeeping)

- opendal 0.52 → 0.58 (S3 / GDrive storage)
- aes-gcm 0.10 → 0.11, base64 0.22 → 0.23, getrandom 0.3 → 0.4,
  rand_core 0.6 → 0.10, redis 1.4 → 1.5, schemars 1.2.1 → 1.2.2,
  serde 1.0.228 → 1.0.229, sha2 0.10 → 0.11
