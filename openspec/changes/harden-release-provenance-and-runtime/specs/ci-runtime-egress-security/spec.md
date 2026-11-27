<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# CI Runtime Egress Security

## ADDED Requirements

### Requirement: Secret-bearing jobs receive runtime network monitoring
Android/API release jobs and selected scheduled or integration jobs receiving GDrive or LLM credentials SHALL run a full-length SHA-pinned StepSecurity Harden-Runner as their first step. Initial deployment SHALL use `egress-policy: audit`.

#### Scenario: Release job starts
- **WHEN** a protected release job starts after environment approval
- **THEN** Harden-Runner begins monitoring before checkout, dependency installation, signing, or publication steps execute

#### Scenario: Secret-bearing scheduled job starts
- **WHEN** a selected GDrive or LLM workflow receives its credentials
- **THEN** outbound network activity is recorded for baseline and anomaly review

### Requirement: Release egress blocking is derived from observed baselines
Release jobs SHALL move from audit mode to an explicit egress block policy only after representative successful runs establish required package, SDK, GitHub, registry, API, and observability destinations. The allowlist SHALL avoid broad wildcard destinations that permit trivial exfiltration.

#### Scenario: Release connects to an unapproved destination
- **WHEN** block mode is active and a release step attempts an outbound connection outside its reviewed allowlist
- **THEN** Harden-Runner denies or reports the connection according to its enforced policy and the release fails visibly

#### Scenario: Baseline is incomplete
- **WHEN** a required release destination has not yet been observed and reviewed
- **THEN** the job remains in audit mode until the allowlist is completed rather than enabling an untested blocking policy

### Requirement: Scheduled-job blocking is introduced incrementally
Scheduled and integration jobs SHALL retain audit mode until normal, retry, and fallback network behavior is understood. Any later block policy SHALL be tested without real credentials before being applied to secret-bearing runs.

#### Scenario: Retry path needs an additional endpoint
- **WHEN** baseline analysis identifies a legitimate provider retry or fallback destination
- **THEN** that destination is reviewed explicitly before inclusion in the allowlist

#### Scenario: Blocking policy is tested
- **WHEN** maintainers validate a new block policy
- **THEN** the controlled test uses no production signing, GDrive, LLM, or other real secret

### Requirement: Checkout credentials are not persisted unnecessarily
Jobs that execute build, dependency, analysis, or release code without authenticated Git writes SHALL configure checkout with `persist-credentials: false`. Any exception SHALL identify the authenticated Git operation that requires persisted credentials.

#### Scenario: Build dependencies execute after checkout
- **WHEN** a job checks out the repository and then runs third-party build or dependency code without pushing commits
- **THEN** the checkout token is not left in local Git configuration for that code to reuse

### Requirement: Runtime controls fail visibly
Runtime-monitoring or egress-policy failures SHALL produce actionable logs and SHALL NOT be silently ignored with a blanket `continue-on-error`. Disabling or bypassing the control SHALL require a reviewed workflow change.

#### Scenario: Runtime security step fails
- **WHEN** Harden-Runner or its enforced egress policy fails during a release
- **THEN** the job outcome and logs expose the failure instead of continuing silently to publication
