<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Flutter Release Signing Delta

## ADDED Requirements

### Requirement: Independent approval precedes signing-secret exposure
The Android `Release` environment SHALL require an eligible independent reviewer and prevent self-review before the build/publish job can access `KEYSTORE_BASE64`, keystore passwords, or other protected production signing configuration. This control SHALL preserve the existing one-project-key and fingerprint-verification requirements.

#### Scenario: Release is not independently approved
- **WHEN** a `v*` tag starts the Flutter workflow and no eligible independent reviewer approves the protected deployment
- **THEN** the signing job does not start and Android signing secrets are not exposed to it

#### Scenario: Triggering actor attempts self-approval
- **WHEN** the actor who pushed the release tag attempts to approve their own deployment
- **THEN** self-review prevention rejects the approval and the signing job remains blocked

### Requirement: API publication cannot access Android signing secrets
The API image release SHALL use a separate environment and SHALL NOT be granted access to the Android `Release` environment's keystore or signing configuration.

#### Scenario: API release tag is pushed
- **WHEN** an `api-v*` tag triggers the image-release workflow
- **THEN** the job receives only API publication and attestation credentials, with no Android keystore material available

### Requirement: Signing-key compromise follows the custody break-glass process
If CI logs, workflow behavior, or incident evidence suggests that Android signing material was exposed, maintainers SHALL follow the documented key-custody incident and rotation process rather than merely deleting logs or rerunning the release.

#### Scenario: Signing material may have been exposed
- **WHEN** a security incident identifies possible keystore or password exfiltration
- **THEN** maintainers preserve relevant evidence, revoke affected CI access, assess published artifacts, and invoke the existing signing-key break-glass procedure
