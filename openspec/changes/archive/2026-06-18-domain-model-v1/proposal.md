## Why

This change establishes the foundation of the core domain layer for breakdown-rs, a collaborative costume scheduling app. It implements the aggregate boundaries, business logic, commands, and events using CQRS and Event Sourcing via the `kameo_es` crate in a pure Hexagonal Architecture (`crates/core`), setting up strict typing and numeric safety for all future modules.

## What Changes

- Implement core domain models under `crates/core` completely decoupled from infrastructure concerns (no `sqlx`, `axum` dependencies).
- Establish Event-Sourced Actor pattern using `kameo_es` for deterministic state transitions.
- Model four main aggregates: Character, Scene, Costume, and Calculation.
- Define strongly typed Value Objects for cross-domain IDs globally (e.g. `ProjectId`) and Optimistic Locking (`AggregateVersion`).
- Enforce `rust_decimal` for all numeric values (measurements, currencies) to prevent float inaccuracies.
- Implement explicit compensation functions ("Reverse Actions") instead of generic rollbacks (Undo).
- Distinguish between "Form-Data Updates" (God-Commands for state overrides) and "Behavioral Actions" (granular event-based logic for relations, e.g., assigning/unassigning resources).

## Capabilities

### New Capabilities
- `core-domain-character`: Aggregates, Commands, Events for Character capabilities including measurements and data management.
- `core-domain-scene`: Aggregates, Commands, Events for Scene planning and character assignment.
- `core-domain-costume`: Aggregates, Commands, Events for Fundus and Character Costume management.
- `core-domain-calculation`: Aggregates, Commands, Events for Währungseinheiten (currency) and item cost calculations.
- `core-domain-shared`: Global Value Objects, Aliases (ProjectId, Uuidv7 logic), and Optimistic Locking semantics (`AggregateVersion`).

### Modified Capabilities

## Impact

- **Core Codebase**: Initializes `crates/core` with new models.
- **Dependencies**: Integrates `rust_decimal`, `kameo_es`, and `thiserror` heavily. Enforces UUIDv7 from the `uuid` crate.
- **No Infra/API impact yet**: This prepares strictly pure models. APIs and Projects are kept out of boundary intentionally until future Epics.