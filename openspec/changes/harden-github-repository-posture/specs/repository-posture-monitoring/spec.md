<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Repository Posture Monitoring

## ADDED Requirements

### Requirement: OpenSSF Scorecard runs on a recurring schedule
The repository SHALL run the official OpenSSF Scorecard Action weekly, on `main` pushes, on relevant branch-protection changes, and on manual dispatch. The action SHALL be pinned by a full-length commit SHA.

#### Scenario: Weekly posture check executes
- **WHEN** the scheduled weekly run starts
- **THEN** Scorecard evaluates the public repository and produces a current posture report

#### Scenario: Protection configuration changes
- **WHEN** a relevant branch-protection event occurs
- **THEN** a new Scorecard evaluation is triggered

### Requirement: Posture monitoring uses least privilege
Scorecard SHALL use the repository's standard token with only the permissions required for reading, artifact reporting, SARIF upload, and result publication. The workflow SHALL NOT introduce a personal access token with repository-administration rights.

#### Scenario: Scorecard workflow permissions are reviewed
- **WHEN** a reviewer inspects the Scorecard workflow
- **THEN** read permissions are the default and elevated permissions are limited to the reporting job

#### Scenario: Full legacy protection data is unavailable
- **WHEN** Scorecard cannot inspect a legacy-only setting with the standard token
- **THEN** maintainers document the visibility limitation and do not add an administrative PAT merely to improve the score

### Requirement: Scorecard begins as non-blocking monitoring
Scorecard results SHALL establish a non-blocking baseline and SHALL NOT initially prevent merges solely because of an aggregate score. Individual findings SHALL be remediated or recorded with a rationale and revisit condition.

#### Scenario: Baseline contains findings
- **WHEN** the first Scorecard run reports posture gaps
- **THEN** maintainers triage the individual checks without converting the aggregate score directly into a merge gate

#### Scenario: Finding is accepted temporarily
- **WHEN** a finding cannot be remediated immediately
- **THEN** its record identifies the check, rationale, owner, and revisit condition

### Requirement: Reporting failure does not hide analysis results
Scorecard analysis SHALL produce a retained diagnostic artifact, and SARIF publication SHALL occur only with the permissions valid for the event context. An upload failure SHALL NOT erase the underlying report.

#### Scenario: SARIF upload is unavailable
- **WHEN** the workflow cannot publish SARIF for a restricted event
- **THEN** the raw Scorecard artifact remains available for diagnosis and the limitation is visible in logs
