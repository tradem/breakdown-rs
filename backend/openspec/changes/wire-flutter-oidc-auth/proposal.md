<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

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

## Design Decisions (resolved during spec-hardening, issue #272)
The PR #269 review flagged four auth/transport open questions. Resolved here;
encoded as requirements in `specs/flutter-client-authz/spec.md`.

### D1. Android-reachable dev IdP transport (HTTPS + dev CA, documented
exception)
- **Primary**: the dev IdP (Logto) is served over **HTTPS** using the
  **dev-pinned CA set** — the same dev CA that signs the backend API cert on
  `:3000`. The Flutter **dev** flavor pins that dev CA for both API and IdP
  hosts. On the Android emulator the IdP is reachable at
  `https://10.0.2.2:3301` (emulator loopback). This keeps pinning consistent
  and avoids any unpinned transport.
- **Documented exception**: if a contributor must use an HTTP port-forward
  (e.g. `http://localhost:3301`) that cannot be HTTPS-pinned in their
  environment, this is a **dev-flavor-only** exception gated by an explicit
  `--dart-define=DEV_IDP_INSECURE=1`. It is HARD-disabled in `prod` (the
  flavor config omits the flag and the code asserts `kReleaseMode ||
  !devInsecure`), and the pinning layer is bypassed **only for the IdP host**
  under that flag. This is the lone documented exception to pinning; it is
  never available in prod builds.

### D2. `currentMembershipProvider` scope + role mapping
- `currentMembershipProvider` becomes a **family** keyed by `seasonId` (and
  possibly `seriesId`): `currentMembershipProvider(SeasonId id)`. It reads
  the backend membership/role read-model for the active season (a
  `GET /v1/seasons/{id}/membership` projection DTO, or folded into a whoami
  projection) — the client never reconstructs roles from other projections
  (CQRS-boundary rule).
- The DTO exposes backend-computed booleans. The "active continuity role" is
  mapped from `has_active_costume_role_in_season(season_id, sub)` (the
  backend's authorization predicate) surfaced as a field on the membership
  DTO (e.g. `canUploadContinuityPhotos`, `canAssignCostumes`). The client
  derives a local capability enum from these booleans; it does NOT
  re-implement the predicate.
- **Server remains authoritative**: the client check is a gate (UX +
  defense-in-depth), never authorization. The backend re-checks on every
  gated handler (AUTHZ-GATE). A client "allow" never substitutes for server
  enforcement.

### D3. Loading/error behavior (deny only on resolved-denial)
- `currentMembershipProvider` is `AsyncValue<Membership>`.
  - **Loading** (`valueOrNull == null` and not error): the gated action is
    **disabled with a spinner**, NOT denied. No 403 shown.
  - **Error**: the gated action is **disabled with a retry affordance**; the
    error is shown but the user is NOT told "forbidden" (that would be a
    false denial). A retry triggers
    `ref.refresh(currentMembershipProvider(seasonId))`.
  - **Resolved denial** (value present, capability `false`): show localized
    403 narrative, never issue the request.
- This refines the existing "User lacks upload role" scenario: denial is a
  *resolved* state, distinct from loading/error.

### D4. Exclusive, fail-closed TLS pinning
- Pinning is **exclusive**: the `SecurityContext` is constructed with **no
  default trust roots**; only the per-flavor pinned CA PEM(s) from
  `--dart-define` are added. Platform/OS trust store is **excluded in both
  flavors** (not just prod) — dev adds the dev CA, prod adds the prod CA,
  neither falls back to system roots.
- **Fail-closed at startup**: if the required `--dart-define` CA list is
  missing/empty or fails to parse as valid PEM, the `HttpClient`/`dio`
  construction throws at the composition root (`lib/main.dart`) -> the app
  aborts startup and shows a fatal "TLS configuration invalid" screen (no
  network calls are ever made with an unpinned context). This is caught in
  `main()` before `runApp`.
- "Adding CAs to the default trust store" is explicitly NOT pinning and is
  rejected; we use a clean `SecurityContext()` with only pinned certs. The
  dev IdP insecure fallback (D1) is the only place verification is relaxed,
  and only for the IdP host under the dev flag.
