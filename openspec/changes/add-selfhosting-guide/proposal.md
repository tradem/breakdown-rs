<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# add-selfhosting-guide

> Implements issue #416 (docs-only).

## Why

`breakdown-rs` is AGPL-3.0, but the officially published Android binaries are
deliberately bound to the project-operated backend at build time: compile-time
`API_BASE`, pinned prod CA, baked `OIDC_ISS`/`OIDC_CLIENT_ID`/
`OIDC_REDIRECT_URI` (the audience is baked when configured and validated
by the backend at runtime, not at startup), fail-closed bootstrap (ADR-032,
spec `flutter-client-authz`, release decision D9). A self-hoster running
their own instance therefore cannot point the official APK at their
deployment — by design, not accident.

Self-hosting IS already possible at the **build level**: the app is
build-time configurable via `--dart-define` (API base, OIDC issuer/client
id/audience, inline pinned CA) plus an instance-owned pinned CA and
instance-owned IdP registration. What is missing is **documentation**, not
product code.

## What Changes

- New guide `frontend-flutter/docs/self-hosting.md`: "Hosting your own
  instance" — backend deployment prerequisites (backend ops docs; ADR-025
  HTTPS edge, own domain, own IdP — ADR-010 / ADR-018), building an
  instance-owned prod APK from source (`--flavor prod -t lib/main_prod.dart`
  + instance `--dart-define`s), instance pinned CA via the bundled
  `assets/certs/prod/ca.pem` asset or the inline `PINNED_CA_PEM` define
  (pinned-CA semantics per ADR-032 stay intact), `oidc-config.json` redirect
  URI handling and the `checkRedirectConsistency` fail-closed contract,
  instance-owned signing key (D9 scopes its one-key invariant to
  developer-published channels only), and a testing path without public
  infrastructure (dev flavor + LAN/tunnel).
- Short notes in the monorepo root `README.md` and
  `frontend-flutter/README.md` linking the guide.

## Non-goals

- No change to the app's runtime behavior: the published project APK stays
  single-backend; the dev-only `api_base_override` rule (spec
  `flutter-app-dialogs`) is untouched.
- No reproducible-build hardening — belongs to `add-fdroid-inclusion` (the
  guide links to it).
- No new locked decision: the guide documents existing locked decisions
  (ADR-010/018/025/032, D9) rather than introducing new ones. If
  implementation revealed a genuine architectural choice, an ADR would be
  raised — none did.

## Capabilities

### New Capabilities
- (none — documentation only)

### Modified Capabilities
- (none)

## Impact

- `frontend-flutter/docs/self-hosting.md` (new)
- `frontend-flutter/README.md` (link note)
- `README.md` (link note)
- No product code, no generated artifacts, no CI changes.
