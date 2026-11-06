<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 805 — A blocked apply run must be distinguishable from a dead one

## Why

Issue #805 (client-side counterpart of #800, follow-up to #762). An API
process crash mid-apply left `ai_import_job.apply_run_id` pointing at a run
whose process was gone, with `apply_progress = {applying, 6/59,
updated_at: 13:58:58Z}` still on the row. The next client POST was answered
`409 ai-import.apply-in-flight` — correctly, because the claim steals only
payloads older than `ApplyProgress::STALE_AFTER` (10 min) — and

- the client's reconciliation loop consumed its bounded budget on that code
  and ended in `ApplyUnresolved`: a generic "outcome unknown" error card;
- nothing on the wire named *how old* the blocking run's last publication was,
  so the UI could not tell "my other device is applying right now" from "a
  dead run left the payload behind";
- the progress card unmounts with the POST, so the frozen 6/59 vanished and
  the only way forward was restarting the app.

The data was never at risk (the apply is row-idempotent and the server steals
a stale claim in the same statement). What broke is the **user-visible
decision**.

### Discovery evidence

| Question | Tool | Result |
|---|---|---|
| Where is the 409 emitted / who maps it? | `trace_path` (inbound) on `apply_script`, then `read` | `infra/src/ai/workers.rs:2086` claims and answers `DomainError::Conflict{code: AI_IMPORT_APPLY_IN_FLIGHT}`; `api/src/handlers/mod.rs:8106` `await?`s it into `ApiError::Domain`. |
| Which facts are already on the wire? | `search_graph` + `read` on `core/src/ai/views.rs` | `AiImportJob.apply_progress` (**additive since #762/#800**) already carries `run_id`, `stage`, `applied`, `total`, `started_at`, `updated_at`; the Dart model has `AiImportJob.applyProgress.updatedAt`. The blocking run's *age* is therefore already readable — only the server's **window** (`STALE_AFTER`) is not. |
| What does the client do with the code? | `search_code pattern=isApplyInFlight` | `lib/data/ai_import_repository.dart:914`; consumed at `:849` (loop, `continue`) and `apply_controller.dart:1439` (copy). |
| Text (occurrence), not symbols | `rg` | ARB keys `aiApplyErrorApplyInFlight` (de/en), the `x-code-registry` entry in `backend/openapi.yaml`, the existing unit test `409 … is a WAIT, not a block`. |
| Coverage | `check_index_coverage` on the touched paths | clean (`frontend-flutter/lib/{data,features}/**`, `backend/crates/{core,api}/**`). |

## Decision

**The blocking run's last publication travels on the 409 itself, in the
problem's declared S1 extensions** (`apply_run_age_seconds`,
`stale_after_seconds`) — not as a new typed read-model field:

- the age is **server-computed** at emission, so a device whose clock is off
  cannot misclassify a live run as dead (a client-side
  `now - updated_at` can);
- the values are per-event facts, so no time-dependent value enters a
  Drift-cached read model (`AiImportJob` rows *are* cached);
- problem extensions are untyped on the wire (`ProblemDetails.extensions`,
  `additionalProperties: {}`), so the Dart client needs **no regeneration** —
  only `backend/openapi.yaml`'s `x-code-registry` catalogue moves;
- the age is honest when absent: a run that has published no frame yet sends
  no `apply_run_age_seconds`, and the client says exactly that instead of
  inventing "just started".

The client then owns the **decision**, not the policy:

- `age < stale_after` → a live run owns the slot. The copy names the age and
  when a takeover becomes possible; the reconciliation loop keeps its bounded
  budget (the #800 case: the client's own earlier POST is still running), and
  if the budget ends on a live run the outcome is `ApplyInFlight`, not the
  generic `ApplyUnresolved`.
- `age >= stale_after` → the run is dead by the server's own predicate. The
  loop stops **immediately** and surfaces `ApplyInFlight`; the takeover is an
  **explicit user action**, never an automatic steal (AC: "no blind
  re-dispatch"). Pressing it re-dispatches the idempotent apply, and the
  server's claim steals the dead slot in the same statement.
- a `409` without the extensions (pre-#805 server) keeps the pre-#805 wait
  behaviour — the client never guesses a window it was not told.

## What

| Layer | Change |
|---|---|
| `core` | `AI_IMPORT_APPLY_IN_FLIGHT` declares the S1 extensions `apply_run_age_seconds` + `stale_after_seconds` (ADR-031 D4 whitelist). |
| `api` | New `ApiError::AiImportApplyInFlight { age_seconds: Option<u64>, stale_after_seconds: u64 }`; `apply_ai_import` catches the claim conflict and enriches it from `apply_run_state` (+ `ApplyProgress::STALE_AFTER`, the single definition of the window); `openapi.yaml` regenerated (`x-code-registry` only). |
| `frontend-flutter` | `applyInFlightInfo(ProblemError)` parses the extensions; `ApplyInFlight` reconciliation outcome; the loop stops on a dead run and reports a live exhaustion as `ApplyInFlight`; `AiApplyState.applyInFlight` (+ clock-stamped observation); the apply card renders a live line with a takeover countdown or a dead line with an explicit "take over now" action that re-dispatches through the same AUTHZ-GATE'd path. |
| docs | `docs/design/screens/ai-import-jobs.md` gains the blocked-run section; CHANGELOGs. |

## Non-goals

- **No second read.** The enriched 409 carries the age; the client does not
  fetch the job again just to learn it (an extra projection read per refused
  dispatch, and the read could answer after the run moved on).
- **No automatic steal.** The server would steal silently on the next claim;
  the client deliberately asks the user first (a live run may be the same
  user's other device).
- **No lowered window.** `STALE_AFTER` stays 10 min; the value that travels
  is the same constant, not a copy.
- **The claim-without-payload corner stays as it is.** A run that crashed
  before publishing its first frame has no payload to age, so no
  `apply_run_age_seconds` is sent and the client keeps waiting that run out.
  Widening that would mean exposing the claim's own row stamp on
  `ApplyRunState` — recorded here as a follow-up candidate, not smuggled in.
- **`applied_episodes` staying `NULL`** (the issue's "also observed") is
  #759's durability question and is not decided here.

## Acceptance

- A client meeting `409 ai-import.apply-in-flight` receives the owning run's
  published age and the server's window, and says in the UI whether the run
  is live or dead (localized, `code`-keyed, never `detail`).
- After `STALE_AFTER` the user has an explicit affordance that re-runs the
  apply without restarting the app.
- The apply stays single-flight: the only automatic retries are the existing
  bounded ones for a *live* run; a dead claim is never stolen without the
  user's tap.
- Tests cover: the dead-run card + takeover dispatch, the live run still
  blocking (and its countdown), the extension parser, the loop's three
  branches (live / dead / no extensions), and the API's enriched 409.
