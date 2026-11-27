<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Release Artifact Integrity

## ADDED Requirements

### Requirement: The exact API image is scanned before publication
The API release pipeline SHALL build or export one staged image artifact, scan that exact artifact with Trivy, and publish only those verified bytes. If another build is required for registry publication, digest equality with the scanned artifact SHALL be proven before push and attestation.

#### Scenario: Staged image contains a fixable Critical vulnerability
- **WHEN** Trivy identifies a Critical vulnerability with an available fix in the staged image
- **THEN** the release fails before GHCR publication and no attestation marks the image as an approved release

#### Scenario: Registry packaging changes the image digest
- **WHEN** the digest produced for registry publication differs from the scanned artifact without a verified digest-equivalence path
- **THEN** the release fails instead of attesting unscanned bytes

### Requirement: Vulnerability exceptions are narrow and revisited
Trivy gating SHALL fail on fixable High and Critical findings. Any exception SHALL identify the vulnerability, affected image or package context, rationale, and revisit date; the pipeline SHALL NOT globally disable failure behavior.

#### Scenario: Upstream vulnerability has no available fix
- **WHEN** maintainers accept an unfixed upstream finding temporarily
- **THEN** its exception is recorded with context and a revisit date while unrelated fixable findings continue to fail the release

### Requirement: GHCR publication includes SBOM and digest-based provenance
The API image build SHALL produce Docker BuildKit SBOM and provenance metadata. After push, the workflow SHALL create a GitHub build-provenance attestation for the immutable GHCR image digest rather than only a mutable tag.

#### Scenario: Consumer verifies an API image
- **WHEN** a consumer obtains the published image digest and expected repository owner
- **THEN** they can verify its GitHub build-provenance attestation against `tradem/breakdown-rs`

#### Scenario: Mutable image tag is retargeted
- **WHEN** a moving minor or major image tag points to a different digest
- **THEN** verification still binds provenance to the selected immutable digest rather than trusting the tag alone

### Requirement: Every Android artifact receives build provenance
After project-signature verification succeeds, the Android release job SHALL create a GitHub build-provenance attestation for each split APK and the AAB. OIDC and attestation permissions SHALL be limited to that job.

#### Scenario: Android artifact is ready for publication
- **WHEN** an APK or AAB passes the existing signing and fingerprint checks
- **THEN** its build-provenance attestation is generated before the release is published

#### Scenario: Attestation fails
- **WHEN** any required Android artifact cannot be attested
- **THEN** the draft release is not published with a partial attestation set

### Requirement: Immutable releases are published draft-first
Android GitHub Releases SHALL remain drafts until the complete expected artifact set, signatures, and attestations have been uploaded and verified. Repository immutable releases SHALL be enabled only after that draft-first behavior is validated.

#### Scenario: Draft has a missing artifact
- **WHEN** one expected split APK, the AAB, or a required verification result is absent
- **THEN** publication stops and the release remains unpublished

#### Scenario: Published immutable artifact is defective
- **WHEN** a defect is discovered after an immutable release has been published
- **THEN** maintainers publish a superseding corrected release rather than moving its tag or replacing its assets

### Requirement: Provenance does not replace other verification
Release verification SHALL distinguish Android signature/fingerprint checks, vulnerability scanning, CI quality gates, and build provenance. A successful attestation alone SHALL NOT be interpreted as proof that an artifact is vulnerability-free or benign.

#### Scenario: Artifact has valid provenance but fails another gate
- **WHEN** an artifact has a valid build-origin attestation but fails signature verification, a required quality gate, or the vulnerability policy
- **THEN** the release remains blocked
