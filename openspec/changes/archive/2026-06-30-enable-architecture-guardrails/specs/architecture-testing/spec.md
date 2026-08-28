## ADDED Requirements

### Requirement: Dependency-level boundary enforcement

The system SHALL enforce that the `breakdown_core` crate has no Cargo-level dependency on infrastructure crates. A `cargo-deny` configuration MUST ban the following crates from `breakdown_core`:
- `sqlx`
- `axum`
- `redis`
- `sierradb-client`
- `tokio` (core SHALL not spawn async runtimes)

The configuration SHALL live at the workspace root as `deny.toml`.

#### Scenario: Forbidden dependency added to core Cargo.toml

- **WHEN** a developer adds `sqlx` to `crates/core/Cargo.toml` dependencies
- **THEN** `cargo deny check bans` fails with a clear error message naming the banned crate and the violating package

#### Scenario: Allowed dependency in core passes

- **WHEN** a developer adds a permitted crate (e.g., `serde`, `uuid`, `thiserror`) to `crates/core/Cargo.toml`
- **THEN** `cargo deny check bans` passes without error

### Requirement: Source-level boundary enforcement

The system SHALL enforce that source files in `breakdown_core` do not contain `use` statements importing from forbidden modules. An architecture test using `rust_arkitect` MUST verify that no module within `breakdown_core` imports from:
- `sqlx`
- `axum`
- `redis`
- `sierradb_client`
- `breakdown_infra` (the `infra` crate)
- `api` (the `api` crate)

The test SHALL be a standard `#[test]` function runnable via `cargo test`.

#### Scenario: Forbidden use statement in core source

- **WHEN** a developer adds `use sqlx::PgPool;` to any `.rs` file under `crates/core/src/`
- **THEN** the architecture test fails with a message identifying the violating file, the forbidden dependency, and the applicable rule

#### Scenario: Allowed use statement in core source

- **WHEN** a developer adds `use breakdown_core::shared::EntityId;` to a core source file (intra-core dependency)
- **THEN** the architecture test passes

#### Scenario: Infra crate imports core (allowed direction)

- **WHEN** `crates/infra` imports from `breakdown_core` (e.g., `use breakdown_core::character::CharacterEvent`)
- **THEN** the architecture test passes (dependency direction is correct: outer → inner)

### Requirement: CI integration

The system SHALL execute architecture tests as part of the CI pipeline on every pull request. The CI job MUST:
- Run `cargo deny check bans` for dependency-level enforcement
- Run `cargo test` including the architecture test suite for source-level enforcement
- Fail the pipeline if either check fails

#### Scenario: CI catches architecture violation in PR

- **WHEN** a pull request introduces an architectural violation (forbidden use or dependency)
- **THEN** the CI pipeline fails with output identifying the specific violation

#### Scenario: CI passes for compliant changes

- **WHEN** a pull request does not introduce architectural violations
- **THEN** the CI pipeline passes the architecture check stage

### Requirement: Local testability

The system SHALL allow developers to run architecture tests locally using standard Cargo commands. Both `cargo deny check bans` and `cargo test -p architecture_tests` (or the equivalent test target) MUST work without requiring network access or special infrastructure.

#### Scenario: Developer runs architecture tests locally

- **WHEN** a developer executes `cargo test -p architecture_tests` in their local environment
- **THEN** the architecture tests run and report pass/fail within 30 seconds

#### Scenario: Developer checks dependency bans locally

- **WHEN** a developer executes `cargo deny check bans` in their local environment
- **THEN** the dependency check runs and reports pass/fail within 10 seconds

### Requirement: Clear violation messages

The system SHALL produce human-readable violation messages that clearly identify the nature and location of the violation. Error output MUST include:
- The rule that was violated (e.g., "core must not depend on sqlx")
- The file or module where the violation occurred
- The specific forbidden dependency that was found

#### Scenario: Violation message for source-level breach

- **WHEN** the architecture test detects a forbidden `use` statement
- **THEN** the error message contains the violating file path, the forbidden dependency name, and the rule description

#### Scenario: Violation message for dependency-level breach

- **WHEN** `cargo deny check bans` detects a banned dependency
- **THEN** the error message contains the banned crate name and the package that declared it
