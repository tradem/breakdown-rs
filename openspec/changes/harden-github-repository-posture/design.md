<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3.1-pro (neuralwatt) -->

# Design: Harden GitHub Repository Posture

## Context

The public repository `tradem/breakdown-rs` already has SHA-pinned actions by convention, CODEOWNERS, required reviews, strict core status checks, Gitleaks, and read-only default workflow tokens. Historical issues #83 and #86 established that baseline.

A read-only live configuration review on 2026-11-26 found a different effective state in several important areas:

| Control | Observed state |
|---|---|
| Dependabot alerts and security updates | Disabled |
| Secret Scanning and Push Protection | Disabled |
| Private Vulnerability Reporting | Disabled; no security policy URL |
| CodeQL default setup | Not configured; Rust and Actions are available languages |
| Actions permissions | All actions allowed; full-length SHA pinning not enforced |
| Default `GITHUB_TOKEN` | Read-only; Actions cannot approve pull-request reviews |
| `main` classic protection | One review, CODEOWNERS, stale-review dismissal, strict checks |
| `main` required checks | Only `Check`, `Clippy`, `Build`, `Format`, `Test` |
| `main` classic bypass behavior | Force pushes allowed; admins not enforced |
| `main` active ruleset | Deletion/non-fast-forward/creation rules, but repository admins have `always` bypass |
| Repository collaborators | One user with administrator permission |

Classic branch protection and the active ruleset must be evaluated together. The ruleset already blocks non-fast-forward updates for ordinary users, but the standing administrator bypass prevents that from being an administrator-independent guarantee.

The repository is public, so GitHub's native public-repository security capabilities and OpenSSF tooling provide a low-cost baseline. Account-level authentication, personal tokens, OAuth grants, and some GitHub App settings cannot be established from repository files and require an explicit administrator review.

## Goals / Non-Goals

**Goals:**

- Establish a documented, verifiable repository-security baseline using native controls first.
- Make the existing full-length SHA-pinning convention platform-enforced.
- Remove standing bypasses and preserve effective review and status-check protection during ruleset consolidation.
- Prevent known secrets and vulnerable dependencies from entering the repository where native controls support it.
- Provide a private vulnerability-intake channel and an incident/recovery runbook.
- Detect posture drift with OpenSSF Scorecard without introducing an administrative CI credential.
- State residual risks honestly, especially for a solo administrator.

**Non-Goals:**

- Purchasing or integrating Wiz, Aikido, Socket, or another hosted security platform.
- Implementing application SAST, Dependency Review, zizmor, or OSV-Scanner; those belong to `add-ci-security-gates`.
- Redesigning release tags, environments, signing, provenance, or runner egress; those belong to `harden-release-provenance-and-runtime`.
- Making mandatory commit/tag signatures a precondition for this change.
- Claiming that repository settings can fully contain a malicious repository administrator.
- Storing GitHub settings or an administrative PAT in CI for configuration management.

## Decisions

### D1: Use native GitHub controls before adding external platforms

Enable Secret Scanning, Push Protection, Dependabot Alerts, Dependabot Security Updates, and Private Vulnerability Reporting directly. Keep Gitleaks as complementary custom-pattern and CI enforcement coverage.

This minimizes third-party credentials and duplicated alerts. Wiz's official pricing flow is quote-based and no permanent OSS offering was established during research; Aikido and Socket remain optional later evaluations, not prerequisites.

### D2: Enforce full-length SHA pins through the Actions repository policy

Set `sha_pinning_required=true` while retaining the existing weekly Dependabot `github-actions` updates. Do not introduce an action allowlist in this change: the maintenance cost and release friction outweigh its incremental benefit after SHA enforcement, CODEOWNERS, actionlint, and the later zizmor gate.

All first- and third-party actions, including GitHub-owned actions, must follow the full-length SHA rule. Local reusable workflows remain subject to CODEOWNERS review.

### D3: Consolidate protection semantics without a protection gap

Use one documented ruleset as the target source of truth for `main`. Before retiring any classic protection, reproduce all effective requirements: pull request, one approval, CODEOWNERS, stale-review dismissal, strict up-to-date checks, all currently required check names, deletion denial, and non-fast-forward denial.

Remove the repository-admin `always` bypass and enable administrator enforcement while classic protection remains. Add conversation resolution and last-push approval after confirming that at least one independent reviewer can satisfy them. If the project has only one active maintainer, the last-push-approval task remains explicitly blocked rather than weakening the meaning of approval.

A break-glass exception is manual, exceptional, logged, and time-bounded. There is no standing `always` bypass. Any temporary bypass must have a named reason, creation time, removal owner, and post-incident review; administrator rights to edit the ruleset remain a residual risk.

Mandatory signed commits are deferred: hardware-backed signing can be valuable, but signatures do not establish review independence or benign intent.

### D4: Treat account and token hygiene as operational controls

The runbook requires phishing-resistant authentication (passkey or FIDO2 security key), offline recovery codes, active-session review, and an inventory of SSH keys, fine-grained PATs, OAuth Apps, and GitHub Apps. Automation uses a least-privilege GitHub App with short-lived installation tokens where practical instead of a broad classic PAT.

No long-lived administrative token is introduced for Scorecard or configuration verification. Live verification uses an administrator's interactive `gh` session or GitHub's UI and records only non-secret results.

### D5: Monitor posture with OpenSSF Scorecard, not a custom admin bot

Run the official Scorecard Action on pushes to `main`, relevant protection changes, a weekly schedule, and manual dispatch. Publish SARIF to code scanning where permitted and retain a short-lived artifact for diagnosis.

Scorecard starts non-blocking. A score is a monitoring signal, not a merge-time security proof. Repository rules make posture data accessible more consistently than legacy-only settings; no elevated PAT is added merely to improve a score.

### D6: Provide private, actionable vulnerability intake

Add root `SECURITY.md` with supported versions, the private-reporting entry point, report-content expectations, response objectives, and a prohibition on public disclosure of unresolved vulnerabilities. Keep exact response targets operational rather than contractual guarantees.

The incident section distinguishes secret exposure from vulnerability disclosure: exposed credentials must be revoked/rotated; deleting a commit does not revoke them.

### D7: Verify effective settings with read-only evidence

The runbook maps every target control to a UI location or read-only GitHub API query. Completion requires before/after evidence for repository security features, Actions permissions, branch/ruleset behavior, and required checks. Secrets, access tokens, private app metadata, and personal security details are never committed as evidence.

## Risks / Trade-offs

- **Ruleset consolidation accidentally drops reviews or checks** → Apply the target rules in evaluate mode first, compare both configurations, migrate all requirements, and only then remove the overlapping classic rule.
- **Solo maintainer cannot satisfy independent approval** → Leave independent last-push approval explicitly incomplete; prioritize account hardening and do not use a second self-controlled account as simulated separation of duties.
- **Push Protection does not recognize every secret format** → Retain Gitleaks and custom patterns, rotate any exposed secret, and test only with documented harmless test patterns.
- **Dependabot security updates increase PR volume** → Keep existing grouping for routine updates, review security updates separately, and use alerts as triage input rather than auto-merging.
- **Scorecard creates false confidence or alert noise** → Use it as a non-blocking baseline, review individual checks, and document accepted risks with revisit dates.
- **Administrator can disable the controls** → Remove standing bypasses, monitor posture, review account activity, and document that a second independent administrator/reviewer is required for stronger separation.
- **External tools expand the supply-chain attack surface** → Native controls first; any later GitHub App evaluation requires a permission and data-flow review.

## Migration Plan

1. Capture the current non-secret configuration and verify that no pending settings change is in progress.
2. Enable native secret/dependency/reporting controls and the Actions SHA policy. These settings can be reverted individually without application deployment.
3. Add the target `main` ruleset in evaluate mode, compare results with classic protection, then activate it and remove only redundant classic behavior after parity is proven.
4. Add `SECURITY.md`, the operations runbook, and Scorecard in one reviewed repository change.
5. Run a harmless Push Protection test, a non-fast-forward rejection test on a disposable ref, and a Scorecard baseline. Do not use a real credential for testing.
6. Review results after one week and document residual exceptions. Roll back workflow additions by reverting the reviewed commit; settings rollback must preserve the stronger of the old and new protections unless it is blocking legitimate work.

## Open Questions

- Who can act as the independent reviewer for last-push approval and, later, protected releases? This is an operational prerequisite, not a reason to weaken the specification.
- Which emergency-break-glass custodian is available when the primary maintainer is unavailable? Until answered, no standing bypass is acceptable.
- Are GitHub's optional non-provider-pattern and validity-check features useful for the repository's actual credential formats? Enable supported checks after evaluating false positives; the core secret-scanning and push-protection requirements do not depend on them.

## Source Register

All sources were accessed or revalidated on 2026-11-26. Product capabilities and free-tier conditions can change; re-check them during implementation.

### GitHub repository and Actions controls

- [GitHub Actions secure use reference](https://docs.github.com/en/actions/reference/security/secure-use)
- [Managing GitHub Actions settings for a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository)
- [About repository rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
- [About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- [Troubleshooting required status checks](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks)
- [REST: get branch protection](https://docs.github.com/rest/branches/branch-protection#get-branch-protection)
- [REST: get a repository ruleset](https://docs.github.com/rest/repos/rules#get-a-repository-ruleset)
- [REST: get GitHub Actions permissions for a repository](https://docs.github.com/rest/actions/permissions#get-github-actions-permissions-for-a-repository)

### Secrets, dependencies, and vulnerability reporting

- [About secret scanning](https://docs.github.com/en/code-security/concepts/secret-security/about-secret-scanning)
- [Push Protection](https://docs.github.com/en/code-security/concepts/secret-security/push-protection)
- [About Dependabot alerts](https://docs.github.com/en/code-security/dependabot/dependabot-alerts/about-dependabot-alerts)
- [Configure Dependabot security updates](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/configure-security-updates)
- [Configure private vulnerability reporting](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository)
- [Add a security policy](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/add-security-policy)
- [Gitleaks](https://github.com/gitleaks/gitleaks)

### Account, token, and monitoring controls

- [About passkeys](https://docs.github.com/en/authentication/authenticating-with-a-passkey/about-passkeys)
- [Managing personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
- [About authentication to GitHub with GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/about-authentication-with-a-github-app)
- [OpenSSF Scorecard](https://github.com/ossf/scorecard)
- [OpenSSF Scorecard Action](https://github.com/ossf/scorecard-action)
- [OpenSSF Scorecard check documentation](https://github.com/ossf/scorecard/blob/main/docs/checks.md)

### Platform alternatives considered and deferred

- [Wiz pricing](https://www.wiz.io/pricing)
- [Aikido pricing](https://www.aikido.dev/pricing)
- [Socket pricing](https://socket.dev/pricing)
- [Prowler open-source cloud-security project](https://github.com/prowler-cloud/prowler)
