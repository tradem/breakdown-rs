# Aggregate Version Semantics

Define the canonical `AggregateVersion` contract used across the domain, the `*Commands` ports, projection rows, and optimistic concurrency: 1-based domain version with `INITIAL = 1`, with `±1` translation to/from the SierraDB stream version performed exclusively in `crates/infra`.

## Requirements

### Requirement: Canonical AggregateVersion contract
The canonical version notion exposed across the domain, the `*Commands` ports, the projection rows, and the optimistic-concurrency path SHALL be the 1-based `AggregateVersion` with `AggregateVersion::INITIAL = 1`, incremented by one on every aggregate mutation. A stream that has received `N` events SHALL expose `AggregateVersion(N)` to callers and in projections. The SierraDB `stream_version` (0-based) SHALL NOT be exposed across any `core` or `*Commands` port boundary.

#### Scenario: Domain version is one-based and starts at INITIAL
- **WHEN** an aggregate is created (first event appended with SierraDB `stream_version = 0`)
- **THEN** the version exposed to callers is `AggregateVersion::INITIAL` (`1`)
- **AND** the version stored in the corresponding `projection_*` row is `1`

#### Scenario: Domain version increments per mutation
- **WHEN** an existing aggregate with domain version `K` is mutated by a further command
- **THEN** the new domain version exposed to callers is `AggregateVersion(K + 1)`
- **AND** the corresponding `projection_*` row's `version` becomes `K + 1`

### Requirement: Stream-version translation happens only at the infra port boundary
Translation between the SierraDB `stream_version` (0-based) and the canonical domain `AggregateVersion` (1-based) SHALL occur exclusively inside `crates/infra`, at the `*Commands` adapter / projector boundary. The domain rule SHALL be `domain_version = stream_version + 1` and `stream_version = domain_version - 1`. `crates/core` SHALL NOT contain any reference to SierraDB `stream_version`, `ExpectedVersion`, or `CurrentVersion` types.

#### Scenario: Core is free of stream-version translation
- **WHEN** `crates/core` is built
- **THEN** no symbol from `sierradb_client`, `redis`, `kameo_es` event-store backend, `ExpectedVersion`, or `CurrentVersion` is reachable from `core`'s public API
- **AND** no `stream_version` arithmetic appears in `core`

### Requirement: Invalid zero domain version is rejected on the OCC input path
Any `update_*` `*Commands` port method that receives an expected `AggregateVersion(0)` SHALL return a `DomainError::VersionConflict` without appending any event to SierraDB, rather than underflowing `ExpectedVersion::Exact` or panicking. A non-existent/empty stream SHALL be reported on conflict paths as `current = AggregateVersion(0)` (no events → no domain version yet).

#### Scenario: Zero expected version is a client error
- **WHEN** an `update_*` command carries `version = AggregateVersion(0)`
- **THEN** the port method returns `DomainError::VersionConflict` with `current = 0`
- **AND** no event is appended to SierraDB

#### Scenario: Conflict against an empty stream reports current zero
- **WHEN** an `update_*` command targets a stream that has no events yet and the expected version is non-empty
- **THEN** the port method returns `DomainError::VersionConflict` whose `current` is `AggregateVersion(0)`
