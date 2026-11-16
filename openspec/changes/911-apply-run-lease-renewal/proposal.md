<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Renew the apply run's lease while it executes (issue #911)

## Why

`ai-import-durable-apply-run` (#899, PR #906) made the apply run durable and gave the
job row a single-flight **slot**. Its predicate is silence-based: a `running` slot whose
owner published nothing for `ApplyProgress::STALE_AFTER` (10 min) may be taken over.

That is correct for a **script** apply — its row loop publishes progress frames, so a
live owner keeps proving it is alive (and #800's `ApplyRunHeartbeat` covers a single slow
row). It is wrong for a **schedule** apply: that run is one merge loop over the project's
existing scenes and days and publishes **no frames at all**, so a run that merely outlives
the window is indistinguishable from a crashed owner and can be taken over *while it is
still executing*:

- `claim_apply_run` / `request_apply_run` (single-flight steal) judge such an owner by
  `COALESCE(apply_progress->>'updated_at', apply_claim_at, updated_at)` — for a payload-less
  owner that is the claim stamp, frozen since the claim;
- `requested_apply_runs` (the poll) + `begin_apply_run` (the takeover) use the same
  expression, so the poll hands the row to another replica and mints a fresh run id.

The design accepts the *convergence* (a stolen run's appends recover via `derive_id` +
`ExpectedVersion::Empty` + `created_now`, never a duplicate aggregate), but two live runs
on one slot mean duplicated command traffic and a telemetry write racing the terminal
transition (the run-fenced `record_run_telemetry` keeps the *data* honest).

## What changes

- **Core port** — `AiImportQueue::renew_apply_run(id, run_id) -> Result<bool, _>`,
  default `Ok(true)` for slot-less adapters (the same optimistic default as
  `claim_apply_run` / `record_run_telemetry`). `false` = the slot moved on.
- **Postgres adapter** — one owner-fenced statement:
  `UPDATE ai_import.ai_import_job SET apply_claim_at = now() WHERE id = $1 AND apply_run_id = $2`
  (rows affected → the verdict). Deliberately narrow: no payload, no `apply_run_seq`, no
  `updated_at`, no `pg_notify` — the renewal proves *aliveness*, never progress.
- **All four silence predicates** (`claim_apply_run`, `request_apply_run`,
  `begin_apply_run`, `requested_apply_runs`) compare the **newer** of the published frame
  and the lease stamp (`COALESCE(GREATEST(…, apply_claim_at), updated_at)`), and
  `ApplyRunState::owner_silence_at` mirrors that pair. Judging a payload owner by its frame
  alone would leave a renewing run stealable — a schedule apply publishes no frame at all,
  and a script apply's trailing step publishes one `finalizing` frame and then works. The
  reported `409` age must describe the same decision, or a client would be told to take
  over a slot the server would refuse.
- **Infra** — `infra::ai::with_apply_run_lease(queue, job_id, run_id, window, run)`: runs
  the execute future under a renewal ticker (`renewal_interval(window)`, a third of the
  window, via the existing `LeaseHeartbeat` cadence) plus `apply_run_lease_window()` =
  `ApplyProgress::STALE_AFTER`. The renewal lives in the **same future** as the run, so it
  is cancelled with it — a killed replica still becomes stealable after one window, which
  is the acceptance criterion *and* the reason this is not a spawned `JoinHandle` (a
  detached renewal task would keep a dead run's slot alive forever).
- **API runner** — `ApplyRunner::run_claimed` wraps `execute` in it, so both branches are
  covered (the script branch additionally keeps its per-row progress writes) and every
  caller — the production poll loop and the handler tests — is protected.
- **Tests** — infra unit tests (scripted fake: renews at cadence, stops on `false`,
  keeps retrying on a transient error, a zero window disables it) + two PostgreSQL
  integration cases (a renewed silent owner is not stealable and reports a fresh silence;
  a taken-over run's renewal reports `false`).

## Not in scope

- A configurable window/interval: the cadence is derived from `STALE_AFTER`, one
  definition, no new env var (an operator knob here would let the renewal and the steal
  predicate disagree).
- Any client change: no wire field changes, no new problem code, `openapi.yaml` untouched.

## Discovery evidence

- **Graph (codebase-memory, project `breakdown-rs`)** — symbol/`trace_path` shape for
  `AiImportQueue` (`crates/core/src/ai/ports.rs`), the adapter in
  `crates/infra/src/ai/queue.rs` (`claim_apply_run`, `begin_apply_run`,
  `requested_apply_runs`, `record_run_telemetry`), `ApplyRunner::run_claimed` in
  `crates/api/src/apply_runner.rs`, and the existing lease pattern in
  `crates/infra/src/ai/heartbeat.rs`.
- **Text (occurrence)** — `rg "STALE_AFTER"` to enumerate every staleness reader (the
  single window definition); `rg "record_run_telemetry"` for the run-fence shape.
- **Coverage** — `crates/{core,infra,api}/src/ai/**`, `crates/api/src/apply_runner.rs`,
  `crates/integration-tests/tests/ai_import_job_progress.rs` (clean at generation
  `dd35739`; reindex check before the drift claim).
