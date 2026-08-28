# Security Audit

## Purpose

Automatically scan Cargo dependencies for known security vulnerabilities on a daily schedule, on pull requests that modify `Cargo.lock`, and on manual trigger. This ensures timely detection of new advisories and prevents vulnerable dependencies from being merged.

## Requirements

### Requirement: Security audit runs on a daily schedule
A security audit workflow SHALL execute automatically on a daily schedule to check for known vulnerabilities in Cargo dependencies.

#### Scenario: Daily audit executes
- **WHEN** the scheduled time arrives (daily)
- **THEN** the audit workflow SHALL run `rustsec/audit-check` against the workspace `Cargo.lock`

### Requirement: Security audit runs on PRs modifying Cargo.lock
The security audit workflow SHALL trigger on pull requests that modify the `Cargo.lock` file.

#### Scenario: PR with Cargo.lock change triggers audit
- **WHEN** a pull request modifies `backend/Cargo.lock`
- **THEN** the audit workflow SHALL execute and report any known vulnerabilities

### Requirement: Security audit can be triggered manually
The security audit workflow SHALL support `workflow_dispatch` for manual execution.

#### Scenario: Manual audit trigger
- **WHEN** a developer manually triggers the audit workflow from the GitHub Actions UI
- **THEN** the workflow SHALL execute the security audit

### Requirement: Security audit reports vulnerabilities
The security audit step SHALL use the `rustsec/audit-check` action to scan for known vulnerabilities.

#### Scenario: No vulnerabilities found
- **WHEN** no dependencies have known security advisories
- **THEN** the audit job SHALL pass

#### Scenario: Vulnerability found
- **WHEN** a dependency has a known security advisory
- **THEN** the audit job SHALL fail and report the vulnerability details
