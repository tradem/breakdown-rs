<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

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
