<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# flutter-release-artifacts Delta (issue #419 — dev flavor coexistence)

## ADDED Requirements

### Requirement: Dev Flavor Coexistence with Published Prod Installs
The `dev` and `prod` Gradle flavors SHALL ship DISTINCT Android
application IDs (`applicationIdSuffix = ".dev"` on the dev flavor) AND
distinct OIDC redirect schemes — the dev scheme is derived
deterministically from the base scheme carried by `oidc-config.json` by
appending `-dev` to a custom scheme (`breakdown://` →
`breakdown-dev://`; http/https schemes are exempt; scheme-less values
pass through unchanged and fail closed elsewhere). The base scheme SHALL
be a lowercase RFC-style scheme and MUST NOT end in the reserved `-dev`
suffix: a base scheme ending in `-dev` would make BOTH flavors register
the same scheme (breaking the exactly-one-app redirect guarantee) and is
rejected at build time by the Gradle validation. The derivation SHALL
exist in exactly two textually-mirrored places: the Gradle manifest
registration and the Dart-side `deriveOidcRedirectUri`. This allows a
locally built dev install (debug-signed) to coexist with a published
prod install (project-key signed) — no certificate-mismatch uninstall —
while the browser OAuth redirect always resolves to exactly ONE
installed app. The dev IdP client registration MUST allowlist the
derived dev URI (`docs/self-hosting.md` §4). The prod application ID,
prod redirect scheme, and D9 signing posture are unchanged by this
requirement.

#### Scenario: Local dev install over a published prod install
- **WHEN** a tester has a published `prodRelease` APK installed and
  installs a locally built `devRelease`.
- **THEN** both apps coexist (distinct application IDs) and the OAuth
  redirect resolves to the dev install's scoped scheme
  (`breakdown-dev://auth/callback`), never ambiguously.

#### Scenario: Prod artifacts unchanged
- **WHEN** the release workflow builds `--flavor prod`.
- **THEN** the application ID is `rs.breakdown.frontend_flutter` and the
  redirect scheme is the base scheme from `oidc-config.json` — identical
  to prior releases, so published builds still update in place.
