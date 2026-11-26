<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Repository Security Posture

## ADDED Requirements

### Requirement: Native secret protection is enabled
The public repository SHALL have GitHub Secret Scanning and Secret Scanning Push Protection enabled. Existing Gitleaks scanning SHALL remain as complementary coverage for custom patterns and CI enforcement.

#### Scenario: Supported secret is pushed
- **WHEN** a contributor attempts to push a harmless test value matching a GitHub-supported secret pattern
- **THEN** Push Protection rejects the push before the value enters repository history

#### Scenario: Unsupported custom pattern is introduced
- **WHEN** a pull request introduces a value matched by the repository's custom Gitleaks rules but not by GitHub's provider patterns
- **THEN** the Gitleaks CI gate reports the finding independently of GitHub Push Protection

### Requirement: Full-length action SHA pinning is platform-enforced
Repository Actions settings SHALL require actions to be referenced by a full-length commit SHA. The repository SHALL retain reviewed Dependabot updates for those pins.

#### Scenario: Moving action tag is introduced
- **WHEN** a workflow references an action by a mutable tag such as `@v4`
- **THEN** GitHub refuses to run that workflow under the repository Actions policy

#### Scenario: Action pin is updated
- **WHEN** Dependabot opens an action-update pull request
- **THEN** the pull request updates the full-length SHA and its human-readable version comment through the normal review process

### Requirement: Main protection has one effective contract
The effective `main` protection SHALL preserve pull-request review, CODEOWNERS review, stale-review dismissal, up-to-date required checks, deletion denial, and non-fast-forward denial while classic protection and rulesets are consolidated. No migration step SHALL silently remove an existing required check or review requirement.

#### Scenario: Ruleset parity is reviewed
- **WHEN** an administrator compares classic branch protection with the target ruleset before consolidation
- **THEN** every existing review and required-check requirement is present in the target configuration

#### Scenario: Ordinary user attempts a force-push
- **WHEN** a non-bypassed user attempts a non-fast-forward update to `main`
- **THEN** the effective repository rules reject the update

### Requirement: Standing administrator bypass is removed
The effective `main` protection SHALL NOT contain a standing repository-administrator `always` bypass. Any emergency exception SHALL be manually scoped, documented, time-bounded, and reviewed after use.

#### Scenario: Administrator attempts a prohibited direct update
- **WHEN** an administrator attempts an update forbidden by the active `main` rules without an active emergency exception
- **THEN** the same rule rejection applies as for other contributors

#### Scenario: Emergency bypass is used
- **WHEN** a documented incident requires a temporary bypass
- **THEN** the bypass record contains a reason, creator, creation time, removal owner, and post-incident review, and the bypass is removed after the incident

### Requirement: Recent changes receive independent approval
Once at least one independent reviewer is available, `main` protection SHALL require approval of the most recent push and resolution of review conversations. Self-review SHALL NOT satisfy independent approval.

#### Scenario: New commit arrives after approval
- **WHEN** a contributor pushes a new commit after an earlier approval
- **THEN** the most recent push requires the configured independent approval before merge

#### Scenario: Project has only one active maintainer
- **WHEN** no independent reviewer exists
- **THEN** the independent last-push-approval control is reported as incomplete rather than satisfied by the maintainer approving their own change

### Requirement: Account and automation access follows least privilege
The repository-security runbook SHALL require phishing-resistant authentication, offline recovery material, periodic session/key/app review, and repository-scoped short-lived automation credentials. New automation SHALL use a least-privilege GitHub App or fine-grained short-lived credential instead of a broad classic PAT where the integration supports it.

#### Scenario: Maintainer access is reviewed
- **WHEN** the periodic repository-security review runs
- **THEN** active sessions, recovery material, SSH keys, PATs, OAuth Apps, and GitHub Apps are checked without recording secret values in the repository

#### Scenario: New automation needs repository access
- **WHEN** a new integration requests repository permissions
- **THEN** its repository scope, permissions, token lifetime, and data flow are reviewed before installation

### Requirement: Configuration verification is read-only
Repository-posture verification SHALL use GitHub's UI or read-only API operations and SHALL NOT require a long-lived administrative PAT in CI. Committed evidence SHALL exclude credentials and private account-security details.

#### Scenario: Target posture is verified
- **WHEN** an administrator runs the documented verification procedure
- **THEN** the procedure reports the effective security features, Actions policy, branch/ruleset rules, bypass actors, and required checks without modifying them

#### Scenario: Evidence is added to the repository
- **WHEN** configuration evidence is committed
- **THEN** it contains only non-secret configuration values and source links
