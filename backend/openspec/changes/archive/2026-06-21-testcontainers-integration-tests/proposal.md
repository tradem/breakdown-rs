## Why

The event-sourced aggregates and projectors in `crates/infra` are today only covered by in-process whitebox unit tests. Nothing verifies the full `command → event → projector → Postgres` round-trip against a real database, so migration drift, SQL-type mismatches, transaction/`StreamId` causation semantics, connection-pool behaviour and partial-failure paths remain hidden until production. We need a deterministic, isolated, Docker-based integration test harness — and the ADR that records this decision (ticket #20 / ADR-014).

## What Changes

- Add `testcontainers` + `testcontainers-modules` (`postgres` feature) as `[dev-dependencies]` of a new dedicated test crate.
- Introduce a new workspace member `crates/integration-tests` hosting black-box end-to-end tests (separate from the whitebox `#[cfg(test)]` surface that feeds `cargo-mutants`).
- Provide a shared, reusable test harness helper (`spawn_postgres()` → `PgPool` + owned `Container`) that keeps the container alive for the test's lifetime and runs `sqlx` migrations / `kameo_es` schema provisioning against it.
- Add at least one **smoke integration test** as a template: round-trip a single aggregate (e.g. `Costume`) through its command handler + projector against the spun-up Postgres.
- Draft and merge **ADR-014** (`docs/architecture/adrs/ADR-014-testcontainers-integration-testing.md`) following `docs/architecture/adrs/templates/ADR-template.md`, covering decision, alternatives, consequences, relationship to ADR-002 / ADR-003, and an explicit statement that these tests are **not** part of the `cargo-mutants` surface.
- Add a CI workflow that runs the integration suite on PRs touching `backend/crates/{core,infra}/**` (documented in CI config + `backend/AGENTS.md` and repo `README.md`).
- Wire a `testing` cargo feature so the shared `spawn_postgres` helper (and any future test doubles) can be reused by downstream crates.

## Capabilities

### New Capabilities

- `integration-testing`: Black-box, Docker-based integration tests that spin up an ephemeral Postgres per test/suite via Testcontainers, provision the event-store + projection schema, and assert the full `command → event → projector → projection` round-trip through the public `core`/`infra` API. Defines the shared test-harness contract, container lifecycle policy, and the boundary with whitebox/mutation tests.

### Modified Capabilities

<!-- No existing spec-level behaviour is being changed. The new harness is additive and does not alter production command/event/projection requirements. -->

## Impact

- **Code**: New workspace member `crates/integration-tests` plus (optionally) a `testing` feature on `infra` exposing a `pub mod testing` helper. No production behaviour changes.
- **Dependencies (dev only)**: `testcontainers`, `testcontainers-modules` (postgres), and transitively `tokio` test runtime; no runtime deps added.
- **Docs**: ADR-014 (repo `docs/architecture/adrs/`), updates to `backend/AGENTS.md` and repo `README.md` with local-run instructions and the Docker prerequisite.
- **CI**: New job/wf for integration tests on PRs touching `backend/crates/{core,infra}/**`; documented relationship to the separate `cargo-mutants` issue (#18 / mutants issue).
- **Boundary**: Hexagonal architecture preserved — tests consume only `pub` ports of `core`/`infra`; no reverse dependencies introduced.
