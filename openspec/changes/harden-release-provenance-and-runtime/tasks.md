<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Tasks: Harden Release Provenance and Runtime

## 1. Release Managers, Tags, and Environments

- [ ] 1.1 Designate release managers and at least one independent Android/API environment reviewer; if no independent reviewer exists, leave the independent-approval tasks incomplete and record the residual risk instead of using self-approval.
- [ ] 1.2 Create `v*` and `api-v*` tag rulesets in evaluate mode, verify their matches, then activate creation restrictions for designated release managers and update/non-fast-forward/deletion denial for non-exempt actors.
- [ ] 1.3 Add required reviewers and self-review prevention to the existing Android `Release` environment, retain its `v*`-only deployment policy, and keep its secrets limited to Android release configuration.
- [ ] 1.4 Create a separate `Release-API` environment for `api-v*` with required reviewers, self-review prevention, and no Android keystore or signing secrets.
- [ ] 1.5 Verify with a non-production test tag/run that an unapproved deployment waits before protected secrets are available and that the triggering actor cannot satisfy the approval alone.

## 2. Android Draft-First and Provenance

- [ ] 2.1 Update `frontend-flutter/scripts/release/publish-release.sh` to create or reuse a draft, require exactly the three split APKs plus AAB, and fail closed on missing, duplicate, or unexpected assets while retaining dry-run support.
- [ ] 2.2 Update the Android publication flow so signature/fingerprint verification completes before attestation and final draft publication; preserve the existing one-key custody contract and avoid logging secrets.
- [ ] 2.3 Add job-scoped `id-token: write` and `attestations: write`, then create a SHA-pinned GitHub Artifact Attestation for each APK and the AAB before publishing the draft.
- [ ] 2.4 Extend release-script tests for first run, rerun with existing draft, missing artifact, failed signature, failed attestation, and attempted asset replacement; prove that none publishes a partial release.
- [ ] 2.5 Run an end-to-end alpha/beta pre-release, verify all four artifacts and both signature/provenance checks, and only then enable repository immutable releases.

## 3. API Image Scanning, SBOM, and Provenance

- [ ] 3.1 Change `release-image.yml` to use `Release-API` and stage one local or OCI-layout image before publication, with `packages: write`, OIDC, and attestation permissions confined to the protected publication job.
- [ ] 3.2 Add Trivy scanning of the exact staged image with failure on fixable High/Critical findings and a documented exception register containing vulnerability, image/package context, rationale, and revisit date.
- [ ] 3.3 Implement and test the digest-equality guarantee between the scanned artifact and the registry-pushed image so a second unverified build cannot be published or attested.
- [ ] 3.4 Enable Docker BuildKit SBOM and provenance metadata, publish the verified image, capture its immutable registry digest, and add a SHA-pinned GitHub build-provenance attestation for that digest.
- [ ] 3.5 Verify the GHCR artifact with `gh attestation verify` against the expected owner and digest and test that a fixable High/Critical test fixture blocks publication before registry mutation.

## 4. Runtime Egress and Checkout Credentials

- [ ] 4.1 Add full-length SHA-pinned Harden-Runner as the first step in Android/API release jobs with `egress-policy: audit`; ensure runtime-security failures cannot be silently ignored.
- [ ] 4.2 Add audit-mode Harden-Runner to selected GDrive/LLM scheduled and integration jobs and set `persist-credentials: false` wherever those workflows do not perform authenticated Git writes.
- [ ] 4.3 Collect representative normal, retry, and fallback network baselines for package managers, Flutter/Gradle/pub, Rust/Docker, GitHub, GHCR, GDrive, LLM, and observability traffic without committing destination credentials.
- [ ] 4.4 Configure minimal release-job egress block allowlists from the observed baselines, avoiding broad wildcard destinations and copying `disable-sudo` only into jobs that do not require package installation with `sudo`.
- [ ] 4.5 Test release block policy and scheduled-job candidate policies in controlled workflows without production secrets; leave scheduled jobs in audit mode until their complete retry/fallback behavior is proven.

## 5. Recovery, Documentation, and Final Verification

- [ ] 5.1 Update `frontend-flutter/docs/release-signing-key-custody.md`, release runbooks, and `backend/docs/security/security-architecture.md` with environment approval, tag protection, draft-first immutability, attestation verification, Trivy exceptions, and egress operations.
- [ ] 5.2 Document and rehearse compromise response: disable affected workflows, revoke sessions/PATs/apps, rotate exposed GDrive/LLM credentials, preserve logs/attestations, review tags/releases/packages, and invoke the Android key break-glass process when signing material may be exposed.
- [ ] 5.3 Document consumer verification and its limits: Android project signature/fingerprint, GitHub build provenance, GHCR digest, SBOM, Trivy result, and the fact that provenance does not prove benign behavior.
- [ ] 5.4 Run release-script dry-runs/tests, actionlint and other relevant workflow checks, `openspec validate harden-release-provenance-and-runtime --strict`, and `./scripts/add-spdx-headers.sh --check` for changed files.
- [ ] 5.5 Complete one independently approved pre-release for each channel and record non-secret evidence for approval ordering, exact artifact set, immutable publication, digest verification, and egress behavior; if independent approval remains unavailable, leave the corresponding requirement and rollout incomplete.
