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
  claim can already tell a live unpublished owner from a dead one.
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
owner by the row stamp, the **refusal** cannot, because the stamp never leaves
the adapter.

### Discovery evidence

| Question | Tool | Result |
|---|---|---|
| Where is the refusal enriched? | `search_code` + `read` on `apply_ai_import` | `backend/crates/api/src/handlers/mod.rs:8148` ages `run.progress.updated_at` only; no fallback exists. |
| Who constructs `ApplyRunState`? | `search_graph` + `grep "ApplyRunState {"` | 6 sites: the trait default (`core/src/ai/ports.rs:615`), the Postgres read (`infra/src/ai/queue.rs:923`), the SSE handler's no-slot fallback (`api/src/handlers/mod.rs:7083`), and three test fakes (`infra/src/ai/tests.rs:656`, `api/tests/common/mod.rs:2720`, `api/tests/handler_ai_import_apply_sse.rs:105`). |
| Which column does the claim judge an unpublished owner by? | `read` on `claim_apply_run` | `ai_import_job.updated_at` — the same column the claim stamps. No new column, no migration. |
| What does the client do with the age? | `read` on `apply_controller.dart` | `AiApplyInFlight.isStaleAt` already flips to the takeover affordance once `age > staleAfter`; `age == null` is the documented "unaged" card. **No Dart change is needed** — the wire gaining an age is exactly the signal it already consumes. |
| Text (occurrence), not symbols | `rg` | `apply_run_age_seconds` in `error_registry.rs`, `problems/mod.rs`, `backend/openapi.yaml` `x-code-registry`, `docs/design/screens/ai-import-jobs.md`, and the Dart fixtures. |
| Coverage | `check_index_coverage` on `backend/crates/**`, `frontend-flutter/lib/**` | clean. |

## Decision

**Expose the claim's own row stamp on the read, and derive the age from one
core function with the same fallback order as the claim's predicate.**

`ApplyRunState` gains `owner_updated_at: Option<DateTime<Utc>>` — the job
row's `updated_at`, documented as *the owner's last write on the row*, never as
"the last progress frame" (every run-scoped write bumps it, including
`record_telemetry` and `record_applied_episodes`).

`ApplyRunState::owner_silence_at(now)` becomes the single definition of the
reported age:

1. `progress.updated_at` when the owner published a frame — the column the
   steal predicate compares once a payload exists
   (`(apply_progress->>'updated_at')::timestamptz < $3`);
2. else the row's `updated_at` — the column the steal predicate compares while
   `apply_progress IS NULL`;
3. else `None`.

Requirement (2) is what makes the acceptance criterion structural: **the
verdict and the steal read the same column**, so they cannot disagree. And
requirement (3) keeps the pre-#805 honesty intact: an adapter that reports no
stamp (a pre-migration row, a fake that does not track it) yields no age
rather than an invented `0`.

Rejected alternative — have the claim publish an initial `applying 0/N` frame:
it erases the "the owner published nothing" state #805 deliberately kept
honest, makes `started_at` a lie for work that has not begun, and writes a
payload from a claim that is a single `UPDATE` statement.

No migration, no new problem code, no wire-shape change: `ApplyRunState` is an
internal read (not `Serialize`d), the two S1 extension names and
`stale_after_seconds` semantics are untouched, and `openapi.yaml`'s
`x-code-registry` entry does not move.

## Affected packages / artifacts

| Package / Artifact | Action | Reason |
|---|---|---|
| `core` | minor bump (doc + view field + `owner_silence_at`) | `ApplyRunState` gains `owner_updated_at`; the age definition moves here. |
| `infra` | lockstep bump | The Postgres read selects `updated_at`; the fake mirrors the claim stamp. |
| `api` | lockstep bump | The refusal uses `owner_silence_at`; the "no slot" fallback fills the stamp. |
| `breakdown_api` (Dart client) | none | Problem extensions are untyped on the wire; the Dart parser already reads the age. |
| `frontend-flutter` | none | `isStaleAt` already renders the takeover once an age exists (PR #862). |
| OpenSpec | new change `863-apply-claim-age` | Delta spec + tasks. |

## Non-goals

- Publishing a frame from the claim (see the rejected alternative).
- Changing `stale_after_seconds` or `ApplyProgress::STALE_AFTER`.
- Touching the Flutter client: it needs no behavioural change. The
  `docs/design/screens/ai-import-jobs.md` sentence that promised "absent when
  that run published nothing yet" is corrected there, because it is now about
  a pre-#863 server only.
