<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Compose the apply-outcome identity through both HTTP surfaces (issue #912)

## Why

Review of PR #906 established the rule: a finished apply run keeps its
**identity** (`apply_result_run_id` survives the terminal transition) while
`apply_run_id` stays live **ownership** and is freed on completion. Three seams
proved the chain, each on its own:

| seam | proof (before this change) |
|---|---|
| what PostgreSQL holds | `crates/integration-tests/tests/ai_import_job_progress.rs::a_finished_run_keeps_its_identity_and_frees_the_slot` |
| what the frame reports | `crates/api/tests/handler_ai_import_apply_sse.rs::the_frame_reports_the_owner_then_the_outcomes_run` — the extracted `handlers::apply_frame_run_id` |
| what the client compares | `frontend-flutter/test/unit/ai_import_repositories_test.dart` |

The **join** between them was untested: no case drove the real
`GET /v1/ai-import/jobs/{id}` handler and the real `apply-events` stream handler
against a row that a real `PgAiImportQueue` wrote. The residual risk is small —
one field copy plus one frame mapping — but it is the copy a client's "is this
outcome mine?" decision depends on, and two independent expressions implement it
(`infra::ai::decode_run_identity` for the DTO, `handlers::apply_frame_run_id` for
the frame). Either could silently stop surfacing the id with every existing test
still green.

## What changes

One case, `crates/api/tests/handler_ai_import_pg_composition.rs`, added to the
existing `handlers_ai` harness:

1. **`PgQueuePorts`** — a `Ports` set that forwards 39 of 40 associated ports to
   the existing `FakePorts` and overrides only `AiImportQueue` with the
   production `PgAiImportQueue`. The compiler enforces completeness, so a new
   port on `Ports` cannot be forgotten here.
2. **A PostgreSQL fixture inside `crates/api`** — `crates/integration-tests` may
   not be depended on (AGENTS.md §4), so the container spawn + migration run is
   local to the case (honours `POSTGRES_IMAGE`, like the integration-tests
   fixture, so the CI pre-pull is a cache hit).
3. **The case** — seed a `succeeded` job, dispatch and run A through the same
   `request_apply_run` → `begin_apply_run` → `ApplyRunner::run_claimed` pair the
   handlers use, then assert **both** surfaces report A; dispatch and run B, then
   assert **both** report B.
4. **The gate** — `AI_IMPORT_PG_TESTS=1`. Without it the case returns
   immediately, so `cargo test -p api` stays container-free; only the
   "Testcontainers integration tests" job sets it.
5. **The rule written down** — the apply-outcome identity was documented in code
   comments only (changes `800` and `899` shipped no spec delta).
   `specs/ai-import/spec.md` now states the requirement: every surface that
   reports an apply outcome names the run that produced it, with scenarios for a
   live run, a finished run and a superseding run.

## Non-goals

- No production code change. The case is a proof, not a fix — the identity chain
  behaves correctly today.
- No `PgQueuePorts`-style port set for the other 39 ports: a whole port set built
  on real infrastructure would prove nothing this case needs, at the cost the
  issue already weighed.
- No new `[[test]]` target: issue #631 collapsed per-file targets because each
  pays a full-graph link. The case rides the existing `handlers_ai` harness.

## Acceptance

A handler that drops `apply_run_id` (job read) or the frame's `run_id` fails the
case, and the case runs in CI. Both directions were verified by mutating the two
readers (`decode_run_identity`, `apply_frame_run_id`) and observing the failure.
