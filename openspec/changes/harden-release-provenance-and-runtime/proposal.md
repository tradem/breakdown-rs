<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Harden Release Provenance and Runtime

**Tracking issue:** [#998](https://github.com/tradem/breakdown-rs/issues/998)

## Why

Release workflows can publish GHCR images and signed Android artifacts from tags, but the live Android environment has no required reviewers, release tags lack a dedicated ruleset, and the API image has no protected environment or provenance. A compromised writer or maintainer account could therefore turn tag creation into a release path without an independent approval boundary.

This change protects the release control plane and makes published artifacts verifiable. It depends on the account/ruleset baseline from `harden-github-repository-posture` and the security gates from `add-ci-security-gates`.

## What Changes

- Protect `v*` and `api-v*` tags with rulesets that constrain creation to designated release managers and prohibit updates and deletion.
- Keep the existing `Release` environment dedicated to Android, add required reviewers with self-review prevention, and create a separate `Release-API` environment for GHCR publication.
- Require an independent reviewer for protected publication; if the project still has only one maintainer, record the control as incomplete rather than treating self-approval as equivalent.
- Add build provenance attestations for the GHCR image digest and every published APK/AAB, with narrowly scoped OIDC and attestation permissions.
- Generate container SBOM/provenance metadata and scan the exact API image before publication with Trivy; fail on actionable High/Critical findings under a documented exception policy.
- Change Android publication to a draft-first flow so all artifacts and attestations are present before an immutable GitHub Release is published.
- Add StepSecurity Harden-Runner to release jobs and other secret-bearing workflows, beginning with egress audit and moving to an explicit block policy only from observed baselines.
- Remove persisted checkout credentials wherever subsequent build, dependency, or release code does not require authenticated Git writes.
- Extend release dry-runs and operational runbooks with approval, attestation, immutability, egress, and compromise-recovery checks.
- Do not add Wiz or another security SaaS, change Android signing keys, or redesign distribution channels in this change.

## Capabilities

### New Capabilities

- `release-authorization`: Protected release tags, isolated environments, independent approval, and release-manager responsibilities.
- `release-artifact-integrity`: Image scanning, SBOM/provenance, digest-based attestations, immutable releases, and consumer verification.
- `ci-runtime-egress-security`: Runtime network monitoring, least-privilege checkout credentials, and controlled egress policies for secret-bearing jobs.

### Modified Capabilities

- `flutter-release-artifacts`: Adds draft-first immutable publication, attestation, and verification requirements to the existing artifact contract.
- `flutter-release-signing`: Adds independent environment approval before signing secrets become available while preserving the one-key custody model.

## Impact

- GitHub tag rulesets, the existing `Release` environment, a new `Release-API` environment, and repository release-immutability settings.
- `.github/workflows/flutter-release.yml`, `release-image.yml`, and secret-bearing scheduled/integration workflows selected for runtime monitoring.
- `frontend-flutter/scripts/release/publish-release.sh` and associated release verification/dry-run scripts and tests.
- `backend/Dockerfile` or its build path only as needed to scan and attest the exact published image; no application behavior change is intended.
- `frontend-flutter/docs/release-signing-key-custody.md`, release runbooks, and `backend/docs/security/security-architecture.md`.
- CI-only dependencies: GitHub Artifact Attestations, Trivy, StepSecurity Harden-Runner, and Docker BuildKit attestations.
- No backend API, database, event, Flutter UI, signing-fingerprint, or application wire-contract changes.
