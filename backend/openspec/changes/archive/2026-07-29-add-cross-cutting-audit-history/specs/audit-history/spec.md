## ADDED Requirements

### Requirement: Shared `EventMetadata` captures actor, provenance, and tenant on every event
Every event-sourced aggregate in `crates/core` SHALL declare `type Metadata = core::shared::EventMetadata`. `EventMetadata` SHALL carry `actor: Option<UserId>` (the authenticated OIDC `sub`), `provenance: Provenance` (a discriminator of `Human | Saga(&'static str) | System`), and `series_id: Option<SeriesId>` (the denormalized tenant key). The previous `MembershipMetadata` and the `()` metadata on the other 10 aggregates SHALL be superseded by this shared type.

#### Scenario: Human actor is recorded on a dispatched command
- **WHEN** an authenticated `UserId` dispatches a `CreateScene` command whose adapter injects `EventMetadata { actor: Some(user), provenance: Provenance::Human, series_id: Some(sid) }`
- **THEN** the persisted event's metadata carries that `actor`, `provenance = Human`, and the `series_id`

#### Scenario: Saga-dispatched command records its provenance
- **WHEN** `SeasonSeedingSaga` dispatches `CreateCostumeCategory` for a season's default categories
- **THEN** the command adapter injects `EventMetadata { actor: None, provenance: Provenance::Saga("SeasonSeedingSaga"), series_id: Some(sid) }`
- **AND** the resulting audit row records `provenance = Saga("SeasonSeedingSaga")` and `actor = NULL` (not the system conflation)

#### Scenario: System-initiated command records System provenance
- **WHEN** a command is dispatched by an internal system path that is neither authenticated human nor a named saga
- **THEN** `EventMetadata` carries `provenance = System` and `actor = None`

#### Scenario: Pre-existing events of formerly `()`-aggregates carry NULL actor and System provenance
- **WHEN** an audit row is read for a pre-change event of a formerly `()`-metadata aggregate
- **THEN** `actor` is `NULL` and `provenance` reflects the honest state (`System`), not a fabricated value

### Requirement: `series_id` is denormalized in command metadata, not resolved at projection time
Each command adapter SHALL resolve `series_id` at dispatch time and inject it into `EventMetadata.series_id`. The `AuditProjector` SHALL copy `series_id` from the event metadata verbatim into `projection_audit.series_id` and SHALL NOT walk the entity→series chain at read time. This eliminates the projector's ordering dependency on parent aggregate projectors.

#### Scenario: Block command carries its denormalized series_id
- **WHEN** `CreateBlock` is dispatched and the command payload already carries `series_id`
- **THEN** the adapter injects that `series_id` into `EventMetadata` without an additional lookup
- **AND** the resulting audit row's `series_id` matches the command's `series_id`

#### Scenario: Scene command resolves series_id via a single read
- **WHEN** `CreateScene` is dispatched and the command payload carries `episode_id` but not `series_id`
- **THEN** the adapter performs a single read (via the relevant repository) to resolve the parent `series_id`
- **AND** injects the resolved `series_id` into `EventMetadata`
- **AND** the audit projector copies it without any further lookup

#### Scenario: Audit projector has no chain-resolution dependency
- **WHEN** a child aggregate's event (e.g. `SceneCreated`) is projected before the parent aggregate's event (`BlockCreated`) in its own transaction
- **THEN** the audit projector reads `series_id` directly from `EventMetadata` and succeeds
- **AND** never blocks or FK-fails on a missing parent-projection row

### Requirement: Audit history covers every aggregate category
The `AuditProjector` SHALL be registered as an `EntityEventHandler` for every aggregate category in the system (`season`, `block`, `episode`, `scene`, `scene_shoot`, `shooting_day`, `character`, `costume`, `costume_category`, `photo`, `membership`). Every category's events SHALL be written into `projection_audit` with actor, provenance, `series_id`, `event_type`, `entity_id`, `payload`, and `occurred_at`.

#### Scenario: Non-membership events appear in the audit projection
- **WHEN** `CreateCharacter` is dispatched and projected
- **THEN** a row exists in `projection_audit` with `entity_type = "character"`, `event_type = "CharacterCreated"`, and the actor from `EventMetadata`

#### Scenario: Membership events continue to project as before
- **WHEN** `MemberInvited` is dispatched and projected
- **THEN** a row exists in `projection_audit` with `entity_type = "membership"`, `event_type = "MemberInvited"`, and the actor from `EventMetadata` (unchanged from v1 behavior)

#### Scenario: Idempotent projection under redelivery
- **WHEN** the same event is delivered to the audit projector twice
- **THEN** only one row exists in `projection_audit` (the second is a no-op via the `event_key ON CONFLICT DO NOTHING` guard)

### Requirement: Compile-time-exhaustive audit-projector coverage guard
An exhaustive `AuditCategory` enum SHALL enumerate every aggregate category with an audit projector. The supervisor registration path SHALL match on this enum exhaustively, so that adding a new aggregate category without adding a variant (and registering its audit projector) fails compilation.

#### Scenario: New aggregate added without variant fails to build
- **WHEN** a developer adds a 12th aggregate but does not add a variant to `AuditCategory` or register its audit projector
- **THEN** the workspace fails to compile (non-exhaustive match error in supervisor registration)

#### Scenario: All current categories are covered
- **WHEN** the `AuditCategory` enum and supervisor registration are compiled
- **THEN** all 11 categories (`season`, `block`, `episode`, `scene`, `scene_shoot`, `shooting_day`, `character`, `costume`, `costume_category`, `photo`, `membership`) have a registered `EntityEventHandler` audit projector

### Requirement: Audit history is read from the projection, never directly from the event store
The audit history view SHALL be served exclusively from the Postgres `projection_audit` via the `AuditRepository` port. No code path serving the history view SHALL query the SierraDB event store directly. The event store remains the authoritative source for replay/rebuild only.

#### Scenario: History view query path
- **WHEN** an administrator requests the audit history (filtered by actor, entity, time range, or series)
- **THEN** the request is served via `AuditRepository` against `projection_audit`
- **AND** no read against SierraDB's `ESCAN`/`EPSCAN`/`EGET` is performed to serve the view

#### Scenario: Projection is rebuildable from the event store
- **WHEN** the event store is replayed from its earliest checkpoint
- **THEN** the `AuditProjector` reconstructs `projection_audit` deterministically and idempotently

### Requirement: Audit history supports tenant-scoped queries
`AuditRepository` SHALL support queries scoped by `series_id` so an administrator can view history for a single series (tenant). Existing query methods (`list_by_block`, `list_by_actor`, `list_by_time_range`, `list_by_entity`) SHALL remain available.

#### Scenario: List by series
- **WHEN** `list_by_series(series_id, limit, offset)` is called
- **THEN** audit rows matching that `series_id` are returned, newest first, with `LIMIT`/`OFFSET` pagination

#### Scenario: Tenant filter excludes other series
- **WHEN** an audit row's `series_id` differs from the requested `series_id`
- **THEN** it is excluded from the result set
