<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Design: Add CI Security Gates

## Context

The repository's required `main` checks are currently limited to `Check`, `Clippy`, `Build`, `Format`, and `Test`. Security tooling exists but has inconsistent gating semantics:

- `audit.yml` runs `cargo-deny check advisories` and Gitleaks, but its pull-request trigger only matches `backend/Cargo.lock` changes.
- `lint-workflows.yml` runs actionlint only when workflow paths change.
- `flutter-ci.yml` contains another job named `Gitleaks (secrets)`, creating ambiguous check identity.
- No Dependency Review, zizmor, OSV-Scanner, or configured CodeQL check exists.
- GitHub reports `rust` and `actions` among the available CodeQL default-setup languages.
- Workflows use `pull_request`, not `pull_request_target`; fork PRs receive no repository secrets and cannot upload SARIF with the normal restricted token.

The design must make security checks required without allowing path filters or duplicate names to create pending, missing, or misleading merge signals. It builds on the native secret/dependency settings and platform-enforced SHA pinning from `harden-github-repository-posture`.

## Goals / Non-Goals

**Goals:**

- Produce one unambiguous result for every required security check on every pull request.
- Block known High/Critical dependency regressions and scanner-detected security violations before merge.
- Add CodeQL for Rust and GitHub Actions, and zizmor for workflow-specific security analysis.
- Extend OSV vulnerability monitoring across supported committed lockfiles without duplicating every Dependabot alert as a second blocking gate.
- Preserve fork-PR safety and least-privilege tokens.
- Make scanner failures independent of optional SARIF upload permissions.

**Non-Goals:**

- Replacing existing Rust tests, Flutter analysis, architecture guardrails, Gitleaks, or `cargo-deny`.
- Adding CodeQL for Dart, which is not listed as an available language for this repository.
- Adding hosted security platforms or runtime network controls.
- Blocking every informational OSV or CodeQL finding immediately without a baseline.
- Changing release environments, tags, provenance, or artifact publication.

## Decisions

### D1: Separate scan execution from SARIF publication

Every scanner's local exit status determines job success. SARIF upload is conditional on an event/repository context where `security-events: write` is valid and must never convert a failed scan into success. Fork PRs therefore still receive a hard job failure even if their findings cannot be uploaded to code scanning.

Workflows have top-level `permissions: contents: read`; only same-repository jobs that upload SARIF receive job-scoped `security-events: write`. Checkout uses `persist-credentials: false` unless authenticated Git operations are required.

### D2: Make trigger coverage match required-check semantics

Run `Audit`, repository Gitleaks, actionlint, zizmor, Dependency Review, and the stabilized CodeQL checks on every pull request targeting `main`. Run them on `main` pushes as well; retain daily/weekly schedules where they detect newly published advisories.

Remove or restructure path filters before marking a check required. A workflow skipped by path filtering can leave a required check pending and block merging, while a different workflow with the same check name can produce ambiguous results.

Give repository Gitleaks and Flutter-specific legacy scanning unique names. The required-check register maps each required name to exactly one workflow/job definition.

### D3: Use Dependency Review as the blocking dependency-diff gate

Add `actions/dependency-review-action` on every pull request with `fail-on-severity: high`. This covers newly introduced known High/Critical vulnerabilities in dependency changes visible to GitHub's dependency graph, including supported Cargo and Pub manifests/lockfiles.

Start without a new license-denial policy; license policy is already handled elsewhere and should not be conflated with vulnerability gating. An accepted advisory exception must identify the advisory, affected package, rationale, and revisit condition. No blanket `continue-on-error` is permitted.

Dependabot alerts/security updates remain the always-on detection and remediation channel; Dependency Review supplies the merge-time diff decision.

### D4: Start CodeQL with default setup for Rust and Actions

Use GitHub's default setup to minimize custom build logic and keep analysis aligned with GitHub's supported extractor behavior. Select Rust and Actions initially; do not enable every detected language merely because it appears in the repository.

Pilot on pull requests, `main`, and a schedule. Inspect findings and runtime, then add the stable CodeQL check names to required checks. If default setup cannot build or extract the Rust workspace reliably, replace it with an advanced, SHA-pinned CodeQL workflow within this change rather than silently dropping Rust coverage.

Kotlin/Android analysis is deferred because it may require a Flutter/Android-aware build and is not needed for the initial gate.

### D5: Run actionlint and zizmor as complementary workflow gates

Keep actionlint for workflow syntax, expression, and shell correctness. Add zizmor for security-specific findings such as credential persistence, excessive permissions, dangerous triggers, template injection, and unpinned references.

Both run on every pull request. Their configurations use the high-signal default persona first; a documented finding suppression must name the rule and rationale. The repository Actions SHA policy remains the authoritative platform backstop for unpinned actions.

### D6: Use OSV-Scanner as scheduled monorepo coverage

Run the official OSV-Scanner reusable workflow or a checksum-verified pinned binary weekly and on manual dispatch. Scan the repository recursively so supported lockfiles, including `backend/Cargo.lock` and `frontend-flutter/pubspec.lock`, are evaluated against OSV data.

Publish results to code scanning where supported, but do not make the full-repository OSV result a second blanket blocking gate in the initial rollout. New dependency diffs are gated by Dependency Review; OSV catches ecosystem/database differences and newly disclosed vulnerabilities in the existing lockfiles.

### D7: Promote checks only after evidence, then keep them required

For each new check: establish a clean baseline, test its failure path, verify fork behavior, freeze its unique name, and only then add it to the effective `main` required-check list. A failed required security check cannot be bypassed by an ordinary merge or a standing administrator bypass.

Removing a check from required status is a deliberate rollback action recorded in the issue, not a response to a single inconvenient finding.

## Risks / Trade-offs

- **Path-filtered checks remain pending** → Make required workflows run on every pull request and test opened/synchronize/reopened events before updating rulesets.
- **Duplicate check names satisfy the wrong requirement** → Maintain a one-to-one workflow/job/check-name register and rename the Flutter-specific duplicate.
- **CodeQL default setup cannot analyze the Rust workspace** → Time-box diagnosis, then use an advanced workflow with the same check contract; do not claim Rust coverage from Actions-only analysis.
- **High-severity advisory has no available fix** → Document a narrow exception with exploitability rationale and revisit trigger; do not disable the whole gate.
- **OSV, Dependabot, and `cargo-deny` produce duplicate alerts** → Assign each tool a role: diff gate, native alert/remediation, Rust daily audit, and scheduled cross-ecosystem coverage.
- **Fork PR cannot upload SARIF** → Keep scanner exit codes authoritative and treat upload as a same-repository reporting enhancement.
- **Additional CI increases runtime and rate limits** → Keep scanners lightweight, avoid rebuilding the full workspace in OSV/zizmor jobs, and monitor runtime before adding more platforms.
- **Scanner configuration itself becomes a supply-chain risk** → Full-length SHA pins, CODEOWNERS on `.github/`, no secret-bearing `pull_request_target`, and weekly reviewed Dependabot bumps.

## Migration Plan

1. Record current check names and required-check configuration.
2. Change triggers and unique names without making the affected checks required; verify every PR receives each result.
3. Add Dependency Review, zizmor, and OSV in reporting/pilot mode as applicable; add CodeQL default setup.
4. Triage existing findings and add only narrow, documented exceptions.
5. Exercise a deliberately vulnerable dependency diff and an unsafe workflow on a disposable test PR, then close it without merging.
6. Promote stable checks to required in the effective ruleset and retain the existing five core checks.
7. Observe one weekly OSV run and several ordinary/fork PRs. Roll back a problematic required-check entry temporarily while preserving the scanner as non-blocking and recording the reason; restore it after correction.

## Open Questions

- Does CodeQL default setup complete Rust extraction within an acceptable CI-time budget? The advanced-workflow fallback is part of this change if not.
- Which existing CodeQL/OSV findings require remediation versus narrowly scoped exceptions? This is a baseline task and must not be answered with a global suppression.
- Can the duplicate Flutter Gitleaks job be removed after repository-wide scanning is proven on release tags, or must it remain under a unique release-gate name? The required-check identity must remain unambiguous in either case.

## Source Register

All sources were accessed or revalidated on 2026-11-26. Pin actual action versions only during implementation; the version comments in this design are intentionally not implementation pins.

### GitHub security and workflow behavior

- [GitHub Actions secure use reference](https://docs.github.com/en/actions/reference/security/secure-use)
- [Dependency Review Action](https://github.com/actions/dependency-review-action)
- [About dependency review](https://docs.github.com/en/code-security/concepts/supply-chain-security/about-dependency-review)
- [Configure code scanning](https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/configure-code-scanning/configure-code-scanning)
- [CodeQL supported languages and frameworks](https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/)
- [Troubleshooting required status checks](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks)
- [Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
- [Automatic token authentication](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token)
- [Uploading SARIF files to GitHub](https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/integrate-with-existing-tools/upload-sarif-file)

### Open-source analysis tools

- [zizmor documentation](https://docs.zizmor.sh/)
- [zizmor repository](https://github.com/zizmorcore/zizmor)
- [actionlint](https://github.com/rhysd/actionlint)
- [OSV-Scanner supported languages and lockfiles](https://google.github.io/osv-scanner/supported-languages-and-lockfiles/)
- [OSV-Scanner GitHub Action](https://github.com/google/osv-scanner-action)
- [OSV vulnerability database](https://osv.dev/)
- [Gitleaks](https://github.com/gitleaks/gitleaks)
- [cargo-deny](https://github.com/EmbarkStudios/cargo-deny)
- [RustSec Advisory Database](https://github.com/RustSec/advisory-db)
