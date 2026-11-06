<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 863 — An apply claim that never published must still age

## Why

Follow-up to #805 (PR #862), which put the blocked apply run's silence on the
wire (`apply_run_age_seconds`) next to the server's window
(`stale_after_seconds`), so the refusal became a decision instead of a wait.

One corner stayed open **on purpose** and is now the defect:

- `AiImportQueue::claim_apply_run` stamps the job row (`updated_at = now()`)
  and leaves `apply_progress` NULL. Its own steal predicate handles exactly
  that state — `OR (apply_progress IS NULL AND updated_at < $3)` — so the
  claim can already tell a live unpublished owner from a dead one. (The stamp
  itself is the second defect this change closes; see the review follow-up in
  Decision.)
- `ApplyRunState` exposes only `owner`, `seq` and `progress`. With no payload
  there is nothing to age, so the #805 enrichment in `apply_ai_import` (which
  reads `run.progress`) yields `None` and the refusal carries
  `stale_after_seconds` **only**.
- The client (correctly) renders that as "an apply is running, no progress
  published yet", offers no takeover, and the user waits the full window
  (`ApplyProgress::STALE_AFTER`, 10 min) for a run that is already dead.

The window is not theoretical: the first `publish_apply_progress` in
`ApplyWorker::run_script_apply` happens **after** plan assembly (episode, day
and group resolution), so claim → first-frame covers real work.

The production asymmetry is the point: the **claim** can judge an unpublished
owner by a row stamp, the **refusal** cannot, because the stamp never leaves the
adapter.

### Discovery evidence

| Question | Tool | Result |
|---|---|---|
| Where is the refusal enriched? | `search_code` + `read` on `apply_ai_import` | `backend/crates/api/src/handlers/mod.rs:8148` ages `run.progress.updated_at` only; no fallback exists. |
| Who constructs `ApplyRunState`? | `search_graph` + `grep "ApplyRunState {"` | 6 sites: the trait default (`core/src/ai/ports.rs:615`), the Postgres read (`infra/src/ai/queue.rs:923`), the SSE handler's no-slot fallback (`api/src/handlers/mod.rs:7083`), and three test fakes (`infra/src/ai/tests.rs:656`, `api/tests/common/mod.rs:2720`, `api/tests/handler_ai_import_apply_sse.rs:105`). |
| Which stamp does the claim judge an unpublished owner by? | `read` on `claim_apply_run` | `ai_import_job.updated_at` — the column the claim stamps, and the one every run-scoped write bumps (see the review follow-up below: that coupling is what the owner-scoped stamp replaces). |
| What does the client do with the age? | `read` on `apply_controller.dart` | `AiApplyInFlight.isStaleAt` already flips to the takeover affordance once `age > staleAfter`; `age == null` is the documented "unaged" card. **No Dart change is needed** — the wire gaining an age is exactly the signal it already consumes. |
| Text (occurrence), not symbols | `rg` | `apply_run_age_seconds` in `error_registry.rs`, `problems/mod.rs`, `backend/openapi.yaml` `x-code-registry`, `docs/design/screens/ai-import-jobs.md`, and the Dart fixtures. |
| Coverage | `check_index_coverage` on `backend/crates/**`, `frontend-flutter/lib/**` | clean. |

## Decision

**Expose an owner-scoped claim instant on the read, and derive the age from one
core function with the same fallback order as the claim's predicate.**

`ApplyRunState` gains `owner_claimed_at: Option<DateTime<Utc>>` — the instant the
current run **took the slot**, backed by a new `ai_import_job.apply_claim_at`
column (migration `20261106000002`) written by the claim and by nothing else.

The column is a review follow-up, and the reason is worth keeping: the tempting
implementation is the job row's `updated_at`, which the claim also stamps.
But that column is bumped by *every* run-scoped write, including a **previous**
apply's `record_applied_episodes` / `record_telemetry`, which land after that
apply released the slot. Such a write can land after the next claim and would
then describe the new owner as fresher than it is — understating a dead run's
silence by the gap to that write and delaying the steal by the same amount. An
owner-scoped column cannot be moved by anyone else's write.

`ApplyRunState::owner_silence_at(now)` becomes the single definition of the
reported age:

1. `progress.updated_at` when the owner published a frame — the stamp the
   steal predicate compares once a payload exists
   (`(apply_progress->>'updated_at')::timestamptz < $3`);
2. else `owner_claimed_at` — the stamp the steal predicate compares while
   `apply_progress IS NULL` (`COALESCE(apply_claim_at, updated_at) < $3`, the
   `COALESCE` being the rolling-deploy fallback for a claim made before the
   column existed);
3. else `None`.

Requirement (2) is what makes the acceptance criterion structural: **the
verdict and the steal read the same owner-scoped instant**, so they cannot
disagree and no third party's late write can move it. And requirement (3) keeps
the pre-#805 honesty intact: a slot that reports no claim instant (a claim made
before the column existed, a fake that does not track it) yields no age rather
than an invented `0`.

Rejected alternative — have the claim publish an initial `applying 0/N` frame:
it erases the "the owner published nothing" state #805 deliberately kept
honest, makes `started_at` a lie for work that has not begun, and writes a
payload from a claim that is a single `UPDATE` statement.

One migration (`apply_claim_at`, nullable, no backfill), no new problem code, no
wire-shape change: `ApplyRunState` is an internal read (not `Serialize`d), the
two S1 extension names and `stale_after_seconds` semantics are untouched, and
`openapi.yaml`'s `x-code-registry` entry does not move.

## Affected packages / artifacts

| Package / Artifact | Action | Reason |
|---|---|---|
| `core` | minor bump (doc + view field + `owner_silence_at`) | `ApplyRunState` gains `owner_claimed_at`; the age definition moves here. |
| `infra` | lockstep bump + migration `20261106000002_ai_apply_claim_stamp` | The claim writes `apply_claim_at`, the read selects it, the fakes mirror it. |
| `api` | lockstep bump | The refusal uses `owner_silence_at`; the "no slot" fallback reports no claim instant. |
| `breakdown_api` (Dart client) | none | Problem extensions are untyped on the wire; the Dart parser already reads the age. |
| `frontend-flutter` | none | `isStaleAt` already renders the takeover once an age exists (PR #862). |
| OpenSpec | new change `863-apply-claim-age` | Delta spec + tasks. |

## Non-goals

- Publishing a frame from the claim (see the rejected alternative).
- Changing `stale_after_seconds` or `ApplyProgress::STALE_AFTER`.
- Backfilling `apply_claim_at` for in-flight claims: a claim made before the
  column existed reports no age and keeps the old `COALESCE` steal fallback.
- Touching the Flutter client: it needs no behavioural change. The
  `docs/design/screens/ai-import-jobs.md` sentence that promised "absent when
  that run published nothing yet" is corrected there, because it is now about
  a pre-#863 server only.
