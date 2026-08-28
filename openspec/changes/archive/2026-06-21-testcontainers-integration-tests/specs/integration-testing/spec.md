## ADDED Requirements

### Requirement: Integration tests run against an ephemeral Postgres in Docker
The integration test harness SHALL provide a shared helper that starts an isolated, ephemeral PostgreSQL instance via the `testcontainers` / `testcontainers-modules` crates, returns a usable `sqlx::PgPool`, and keeps the container alive for the lifetime of the owning test by returning the `Container`/`ContainerAsync` guard to the caller. The harness MUST NOT depend on any shared, long-lived developer database.

#### Scenario: Test gets its own isolated database
- **WHEN** a `#[tokio::test]` calls `spawn_postgres()` and obtains the returned `(PgPool, Container)` tuple
- **THEN** the pool connects to a fresh, empty Postgres instance whose state cannot be observed by any other concurrent test
- **AND** dropping the `Container` guard tears the instance down so no residue persists between test runs

#### Scenario: Fixture IDs are UUIDv7
- **WHEN** integration test fixtures create entities or events
- **THEN** all identifiers MUST be `Uuid::now_v7()` and MUST NOT use `Uuid::new_v4()` (per ADR-004)

### Requirement: Harness provisions the event-store and projection schemas
The harness SHALL provision the schemas required for an end-to-end round-trip against the spun-up Postgres: the `kameo_es` event-store schema (via its public bootstrap path, or a checked-in fixture kept in sync with the pinned `kameo_es` revision) and the projection schema via `sqlx::migrate!` from the migrations directory. Migration drift surfaced by the harness MUST fail the test, not be silently patched.

#### Scenario: Schema is ready before the test body runs
- **WHEN** `spawn_postgres()` returns successfully
- **THEN** the returned pool already has both the event-store tables and the projection tables migrated
- **AND** a subsequent `sqlx` query against any projection table succeeds without a "relation does not exist" error

#### Scenario: Migration drift fails the test
- **WHEN** a migration present on disk is missing from the spun-up schema (or vice-versa)
- **THEN** the harness reports a schema provisioning failure
- **AND** the test is marked failed rather than proceeding with a silently patched schema

### Requirement: Black-box end-to-end round-trip smoke test
The harness MUST include at least one smoke integration test that, against the spun-up Postgres, drives a real aggregate through the full `command → event → event-store → projector → projection` chain using only the public API of `core` and `infra`. It SHALL serve as the template for all future integration tests.

#### Scenario: Costume command round-trips into a projection row
- **WHEN** the test sends a `CreateCostume`-style command to a `Costume` aggregate backed by the real Postgres event store
- **THEN** the corresponding event is persisted in the event store
- **AND** the projector updates the `Costume` projection
- **AND** a read query against the projection returns the created costume's data, including its UUIDv7 id and project id
- **AND** the aggregate re-hydrated from the event store matches the state produced by replaying the events

#### Scenario: Smoke test demonstrates the template pattern
- **WHEN** a developer adds a new integration test
- **THEN** the smoke test file documents the canonical structure: `spawn_postgres()` → seed via public command API → assert via public query API → drop guards

### Requirement: Clear boundary with mutation-testing (whitebox) surface
Integration tests SHALL live in a dedicated crate (`crates/integration-tests`) that consumes only the `pub` API of `core` and `infra`. The integration tests MUST be excluded from the `cargo-mutants` surface. The harness helper(s) SHALL be exposed behind a `testing` cargo feature on `infra` (and `core` where needed) so they are never compiled into production builds, and no production crate MAY depend on the `integration-tests` crate.

#### Scenario: Production builds exclude testing helpers
- **WHEN** any production crate is built without the `testing` feature
- **THEN** none of the `spawn_postgres` / test-context helpers are compiled into that build

#### Scenario: No production crate depends on the test crate
- **WHEN** `cargo tree -p integration-tests` is run
- **THEN** `crates/{core,infra,api}` appear only as dependencies of `integration-tests`, never the reverse
- **AND** `integration-tests` appears as a dependency of no other workspace crate

#### Scenario: Integration tests are not mutated
- **WHEN** `cargo mutants` runs
- **THEN** the `crates/integration-tests` crate is excluded from the mutation surface (via mutants config / `--exclude`), leaving only whitebox `#[cfg(test)]` modules as the mutation target

### Requirement: ADR-014 records the Testcontainers decision
The repository SHALL contain `docs/architecture/adrs/ADR-014-testcontainers-integration-testing.md` following `docs/architecture/adrs/templates/ADR-template.md`. It MUST record: the decision to adopt Testcontainers (Rust crate) for Postgres integration testing; alternatives considered (shared dev DB, `sqlx::test` macro, docker-compose-based test env, in-memory `kameo_es` stores only); consequences (Docker required on dev + CI, test-runtime cost, isolation strategy); relationship to ADR-002 (event-sourcing/CQRS) and ADR-003 (PostgreSQL); and an explicit statement that these integration tests are not part of the `cargo-mutants` surface, cross-linked to the mutants tracking issue.

#### Scenario: ADR exists and is linked from related ADRs
- **WHEN** the ADR file is read
- **THEN** it follows the template's Context → Decision → Consequences → Alternatives structure
- **AND** ADR-002 and ADR-003 list ADR-014 under their related-ADRs sections
- **AND** the mutants exclusion is stated explicitly with a cross-link

### Requirement: CI runs the integration suite on relevant PRs
A CI workflow SHALL run the integration test suite on pull requests whose changes touch `backend/crates/{core,infra}/**`. The workflow and the Docker prerequisite MUST be documented in the CI configuration, `backend/AGENTS.md`, and the repository `README.md`, including the exact command to run the suite locally.

#### Scenario: PR touching core or infra runs integration tests
- **WHEN** a pull request modifies files under `backend/crates/core/**` or `backend/crates/infra/**`
- **THEN** CI runs the integration test crate against a Testcontainers-backed Postgres
- **AND** the suite status is a required (or clearly documented) check for those paths

#### Scenario: Local run instructions are present
- **WHEN** a developer reads `README.md` / `AGENTS.md`
- **THEN** they find the Docker prerequisite and the exact `cargo test -p integration-tests` (or equivalent) command to run the suite locally
