<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — compose the apply-outcome identity through both HTTP surfaces (issue #912)

## 1. The port set (`crates/api/tests/handler_ai_import_pg_composition.rs`)

- [x] 1.1 `PgQueuePorts { inner: FakePorts, queue: PgAiImportQueue }` implementing
      `Ports`: 40 associated types aliased from `FakePorts`, 41 accessors
      forwarding to `inner`, and `ai_import_queue()` returning the PostgreSQL
      adapter. Forwarding through the trait accessors (not the struct fields)
      keeps the fake's own field mapping — `wardrobe_commands` → `piece_commands`,
      the three `ai_payload_store` aliases — in one place.
- [x] 1.2 Keep the compile-time completeness: the set must not be built from a
      generic `FakePorts<Q>` (a default type parameter would need inference at
      ~325 construction sites) and must not be macro-generated (a reviewer cannot
      audit the mapping).

## 2. The PostgreSQL fixture (same file)

- [x] 2.1 `spawn_postgres()` — `testcontainers` + `testcontainers-modules`
      (`postgres`), tag overridden from `POSTGRES_IMAGE` exactly like the
      integration-tests fixture, `fsync=off`, 120 s startup timeout, then
      `sqlx::migrate!("../infra/migrations")`.
- [x] 2.2 Add `testcontainers` / `testcontainers-modules` to `crates/api`
      `[dev-dependencies]` (versions mirroring `crates/integration-tests`) with a
      comment stating the env gate and why the dependency is acceptable there.

## 3. The case

- [x] 3.1 Seed: `ScriptContext` payload into the `AiPreviewStore` port → handle →
      `PgAiImportQueue::seed_succeeded(enqueue_request, handle)`. `block_id: None`
      on purpose, so `authorize_ai_job` resolves no season and the handlers are
      gated by ownership alone — the case is about identity, not the costume-role
      policy.
- [x] 3.2 Run A: `request_apply_run` → `begin_apply_run` → `ApplyRunner::run_claimed`,
      i.e. the same pair the `POST /apply` handler uses and the same runner
      production uses; the run's own `complete_apply_run` is what releases
      ownership and stamps the attribution.
- [x] 3.3 Assert the intermediate slot: `owner == None` (slot freed),
      `result_run_id == Some(A)` (attribution kept).
- [x] 3.4 Assert `GET /v1/ai-import/jobs/{id}` through the real handler by its
      **wire JSON** (`job.apply_run_id`, `job.apply_state`), not by the Rust DTO —
      the wire is what the client decodes.
- [x] 3.5 Assert the **terminal** `apply-events` frame carries `run_id == A`,
      read from the real stream body (snapshot-first, so the frame arrives first
      and the stream closes — no timer, no polling loop).
- [x] 3.6 Repeat 3.2/3.4/3.5 for run B on the freed slot and assert both surfaces
      now name B (which is how run A's late client detects it).

## 4. Gating, harness and CI

- [x] 4.1 `AI_IMPORT_PG_TESTS=1` gate at the top of the case; without it print the
      reason and return, so the case passes as a skip.
- [x] 4.2 Register the case file in the existing `handlers_ai` harness
      (`#[path]` module) — no new `[[test]]` target (issue #631 link cost).
- [x] 4.3 Document the gate in `crates/api/tests/README.md` ("Environment-gated
      cases"), including that a green local `cargo test -p api` does not prove the
      case ran.
- [x] 4.4 CI: a step in the "Testcontainers integration tests" job
      (`integration-tests.yml`) with `AI_IMPORT_PG_TESTS=1`, a runner filter and a
      10-minute timeout. The fast `cargo test --workspace` job keeps running it as
      a skip.

## 5. Specification

- [x] 5.1 Delta `specs/ai-import/spec.md`: the identity rule as a requirement with
      four scenarios (live run, finished run, superseding run, composition
      coverage). The rule existed only in code comments before — changes `800`
      and `899` shipped without a spec delta.
- [x] 5.2 `openspec validate 912-ai-import-pg-composition`: valid.

## 6. Verification

- [x] 6.1 `cargo test -p api --test handlers_ai -- handler_ai_import_pg_composition`
      without the gate: passes (skip), no container started. The full harness
      reports 140 passed.
- [x] 6.2 With `AI_IMPORT_PG_TESTS=1` + Docker: passes (~4 s, including container
      start and migrations).
- [x] 6.3 Mutation proof — `apply_frame_run_id` → `slot.owner` only: the frame
      assertion fails. `decode_run_identity` → `owner` only: the job-read
      assertion fails. Both reverted.
- [x] 6.4 `cargo fmt -p api` + `cargo clippy -p api --tests`: clean.
