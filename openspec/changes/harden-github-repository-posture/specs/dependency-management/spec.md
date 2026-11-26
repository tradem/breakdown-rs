<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Dependency Management Delta

## ADDED Requirements

### Requirement: Dependabot vulnerability alerts are enabled
The repository SHALL enable Dependabot alerts for supported dependency manifests and lockfiles. Routine version updates SHALL remain configured alongside vulnerability alerts.

#### Scenario: Supported dependency receives a security advisory
- **WHEN** GitHub associates a new advisory with a dependency in the repository's dependency graph
- **THEN** a Dependabot vulnerability alert becomes visible to maintainers

#### Scenario: Routine dependency updates continue
- **WHEN** vulnerability alerts are enabled
- **THEN** the existing Cargo, GitHub Actions, Pub, and Gradle version-update configuration remains active

### Requirement: Dependabot security updates are enabled
The repository SHALL enable Dependabot security updates for supported ecosystems so GitHub can open remediation pull requests for vulnerable dependencies.

#### Scenario: Vulnerable dependency has a compatible patched version
- **WHEN** Dependabot identifies a security update supported for the affected manifest
- **THEN** it opens a pull request that maintainers validate through the normal required checks

#### Scenario: Security update cannot be generated
- **WHEN** an ecosystem, constraint, or dependency graph prevents automatic remediation
- **THEN** the vulnerability alert remains visible and maintainers record a manual remediation or exception

### Requirement: Security updates are reviewed rather than auto-merged
Dependabot security-update pull requests SHALL pass the same required reviews and checks as other dependency changes and SHALL NOT be automatically merged solely because they address an advisory.

#### Scenario: Security update breaks compatibility
- **WHEN** a generated security-update pull request fails a required check
- **THEN** it remains unmerged until the dependency or affected code is corrected
