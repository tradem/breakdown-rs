<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Proposal: 419-dev-flavor-app-id-and-scheme — distinct dev application ID with a scoped redirect scheme

## Summary

Issue #419: a locally built dev-flavor release APK is debug-signed while the
published prod APK carries the project key, and both flavors deliberately
share ONE application ID (`rs.breakdown.frontend_flutter`) — so installing a
local `devRelease` over a published prod APK fails with a certificate-mismatch
error (and vice versa). The impact is developer-only friction, but the fix
that preserves every existing guarantee is cheap: give the dev flavor a
distinct application ID (`applicationIdSuffix = ".dev"`) AND a distinct,
deterministically derived redirect scheme (`breakdown://` →
`breakdown-dev://`), which removes BOTH the certificate clash and the
deep-link resolution ambiguity that originally motivated the
single-application-ID posture.

User decision (ask_user, 2026): **Option 2, variant 2b** — suffix the
application ID *and* scope the redirect scheme, instead of accepting an
app-chooser while both apps are installed (2a) or distributing keystore
material to dev machines (3, rejected: contradicts D9 custody).

## Context and constraints

- The single application ID existed to keep `breakdown://auth/callback`
  unambiguous: one registered handler for the scheme. Two co-installed
  variants sharing the scheme would make the IdP redirect resolve
  non-deterministically.
- The dev flavor is dev-runtime-only and never published (spec
  `flutter-release-artifacts`); the published chain (alpha → stable) is
  always `prodRelease` with the project key.
- `oidc-config.json` stays the single source for the redirect URI: BOTH the
  Gradle deep-link registration and the Dart side derive their per-flavor
  value from the same base URI deterministically — no new build input.
- `checkRedirectConsistency` (raw define ↔ bundled file) remains
  **unchanged**: derivation is deterministic, so raw agreement still implies
  derived agreement; the check keeps proving exactly what it proved before.
- The dev IdP (Logto dev instance) must allowlist the derived
  `breakdown-dev://auth/callback` — an ops note in
  `docs/self-hosting.md`, no code.

## Changes

1. **`android/app/build.gradle.kts`** — hoist the redirect-URI read /
   scheme validation / explicit `-PoidcRedirectScheme` check to the
   script top level (same semantics, evaluated once); dev flavor gets
   `applicationIdSuffix = ".dev"` and registers the derived
   `breakdown-dev://` scheme via the manifest placeholder; prod flavor
   keeps the base scheme. http/https schemes are exempt (App-Links-style
   URIs are not scheme-ambiguous and must not be mangled).
2. **`android/app/src/main/AndroidManifest.xml`** — intent-filter comment
   updated (per-flavor scheme, no more one-application-ID rationale).
3. **`lib/app_config.dart`** — new pure `deriveOidcRedirectUri(uri, flavor)`
   (Tier-1 testable, exact textual mirror of the Gradle derivation) and an
   `effectiveOidcRedirectUri` getter on `AppConfig`.
4. **`lib/auth/auth_providers.dart`** — `oidcClientConfig` and
   `authorizationUi` consume the *effective* (flavor-derived) redirect URI.
5. **`lib/app.dart`** — comment updates only (`applyApiBaseOverride`
   no longer cites the shared application ID as the reason prod clears a
   stored override; it stays as defense-in-depth).
6. **`oidc-config.json`** — `_note` mentions the per-flavor derivation.
7. **Docs** — `docs/release-process.md` (local dev builds coexist with
   published prod; certificate-mismatch note replaced), `docs/self-hosting.md`
   (register both schemes; the `-dev` derivation rule).
8. **Tests** — unit tests for the derivation (prod identity, dev derive,
   dev idempotence, empty/invalid unchanged, http/https exempt) +
   `authorizationUi`/`oidcClientConfig` consume the derived URI.

## Non-goals

- No change to the prod artifact chain, signing, or D9 custody.
- No change to `checkRedirectConsistency` logic or error copy.
- Existing dev installs (same application ID, debug-signed) will NOT
  update in place into the new `rs.breakdown.frontend_flutter.dev` — one
  manual uninstall of the old dev build is documented.

## Acceptance criteria (from issue #419 options)

- [x] Evaluate the three options with the user; choose deliberately. (2b)
- [x] Local dev-flavor installs coexist with published prod installs
      (no certificate-mismatch uninstall dance).
- [x] The browser redirect resolves to exactly one installed app, always.
- [x] `oidc-config.json` remains the single redirect source; the
      Gradle↔Dart fail-closed consistency posture is unchanged.
- [x] D9 untouched: signing material never leaves CI.
