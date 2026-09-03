---
description: GitHub Actions workflow hardening - SHA pinning, Dependabot bumps, script-injection hygiene.
applyTo:
  - ".github/workflows/**"
  - ".github/dependabot.yml"
---

# CI hardening: SHA-pinning and script-injection hygiene

All GitHub Actions workflows must follow these rules:

- **SHA-pin third-party actions.** Never use a moving tag (`@v7`, `@v2`, `@stable`)
  directly. Always pin to a 40-character commit SHA with a trailing `# v7` comment for
  readability. Dependabot (configured in `.github/dependabot.yml`) opens weekly PRs to
  bump SHAs automatically.
- **Script-injection avoidance.** Never interpolate `${{ github.event.* }}` or other
  expression values directly into a `run:` shell command. Pass them through `env:`
  injection instead (GitHub docs: *Security hardening for GitHub Actions*).

Guardrail ast-grep-rule detail: `backend/.github/instructions/ci-hardening.instructions.md` (fires on reads under `backend/rules/`, `backend/rules-tests/`, `backend/scripts/`).
