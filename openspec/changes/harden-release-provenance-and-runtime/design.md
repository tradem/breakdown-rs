<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Design: Harden Release Provenance and Runtime

## Context

Two tag-triggered publication paths exist:

- `flutter-release.yml` uses `v*`, reusable quality gates, a `Release` environment, Android signing secrets, and `contents: write` for GitHub Release publication.
- `release-image.yml` uses `api-v*`, `packages: write`, and direct GHCR publication without an environment.

The live review on 2026-11-26 found that `Release` has only a custom `v*` tag deployment policy and no required reviewers. No tag ruleset exists. The Android workflow comments describe reviewer gating, but the effective settings do not provide it. The API workflow has no protected environment, SBOM/provenance, image scan, or artifact attestation. Android artifacts have project signatures but no GitHub build-provenance attestation or immutable-release contract.

The project currently has one administrator. A second self-controlled account is not independent approval. Full completion of the independent-approval control therefore requires a second trusted person; implementation must not disguise that prerequisite.

This change assumes native account/ruleset controls from `harden-github-repository-posture` and stable required security checks from `add-ci-security-gates`.

## Goals / Non-Goals

**Goals:**

- Make release-tag creation, environment approval, signing, and publication explicit separate control points.
- Prevent the triggering actor from providing the sole approval for a protected release.
- Keep Android signing secrets isolated from API-image publication.
- Scan the exact image bytes before GHCR publication and attest the resulting immutable digest.
- Provide build-provenance verification for GHCR, APK, and AAB artifacts.
- Publish Android releases draft-first so immutable releases contain the complete artifact set.
- Observe and then constrain unexpected network egress from secret-bearing CI jobs.
- Provide tested recovery and rollback procedures.

**Non-Goals:**

- Replacing or rotating the Android signing key as part of routine hardening.
- Adding Wiz or another hosted security dashboard.
- Claiming that provenance proves an artifact is vulnerability-free or benign.
- Changing F-Droid, Play Store, application IDs, signing fingerprints, or distribution policy.
- Blocking scheduled jobs immediately with an untested network allowlist.
- Making a sole maintainer's self-approval satisfy independent review.

## Decisions

### D1: Constrain release tags independently from branch protection

Create tag-targeted rulesets for `v*` and `api-v*`. Restrict creation to designated release-manager actors through the narrowest available bypass/configuration, and deny updates, non-fast-forward changes, and deletion for everyone else. Do not reuse the `main` branch ruleset because tags have different review and lifecycle semantics.

Tag protection reduces accidental or unauthorized release triggers but does not replace environment approval: an administrator may still be able to change repository settings.

### D2: Isolate Android and API publication environments

Keep the existing `Release` environment exclusively for Android and its `v*` tag policy. Do not add `api-v*` to it, because doing so would make Android signing secrets available to a workflow changed on an API release tag.

Create `Release-API` with only `api-v*` deployment refs and no Android secrets. The API release job references this environment and receives only `contents: read`, `packages: write`, `id-token: write`, and `attestations: write` when required.

Both environments require at least one reviewer who is not the workflow-triggering actor, with self-review prevention enabled. If no independent reviewer exists, protected publication remains incomplete/blocked; a runbook may allow an explicitly accepted, less-strong solo release mode only as a documented residual risk, never as completion of this requirement.

### D3: Preserve a single signed Android artifact lineage and publish draft-first

Keep the existing project keystore, fingerprint verification, and one-key contract. Add attestation after signing and verification, not in place of either.

The publication script creates or reuses a draft GitHub Release, uploads exactly the three split APKs and one AAB, verifies the asset set and attestations, and only then publishes the release. A rerun reuses the draft or fails visibly; it never silently replaces an asset.

Enable repository immutable releases only after this draft-first path passes a dry-run. A mistaken published immutable release is corrected by a superseding release/version, not by moving its tag or replacing its assets.

### D4: Scan and publish the same API image bytes

Build the API image once into a local or OCI-layout staging output, scan that exact output with Trivy, and publish it without a second unverified rebuild. If the registry push requires a rebuild, the pipeline must prove digest equality with the scanned artifact before continuing.

Fail on High/Critical vulnerabilities for which a fix is available. Unfixed findings and false positives follow a narrow exception register containing the vulnerability, image/digest context, rationale, and revisit date. Do not globally disable Trivy failure behavior.

Enable Docker BuildKit SBOM and provenance attestations. After push, capture the immutable registry digest and create a GitHub build-provenance attestation for that digest with `push-to-registry` semantics. Never attest only a mutable tag.

### D5: Attest every Android artifact and provide consumer verification

Create GitHub Artifact Attestations for each APK and the AAB after their project-signature checks pass. Grant `id-token: write` and `attestations: write` only to the Android build/publish job.

The release notes/runbook document both independent checks:

1. Android signature/fingerprint verification against the project key.
2. GitHub build-provenance verification against `tradem/breakdown-rs` and the expected workflow/ref.

A successful attestation establishes build origin and integrity; it is not a substitute for tests, Trivy, signature verification, or review.

### D6: Introduce Harden-Runner from observed evidence

Add the SHA-pinned StepSecurity Harden-Runner as the first step in Android/API release jobs and selected scheduled/integration jobs that receive GDrive or LLM credentials.

Start every job in `egress-policy: audit`. Record expected package, SDK, API, registry, GitHub, and observability endpoints over representative runs. Release jobs then move to `egress-policy: block` with a minimal destination allowlist. Scheduled jobs move to block mode only after their normal and retry paths are understood; until then they retain audit monitoring.

Test block mode in a controlled workflow without real secrets. An allowlist must not include broad wildcard destinations that make exfiltration trivial. Disabling runner `sudo` is optional per job and cannot be copied blindly into jobs that currently install packages with `sudo`.

### D7: Minimize credential persistence and recovery time

Use `persist-credentials: false` for checkout in every job that does not perform authenticated Git writes. Keep write-scoped tokens and signing/registry credentials confined to the protected publication job.

Extend release and incident runbooks with: disable affected workflows, revoke sessions/PATs/GitHub Apps, rotate exposed API/GDrive credentials, preserve relevant logs/attestations, review tags/releases/packages, and follow the existing Android key-custody break-glass process if signing material may be exposed.

## Risks / Trade-offs

- **No independent reviewer is available** → Keep the approval requirement visibly incomplete and releases blocked or explicitly risk-accepted; never claim self-approval as a completed control.
- **Environment or tag migration breaks releases** → Rehearse with a pre-release/draft, preserve existing tag patterns, and roll forward with a corrected tag instead of rewriting published history.
- **Immutable release is published with missing or wrong assets** → Draft-first verification, exact asset manifest, and publish only after all attestations succeed; recover through a superseding release.
- **Scanned image differs from pushed image** → Scan an OCI/local artifact and enforce digest equality before attestation/publication.
- **Trivy reports unactionable upstream CVEs** → Gate on fixable High/Critical findings and use expiring, justified exceptions rather than disabling scanning.
- **Egress block mode breaks package downloads or retries** → Audit representative runs first, include retry/backup endpoints deliberately, and deploy block mode incrementally.
- **Harden-Runner becomes another trusted dependency** → Pin by SHA, restrict its use to high-value jobs, review updates, and keep native least-privilege controls.
- **Attestation creates false confidence** → Document its limited guarantee and verify signature, provenance, tests, and vulnerability results independently.
- **Compromised administrator edits all protections** → Independent release reviewer, account hardening, monitoring, and incident response reduce but cannot eliminate this residual risk.

## Migration Plan

1. Designate release managers and at least one independent environment reviewer; record this prerequisite without exposing personal security details.
2. Add tag rulesets in evaluate mode, verify expected matches, then activate creation/update/deletion restrictions.
3. Add reviewer protection to Android `Release`, create isolated `Release-API`, and test that an unapproved run waits before secrets are available.
4. Implement draft-first Android publication and attestations in dry-run/test releases; enable immutable releases only after the complete asset set is verified.
5. Change the API pipeline to staged build → exact-artifact Trivy scan → push → digest attestation; verify with `gh attestation verify` against the GHCR digest.
6. Add Harden-Runner in audit mode, collect baselines, and enable block mode first in release jobs.
7. Run an end-to-end pre-release and document evidence. Roll back unmerged workflow changes by revert; roll back a published artifact only by marking it superseded and publishing a corrected version, never by mutating an immutable release.

## Open Questions

- Who is the independent Android/API environment reviewer, and are the same reviewers acceptable for both environments? This must be answered before independent approval can be marked complete.
- Which destinations are required for Flutter/Gradle/pub, Rust/Docker, GHCR, GDrive, LLM, and observability traffic? The implementation must derive these from audit evidence rather than guessing.
- Should pre-release tags require the same independent approval as stable tags? The safe default is yes; any exception must be explicit and must not expose production signing secrets without approval.

## Source Register

All sources were accessed or revalidated on 2026-11-26. Actual third-party actions must be pinned to reviewed full-length commit SHAs during implementation.

### Release authorization and artifact integrity

- [GitHub Actions secure use reference](https://docs.github.com/en/actions/reference/security/secure-use)
- [About repository rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
- [Managing deployment environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)
- [Reviewing deployments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/review-deployments)
- [About releases, including immutable releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
- [Using Artifact Attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations)
- [Verifying Artifact Attestations with the GitHub CLI](https://cli.github.com/manual/gh_attestation_verify)
- [SLSA provenance](https://slsa.dev/spec/v1.0/provenance)
- [Sigstore](https://www.sigstore.dev/)
- [Docker BuildKit attestations](https://docs.docker.com/build/metadata/attestations/)
- [Docker SBOM attestations](https://docs.docker.com/build/metadata/attestations/sbom/)
- [Docker build provenance attestations](https://docs.docker.com/build/metadata/attestations/slsa-provenance/)

### Vulnerability and runtime scanning

- [Trivy documentation](https://trivy.dev/)
- [Trivy repository](https://github.com/aquasecurity/trivy)
- [StepSecurity Harden-Runner documentation](https://docs.stepsecurity.io/github-actions/harden-runner)
- [StepSecurity Harden-Runner repository](https://github.com/step-security/harden-runner)

### Project-local release contracts

- `frontend-flutter/docs/release-signing-key-custody.md`
- `.github/workflows/flutter-release.yml`
- `.github/workflows/release-image.yml`
- `openspec/specs/flutter-release-artifacts/spec.md`
- `openspec/specs/flutter-release-signing/spec.md`
