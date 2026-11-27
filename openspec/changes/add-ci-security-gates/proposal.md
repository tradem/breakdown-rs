<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Add CI Security Gates

**Tracking issue:** [#997](https://github.com/tradem/breakdown-rs/issues/997)

## Why

The repository runs several security tools, but most are not required merge checks and some only run for narrow path filters. A pull request can therefore merge on the strength of the five core Rust checks without a consistent secret, dependency, code, or workflow-security decision.

This change turns the existing scanners into coherent pull-request gates and fills the highest-value analysis gaps with CodeQL, Dependency Review, zizmor, and OSV-Scanner. It depends on the native repository protections and Actions policy established by `harden-github-repository-posture`; release-only hardening remains in `harden-release-provenance-and-runtime`.

## What Changes

- Make repository-wide Gitleaks and Cargo advisory checks run on every pull request and on `main`, not only when `backend/Cargo.lock` changes.
- Add GitHub Dependency Review on every pull request and fail on newly introduced High or Critical known vulnerabilities, subject to documented advisory exceptions.
- Enable CodeQL code scanning for Rust and GitHub Actions using GitHub's default setup, then promote the stable checks to required status checks after a pilot.
- Add zizmor alongside actionlint for GitHub Actions security analysis and run both on every pull request so they can safely become required checks.
- Add scheduled monorepo OSV-Scanner coverage for committed lockfiles, including Cargo and Pub, as reporting-based defense in depth rather than a duplicate blocking gate.
- Disambiguate duplicate security-check names so required checks identify one unambiguous result.
- Update branch/ruleset requirements only after trigger coverage and check-name stability have been demonstrated.
- Preserve fork-PR isolation, read-only default tokens, full SHA pinning, safe expression handling, and failure of the scan itself even when SARIF upload is unavailable.
- Add reproducible acceptance tests for unsafe workflow references, vulnerable dependency changes, fork PRs, and required-check behavior.

## Capabilities

### New Capabilities

- `pull-request-security-gates`: Required-check identity, trigger coverage, dependency-review decisions, and merge-blocking semantics for security checks.
- `code-and-workflow-security-analysis`: CodeQL, actionlint, and zizmor analysis scope, permissions, and failure behavior.
- `dependency-vulnerability-monitoring`: Scheduled OSV-Scanner coverage and advisory triage across supported monorepo lockfiles.

### Modified Capabilities

- `ci-pipeline`: Extends the CI contract with stable, required security gates while preserving the existing build and quality jobs.
- `security-audit`: Replaces the outdated scanner/trigger assumptions with repository-wide secret scanning and Cargo advisory checks on every pull request and `main`.

## Impact

- `.github/workflows/audit.yml`, `lint-workflows.yml`, `flutter-ci.yml`, and a new Dependency Review/OSV security workflow or workflows.
- GitHub Code Scanning default setup and branch/ruleset required-check configuration.
- `openspec/specs/ci-pipeline/spec.md` and `openspec/specs/security-audit/spec.md` when synchronized after implementation.
- CI documentation and security architecture/runbooks.
- New CI-only tools: `actions/dependency-review-action`, zizmor, OSV-Scanner, and GitHub CodeQL; no application runtime dependencies.
- Additional CI minutes and advisory triage; no production API, database, Flutter UI, event, or application wire-contract changes.
