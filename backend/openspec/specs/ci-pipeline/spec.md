# CI Pipeline

## Purpose

Define the continuous integration pipeline that automatically verifies compilation, unit tests, code quality (clippy), formatting, and dependency policy on every push to main and on pull requests. The pipeline ensures that breaking changes are caught early and that code quality gates are consistently enforced.

## Requirements

### Requirement: CI workflow triggers on push to main and on pull requests
The CI workflow SHALL trigger on every `push` event to the `main` branch and on every `pull_request` event targeting any branch.

#### Scenario: Push to main triggers CI
- **WHEN** a commit is pushed to the `main` branch
- **THEN** all CI jobs (build, test, clippy, fmt, check) SHALL execute

#### Scenario: Pull request triggers CI
- **WHEN** a pull request is opened or updated
- **THEN** all CI jobs (build, test, clippy, fmt, check) SHALL execute

### Requirement: CI runs cargo build
The CI workflow SHALL include a `build` job that compiles the entire workspace with all targets and features.

#### Scenario: Build succeeds for clean workspace
- **WHEN** `cargo build --all-targets --all-features` is executed
- **THEN** the job SHALL pass with exit code 0

### Requirement: CI runs cargo test
The CI workflow SHALL include a `test` job that runs all unit tests across the workspace (excluding integration tests which have their own workflow).

#### Scenario: Unit tests pass
- **WHEN** `cargo test --workspace` is executed
- **THEN** the job SHALL pass with exit code 0

### Requirement: CI runs cargo clippy with warnings as errors
The CI workflow SHALL include a `clippy` job that runs clippy on all targets and features, treating warnings as errors.

#### Scenario: Clippy passes with no warnings
- **WHEN** `cargo clippy --all-targets --all-features -- -D warnings` is executed on code with no lint warnings
- **THEN** the job SHALL pass with exit code 0

#### Scenario: Clippy fails on lint warnings
- **WHEN** `cargo clippy --all-targets --all-features -- -D warnings` is executed on code with lint warnings
- **THEN** the job SHALL fail with a non-zero exit code

### Requirement: CI checks formatting with rustfmt
The CI workflow SHALL include a `fmt` job that verifies all code is formatted according to rustfmt defaults.

#### Scenario: Formatting check passes
- **WHEN** `cargo fmt --all -- --check` is executed on properly formatted code
- **THEN** the job SHALL pass with exit code 0

#### Scenario: Formatting check fails
- **WHEN** `cargo fmt --all -- --check` is executed on improperly formatted code
- **THEN** the job SHALL fail with a non-zero exit code

### Requirement: CI runs cargo check
The CI workflow SHALL include a `check` job that performs fast type-checking on all targets and features.

#### Scenario: Type check passes
- **WHEN** `cargo check --all-targets --all-features` is executed
- **THEN** the job SHALL pass with exit code 0

### Requirement: CI jobs use build caching
All CI jobs SHALL use `Swatinem/rust-cache@v2` to cache the Cargo registry and target directory.

#### Scenario: Cache restores on subsequent runs
- **WHEN** a CI job runs after the first execution
- **THEN** the `rust-cache` action SHALL restore cached dependencies from a previous run

### Requirement: CI jobs run in parallel
The build, test, clippy, fmt, and check jobs SHALL run in parallel (not sequentially).

#### Scenario: Jobs execute concurrently
- **WHEN** a CI workflow is triggered
- **THEN** all five jobs SHALL start without waiting for each other to complete

### Requirement: CI uses colored output
All CI jobs SHALL set `CARGO_TERM_COLOR: always` for readable colored output in logs.

#### Scenario: Colored output in CI logs
- **WHEN** any CI job produces Cargo output
- **THEN** the output SHALL include ANSI color codes for readability
