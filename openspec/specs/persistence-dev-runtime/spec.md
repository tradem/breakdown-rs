# Purpose

Define the scope and boundary of the `persistence-layer-v1` change: Postgres-only dev runtime, projection schema, and read/write port contracts. Production-grade SierraDB runtime and end-to-end round-trip are deferred to the `sierradb-runtime-and-round-trip` follow-up.

# Requirements

### Requirement: Minimal dev Postgres compose
`crates/infra` (or the repo dev tooling) SHALL provide a `docker-compose.dev.yml` that starts a single Postgres instance suitable for running projection migrations and the read/write path locally. It SHALL NOT include SierraDB, production-grade hardening, pinned container tags beyond a sensible default, persistent volumes, backup, or monitoring.

#### Scenario: Developer boots Postgres for projector/repo work
- **WHEN** `docker compose -f docker-compose.dev.yml up` is run
- **THEN** a Postgres instance is reachable on the documented port
- **AND** `sqlx::migrate!` against that instance applies the projection schema cleanly

#### Scenario: No SierraDB in the dev compose
- **WHEN** the dev compose is inspected
- **THEN** it contains exactly one service: Postgres
- **AND** SierraDB is absent

### Requirement: Documented local-run instructions
Local-run instructions for the dev Postgres compose and `sqlx::migrate` SHALL be recorded where developers look — `backend/AGENTS.md` and the repository `README.md` — including the exact command to start the dev database and apply migrations. The Docker prerequisite SHALL be stated.

#### Scenario: A new developer can boot the stack
- **WHEN** a developer reads `README.md` or `backend/AGENTS.md`
- **THEN** they find the start command, the migration command, and the Docker prerequisite

### Requirement: Production-grade runtime and SierraDB are out of scope
Production-grade compose (Postgres + SierraDB, pinned tags, volumes, backups, healthchecks, OpenTelemetry hooks per ADR-011), the SierraDB dev compose, and the SierraDB end-to-end round-trip integration test SHALL be deferred to the separate `sierradb-runtime-and-round-trip` change. v1's dev compose SHALL NOT be considered production-ready.

#### Scenario: v1 ships no SierraDB runtime
- **WHEN** the v1 change is delivered
- **THEN** no SierraDB container configuration, pinned image, or SierraDB lifecycle management is included
- **AND** a follow-up change named `sierradb-runtime-and-round-trip` is referenced as the owner of that work
