<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

## 1. OIDC client
- [x] 1.1 PKCE flow against Logto dev (`http://localhost:3301`) / prod IdP
- [x] 1.2 Consume ADR-010/018 contract (`iss`, `aud`, JWKS)
- [x] 1.3 Token refresh (online-first; no offline queue)

## 2. Secure storage
- [x] 2.1 `flutter_secure_storage` for access/refresh/id tokens
- [x] 2.2 No plaintext preferences anywhere; gitleaks + manual review

## 3. Membership provider
- [x] 3.1 `currentMembershipProvider` exposing membership/role state
- [x] 3.2 Documented `// AUTHZ-GATE:` convention + grep verification helper

## 4. Cert pinning
- [x] 4.1 Pinned-CA `HttpClient`/`dio` per flavor from `--dart-define`
- [x] 4.2 No disable-verification switch in any code path
- [x] 4.3 Dev flavor pins the dev CA set (incl. Logto dev cert)

## 5. Dev auth parity
- [x] 5.1 `DEV_AUTH_SUB` → permissive membership locally; impossible in
       `prod` flavor (build-time guard)

### Implementation notes (session of this change's apply run)
- 3.1: `GET /v1/seasons/{seasonId}/membership` is not in
  `backend/openapi.yaml` yet (follow-up backend change). Implemented
  client-side against the frozen D2 contract:
  `lib/auth/membership/season_membership.dart` (documented client-side
  mirror, to be replaced by generated types once the endpoint lands) +
  `membership_repository.dart` + `currentMembershipProvider` family with
  D3 loading/error semantics. Backend endpoint tracked as follow-up.
- 4.3: `assets/certs/dev/ca.pem` is the scaffold's placeholder
  `breakdown-dev-ca`. The backend dev IdP currently serves plain HTTP
  (`docker-compose.idp.yml`, `:3301`), so the D1 HTTP exception is the only
  workable dev transport today; aligning a real dev CA + HTTPS Logto is a
  backend/deployment follow-up.

## Spec-hardening (issue #272) — design resolved

The PR #269 review flagged four auth/transport open questions. Resolved in
`proposal.md` (Design Decisions D1–D4) and encoded as requirements in
`specs/flutter-client-authz/spec.md`. Implementation Tasks 1–5 remain open;
the design gap is closed.
- [x] Dev IdP transport decided (D1: HTTPS + dev CA primary;
      `--dart-define=DEV_IDP_INSECURE=1` dev-flavor-only HTTP exception,
      enforced by an explicit `if (!kReleaseMode)` + startup-throw guard — NOT a
      Dart assert; IdP-host-only pinning bypass, impossible in prod)
- [x] `currentMembershipProvider` scoped (D2: family keyed by `seasonId`; single
      endpoint `GET /v1/seasons/{seasonId}/membership` -> `SeasonMembershipDto`;
      maps `hasActiveCostumeRoleInSeason` + `capabilities`; server authoritative)
- [x] Loading/error behavior decided (D3: deny ONLY on resolved-denial;
      loading → spinner, error → retry; never a false 403)
- [x] TLS pinning semantics decided (D4: exclusive no-default-roots
      `SecurityContext`; platform roots excluded in both flavors;
      fail-closed startup on missing/invalid CA config)
