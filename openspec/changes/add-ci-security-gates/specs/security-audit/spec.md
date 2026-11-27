<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Security Audit Delta

## MODIFIED Requirements

### Requirement: Security audit runs on a daily schedule
A security audit workflow SHALL execute automatically on a daily schedule to check for known vulnerabilities in Cargo dependencies using the repository's `cargo-deny` advisory configuration.

#### Scenario: Daily audit executes
- **WHEN** the scheduled time arrives (daily)
- **THEN** the audit workflow runs `cargo-deny check advisories` against the backend workspace `Cargo.lock`

### Requirement: Security audit reports vulnerabilities
The security audit step SHALL use `cargo-deny check advisories` and the checked-in `backend/deny.toml` policy to scan for known RustSec vulnerabilities. An ignored advisory SHALL retain its documented rationale and revisit condition.

#### Scenario: No vulnerabilities found
- **WHEN** no enabled dependencies have unignored known security advisories
- **THEN** the audit job passes

#### Scenario: Vulnerability found
- **WHEN** a dependency has a known security advisory not covered by a configured exception
- **THEN** the audit job fails and reports the vulnerability details

## REMOVED Requirements

### Requirement: Security audit runs on PRs modifying Cargo.lock
**Reason**: A path-limited audit cannot serve as a required repository-wide security gate and leaves other pull requests without a consistent result.
**Migration**: Replace this requirement with the new every-pull-request audit and secret-scanning requirements below.

#### Scenario: PR with Cargo.lock change triggers audit
- **WHEN** a pull request modifies `backend/Cargo.lock`
- **THEN** the audit workflow SHALL execute and report any known vulnerabilities

## ADDED Requirements

### Requirement: Security audit runs on every pull request
The Cargo advisory audit SHALL run on every pull request targeting `main`, on pushes to `main`, on the daily schedule, and on manual dispatch. Its result SHALL NOT depend on whether `backend/Cargo.lock` changed.

#### Scenario: Pull request leaves Cargo.lock unchanged
- **WHEN** a pull request changes only application source, documentation, or workflows
- **THEN** the Cargo advisory audit still executes and reports a result

#### Scenario: Pull request changes Cargo.lock
- **WHEN** a pull request updates backend dependencies
- **THEN** both the Cargo advisory audit and Dependency Review evaluate their respective security contracts

### Requirement: Repository secret scanning runs on every pull request
Gitleaks SHALL scan the repository on every pull request targeting `main`, on `main`, on a recurring full-history schedule, and on manual dispatch. Pull-request scans SHALL cover the complete pull-request commit range rather than only the first page of commits.

#### Scenario: Large pull request contains a secret in a later commit
- **WHEN** a pull request contains more commits than GitHub's default commit-list page size and a later commit introduces a detected secret
- **THEN** Gitleaks still scans that commit and fails the repository secret-scanning job

#### Scenario: Fork pull request cannot upload SARIF
- **WHEN** Gitleaks detects a secret in a fork pull request where SARIF upload is not permitted
- **THEN** the Gitleaks job still fails and reports the finding in its restricted logs

### Requirement: Secret-scanning check identity is unambiguous
The repository-wide Gitleaks job SHALL have a unique check name distinct from any Flutter-specific secret-scanning job retained for release quality gates.

#### Scenario: Both secret-scanning paths execute
- **WHEN** repository-wide and Flutter-specific workflows both run Gitleaks
- **THEN** their results use distinct names so the required repository-wide check cannot be satisfied by the wrong job
