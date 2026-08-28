## ADDED Requirements

### Requirement: Projection version mirrors the canonical domain version
Every `projection_*.version` column SHALL mirror the canonical 1-based domain `AggregateVersion` carried in the decoded event payload's `version` field (i.e. `AggregateVersion::INITIAL = 1` for the first event, incremented per mutation), NOT the raw SierraDB `stream_version`. A projector SHALL NOT bind `event.stream_version` into any `projection_*` column. The projection version SHALL be directly reusable as the expected `AggregateVersion` on the next `*Commands` write without any client-side translation.

#### Scenario: Created projection row carries INITIAL
- **WHEN** a `*Created` event with payload `version = AggregateVersion::INITIAL` and SierraDB `stream_version = 0` is projected
- **THEN** the inserted `projection_*.version` column is `1`
- **AND** no projector binds `event.stream_version` into that column

#### Scenario: Mutated projection row increments the domain version
- **WHEN** a mutation event with payload `version = AggregateVersion(K)` and SierraDB `stream_version = K - 1` is projected
- **THEN** the updated `projection_*.version` column is `K` for the parent row (and any touched sub-row)

#### Scenario: Projection version feeds back without translation
- **WHEN** a client reads `projection_*.version = K` and issues an `update_*` command with `version = AggregateVersion(K)`
- **THEN** the write succeeds with no spurious `VersionConflict`, because the projection version equals the canonical domain version the port expects
