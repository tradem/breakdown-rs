<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Code and Workflow Security Analysis

## ADDED Requirements

### Requirement: CodeQL analyzes Rust and GitHub Actions
GitHub Code Scanning SHALL analyze Rust and GitHub Actions on pull requests, `main`, and a recurring schedule. The initial implementation SHALL use GitHub CodeQL default setup for those languages.

#### Scenario: Rust security query identifies a finding
- **WHEN** CodeQL analyzes a Rust change matching an enabled security query
- **THEN** the finding is associated with the pull request or `main` analysis and is available for triage

#### Scenario: Workflow security query identifies a finding
- **WHEN** CodeQL analyzes a GitHub Actions workflow change matching an enabled security query
- **THEN** the finding is reported without granting the analysis job write access to repository contents

### Requirement: Rust analysis has a working fallback
If CodeQL default setup cannot extract the Rust workspace reliably, the change SHALL replace it with an advanced SHA-pinned CodeQL workflow that preserves Rust and Actions coverage. The change SHALL NOT claim Rust coverage from an Actions-only analysis.

#### Scenario: Default setup cannot extract Rust
- **WHEN** the default-setup run fails or produces no valid Rust database after diagnosis
- **THEN** maintainers implement and validate the advanced-workflow fallback before promoting CodeQL to required status

### Requirement: Actionlint and zizmor analyze every pull request
The workflow-linting path SHALL run actionlint for workflow correctness and zizmor for security-specific analysis on every pull request targeting `main`.

#### Scenario: Workflow contains an unsafe expression
- **WHEN** a pull request introduces a workflow expression or trigger pattern covered by actionlint or zizmor security checks
- **THEN** at least one applicable gate fails with a finding identifying the affected workflow

#### Scenario: Workflow is valid and hardened
- **WHEN** a pull request contains workflows satisfying both tools' enabled rules
- **THEN** both checks pass and produce stable results eligible for required-check promotion

### Requirement: Analysis configuration follows least privilege and pinning
CodeQL, actionlint, and zizmor workflows SHALL use read-only contents permissions by default, full-length action SHA pins, and no repository secrets for fork pull requests. Rule suppressions SHALL identify the rule and a rationale.

#### Scenario: Analysis workflow is reviewed
- **WHEN** a reviewer inspects an analysis workflow
- **THEN** every external action is full-length SHA-pinned and elevated permissions are limited to an explicit reporting need

#### Scenario: Finding is suppressed
- **WHEN** a specific zizmor or CodeQL finding is intentionally suppressed
- **THEN** the suppression is narrow, reviewable, and accompanied by its rule identity and justification
