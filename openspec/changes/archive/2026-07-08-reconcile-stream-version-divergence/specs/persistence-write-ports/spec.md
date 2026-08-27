## MODIFIED Requirements

### Requirement: Command methods carry version for optimistic locking
Every `*Commands` method that mutates an existing aggregate SHALL accept the caller-supplied expected `AggregateVersion` from the corresponding command struct, so that optimistic-concurrency failures surface to the caller. The port boundary SHALL expose only the canonical 1-based domain `AggregateVersion` (with `AggregateVersion::INITIAL = 1`); the SierraDB `stream_version` (0-based) SHALL NOT cross the port boundary. The infra adapter SHALL translate the domain version to/from the SierraDB stream version at the boundary using `stream_version = domain_version - 1` and `domain_version = stream_version + 1`. `Create*` methods SHALL use `ExpectedVersion::Empty` (no translation) and SHALL return `AggregateVersion::INITIAL` (`1`) on the first appended event. An `update_*` method SHALL return the new domain version after the mutation, computed from the appended event's `stream_version + 1`.

#### Scenario: Stale version is rejected at the port boundary
- **WHEN** a `*Commands` method is invoked with a command whose `version` is older than the aggregate's current version
- **THEN** the method returns an error indicating a version conflict
- **AND** no event is appended to SierraDB

#### Scenario: Create reply carries the canonical domain version
- **WHEN** a `Create*` command is dispatched via its `*Commands` port against an empty stream
- **THEN** the port method returns `AggregateVersion::INITIAL` (`1`)
- **AND** the next command targeting the same aggregate accepts `AggregateVersion(1)` as the expected version without a spurious `VersionConflict`

#### Scenario: Update reply round-trips into the next update
- **WHEN** an `update_*` command succeeds and returns `AggregateVersion(K)`
- **THEN** issuing a further `update_*` command on the same aggregate with `version = AggregateVersion(K)` succeeds
- **AND** no spurious `VersionConflict` is raised by the SierraDB optimistic-concurrency check

#### Scenario: Read-model version reuses directly as the next expected version
- **WHEN** a client reads a `projection_*` row whose `version` is `AggregateVersion(K)` and feeds it as the expected version on the next `update_*` command
- **THEN** the port method succeeds against SierraDB
- **AND** SierraDB never receives a raw 1-based domain version as an `ExpectedVersion::Exact` stream position
