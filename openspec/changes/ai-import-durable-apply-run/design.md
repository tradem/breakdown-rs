<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## Context

The AI import has two lifecycles today, and they disagree.

*The preview* is durable. A job row in `ai_import.ai_import_job` is claimed with an
owner-fenced lease (`AiImportQueue::claim`, `claimed_by` + `lease_expires_at`), kept
alive by `LeaseHeartbeat`, recovered after a crash by lease expiry, and observed
through a push stream (`AiJobEventHub` + `pg_notify`). Nothing about it depends on a
client staying connected.

*The apply* is not. `apply_ai_import` validates the request and then **awaits**
`ApplyWorker::apply_script` inside the handler. Issue #762 gave the apply its own
progress stream (`GET /jobs/{id}/apply-events`) and issue #800/#805 gave the *slot*
owner fenced claims, silence stamps and a staleness window — so the observability and
the single-flight semantics are already right. What is missing is that the work itself
lives in the request:

- `ApplyRunGuard` is armed "for exactly as long as this future lives: a client that
  disconnects mid-apply drops it" — i.e. the design documents that a suspend aborts the
  apply;
- the run's progress payload is cleared by that drop, so the client's remaining-time
  display freezes at "applying 12/57";
- the apply's counters (`ApplyAiImportResponse`) exist only in the response body, so a
  client that missed the response can never learn what committed;
- on the client, `isAmbiguousTimeout` covers only `connectionTimeout`/`sendTimeout`/
  `receiveTimeout`, so the suspend case (`connectionError`) is classified *definitive*
  and surfaced as a failure.

The mapping protocol underneath is already resumable: every aggregate is reserved
before dispatch (`derive_id` + `ExpectedVersion::Empty` + `created_now` recovery) and
every phase is confirmed monotonically, so a re-driven apply converges instead of
duplicating. That property is what makes a durable run cheap: resumption is the
*normal* path, not a special case.

## Goals / Non-Goals

**Goals:**

- An apply survives the loss of the client that started it, and the client can
  re-attach to it instead of restarting it.
- The run's outcome is durable and readable after the fact, not only in the `POST`
  response body.
- One run per preview, whichever way a client re-enters: a second `POST` while a live
  run owns the slot is a *wait*, and an abandoned run stays stealable through the
  existing staleness window.
- No new aggregate, no new event stream, no new dependency: the run rides the existing
  job row, the existing fenced writes and the existing SSE hub.
- The Flutter client distinguishes "the request died" from "the apply failed" and
  re-attaches on its own.

**Non-Goals:**

- Apply *duration* (the row loop's round-trip count, batching, row parallelism). That is
  its own additive change; this one must not block on it and must not change the
  protocol it optimizes.
- A general-purpose job runner for other long handlers. Only the apply is migrated.
- Multi-run history for one preview (a run ledger). One run slot per job stays enough:
  a re-apply after a finished run overwrites the slot, which is what the client needs.
- Editing a preview, or making the apply transactional across aggregates. The protocol
  stays idempotent-and-converging, never atomic.

## Decisions

### D1 — The run slot becomes a dispatchable work item (extend the job row, no new table)

The job row already holds everything a run needs to be claimable: the fenced claim
(`apply_run_claimed_by`, `apply_run_claimed_at`), the progress payload with `run_id`
and `stage`, and the silence stamp the #805 refusal reports. What is missing is a
*state* a worker can poll — today "requested" is implicit in "a request is in flight".

Add one column to `ai_import.ai_import_job`: `apply_state`
(`idle` | `requested` | `running` | `done` | `failed`), written through owner-fenced
methods on `AiImportQueue` (`request_apply_run`, `mark_apply_running`,
`complete_apply_run`, `fail_apply_run`), and let the existing AI worker loop claim
`requested` rows exactly as it claims `pending` jobs.

*Why not a separate `ai_import.apply_run` table?* One run slot per preview is the
contract (single-flight is per preview, not per run), and the progress payload, the
claim columns and the crash-recovery stamps already live on the job row. A second table
would duplicate them and need its own joiner. It is added only when a run *ledger*
becomes a requirement.

*Why `done`/`failed` instead of clearing?* The outcome must outlive the client. The
persisted result is what the terminal stream frame and `GET /jobs/{id}` serve; a
re-apply overwrites it (a new `run_id`).

### D2 — `POST /apply` validates, claims and dispatches: `202 ApplyRunAccepted`

The handler keeps everything it does today *before* the first write: load the job,
`authorize_ai_job`, require `succeeded`, resolve the target episode/project/block/season,
validate the mapping/episode-group/shooting-day/uncertainty payloads against the preview,
load the category vocabulary. It then claims the run slot (`claim_apply_run`, unchanged),
persists the **resolved apply request** next to the run (the worker needs the reviewer's
decisions, which are not in the preview payload), flips `apply_state = requested` and
answers `202 { run_id, stage, started_at }`.

The apply request is persisted as a JSONB payload on the run slot (`apply_request`)
rather than held in memory: a `requested` row must be resumable by *any* replica after a
rolling deploy, and a restart-between-claim-and-dispatch must not strand it.

**BREAKING:** the counters leave the `POST` body. This is acceptable in place (no `/v2`
window, ADR-021/ADR-035-B5 precedent: the client is an in-repo beta that ships with the
backend) — but the ordering is: backend + OpenAPI + regenerated Dart client + client
change in one PR, and the CHANGELOG marks it.

*Alternative rejected:* keep the inline path and only add a "detach" flag. It would
re-introduce the same request-bound lifetime for one branch and leave two apply
lifetimes to reason about.

### D3 — The dispatched run is owned by the worker, not by the request

`ApplyWorker::apply_script` becomes a *worker* entry point taking the persisted
`ApplyRequest`. The `ApplyRunGuard` (which clears the progress payload on drop) moves
from the handler future to the worker task; it must no longer be reachable by a dropped
connection, so the guard's contract changes from "this future's lifetime" to "this run's
lifetime" and the progress clear happens in `complete_apply_run` / `fail_apply_run`.

Shutdown gains one obligation: the API must cancel-and-join dispatched apply tasks before
the pool/limiter teardown, in the same ordering the concurrency permits already document
(`AI_IMPORT_*` runtime). A run interrupted by shutdown stays `running` with a stale
silence stamp and is recovered by the documented steal path — the same behaviour a
crashed replica has.

### D4 — The outcome lives on the run slot and is served twice

`ApplyAiImportResponse` is persisted (`apply_result` JSONB) by the worker before
`apply_state = done`. Two readers, one writer:

- `GET /jobs/{id}/apply-events`: the stream's **terminal frame** carries the result, then
  closes (mirroring how the job stream closes on a terminal status). A client that
  re-attaches after the run finished gets the terminal frame immediately — no `POST`
  needed.
- `GET /jobs/{id}`: the job response gains `apply_state` + `apply_result` so a screen
  that was never on the stream can still render "imported N scenes, M costumes
  unapplied".

A failed run persists its `DomainError` as the registered problem `code` (never a
`detail`-only string, ADR-031) so the client's error narrative is code-driven like every
other apply failure.

### D5 — Attach, don't repeat: the client's re-entry path

The three entry cases, in the client's terms:

1. **The `POST` returned `202`** — open `apply-events`, follow to the terminal frame,
   render the result from it.
2. **The `POST` died** (`connectionError`, timeouts, a closed socket) — the outcome is
   *unknown*, which is the same class as today's ambiguous timeout: re-read the job,
   then open `apply-events`. A live run is followed, never re-dispatched; a `409
   ai-import.apply-in-flight` is a *wait* (attach to the run the refusal names), not an
   error.
3. **The screen is re-entered after a suspend** (a fresh process, no in-memory state) —
   same as case 2: `GET /jobs/{id}` → `apply_state` decides between "no run"
   (offer Apply), "live run" (attach), and "finished" (render the persisted result).

`isAmbiguousTimeout` gains `transport.connectionError` and the `unknown`
(Dio `DioExceptionType.unknown` on a streamed body) code, and is renamed to
`isResumableDispatch` so the predicate states what it decides.

### D6 — Steal only on the server's own verdict

The client never mirrors `ApplyProgress::STALE_AFTER`. The `409` already carries
`apply_run_age_seconds` + `stale_after_seconds` (issue #805); the takeover affordance is
offered only when `age >= stale_after` **as the server reported it**, and a takeover is
just a `POST` that the server accepts because its own claim has expired. No new
client-side policy, no new constant.

## Risks / Trade-offs

- **Two replicas can run the same preview after a steal.** Unchanged from today
  (documented convergence: `derive_id` + `ExpectedVersion::Empty` + `created_now`); the
  cost is a few recovered appends, never a duplicate aggregate. The per-run mapping
  cache (performance PR) makes this *more* visible — a stolen run may dispatch a create
  the other run already committed — which is why that PR documents the same convergence
  path.
- **`202` is a breaking wire change.** Mitigated by shipping backend + client together
  and by the in-repo client being pre-release; the alternative (dual contract) would
  mean two apply lifetimes.
- **A persisted request payload is reviewer data at rest.** It contains no credentials
  (the AI credential lives in the vault; the request carries mapping decisions and
  episode/day groups) and lives on the same row as the preview handle. It is deleted
  when the payload GC sweeps the job (same lifecycle as `preview_handle`).
- **Shutdown ordering.** A missed join leaves a task writing into a torn-down pool. The
  ordering obligation is explicit (D3) and testable with the existing
  fault-injection/shutdown harness.
- **One more state machine on the job row.** `apply_state` must never contradict
  `apply_progress` (a `done` run cannot have a live progress payload). Both are written
  by the same fenced statement pairs, and the integration tests pin the pairs.
- **A stuck `requested` row** (claimed, never dispatched) is recoverable by the same
  staleness window; the periodic sweep that already queries `failed` jobs can log it.
