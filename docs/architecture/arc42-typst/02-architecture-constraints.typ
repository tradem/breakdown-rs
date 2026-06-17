= Architecture Constraints

== Technical Constraints

=== Programming Language
- *Rust*: Chosen for performance, safety, and modern tooling
- *Edition 2021*: Latest stable Rust edition

=== Database
- *PostgreSQL*: Required for Event Store and Projections
- *Version*: 15+ (for proper JSONB support)

=== Framework Constraints
- *Axum*: Web framework (see #adr-ref(num: 5, title: "Use Axum")[ADR-005])
- *kameo*: Actor framework for Event Sourcing
- *SQLx*: Async PostgreSQL driver

== Organizational Constraints

=== Development Process
- *Test-Driven Development*: Required for all core logic
- *Mutation Testing*: `cargo mutants` must pass
- *Architecture Tests*: `arch_test` crate enforces boundaries

=== Documentation
- *ADRs*: All architectural decisions documented (see `docs/architecture/adrs/`)
- *OpenAPI*: API specification must be up-to-date
- *arc42*: Architecture documentation in Typst (this document)

== Conventions

=== Code Style
- `rustfmt` with default settings
- `clippy` warnings must be fixed
- No `unwrap()` in production code

=== Naming Conventions
- *Commands*: Imperative tense (e.g., `CreateScene`)
- *Events*: Past tense (e.g., `SceneCreated`)
- *Aggregates*: Noun (e.g., `SceneAggregate`)

=== Git Conventions
- *Conventional Commits*: `feat:`, `fix:`, `docs:`, etc.
- *Branch Naming*: `feature/`, `fix/`, `docs/`
- *Gitleaks*: No secrets in commits

// TODO: Add more constraints as needed
// TODO: Link to ADRs where relevant
