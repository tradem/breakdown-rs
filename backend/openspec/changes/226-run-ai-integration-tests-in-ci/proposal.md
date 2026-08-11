<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (opencode-go) -->

# Proposal: Run remaining AI import/payload integration tests in CI (Issue #226)

## Drift check

Issue #226 asks to wire the AI import/payload integration test files that are
absent from `.github/workflows/integration-tests.yml` into CI.

What has landed since the issue was filed:

- **#225** added `ai_payload_storage_round_trip` to the SierraDB sequential
  group and pre-pulls the Garage image (`GARAGE_IMAGE`) — it documents the
  remaining gap, which is exactly what this change closes.
- `ai_gdrive_fixture_test` and `ai_llm_smoke_test` are **nightly-only by
  design**: both already run in `.github/workflows/ai-import-nightly.yml`, and
  the GDrive fixture additionally runs in `integration-tests.yml` for trusted
  contexts. No action needed.
- `event_fixture_contract_tests.rs` and `wire_contract_fixture_tests.rs` are
  ADR-021 fixture-capture tools, not AI integration tests — out of scope.

Verification of the remaining 8 files (grep for `spawn_sierradb` /
`spawn_postgres` / `spawn_garage`):

| File | Containers per run | Category |
|---|---|---|
| `ai_import_mapping_reservation.rs` | 3 × Postgres | Postgres-only, light |
| `ai_import_queue_telemetry.rs` | 2 × Postgres | Postgres-only, light |
| `ai_concurrency_shutdown.rs` | 2 × Postgres | Postgres-only, light |
| `ai_payload_restart_recovery.rs` | 6 × Postgres | Postgres-only, light |
| `ai_import_queue_lease.rs` | 13 × Postgres | Postgres-only, **heavy** |
| `ai_import_permit_reconciliation.rs` | 9 × Postgres | Postgres-only, **heavy** |
| `ai_concurrency_permit_cancellation.rs` | 12 × Postgres | Postgres-only, **heavy** |
| `ai_payload_gc_cleanup_state.rs` | 9 × Postgres + 4 × Garage | Postgres-only, **heavy** |

None of the 8 files needs SierraDB; only `ai_payload_storage_round_trip`
(already wired by #225) does. None requires poppler/pdftotext or a live LLM.

## Decision (user-confirmed): hybrid job split

Recent CI runs of `integration-tests.yml` take ~10.5–12.5 min. Adding all 8
files to the existing single job would add an estimated ~8–18 min (the heavy
files spawn up to 13 Postgres containers per binary), putting the 30-minute
job timeout at risk. Per the issue's own acceptance criterion ("may need
splitting if not"), the user chose the **hybrid** split:

1. **Light files** (4) join the existing *Postgres-only integration tests
   (parallel)* step in the main job: `ai_concurrency_shutdown`,
   `ai_import_mapping_reservation`, `ai_import_queue_telemetry`,
   `ai_payload_restart_recovery`.
2. **Heavy files** (4) move to a **new second job** (own runner, own
   30-minute budget, runs in parallel with the main job):
   `ai_import_queue_lease`, `ai_import_permit_reconciliation`,
   `ai_concurrency_permit_cancellation`, `ai_payload_gc_cleanup_state`.

The new job reuses the exact checkout/toolchain/docker-verify/pre-pull/
rust-cache step pattern from the main job (repo convention; the retry helper
is duplicated inline in `ai-import-nightly.yml` the same way). It pre-pulls
only `POSTGRES_IMAGE` and `GARAGE_IMAGE` — the heavy files' containers.
Same `concurrency` group applies, so same-ref runs still cancel each other;
the two jobs in one run use separate runners, so there is no Docker
resource contention.

## Changes

- `.github/workflows/integration-tests.yml`
  - Main job: add the 4 light `--test` flags to the parallel step.
  - New job `ai-import-integration-tests`: checkout, toolchain, Docker
    verify, pre-pull (Postgres + Garage), rust-cache, then
    `cargo test -p integration-tests --test ai_concurrency_permit_cancellation
    --test ai_import_permit_reconciliation --test ai_import_queue_lease
    --test ai_payload_gc_cleanup_state -- --nocapture`.
  - Header comment updated to document the split and its rationale.
- `backend/openspec/changes/226-run-ai-integration-tests-in-ci/proposal.md`
  (this file).

No crate code changes, no version bumps.

## Validation

- `actionlint` (mirrors the repo's `lint-workflows.yml` job) must pass on the
  edited workflow; the workflow linter runs on PRs touching
  `.github/workflows/**`.
- YAML parse check of the workflow file.
- A real CI run on the PR exercises both jobs and verifies the 30-minute
  budgets; the concurrency/contention behavior is observable there.

## Out of scope / follow-ups

- If the light additions push the main job past 30 minutes in practice, a
  follow-up can move more files to the second job.
- The `event_fixture_contract_tests` / `wire_contract_fixture_tests`
  fixture-capture suites remain unwired (manual/out-of-band by design).
