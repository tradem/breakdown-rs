<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Release Authorization

## ADDED Requirements

### Requirement: Release tags have dedicated protection rules
Repository rulesets SHALL cover `v*` and `api-v*` tags. Tag creation SHALL be limited to designated release managers, and tag updates, non-fast-forward changes, and deletion SHALL be prohibited for non-exempt actors.

#### Scenario: Unauthorized actor creates a release tag
- **WHEN** an actor who is not a designated release manager attempts to create a matching release tag
- **THEN** the effective tag rules reject the creation

#### Scenario: Release manager attempts to move an existing tag
- **WHEN** any non-exempt actor attempts to update or delete an existing release tag
- **THEN** the effective tag rules reject the operation

### Requirement: Android and API releases use isolated environments
The existing `Release` environment SHALL remain dedicated to Android `v*` deployments and Android signing secrets. A separate `Release-API` environment SHALL govern `api-v*` GHCR publication and SHALL NOT contain Android signing secrets.

#### Scenario: API release is triggered
- **WHEN** an `api-v*` tag starts the image-release workflow
- **THEN** its publication job uses `Release-API` and cannot access the Android environment's signing secrets

#### Scenario: Android release is triggered
- **WHEN** a `v*` tag starts the Flutter release workflow
- **THEN** its signing/publication job uses the Android-only `Release` environment

### Requirement: Protected publication requires independent approval
Both release environments SHALL require at least one reviewer and SHALL prevent the workflow-triggering actor from satisfying that approval through self-review. Approval SHALL occur before protected signing or publication credentials become available to the job.

#### Scenario: Release has no independent approval
- **WHEN** a protected release job starts and no eligible independent reviewer has approved it
- **THEN** the job remains waiting and cannot access protected environment secrets or publish artifacts

#### Scenario: Triggering actor attempts self-approval
- **WHEN** the actor who initiated the release attempts to approve their own protected deployment
- **THEN** GitHub's self-review prevention rejects that approval

### Requirement: Solo-maintainer operation is not represented as independent approval
If no second trusted reviewer exists, the independent-approval requirement SHALL be reported as incomplete. Any separately accepted solo release process SHALL be documented as a residual risk and SHALL NOT be used to mark this control complete.

#### Scenario: Only one maintainer is available
- **WHEN** the repository has no independent environment reviewer
- **THEN** the security posture records the missing control rather than treating the maintainer's own approval as separation of duties

### Requirement: Publication credentials are job-scoped
Release jobs SHALL receive only the permissions required for their artifact channel. Android `contents: write`, GHCR `packages: write`, and OIDC/attestation permissions SHALL be confined to the protected jobs that use them.

#### Scenario: Quality-gate job runs
- **WHEN** release quality gates execute before publication
- **THEN** they run with read-only contents access and no Android signing or GHCR publication credential

#### Scenario: API image is published and attested
- **WHEN** the protected API job reaches publication
- **THEN** only that job receives the package, OIDC, and attestation permissions required for its operations
