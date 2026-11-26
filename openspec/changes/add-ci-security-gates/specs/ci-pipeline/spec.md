<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# CI Pipeline Delta

## ADDED Requirements

### Requirement: CI protection includes stabilized security gates
The CI protection contract SHALL include repository secret scanning, Cargo advisory audit, Dependency Review, actionlint, zizmor, and stabilized CodeQL checks in addition to the existing build, test, clippy, format, and check jobs. Every required gate SHALL have a stable unique name and execute on every pull request targeting `main`.

#### Scenario: Pull request is evaluated for merge
- **WHEN** all existing core checks pass but a stabilized required security gate fails
- **THEN** the effective branch protection does not permit an ordinary merge

#### Scenario: Required checks are inventoried
- **WHEN** maintainers compare workflow definitions with the effective required-check list
- **THEN** every required security name maps to exactly one active workflow/job and no required workflow is excluded by a path filter

### Requirement: Security-gate rollout preserves existing quality checks
Adding security gates SHALL NOT remove or weaken the existing build, test, clippy, format, check, or dependency-policy requirements.

#### Scenario: Security rollout changes the required-check list
- **WHEN** the new security checks are added to `main` protection
- **THEN** all pre-existing core required checks remain present unless a separate change explicitly replaces them
