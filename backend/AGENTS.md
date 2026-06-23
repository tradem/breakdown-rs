# Agent Guidelines for breakdown-rs

You are the primary coding agent for `breakdown-rs` – a collaborative costume scheduling app. Your goal is to implement features securely, test-driven, and with clean architecture.

## 1. Architecture & Core Patterns
- **Hexagonal Architecture / Poor Man's DI:** No DI frameworks. External dependencies are defined as traits (ports) in `core` and manually injected in the composition root (`main.rs`).
- **CQRS & Event Sourcing:**
  - **Write Side:** All state changes occur via **Commands** sent to **Aggregates**. Aggregates validate commands and emit **Events**. State is never updated directly; it is rebuilt by replaying past events.
  - **Read Side:** **Queries** read from flat PostgreSQL **Projections**. Event Handlers asynchronously update these projections when new events occur. Never query aggregates directly for views.
- **kameo_es (Actors):** We use `kameo_es` for Event-Sourced aggregates. Each aggregate is a `kameo::Actor` implementing `kameo_es::Entity`. Commands act as `kameo_es::Command`.

## 2. Workspace Structure
- **`crates/core`:** Pure domain logic. Contains Commands, Events, Aggregates, Read-Model DTOs, and Port Traits. **No dependencies** on `sqlx`, `axum`, or infrastructure.
- **`crates/infra`:** Infrastructure implementations. Contains EventStore integrations, Projectors (Read-Model updaters), and `sqlx` queries.
- **`crates/api`:** Axum web server. Translates HTTP requests to Core Commands (Write) or Infrastructure Queries (Read).

## 3. Workflow & Best Practices
- **EventStorming Mapping:** 
  1. **Event** (Past tense, e.g., `SceneCreated`) -> `enum` in `core`
  2. **Command** (Imperative, e.g., `CreateScene`) -> `struct` in `core`
  3. **Aggregate** (Noun) -> State `struct` in `core`
- **Open-Spec / API First:** Define the API in the OpenAPI spec before writing code. Map exact types using `serde`.
- **ID Generation:** Strictly use **UUIDv7** (`uuid::Uuid::now_v7()`) for all entities and events. No UUIDv4.
- **Security:** Never hardcode secrets. Your code must pass `gitleaks`.

## 4. Testing & Guardrails
- **Unit/Integration Tests:** Write deterministic tests for domain logic in `core`.
- **Mutation Testing:** Run `cargo mutants` ([crate](https://crates.io/crates/cargo-mutants) • [GitHub](https://github.com/sourcefrog/cargo-mutants)). Improve test coverage if mutants survive. Use `cargo mutants --in-diff` to only test changed code.
- **Architecture Tests:** We use `arch_test` to enforce boundary rules. Run `cargo test -p architecture_tests` to ensure core does not depend on infra/api.

### Integration tests

End-to-end, black-box integration tests live in the dedicated workspace member `crates/integration-tests`. They exercise the full `command → event → event-store → projector → projection` chain against an ephemeral PostgreSQL container managed by [`testcontainers`](https://crates.io/crates/testcontainers).

- **How to run locally**: `cargo test -p integration-tests` (requires Docker or a compatible container runtime).
- **Boundary**: The crate consumes only the `pub` API of `core` and `infra`. It is excluded from the `cargo-mutants` surface — only whitebox `#[cfg(test)]` modules are mutated.
- **CI trigger**: The integration-test job runs on pull requests touching `backend/crates/{core,infra}/**`.
- **Container policy**: Each test gets a fresh Postgres container by default. Optional local container reuse is documented in the harness module docs, but CI always uses fresh containers.

## 5. Code Example: kameo_es Aggregate
```rust
#[derive(Actor, Default)]
pub struct CostumeAggregate { id: Uuid, is_assigned: bool }

impl Entity for CostumeAggregate {
    type ID = Uuid; type Event = CostumeEvent; type Metadata = ();
    fn category() -> &'static str { "costume" }
}

impl Command<CostumeAggregate> for AssignCostume {
    type Reply = Result<(), DomainError>;
    fn execute(self, state: &CostumeAggregate) -> Self::Reply {
        if state.is_assigned { return Err(DomainError::AlreadyAssigned); }
        Ok(CostumeEvent::CostumeAssigned { id: state.id })
    }
    fn apply(event: Self::Event, state: &mut CostumeAggregate) {
        if let CostumeEvent::CostumeAssigned { .. } = event { state.is_assigned = true; }
    }
}
```

## 6. Local Dev Runtime

v1 ships a **Postgres-only** dev compose. SierraDB is not included; the live `command → SierraDB → projector → PG` round-trip is deferred to the `sierradb-runtime-and-round-trip` follow-up change.

### Prerequisites
- Docker (or a compatible container runtime) for the dev database.

### Start the dev database
From the `backend/` directory run:

```bash
docker compose -f docker-compose.dev.yml up -d
```

This starts Postgres on `localhost:5432` with:
- user: `postgres`
- password: `postgres`
- database: `breakdown`

### Apply migrations
With the database running:

```bash
DATABASE_URL=postgres://postgres:postgres@localhost:5432/breakdown cargo run -p api
```

`main.rs` runs `sqlx::migrate!("../infra/migrations")` at boot. Tests that use `infra::testing::spawn_postgres()` apply the same migration set automatically.

### Environment variables used by the API binary
- `DATABASE_URL` – Postgres connection string (default: `postgres://postgres:postgres@localhost:5432/breakdown`)
- `SIERRADB_URL` – SierraDB RESP3 connection string, currently unused in v1 but required by `main.rs` (default: `redis://127.0.0.1:6379`)
- `BIND_ADDR` – HTTP bind address (default: `0.0.0.0:3000`)
- OpenAPI/Swagger UI is served at `http://localhost:3000/swagger-ui`

## 7. Licensing & Headers
- **License:** AGPL-3.0 (see `LICENSE`)
- **SPDX Headers:** Run `./scripts/add-spdx-headers.sh [dir]` to add headers to `.rs`, `.typ`, `.sh` files
- **Format:** `// SPDX-License-Identifier: AGPL-3.0` + `// Copyright (C) 2024 Breakdown RS Contributors`

*When in doubt about the domain logic or workflow, ask questions before generating code.*