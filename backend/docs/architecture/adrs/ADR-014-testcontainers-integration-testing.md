# ADR-014: Testcontainers-based integration testing

**Status**: Accepted
**Date**: 2026-06-21
**Author**: Tobias Rademacher (@tradem)
**Related**: ADR-002 (event-sourcing / CQRS), ADR-003 (PostgreSQL), ADR-015 (SierraDB event store), ADR-016 (SierraDB runtime & round-trip)
**Source change**: `openspec/changes/archive/2026-06-21-testcontainers-integration-tests`

---

## Context

The event-sourced aggregates and projectors in `crates/infra` were only covered
by in-process whitebox unit tests. Nothing verified the full
`command → event → projector → Postgres` round-trip against a real database, so
migration drift, SQL-type mismatches, connection-pool behaviour and partial
failure paths remained hidden until production. We needed a deterministic,
isolated, Docker-based integration test harness and an ADR recording the
decision (GitHub issue #20).

## Decision

Adopt the [`testcontainers`](https://crates.io/crates/testcontainers) Rust crate
(with `testcontainers-modules` for Postgres) for black-box integration testing
against ephemeral PostgreSQL containers. Tests live in a dedicated workspace
member `crates/integration-tests` and consume only the `pub` API of `core` and
`infra`. Each test gets a fresh Postgres container by default; optional local
container reuse is available via `TESTCONTAINTERS_REUSE=1`, but CI always uses
fresh containers.

## Alternatives Considered

- **Shared dev database:** non-isolated, flaky, parallel-unsafe.
- **`sqlx::test` macro:** Postgres-only and too thin for the projector/event-store chain.
- **docker-compose-based test env:** heavier lifecycle, harder to isolate per-test.
- **In-memory `kameo_es` stores only:** would not exercise real RESP3/Postgres behaviour.

## Consequences

- Docker (or a compatible container runtime) is required on dev machines and CI.
- Tests carry a per-run container startup cost; isolation is per-test fresh.
- The `crates/integration-tests` crate is **excluded from the `cargo-mutants`
  surface** (see `.cargo/mutants.toml`); only inline `#[cfg(test)]` modules are mutated.
- ADR-002 and ADR-003 list ADR-014 under their related-ADRs sections.
- ADR-016 extends this harness to also start a SierraDB container for Tier-4
  round-trip tests.
