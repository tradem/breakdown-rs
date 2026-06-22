# ADR-014: Integration Testing with Testcontainers for PostgreSQL

**Status**: Accepted  
**Date**: 2026-06-21  
**Author**: Breakdown RS Contributors

---

## Context

Breakdown RS uses Event Sourcing and CQRS (ADR-002): the event store is provided by **sierradb** through `kameo_es`, while read models / projections live in **PostgreSQL** (ADR-003). Today, automated tests are limited to in-process, whitebox `#[cfg(test)]` modules inside each crate. This is the intended surface for mutation testing, but it cannot exercise:

- The full `command → event → event-store → projector → projection` round-trip.
- Migration drift between the projection schema on disk and the schema expected by projectors.
- SQL type mismatches, connection-pool behavior, or transaction/`StreamId` causality semantics against a real Postgres instance.

To close the Postgres-side gap, we need deterministic, isolated, Docker-based integration tests that run against an ephemeral PostgreSQL instance for projections.

## Decision

We will use the Rust [`testcontainers`](https://crates.io/crates/testcontainers) crate together with [`testcontainers-modules`](https://crates.io/crates/testcontainers-modules) (with the `postgres` feature) to start an ephemeral PostgreSQL container per integration test.

### Key choices

- **Dedicated test crate**: Integration tests live in `crates/integration-tests`, a workspace member whose only purpose is black-box end-to-end testing. It consumes only the public API of `breakdown_core` and `infra`.
- **Shared harness**: `infra::testing::spawn_postgres()` is exposed behind a `testing` cargo feature. It starts a fresh Postgres container, waits for readiness, and returns a `sqlx::PgPool` plus the owning `Container` guard.
- **Schema provisioning**: The projection schema is applied with `sqlx::migrate!` against the migrations directory; migration mismatches fail the test instead of being silently patched. The event-store schema is owned by sierradb and is exercised through the `kameo_es` command service in a separate sierradb-backed integration-test step.
- **Container lifecycle**: One container per test by default, ensuring isolation. Local developers may opt into container reuse (`TESTCONTAINERS_REUSE` or `.with_reuse(true)`) for speed, but CI always uses fresh containers.
- **Mutation-test boundary**: Integration tests are **not** part of the `cargo-mutants` mutation surface. Whitebox `#[cfg(test)]` modules remain the only mutation target.

## Consequences

### Positive

- ✅ **Real database coverage**: Catches projection-schema, SQL, and projector integration issues before production.
- ✅ **Isolation**: Each test gets its own empty Postgres instance; no shared developer database, no cross-test pollution.
- ✅ **Reproducible locally and in CI**: Same container image, same schema provisioning, same isolation strategy.
- ✅ **Clear architecture boundary**: Tests consume only `pub` APIs of `core` and `infra`; no reverse dependencies.
- ✅ **Schema drift detection**: Projection migration mismatches fail loudly.

### Negative

- ⚠️ **Docker required**: Developers and CI runners must have a Docker-compatible container runtime available.
- ⚠️ **Test runtime cost**: Starting a container per test adds seconds per test compared to in-process tests. Mitigated by optional local container reuse and by limiting the CI trigger to PRs touching `backend/crates/{core,infra}/**`.
- ⚠️ **Operational complexity on CI**: Runners must expose Docker clearly; missing Docker must fail the job rather than pass silently.
- ⚠️ **Projection migration maintenance**: Projection migrations must be kept in sync with projector code; mismatches fail tests loudly.

### Mitigation

- Document the Docker prerequisite in `README.md` and the local run command in `AGENTS.md`.
- Trigger the integration-test CI job only on relevant paths; move to a nightly lane if runtime becomes prohibitive.
- Surface container-start and Docker-missing errors explicitly in CI logs.

## Alternatives Considered

1. **Shared developer PostgreSQL database**
   - Rejected: shared state causes flakiness, requires coordination, and cannot guarantee a clean schema per test.
2. **`sqlx::test` macro against a shared Postgres server**
   - Rejected: still relies on a long-lived Postgres server and per-test `CREATE DATABASE` plumbing; less isolated than a full container.
3. **docker-compose-based test environment**
   - Rejected: requires an outer orchestration step and persistent services; conflicts with the goal of isolated, per-test environments.
4. **In-memory `kameo_es` stores only**
   - Rejected: would not exercise the sierradb event-store backend, SQL projection queries, or migration drift.

## Notes

- All integration-test fixtures use UUIDv7 (`Uuid::now_v7()`) per ADR-004; no `Uuid::new_v4()`.
- Integration tests are excluded from `cargo-mutants` so that mutation testing continues to target only whitebox unit tests in `#[cfg(test)]` modules (see issue #18 / the mutants tracking issue).
- The `integration-tests` crate must not be a dependency of any production crate. This is enforced by a CI `cargo tree` lint and by the hexagonal boundary tests.
- The exact local command is: `cargo test -p integration-tests`.
- The Postgres integration-test harness covers projections only. A full `command → sierradb event store → projector → Postgres projection` round-trip requires a sierradb test instance and is intentionally deferred to a follow-up feature branch; the harness structure here is already designed to host that step when it lands.

---

**Related ADRs**:

- [ADR-002: Use Event Sourcing and CQRS](./ADR-002-event-sourcing-cqrs.md)
- [ADR-003: Use PostgreSQL as Primary Database](./ADR-003-use-postgresql.md)
- [ADR-004: Use UUIDv7 for all entities](./ADR-004-use-uuidv7.md)
