<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

# Proposal: Wire Flutter OIDC Auth & Client AUTHZ-GATE

## Why
Foundation `flutter-client-authz` mandates OIDC PKCE tokens in
`flutter_secure_storage`, a `currentMembershipProvider` for client-side
role checks, and per-flavor cert pinning matching the backend's pinned-CA
stance (ADR-024). This change implements it so gated photo/continuity
handlers can be called safely.

## What changes
- OIDC PKCE client against Logto dev / prod IdP, consuming the backend's
  ADR-010 / ADR-018 contract. The dev endpoint must be Android-reachable —
  resolve the HTTPS-with-dev-CA vs port-forwarded-HTTP-exception transport
  during this change's design phase (see tracking issue).
- `flutter_secure_storage` for access/refresh/id tokens (never plaintext).
- `currentMembershipProvider` exposing membership/role state for
  AUTHZ-GATE checks.
- Cert pinning: pinned-CA `HttpClient`/`dio` per flavor from
  `--dart-define`.
- Dev auth mode parity with backend (`DEV_AUTH_SUB`): permissive **only**
  when `OIDC_ISS` is absent AND `DEV_AUTH_SUB` is set (the exact backend
  predicate); impossible in `prod` flavor.
- `// AUTHZ-GATE:` comment convention + grep verification documented.

## Dependencies
- **Depends on:** `scaffold-flutter-project`.
- **Unblocks:** `add-gherkin-critical-scenarios` (capture `.feature` needs
  auth), `first-screen-seasons` (gated writes).

## Non-goals
- No backend auth changes.
- No full offline token refresh with queueing (online-first; see
  `flutter-offline-scope`).
