## Context

The `breakdown-rs` repository currently has a single CI workflow (`integration-tests.yml`) that runs testcontainer-based integration tests on PRs touching backend crates. There is no automated verification for compilation, unit tests, code quality (clippy), formatting (rustfmt), or dependency security. The project uses a hexagonal architecture with `core`, `infra`, `api`, and `integration-tests` crates in a Cargo workspace under `backend/`.

The repository is hosted on GitHub under a free plan. All proposed CI features (GitHub Actions, Dependabot, caching) are available at no cost on free accounts.

## Goals / Non-Goals

**Goals:**
- Gate every PR and main-branch push with build, test, clippy, fmt, and type-check verification.
- Automatically detect outdated or vulnerable dependencies.
- Enforce dependency policy (licenses, duplicates) in CI — extending local `cargo-deny` usage.
- Provide mutation testing feedback on a weekly schedule without blocking PRs.
- Keep CI fast through parallel jobs and Cargo build caching.

**Non-Goals:**
- Building release artifacts or deploying to any environment.
- Running integration tests in the new CI workflow (they stay in `integration-tests.yml`).
- Setting up GitHub Container Registry or Docker image builds.
- Configuring branch protection rules (that's a manual GitHub settings step, not a workflow concern).

## Decisions

### 1. Single `ci.yml` with parallel jobs (not separate workflows per check)

**Decision**: One workflow file with five parallel jobs: `build`, `test`, `clippy`, `fmt`, `check`.

**Rationale**: A single workflow is easier to maintain and provides a unified status check on PRs. Parallel execution keeps wall-clock time low. Separate workflows would create noise in the checks UI and duplicate trigger/cache configuration.

**Alternative considered**: Separate `clippy.yml`, `fmt.yml`, etc. — rejected due to maintenance overhead and duplicate cache setup.

### 2. Triggers: `push` to `main` + `pull_request` (not just PRs)

**Decision**: Trigger on `push` to `main` AND on all `pull_request` events.

**Rationale**: Running on main catches issues from direct pushes and merge commits. PR-only triggers miss post-merge breakage. The user explicitly requested main-branch coverage.

### 3. Dependabot for both `cargo` and `github-actions`

**Decision**: Configure Dependabot to update Cargo dependencies (directory: `/backend`) and GitHub Actions versions (directory: `/`).

**Rationale**: Keeps both Rust crates and action versions current. GitHub Actions version updates prevent security issues from outdated action pinned versions.

### 4. Security audit as a separate scheduled workflow (not a CI step)

**Decision**: A dedicated `audit.yml` workflow running on schedule (daily) and on PRs modifying `Cargo.lock`.

**Rationale**: Security audits are lightweight but should run regularly even without code changes. Keeping it separate avoids adding latency to the main CI pipeline. PR-triggered audit on `Cargo.lock` changes catches new vulnerable deps before merge.

**Alternative considered**: Inline audit step in `ci.yml` — rejected because audit failures on unrelated PRs would be noisy.

### 5. `cargo-deny` as a step in `ci.yml` (not a separate workflow)

**Decision**: Add a `deny` job to `ci.yml` that runs `cargo deny check bans`.

**Rationale**: The project already uses `cargo-deny` locally (AGENTS.md § Architecture Tests). Making it a CI job enforces the policy automatically. It's fast (~seconds) and fits naturally alongside other checks.

### 6. Mutation testing as a weekly scheduled workflow (not on PRs)

**Decision**: A dedicated `mutation-testing.yml` workflow with `schedule` trigger (weekly, Sunday night).

**Rationale**: `cargo-mutants` is slow (can take 30+ minutes). Running it on every PR would be impractical. A weekly schedule provides ongoing quality feedback. Developers can also trigger it manually via `workflow_dispatch`.

### 7. Use `Swatinem/rust-cache@v2` for build caching

**Decision**: Add `Swatinem/rust-cache@v2` step after toolchain installation in every workflow.

**Rationale**: Caches `target/` and `~/.cargo` registry/git. Reduces subsequent build times from minutes to seconds. Widely adopted, well-maintained action.

## Risks / Trade-offs

- **[Risk] CI time on free plan** → Mitigation: Free GitHub accounts get 2,000 minutes/month. Parallel jobs and caching minimize usage. If we hit limits, reduce check frequency or combine jobs.
- **[Risk] Dependabot PR noise** → Mitigation: Set `open-pull-requests-limit: 10` and group minor/patch updates. Review weekly.
- **[Risk] Flaky clippy lints blocking PRs** → Mitigation: Use `-D warnings` but pin Rust toolchain version via `rust-toolchain.toml` to avoid surprise lint additions on Rust updates.
- **[Risk] cargo-deny failures on new deps** → Mitigation: Document allowed/denied sources in `deny.toml`. Failures are informative, not blocking, until the team reviews the policy.
