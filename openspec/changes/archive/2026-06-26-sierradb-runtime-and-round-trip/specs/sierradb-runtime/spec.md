## ADDED Requirements

### Requirement: SierraDB runs locally for development
The change SHALL provide a dev runtime (docker-compose or equivalent) that starts a SierraDB instance speaking RESP3 on a documented port, alongside the Postgres service already provided by `persistence-layer-v1`. `main.rs` SHALL be able to boot against these local containers and serve a live write path.

#### Scenario: Developer boots both tiers
- **WHEN** the dev compose is started
- **THEN** both Postgres and SierraDB are reachable on their documented ports
- **AND** `main.rs` boots end-to-end using a `CommandService` over the SierraDB connection

#### Scenario: Connection string is environment-driven
- **WHEN** `main.rs` starts
- **THEN** it reads the SierraDB connection string (RESP3 `redis://…:9090/`) from environment configuration, not a hardcoded value (gitleaks-clean)

### Requirement: SierraDB version is pinned
The dev and production runtimes SHALL pin SierraDB to a single tested tag matching the mechanism chosen by the SierraDB image-path decision (upstream image or build-from-source), and a NEW or amended ADR SHALL record that decision and supersede ADR-015's "image unknown" note.

#### Scenario: Tag is deterministic
- **WHEN** the runtime configuration is inspected
- **THEN** the SierraDB tag is an explicit, pinned value
- **AND** an ADR records the chosen image-path decision

### Requirement: Production-grade runtime covers both tiers
The production runtime configuration SHALL include, for both Postgres and SierraDB: a pinned version tag, persistent volumes, a backup/recovery story, healthchecks, and OpenTelemetry hooks (ADR-011).

#### Scenario: Both tiers are observable
- **WHEN** the production runtime is deployed
- **THEN** healthchecks for both Postgres and SierraDB are configured
- **AND** observability hooks (tracing/metrics) are wired for both tiers
