<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Pull Request Security Gates

## ADDED Requirements

### Requirement: Every pull request receives all required security results
Every pull request targeting `main` SHALL produce results for repository Gitleaks, Cargo advisory audit, Dependency Review, actionlint, zizmor, and each promoted CodeQL check. Required workflows SHALL NOT use path filters that leave their result absent for an in-scope pull request.

#### Scenario: Pull request does not touch dependency files
- **WHEN** a pull request changes only application source or documentation
- **THEN** all required security checks still report a result

#### Scenario: Pull request is synchronized
- **WHEN** a new commit is pushed to an existing pull request
- **THEN** every required security check runs again against the updated merge context

### Requirement: Required security check names are stable and unambiguous
Each required security check name SHALL map to exactly one workflow/job definition. Repository-wide and Flutter-specific scans SHALL NOT share an ambiguous required-check name.

#### Scenario: Required checks are configured
- **WHEN** an administrator adds security checks to the effective `main` protection
- **THEN** each selected name is traceable to one current workflow/job definition

#### Scenario: Repository and Flutter secret scans execute
- **WHEN** both scans are needed for their respective triggers
- **THEN** their check names distinguish the repository-wide result from any Flutter-specific release-gate result

### Requirement: Dependency Review blocks high-severity dependency regressions
GitHub Dependency Review SHALL run on every pull request and SHALL fail when a dependency change introduces a known High or Critical vulnerability. An advisory exception SHALL be narrowly scoped and documented.

#### Scenario: Pull request introduces a High vulnerability
- **WHEN** Dependency Review identifies a newly introduced High-severity vulnerable dependency
- **THEN** the check fails and the pull request cannot merge through ordinary protection

#### Scenario: Advisory has a documented exception
- **WHEN** maintainers accept a specific advisory temporarily
- **THEN** the exception identifies the advisory, package, rationale, and revisit condition without disabling unrelated findings

### Requirement: Scanner success is independent of SARIF upload permission
A scanner's own exit status SHALL determine job success. SARIF upload SHALL be conditional on a context where the required `security-events` permission is available and SHALL NOT hide a scanner failure.

#### Scenario: Fork pull request introduces a finding
- **WHEN** an untrusted fork pull request triggers a scanner finding and cannot upload SARIF with the restricted token
- **THEN** the scanner job still fails and the finding remains visible in job logs

#### Scenario: Same-repository scan succeeds
- **WHEN** a same-repository scan succeeds and SARIF upload is permitted
- **THEN** the results may be published to code scanning without elevating other jobs

### Requirement: Required security failures block ordinary merges
The effective `main` protection SHALL require all stabilized security checks alongside the existing core checks. A failed required security check SHALL NOT be bypassed by an ordinary merge or a standing administrator bypass.

#### Scenario: Required scanner fails
- **WHEN** a stabilized required security check fails
- **THEN** the pull request remains unmerged until the finding is fixed or a narrowly documented exception is approved

#### Scenario: New check has not completed its pilot
- **WHEN** a new scanner has not yet demonstrated stable trigger coverage and failure behavior
- **THEN** it remains non-blocking until its unique name and results are validated
