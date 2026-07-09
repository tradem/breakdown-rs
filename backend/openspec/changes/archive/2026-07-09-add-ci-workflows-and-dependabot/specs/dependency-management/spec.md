## ADDED Requirements

### Requirement: Dependabot monitors Cargo dependencies
Dependabot SHALL check for updates to Cargo crate dependencies in the `/backend` directory on a weekly schedule.

#### Scenario: Dependabot detects outdated Cargo dependency
- **WHEN** a Cargo crate in `Cargo.lock` has a newer version available
- **THEN** Dependabot SHALL open a pull request with the dependency update

### Requirement: Dependabot monitors GitHub Actions versions
Dependabot SHALL check for updates to GitHub Actions used in workflow files on a weekly schedule.

#### Scenario: Dependabot detects outdated GitHub Action
- **WHEN** a GitHub Action referenced in `.github/workflows/` has a newer version
- **THEN** Dependabot SHALL open a pull request updating the action version

### Requirement: Dependabot PR limit
Dependabot SHALL limit the number of open pull requests to 10 to avoid PR noise.

#### Scenario: PR limit enforced
- **WHEN** Dependabot already has 10 open PRs
- **THEN** Dependabot SHALL NOT open additional PRs until existing ones are merged or closed

### Requirement: Dependabot labels dependency PRs
Dependabot SHALL apply the `dependencies` label to Cargo update PRs and `ci` + `dependencies` labels to GitHub Actions update PRs.

#### Scenario: Cargo dependency PR is labeled
- **WHEN** Dependabot opens a PR for a Cargo dependency update
- **THEN** the PR SHALL have the `dependencies` label

#### Scenario: GitHub Actions PR is labeled
- **WHEN** Dependabot opens a PR for a GitHub Actions update
- **THEN** the PR SHALL have both `ci` and `dependencies` labels

### Requirement: Dependabot uses conventional commit messages
Dependabot commit messages SHALL use the `chore(deps):` prefix for Cargo updates and `chore(ci):` prefix for GitHub Actions updates.

#### Scenario: Cargo update commit message format
- **WHEN** Dependabot commits a Cargo dependency update
- **THEN** the commit message SHALL start with `chore(deps):`

#### Scenario: GitHub Actions update commit message format
- **WHEN** Dependabot commits a GitHub Actions version update
- **THEN** the commit message SHALL start with `chore(ci):`
