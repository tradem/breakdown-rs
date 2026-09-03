---
description: Root-level dev scripts and env files - pointer to the local dev runtime documentation.
applyTo:
  - "scripts/**"
  - ".env*"
---

# Root-level local dev assets

The repository root hosts dev-adjacent assets: `scripts/seed-logto-dev.sh`
(local IdP seeding for OIDC development), `scripts/add-spdx-headers.sh`
(SPX header tooling), `create_issues.sh`, and `.env.idp.example` (template
for the IdP overlay environment).

The full local dev runtime documentation (compose stack, boot sequence,
OIDC/dev-auth mode, IdP overlay, cert wiring) lives in
`backend/.github/instructions/local-dev-runtime.instructions.md` — read it
when working on these assets.
