<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Tasks: Add CI Security Gates

## 1. Check Inventory and Trigger Consistency

- [ ] 1.1 Inventory current workflow/job/check names and required checks; produce a one-to-one register for repository Gitleaks, Cargo Audit, actionlint, zizmor, Dependency Review, CodeQL, and any Flutter-specific Gitleaks result.
- [ ] 1.2 Update `audit.yml` so Cargo advisory audit and repository Gitleaks run on every pull request targeting `main`, on `main`, on their schedules, and manually while preserving complete PR-range/history scanning.
- [ ] 1.3 Disambiguate repository-wide and Flutter-specific Gitleaks check names and prove that the required repository-wide result cannot be satisfied by the Flutter job.
- [ ] 1.4 Update `lint-workflows.yml` to run on every pull request targeting `main` and on `main` without path exclusions that would leave a required result absent.
- [ ] 1.5 Review all modified workflows for read-only default permissions, `persist-credentials: false` where authenticated Git writes are unnecessary, full-length SHA pins, and safe expression handling.

## 2. Dependency and Workflow Analysis

- [ ] 2.1 Add an every-PR Dependency Review workflow using `actions/dependency-review-action` at a reviewed full-length SHA with `fail-on-severity: high`, read-only contents access, and no blanket `continue-on-error`.
- [ ] 2.2 Define the advisory-exception format with advisory/package identity, rationale, and revisit condition; keep license-policy decisions out of the vulnerability gate.
- [ ] 2.3 Add zizmor alongside actionlint using a reviewed full-length SHA or checksum-verified pinned binary, high-signal defaults, and per-rule justified suppressions only.
- [ ] 2.4 Exercise actionlint and zizmor against a disposable unsafe-workflow PR and confirm stable failure output; close the test PR without merging it.

## 3. CodeQL and OSV Coverage

- [ ] 3.1 Enable CodeQL default setup for Rust and GitHub Actions on pull requests, `main`, and a schedule; do not enable unrelated languages solely because they are detected.
- [ ] 3.2 Validate that Rust extraction produces a real Rust database and findings view; if default setup cannot do so reliably, implement and validate an advanced SHA-pinned CodeQL workflow before continuing.
- [ ] 3.3 Triage initial CodeQL results, fixing actionable findings or recording narrow rule-specific exceptions, and freeze the stable CodeQL check names only after successful representative runs.
- [ ] 3.4 Add weekly/manual recursive OSV-Scanner coverage with the official pinned reusable workflow or checksum-verified binary and confirm that both `backend/Cargo.lock` and `frontend-flutter/pubspec.lock` are scanned.
- [ ] 3.5 Configure OSV reporting/artifact or SARIF output as supported, triage the initial baseline, and document why full-scan OSV findings are reporting signals while Dependency Review owns the dependency-diff gate.

## 4. Failure-Path and Fork Verification

- [ ] 4.1 Use a disposable dependency-update PR to prove that a newly introduced High/Critical known vulnerability fails Dependency Review, then close it without merging.
- [ ] 4.2 Use harmless Gitleaks test fixtures to prove that repository secret scanning fails independently of SARIF upload permission; do not use a real secret.
- [ ] 4.3 Verify with a fork or accurately simulated restricted-token PR that no repository secrets are available, contents remain read-only, SARIF upload restrictions do not mask scanner failures, and every required check still returns a result.
- [ ] 4.4 Verify opened, synchronize, and reopened pull-request events for every candidate required check and confirm that no path filter or duplicate check name creates a pending or ambiguous result.

## 5. Required-Check Rollout and Documentation

- [ ] 5.1 Promote the stabilized repository Gitleaks, Cargo Audit, Dependency Review, actionlint, zizmor, and CodeQL names to required checks while preserving `Check`, `Clippy`, `Build`, `Format`, and `Test`.
- [ ] 5.2 Re-read the effective branch/ruleset configuration and verify that a failed required security check blocks an ordinary merge and no standing administrator bypass restores one.
- [ ] 5.3 Update the security architecture and CI runbook with the distinct roles of Dependency Review, Dependabot, `cargo-deny`, OSV, CodeQL, actionlint, zizmor, and Gitleaks, including exception and rollback procedures.
- [ ] 5.4 Run actionlint, the relevant repository workflow tests, `openspec validate add-ci-security-gates --strict`, and `./scripts/add-spdx-headers.sh --check` for changed files.
- [ ] 5.5 Observe at least one scheduled OSV run and representative ordinary/fork PRs after rollout; document CI-time impact, remaining findings, and any required-check rollback without silently deleting evidence.
