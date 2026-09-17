<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# Proposal: Deterministic `block.number-already-exists` fault injection for the wizard Gherkin partial-failure scenario (issue #443)

## Problem

The season setup wizard's Gherkin partial-failure scenario
(`frontend-flutter/features-spec/setup/season-wizard.feature`,
"Partial failure stops the dispatch and offers in-session retry") arranges
failure ONLY by setting `AppWorld.wizardExpectsPartialFailure` in the Given
step. A client-side arrange is impossible by construction: the wizard DERIVES
the first free series-scoped block number from the projections (`max + 1`),
so a pre-seeded conflicting block is avoided, not hit. A real deterministic
`409` requires an injectable failure point server-side.

**Drift finding during analysis:** the backend's real registry code for the
block-number pre-check is `block.number-already-exists`
(`crates/core/src/error_registry.rs:358`, emitted at
`crates/api/src/handlers/mod.rs:848`). The client's `wizardErrorCopy`
(`setup_wizard_state.dart`) maps `blocks.conflict`/`block.conflict` — a code
the backend NEVER emits — so even with fault injection wired up the scenario
would render the generic fallback instead of the series-scoped copy. The
Gherkin then-step asserts the series-scoped copy verbatim. Fixing this code
mapping is part of the acceptance path, not optional cleanup.

## Decision (user-confirmed)

**Mechanism: a `test-support`-feature-gated axum layer** (option 3 of 3:
injection header, dev control endpoint, feature-gated layer). The
compile-time gate is the hardest guarantee the injection can never ship:
release builds do not even contain the code. Costs accepted by the user:
the dev/E2E backend binary must be built with
`--features api/test-support`, and the existing dummy `test-support`
feature (added for cargo-mutants, issue #267) becomes real for the `api`
crate.

## Scope: backend + Flutter client (one PR)

### Backend

1. **New module `crates/api/src/fault_injection.rs`**, entirely inside
   `#[cfg(feature = "test-support")]`:
   - `FaultInjectionState`: process-local `Mutex<HashMap<String, usize>>`
     of armed faults keyed by an injection key (fingerprint string);
     `arm(key)`, `take(key) -> bool` (one-shot latch: `take` removes the
     entry so the FIRST matching request fires and the retry passes).
   - `fault_injection_middleware` (axum `middleware::from_fn_with_state`):
     for `POST /v1/blocks` requests whose request body `series_id`/`number`
     fingerprint matches an armed key AND whose latch is still set, short-
     circuit with the REAL registry problem
     (`DomainError::Conflict { code: &BLOCK_NUMBER_ALREADY_EXISTS, .. }` →
     RFC 9457 `application/problem+json` 409 exactly like the advisory
     pre-check emits). No new problem code is registered (the
     `problem-code-registry` rule is untouched); the middleware reuses the
     existing registry const.
   - The middleware reads and buffers the small JSON request body to derive
     the fingerprint, then re-injects it for the handler. Alternatively the
     key may be carried in an `X-Breakdown-Fault-Key` header honored ONLY by
     this layer — the fingerprint derivation must be deterministic between
     the arming call and the wizard's request, so the header-keyed variant
     is the implementation default (the Gherkin arrange sends the same key
     the middleware waits for; a body-hash would depend on exact JSON
     serialization of the generated Dart client).
2. **Wiring:** `app_router` (routes/mod.rs) gains the layer ONLY under
   `#[cfg(feature = "test-support")]`; `main.rs` passes the
   `FaultInjectionState` (or a no-op/Unit variant in non-test builds is NOT
   needed since cfg removes the layer entirely).
3. **Dev binary gate:** `tool/run_gherkin.sh` and the backend dev-boot docs
   note the E2E backend must run
   `cargo run -p api --features api/test-support` while acceptance runs.
   Exclude: production/GitHub-CI backend boot paths do not enable the
   feature (unchanged commands).
4. **Tests:** a new `crates/api/tests/fault_injection_test.rs` (gated
   `#![cfg(feature = "test-support")]`) asserting: armed key → first
   `POST /v1/blocks` returns 409 `block.number-already-exists` problem JSON;
   retry (second request) passes through (201/other); unarmed key → pass-
   through; non-block routes with the header → pass-through. Also verify
   the response document byte-matches the advisory pre-check's 409 shape
   (code, title, status fields).
5. **Docs:** `docs/security/README.md` safe-patterns note: the
   `X-Breakdown-Fault-Key` header is recognized ONLY in
   `test-support` builds; production builds structurally lack the layer.

### Flutter client

1. **Code mapping fix (acceptance blocker):**
   `lib/features/seasons/setup/setup_wizard_state.dart` `wizardErrorCopy`
   maps the REAL backend code `'block.number-already-exists'` (and keeps
   the legacy `blocks.conflict`/`block.conflict` aliases for unit-test
   fixtures) to the series-scoped copy. Same alignment for
   `episodes.conflict` → `episode.number-already-exists` and
   `seasons.conflict` → `season.number-already-exists` in
   `seasons_screen.dart` / `episodes_screen.dart` where the same real-code
   gap exists.
2. **Gherkin Given step** (`integration_test/gherkin/steps/
   season_wizard_steps.dart`): the arming step performs an HTTP `POST` to
   the dev backend's arming endpoint `/v1/__faults/block-conflict`
   (mounted under the same `#[cfg(feature = "test-support")]` gate inside
   the fault-injection module) with the injection key header/body, then
   sets `wizardExpectsPartialFailure` (kept as the assertion-side intent
   flag). The arming call uses plain `package:http`/`Dio` from the host
   runner process (the runner is a Dart VM process with network access —
   NOT sandboxed — so it can reach `API_BASE` directly).
3. **Keep the unit tier as-is:** `test/features/seasons/setup/
   setup_wizard_controller_test.dart`'s scripted `createResults` fakes
   remain authoritative for deterministic partial-failure coverage.

## Guardrail compliance

- No standalone problem code added (reuses `BLOCK_NUMBER_ALREADY_EXISTS`).
- No `unwrap`/`expect`/`panic!` in production paths (the middleware uses
  `?`/explicit fallback; cfg-gated module still compiles under clippy deny).
- `test-helper-gate` compliant: the fault-injection module is entirely
  `#[cfg(feature = "test-support")]`-gated, not merely a `*_for_test` name.
- No release binary can contain the layer (compile-time absence).
- Header is inert in non-test builds BY ABSENCE (no layer compiled).

## Version-bump plan

| Package | Previous | New | Bump | Reason |
|---|---|---|---|---|
| `api` crate | 0.10.0 | 0.10.0 | none | New cfg-gated module only; entry under open `## [0.10.0] - Unreleased` CHANGELOG section |
| `core` crate | 0.11.0 | 0.11.0 | none | No core change |
| Flutter client | 0.3.0-alpha.8+17 | 0.3.0-alpha.9+18 | pre-release increment (fix) | Code-mapping fix + Gherkin arrange; per alpha-line practice (even fixes bump `+N`) |

## Validation plan

- Backend: `cargo test -p api --features api/test-support --test
  fault_injection_test`, `cargo clippy --workspace --all-targets
  --all-features`, `cargo fmt --check`. However: NOTE the existing dummy
  feature already builds via `--all-features`.
- Flutter: `dart format --set-exit-if-changed .`, `flutter analyze`,
  `flutter test` (unit+widget), `dart run build_runner build` only if
  annotations changed (not expected here), OpenAPI drift: NOT triggered
  (no `backend/openapi.yaml` change — the arming endpoint is cfg-gated and
  MUST NOT appear in the wire contract; o derive nothing new in `#[openapi]
  paths`).

## Out of scope

- Offline command queue, retry persistence beyond the existing in-session
  retry (wizard contract, decisions 3/6).
- A generic fault-injection DSL (block conflict is the single designated
  scenario; episode/season conflicts can follow the same pattern later).
