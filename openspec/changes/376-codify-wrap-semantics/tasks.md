<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (pi) -->

# Tasks

## 1. Contract & core

- [x] 1.1 Register `scene-shoot.shooting-day-wrapped` (409, `shooting_day_id` S0)
      in `problem_codes!` (`crates/core/src/error_registry.rs`), bump `PROBLEM_CODE_COUNT`.
- [x] 1.2 Add `DomainError::ShootingDayWrapped { shooting_day_id }` (`crates/core/src/error.rs`).

## 2. API enforcement

- [x] 2.1 Render the new code in `domain_error_problem`
      (`crates/api/src/problems/mod.rs`) with the `shooting_day_id` extension.
- [x] 2.2 Add Fluent messages (de + en) for `problem-scene-shoot-shooting-day-wrapped`.
- [x] 2.3 Add handler-level wrap-finality gate
      (`ensure_execution_open`, API-edge projection read — CQRS-legal consumer)
      and wire it into start / actual-order / finish / skip / note
      add+update+remove handlers. Plan / replan / continuity-photos stay open.
- [x] 2.4 Write-side enforcement (PR #389 review): add `shooting_day_id` to the
      seven frozen commands; `SceneShootCommandsImpl` dispatches the zero-event
      `EnsureShootingDayOpen` probe against the ShootingDay event stream before
      every frozen command; the SceneShoot aggregate rejects a mismatched
      `shooting_day_id`. Route `day_id` is validated against the scene shoot's
      association at the API edge (404 on mismatch, before the wrap gate).
- [x] 2.5 Atomic serialization (PR #389 review follow-up): `WrapFinalityGate`
      takes a per-day PostgreSQL advisory lock (`pg_advisory_xact_lock`) held
      across `ShootingDayCommandsImpl::wrap`'s append and across each frozen
      SceneShoot mutation's [probe → append] critical section — closing the
      residual check-then-act interleave window between the two event-store
      appends (cross-instance safe; lock key XOR-mixed from both UUIDv7
      halves because the high 64 bits collide for same-millisecond ids).

## 3. Documentation

- [x] 3.1 utoipa descriptions: wrap handler documents the planning-vs-execution
      split; plan handler documents "planning stays supported (201)";
      execution handlers document the wrapped-day 409.
- [x] 3.2 Regenerate `backend/openapi.yaml`
      (`UPDATE_OPENAPI=1 cargo test -p api --test openapi_drift`).
- [x] 3.3 Add the code to `docs/errors/error-codes.md`.

## 4. Tests

- [x] 4.1 Extend `FakeShootingDayRepo` to serve configurable `ShootingDayView`s.
- [x] 4.2 Handler tests: wrap → plan **201** → start **409**
      (`scene-shoot.shooting-day-wrapped`); notes 409; replan 200 (planning open).
- [x] 4.3 Verify: `cargo test -p api -p core`, format, clippy on changed crates,
      OpenAPI drift clean.
- [x] 4.4 Write-side regression tests: `EnsureShootingDayOpen` probe (open →
      Ok/no-events, wrapped → `ShootingDayError::Wrapped`); frozen commands
      reject a mismatched `shooting_day_id`; adapter-level round trip
      (command → SierraDB) rejects `start` after `wrap` with
      `DomainError::ShootingDayWrapped`; handler tests for both day_id
      mismatch directions (404, no wrap bypass / no spurious 409).

## 5. Client

- [x] 5.1 Regenerate the Dart client if `scripts/regen-client.sh` output
      differs from the committed tree.
