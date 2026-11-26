<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Flutter Release Artifacts Delta

## ADDED Requirements

### Requirement: Android release publication is draft-first and immutable
The Flutter release workflow SHALL create or reuse a draft GitHub Release and SHALL upload all three split APKs, the AAB, and their required verification metadata before publishing it. Immutable releases SHALL be enabled only after the complete draft-first flow has passed an end-to-end pre-release test.

#### Scenario: Complete draft is published
- **WHEN** every expected APK/AAB, signature check, and attestation has completed successfully
- **THEN** the workflow publishes the draft as the immutable release for the tag

#### Scenario: Rerun encounters an existing draft
- **WHEN** an earlier attempt left a draft for the same tag
- **THEN** the workflow reuses and validates that draft or fails visibly without silently replacing assets

### Requirement: Android artifact set includes verifiable build provenance
The existing APK/AAB artifact contract SHALL include one verifiable GitHub build-provenance attestation per binary artifact. Release notes or the release runbook SHALL explain how testers and consumers verify both project signatures and build provenance.

#### Scenario: Tester downloads an APK
- **WHEN** a tester obtains an APK from a published release
- **THEN** the release documentation provides a way to verify its project signing fingerprint and its GitHub build provenance independently

#### Scenario: Any binary lacks provenance
- **WHEN** one of the four expected Android binary artifacts has no required attestation
- **THEN** the release remains unpublished
