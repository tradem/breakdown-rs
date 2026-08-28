## Why

The repository currently has only a single CI workflow (`integration-tests.yml`) that runs integration tests on pull requests touching specific backend crates. There is no automated verification for compilation, unit tests, linting, formatting, or dependency security. This means breaking changes can slip through if they don't trigger integration tests, and dependencies with known vulnerabilities go undetected.

## What Changes

- Add a comprehensive CI workflow (`ci.yml`) that runs on **every push to `main`** and **every pull request**, executing: `cargo build`, `cargo test`, `cargo clippy`, `cargo fmt --check`, and `cargo check`.
- Enable Dependabot for Cargo dependencies and GitHub Actions versions to keep dependencies up to date automatically.
- Add a security audit workflow using `rustsec/audit-check` to catch known vulnerabilities in dependencies.
- Add `cargo-deny` as a CI step to enforce dependency policy (license compliance, duplicate detection, allowed sources) — extending the local usage documented in AGENTS.md.
- Add a scheduled mutation testing workflow (`cargo-mutants`) to run weekly, providing quality feedback without blocking PRs.
- Add build caching via `Swatinem/rust-cache@v2` across all workflows to reduce CI time.

## Capabilities

### New Capabilities
- `ci-pipeline`: Core CI workflow with build, test, lint, format, and type-checking jobs running on push to main and on PRs.
- `dependency-management`: Dependabot configuration for automated dependency updates (Cargo + GitHub Actions).
- `security-audit`: Scheduled and PR-triggered security vulnerability scanning via rustsec/audit-check.
- `dependency-policy`: cargo-deny integration for license compliance and dependency policy enforcement in CI.
- `mutation-testing`: Scheduled cargo-mutants runs for ongoing test quality assessment.

### Modified Capabilities
<!-- No existing spec-level requirements are changing. -->

## Impact

- **CI/CD**: New workflow files in `.github/workflows/`. Existing `integration-tests.yml` unchanged.
- **Repository configuration**: New `.github/dependabot.yml` file.
- **Developer workflow**: All PRs will now be gated by clippy, fmt, and build checks. Developers must ensure `cargo clippy`, `cargo fmt`, and `cargo test` pass locally before pushing.
- **Dependencies**: No new Rust crate dependencies — all tools are used via GitHub Actions or CLI.
- **GitHub Free plan**: All proposed features (Dependabot, GitHub Actions, caching) are available on free GitHub accounts at no cost.
