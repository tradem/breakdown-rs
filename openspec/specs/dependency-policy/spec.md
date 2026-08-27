# Dependency Policy

## Purpose

Enforce dependency policy in CI using `cargo-deny` to ensure license compliance, prevent banned crates, and detect duplicate dependencies. This complements the local `cargo-deny` usage documented in the project's development guidelines.

## Requirements

### Requirement: cargo-deny runs in CI
A `deny` job SHALL be included in the CI workflow that runs `cargo deny check bans` to enforce dependency policy.

#### Scenario: Dependency policy passes
- **WHEN** all dependencies comply with the `deny.toml` policy (no banned crates, allowed licenses, no duplicates)
- **THEN** the deny job SHALL pass with exit code 0

#### Scenario: Dependency policy violation
- **WHEN** a dependency violates the `deny.toml` policy
- **THEN** the deny job SHALL fail with a non-zero exit code and report the violation

### Requirement: cargo-deny job uses build caching
The `deny` job SHALL use `Swatinem/rust-cache@v2` for build caching, consistent with other CI jobs.

#### Scenario: Cache restores for deny job
- **WHEN** the deny job runs after the first execution
- **THEN** the `rust-cache` action SHALL restore cached dependencies
