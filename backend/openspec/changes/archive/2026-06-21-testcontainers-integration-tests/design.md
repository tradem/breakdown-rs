## Context

The `breakdown-rs` backend (Rust workspace under `backend/`, member crates `core` / `infra` / `api`) follows hexagonal architecture with CQRS + Event Sourcing (ADR-002) on PostgreSQL (ADR-003), implemented via `kameo_es` actors. Today the only automated tests are in-process, whitebox `#[cfg(test)] mod tests` inside each crate (e.g. `crates/core/src/testing.rs`, aggregate unit tests). There is no path that exercises the full `command → event → event-store → projector → projection` chain against a real database.

GitHub issue #20 asks for a **black-box integration test harness using Testcontainers + Postgres**, plus **ADR-014** recording the decision. Constraints:
- Hexagonal boundaries must hold: tests consume only `pub` ports of `core`/`infra`. No `infra → api` or reverse edges.
- Whitebox tests stay inline (`#[cfg(test)]`) — they are the `cargo-mutants` surface (ticket #18). Integration tests are explicitly excluded from that surface.
- All IDs are UUIDv7 (ADR-004); license header is AGPL-3.0 (`./scripts/add-spdx-headers.sh`).
- `kameo_es` is pulled from a git dependency; its postgres backend manages its own event-store schema.

The ticket lists four open design questions; this design resolves them (see *Decisions*).

## Goals / Non-Goals

**Goals:**
- Deterministic, isolated, locally-and-CI-reproducible integration tests backed by ephemeral Postgres in Docker.
- A reusable harness (`spawn_postgres()` + schema provisioning) usable as the template for all future integration tests.
- At least one end-to-end smoke test round-tripping a real aggregate through `infra`'s event store + projector into a `sqlx` projection.
- ADR-014 merged, capturing decision, alternatives, consequences, and the mutants-boundary statement.
- CI runs the suite on PRs touching `backend/crates/{core,infra}/**`; AGENTS.md + README document local run + Docker prerequisite.

**Non-Goals:**
- Setting up `cargo-mutants` CI (separate issue / mutants ticket).
- Upstreaming a `Context::test()` to `kameo_es` (separate issue, listed out-of-scope in #20).
- Rewriting whitebox unit tests — they stay inline and unchanged.
- Performance/load testing of Postgres.

## Decisions

### D1. Home for integration tests — dedicated workspace member `crates/integration-tests`
**Choice:** New workspace member `crates/integration-tests` (crate name `integration-tests`), with no `#[lib]` production surface — only `tests/` integration tests + a `harness` (or feature-gated `pub mod harness`) module.

**Alternatives considered:**
- `crates/infra/tests/` — closest to the DB layer, but loses the cross-crate (core + infra) end-to-end framing and couples the harness to `infra`'s `pub` surface that is only meant for tests. Would also pull `testcontainers` into `infra`'s `[dev-dependencies]`, blurring the "infra has no test-only crates" rule.
- `crates/integration-tests` (chosen) — keeps `testcontainers` isolated in a crate whose *only* purpose is testing; can depend on both `breakdown_core` and `infra` as a black-box consumer; future crate-local blackbox tests can live here too.

**Why:** Black-box end-to-end scenarios span write (`core` commands → `infra` event store) and read (`infra` projectors → `sqlx` projections); a dedicated crate expresses that scope and keeps dev-dependencies off the production crates.

### D2. Schema provisioning — `kameo_es` owns the event store; harness applies `sqlx` migrations for projections
**Choice:** The harness provisions two things against the spun-up Postgres:
1. `kameo_es` event-store schema — driven by `kameo_es`'s own setup path (per ADR-002 / ADR-003, the event store is `kameo_es` Postgres-backed). The harness uses whatever public bootstrap `kameo_es` exposes; if none, we apply the event-store DDL via a checked-in fixture (referenced, not duplicated).
2. Projection schema — applied from a migrations directory (e.g. `crates/infra/migrations/` or `crates/integration-tests/migrations/`) via `sqlx::migrate!`.

**Why:** Keeps a single source of truth (ADR-003's `events` + `projection_*` tables) and surfaces migration drift in CI — one of the explicit motivations in #20.

### D3. Container lifecycle — container-per-test by default; opt-in reuse for local speed
**Choice:** Each `#[tokio::test]` calls `spawn_postgres()` which starts an **owned** `testcontainers` Postgres container and holds the `Container` guard for the test's lifetime (dropping it tears it down). Local developers can opt into `testcontainers`'s *reuse* mechanism (`TESTCONTAINERS_REUSE` / builder `.with_reuse(true)`) for speed; CI always uses fresh containers.

**Alternatives considered:**
- *Shared container-per-suite* via a `OnceLock<…>` — faster, but reintroduces shared-state flakiness between tests (cross-test row pollution, ordering bugs) that #20 explicitly wants to avoid.
- *`sqlx::test`-style per-test databases on one server* — fast, but still one Postgres server image, complicates schema versioning, and is less isolated than a full container. Listed in #20's alternatives; not chosen.

**Why:** #20's own motivation statement ("isolated, ephemeral Postgres per test run — no shared-state flakiness, reproducible locally and in CI") pins isolation as the priority; reuse flag recovers most of the local speed without compromising CI determinism.

### D4. Reuse surface — `testing` cargo feature on `infra`, gated `pub mod testing`
**Choice:** Add a `testing` feature to `infra` (and, if needed, `core`) that exposes the shared harness helper(s):
- `pub async fn spawn_postgres() -> (PgPool, ContainerAsync<testcontainers_modules::postgres::Postgres>)`
- (Optionally) `pub fn test_context(pool) -> TestContext` wrapping a `kameo_es` context used by tests.

Both are compiled only under `#[cfg(feature = "testing")]`, so they never ship. The new `integration-tests` crate enables `infra/testing` in dev profile, and future crates can do the same.

**Why:** Ticket Q4 asks for a reusable helper; a feature gate is the idiomatic Rust way to publish a test-only API without polluting the public surface or adding a separate "support" crate.

### D5. Versioning, IDs, license headers
- All test fixtures use `Uuid::now_v7()` (ADR-004) — no `Uuid::new_v4()` in test data.
- Every new `.rs`, `.sh`, `.typ` file gets the SPDX header via `./scripts/add-spdx-headers.sh`.
- Secrets: none; testcontainers images are public, no credentials. `gitleaks` stays green.

## Risks / Trade-offs

- **Docker required on dev + CI runner** → documented in `README.md` / `AGENTS.md`; CI job is best-effort (failures on missing Docker are surfaced clearly, not masked) and can be moved to a nightly lane if too slow.
- **`kameo_es` is a git dependency** → a sandboxed/`Context::test()` from upstream would simplify D4; tracked separately out-of-scope (#20 notes). Adopt the manual fixture path now; swap when upstream lands.
- **Test-runtime cost** (≈ seconds per container) → container reuse opt-in (D3) + parallel test groups mitigate; CI path selector limits the suite to `core`/`infra`-touching PRs.
- **Schema drift between event-store fixture and `kameo_es` reality** → harness asserts the schema matches by booting a real aggregate, not by hand-rolling DDL; reviewed when bumping `kameo_es`.
- **Boundary erosion** (tests reaching into `infra` internals) → `arch_test` enforcement (AGENTS.md §4) re-enabled/extended conceptually: integration-tests crate must not be a production dependency of any crate. CI lint: `cargo tree`-based check that nothing depends on `integration-tests`.
- **`testcontainers-modules` version churn** → pin a known-good version; bump deliberately.

## Migration Plan

1. Add ADR-014 (status: Accepted) following the template; cross-link ADR-002, ADR-003, ADR-004.
2. Add `crates/integration-tests` workspace member + `infra`/`core` `testing` features (additive, no behaviour change).
3. Land `spawn_postgres()` harness + one smoke test round-tripping `Costume` (or whichever aggregate has both an event-store path and a projection ready; if projectors are still stubs, the smoke test asserts the event-store round-trip and documents the projector step as a follow-up that the harness already supports).
4. Wire CI workflow (on PRs touching `backend/crates/{core,infra}/**`).
5. Update `backend/AGENTS.md` + repo `README.md`.

Rollback: remove the workspace member and CI job; ADR-014 → Deprecated. No production code shipped, so rollback is trivial/all-reversible.

## Open Questions

- Confirmed-by-default assumptions (no further user input needed to proceed; listed for transparency):
  - Crate name `integration-tests` / capability name `integration-testing`.
  - Default aggregate for the smoke test: `Costume` (richest existing aggregate in `core`).
- To resolve during implementation (deferred, non-blocking):
  - Exact public bootstrap entry-point name in `kameo_es` for provisioning the event store (verify against the pinned git revision when implementing D2 step 1).
  - Whether the projector for the smoke-test aggregate is ready; if not, the smoke test covers the event-store half and the projector half lands as a tracked follow-up using the same harness.
