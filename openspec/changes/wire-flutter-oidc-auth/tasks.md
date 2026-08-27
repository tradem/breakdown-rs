<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

## 1. OIDC client
- [ ] 1.1 PKCE flow against Logto dev (`http://localhost:3301`) / prod IdP
- [ ] 1.2 Consume ADR-010/018 contract (`iss`, `aud`, JWKS)
- [ ] 1.3 Token refresh (online-first; no offline queue)

## 2. Secure storage
- [ ] 2.1 `flutter_secure_storage` for access/refresh/id tokens
- [ ] 2.2 No plaintext preferences anywhere; gitleaks + manual review

## 3. Membership provider
- [ ] 3.1 `currentMembershipProvider` exposing membership/role state
- [ ] 3.2 Documented `// AUTHZ-GATE:` convention + grep verification helper

## 4. Cert pinning
- [ ] 4.1 Pinned-CA `HttpClient`/`dio` per flavor from `--dart-define`
- [ ] 4.2 No disable-verification switch in any code path
- [ ] 4.3 Dev flavor pins the dev CA set (incl. Logto dev cert)

## 5. Dev auth parity
- [ ] 5.1 `DEV_AUTH_SUB` → permissive membership locally; impossible in
       `prod` flavor (build-time guard)

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
