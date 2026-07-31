## ADDED Requirements

### Requirement: Audit projector covers every aggregate category exhaustively
In addition to the per-entity projectors (scene, character, costume, etc.) that maintain the read-model projections, `crates/infra` SHALL provide an `AuditProjector` registered as an `EntityEventHandler` for every aggregate category (`season`, `block`, `episode`, `scene`, `scene_shoot`, `shooting_day`, `character`, `costume`, `costume_category`, `photo`, `membership`). Audit-projector coverage SHALL be enforced by a compile-time-exhaustive `AuditCategory` enum whose variants are matched exhaustively in supervisor registration, so that adding a new aggregate category without registering its audit projector fails the build.

#### Scenario: All aggregate categories have a registered audit projector
- **WHEN** the projector supervisor registration is compiled
- **THEN** every variant of `AuditCategory` (`Season`, `Block`, `Episode`, `Scene`, `SceneShoot`, `ShootingDay`, `Character`, `Costume`, `CostumeCategory`, `Photo`, `Membership`) has a registered `EntityEventHandler` audit projector writing to `projection_audit`

#### Scenario: New aggregate without audit projector variant fails to build
- **WHEN** a developer adds a new aggregate category but does not add a corresponding `AuditCategory` variant or register its `EntityEventHandler` audit projector
- **THEN** the workspace fails to compile with a non-exhaustive match error in the supervisor registration path

#### Scenario: Audit projector is idempotent per event redelivery
- **WHEN** the `AuditProjector` receives the same event twice across redelivery
- **THEN** exactly one row exists in `projection_audit` for that event (via the existing `event_key ON CONFLICT DO NOTHING` guard)

#### Scenario: Audit projector reads series_id from metadata, not from a parent projection
- **WHEN** the `AuditProjector` projects an event for a child aggregate (e.g. `SceneCreated`)
- **THEN** it copies `series_id` from the event's `EventMetadata`
- **AND** performs no lookup against parent aggregate projection rows to resolve `series_id`
