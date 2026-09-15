<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Tasks: add-selfhosting-guide

## 1. Guide

- [x] 1.1 Write `frontend-flutter/docs/self-hosting.md` covering:
  backend deployment prerequisites (ADR-025 edge, own domain, own IdP —
  ADR-010 / ADR-018; backend ops runbooks), building an instance-owned prod
  APK (`--flavor prod -t lib/main_prod.dart` + `API_BASE`, `OIDC_ISS`,
  `OIDC_CLIENT_ID`, `OIDC_AUDIENCE` defines), instance pinned CA
  (`assets/certs/prod/ca.pem` replacement or `PINNED_CA_PEM` inline define;
  pinned-ROOT semantics per ADR-032 stay intact), `oidc-config.json`
  redirect URI + `checkRedirectConsistency` fail-closed contract,
  instance-owned signing key (D9 scoping note), and the dev-flavor testing
  path without public infrastructure (LAN/tunnel, dev auth mode,
  `api_base_override` dev-only rule).

## 2. Link notes

- [x] 2.1 Add a short "Self-hosting" note to the monorepo root `README.md`
  linking the guide.
- [x] 2.2 Replace the template stub in `frontend-flutter/README.md` with a
  short project note linking the guide and the release docs.

## 3. Validation

- [x] 3.1 Verify every technical claim against the code (bootstrap guards,
  `loadPinnedSecurityContext`, `checkRedirectConsistency`, Gradle signing
  config, `build-release.sh`) and every referenced ADR/spec path exists.
- [x] 3.2 Markdown link check (relative paths resolve); gitleaks clean (no
  secrets in the guide); SPDX headers present on all touched files.
