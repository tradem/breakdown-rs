<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Tasks: Harden GitHub Repository Posture

## 1. Baseline and Native GitHub Protections

- [ ] 1.1 Capture the current non-secret repository, Actions, branch-protection, and ruleset configuration with the read-only API commands in the design; compare it with the 2026-11-26 baseline and record only configuration values.
- [ ] 1.2 Enable Secret Scanning and Push Protection, evaluate supported non-provider patterns and validity checks for the project's credential formats, and verify the resulting repository security settings.
- [ ] 1.3 Enable Dependabot Alerts and Dependabot Security Updates while retaining all existing Cargo, GitHub Actions, Pub, and Gradle version-update entries; verify alerts for the dependency graph without auto-merging remediation PRs.
- [ ] 1.4 Enable Private Vulnerability Reporting and confirm that the Security tab exposes the private intake path.
- [ ] 1.5 Enable the repository Actions requirement for full-length commit SHA pins and confirm with a disposable workflow/test ref that a mutable `@v4` reference is rejected without changing `main`.
- [ ] 1.6 Verify that default workflow permissions remain read-only and Actions still cannot approve pull-request reviews.

## 2. Account, Branch, and Ruleset Hardening

- [ ] 2.1 Perform the maintainer access review: phishing-resistant authentication, offline recovery codes, active sessions, SSH keys, PATs, OAuth Apps, and GitHub Apps; record completion without committing private account details.
- [ ] 2.2 Write a parity matrix mapping every existing classic `main` review/check/deletion/non-fast-forward requirement into the target ruleset, including the five current core checks and CODEOWNERS behavior.
- [ ] 2.3 Add or update the target `main` ruleset in evaluate mode, inspect its results, then activate parity before removing redundant classic behavior so no protection gap occurs.
- [ ] 2.4 Remove the standing repository-admin `always` bypass and enforce administrator restrictions in the remaining classic configuration; verify that prohibited direct and non-fast-forward updates are rejected for administrators as well as ordinary actors.
- [ ] 2.5 Designate an independent reviewer, then enable last-push approval and required conversation resolution; if no reviewer is available, leave this task unchecked and record the control as incomplete rather than configuring self-approval.
- [ ] 2.6 Document the emergency break-glass procedure with named reason, timestamps, removal owner, and post-incident review; remove any undocumented standing bypass.

## 3. Security Policy, Runbook, and Monitoring

- [ ] 3.1 Add root `SECURITY.md` with supported versions, private-reporting link, report contents, response objectives, responsible-disclosure guidance, and credential-rotation guidance.
- [ ] 3.2 Add `backend/docs/security/repository-security-posture.md` containing the target settings matrix, read-only `gh api` verification procedure, account/token review checklist, break-glass process, and non-secret evidence rules.
- [ ] 3.3 Add an OpenSSF Scorecard workflow with weekly, `main`, protection-change, and manual triggers; pin every action by full-length SHA, use least-privilege permissions, disable persisted checkout credentials, and require no administrative PAT.
- [ ] 3.4 Configure Scorecard SARIF/artifact reporting so restricted events retain diagnostic output and upload failures do not erase analysis results.
- [ ] 3.5 Update `backend/docs/security/security-architecture.md` and relevant CI-hardening guidance with the native-control baseline, platform-enforced SHA policy, Scorecard role, and links to the new runbook.
- [ ] 3.6 Run the initial Scorecard baseline and create a triage register for individual findings, including owner/rationale/revisit condition where a gap is temporarily accepted.

## 4. Verification and Rollout

- [ ] 4.1 Test Push Protection with a documented harmless test secret pattern, never a real credential, and confirm Gitleaks remains configured for custom-pattern coverage.
- [ ] 4.2 Verify the effective `main` rules through read-only API calls and disposable-ref negative tests for force-push, deletion, missing review, stale review, and missing required checks; do not perform a destructive test on `main`.
- [ ] 4.3 Run actionlint and the repository workflow checks for the new Scorecard workflow, then verify its scheduled/manual result and retained SARIF/artifact output.
- [ ] 4.4 Run `openspec validate harden-github-repository-posture --strict` and `./scripts/add-spdx-headers.sh --check` for the changed files.
- [ ] 4.5 Review the posture after one week, document residual solo-administrator and optional-feature limitations, and confirm that no long-lived administrative token or external security-platform credential was introduced.
