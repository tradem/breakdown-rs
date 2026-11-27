<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Harden GitHub Repository Posture

**Tracking issue:** [#996](https://github.com/tradem/breakdown-rs/issues/996)

## Why

The repository already has useful review and workflow conventions, but the live GitHub configuration leaves native secret and vulnerability protections disabled, permits a standing administrator bypass, and does not enforce the existing SHA-pinning convention. The project needs a verifiable repository-security baseline before adding more CI scanners or changing release publication.

This change continues the defensive work completed in historical issues #83 and #86. It is the first of three ordered changes; `add-ci-security-gates` builds on its settings baseline, and `harden-release-provenance-and-runtime` handles release-specific controls separately.

## What Changes

- Enable and verify GitHub Secret Scanning, Push Protection, Dependabot Alerts, Dependabot Security Updates, and Private Vulnerability Reporting for the public repository.
- Require full-length commit SHA pins through the repository Actions policy instead of relying only on contributor documentation.
- Consolidate the effective `main` protection contract across classic branch protection and repository rulesets without dropping existing review or status-check requirements.
- Remove the standing administrator `always` bypass, prevent force-pushes and deletions through the effective rules, and define a documented, time-bounded emergency exception procedure.
- Require approval of the most recent push and resolved review conversations once an independent reviewer is available; do not represent self-review as independent approval.
- Add a `SECURITY.md` policy and a repository-security runbook covering account hardening, fine-grained tokens, GitHub Apps, recovery, and read-only configuration verification.
- Add OpenSSF Scorecard as scheduled, non-blocking posture monitoring with SARIF reporting and no administrative PAT.
- Record authoritative product documentation and the live-configuration evidence used to define the target posture.
- Defer mandatory commit/tag signatures, third-party security SaaS, and release-specific tag/environment redesign to explicit follow-up scope.

## Capabilities

### New Capabilities

- `repository-security-posture`: Account, Actions-policy, branch/ruleset, secret-protection, and configuration-verification requirements for the public GitHub repository.
- `vulnerability-disclosure`: Private reporting, security-policy content, and vulnerability-intake expectations.
- `repository-posture-monitoring`: Scheduled OpenSSF Scorecard monitoring, least-privilege permissions, and non-blocking baseline management.

### Modified Capabilities

- `dependency-management`: Adds vulnerability alerts and automatic security-update requirements to the existing version-update contract.

## Impact

- GitHub repository settings: Code Security, Actions permissions, classic branch protection, repository rulesets, and private vulnerability reporting.
- New documentation: `SECURITY.md` and a repository-security operations runbook under `backend/docs/security/`.
- New or updated CI: an OpenSSF Scorecard workflow under `.github/workflows/`; all actions remain SHA-pinned.
- Existing documentation: `backend/docs/security/security-architecture.md` supply-chain section and the relevant CI-hardening instructions.
- Dependencies/tooling: OpenSSF Scorecard GitHub Action and GitHub code-scanning SARIF upload; no application runtime dependency changes.
- No backend API, Flutter UI, database, event, authorization-boundary, or application wire-contract changes.
- Repository settings require an administrator to perform and verify manual steps; CI alone cannot prove every account-level control.
