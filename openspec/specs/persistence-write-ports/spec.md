# Purpose

Define the write-side port contract: per-aggregate `*Commands` ports that translate command structs into aggregate replies, with mockable seams, optimistic concurrency, and infra wiring.

# Requirements

### Requirement: Per-aggregate command ports in core
The `core` crate SHALL define one async `*Commands` port per bounded context — `SceneCommands`, `CharacterCommands`, `CostumeCommands`, `CalculationCommands` — that translates the context's command structs into an aggregate reply. The event store itself SHALL NOT be a `core` port; persistence of events is owned by `kameo_es`/SierraDB (ADR-015) and the port boundary is command-shaped, not event-store-shaped.

#### Scenario: API depends on the port, not the adapter
- **WHEN** `crates/api` is compiled
- **THEN** it references only the `*Commands` traits from `core`, never `kameo_es::CommandService` or `redis`/SierraDB types

#### Scenario: Every existing command has a port method
- **WHEN** the four `*Commands` ports are inspected
- **THEN** each command struct declared in `core::{scene,character,costume,calculation}::commands` has a corresponding async method on its context port

### Requirement: Command ports are mockable seams
Each `*Commands` port method SHALL take owned command values (not borrows of infra types) and return the aggregate's reply (`Result<…, DomainError>` style); no `&PgPool`, `&CommandService`, or other infrastructure handle SHALL appear in any port signature.

#### Scenario: A handler unit test can substitute a fake command port
- **WHEN** an Axum handler unit test constructs a hand-written fake `SceneCommands` implementation
- **THEN** the test exercises the HTTP→command translation with no database or SierraDB dependency
- **AND** no `unsafe` or crate-internal type is required to construct the fake

### Requirement: Command methods carry version for optimistic locking
Every `*Commands` method that mutates an existing aggregate SHALL accept the caller-supplied expected `AggregateVersion` from the corresponding command struct, so that optimistic-concurrency failures surface to the caller.

#### Scenario: Stale version is rejected at the port boundary
- **WHEN** a `*Commands` method is invoked with a command whose `version` is older than the aggregate's current version
- **THEN** the method returns an error indicating a version conflict
- **AND** no event is appended to SierraDB

### Requirement: Write-side identifiers are UUIDv7
Every entity id and every event id generated on the write path SHALL be `Uuid::now_v7()` (ADR-004). No `Uuid::new_v4()` SHALL appear on the write path.

#### Scenario: A created aggregate returns a UUIDv7 id
- **WHEN** a `Create*` command is dispatched via its `*Commands` port
- **THEN** the returned id, when inspected, has version nibble `7`

### Requirement: Infra provides the write adapter; event store is not a core port
`crates/infra` SHALL provide the `kameo_es` `CommandService` wiring and per-aggregate `EntityActor` spawn behind the `*Commands` ports. `crates/core` SHALL NOT contain any `EventStore` trait, `redis`/`sierradb` import, or persistence mechanism.

#### Scenario: Core compiles without SierraDB types
- **WHEN** `crates/core` is built
- **THEN** no symbol from `redis`, `sierradb_client`, or a `kameo_es` event-store backend is reachable from `core`'s public API
