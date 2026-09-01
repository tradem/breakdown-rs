<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

## 1. Source the real dev CA
- [x] 1.1 Run `backend/scripts/generate-dev-certs.sh` so `backend/dev-certs/ca.pem`
       (the real dev CA that signs the IdP `:3301` and API `:3000` leaf certs)
       exists
- [x] 1.2 Verify the dev CA signs BOTH dev leaves — the IdP leaf
       (`openssl verify -CAfile backend/dev-certs/ca.pem
       backend/dev-certs/idp.pem` → OK) AND the API leaf
       (`openssl verify -CAfile backend/dev-certs/ca.pem
       backend/dev-certs/api.pem` → OK) — and both leaves carry SAN
       `localhost` + `10.0.2.2` (trusts `https://localhost:3301` /
       `https://10.0.2.2:3301` for IdP and `https://localhost:3000` /
       `https://10.0.2.2:3000` for the API)

## 2. Replace the Flutter dev placeholder
- [x] 2.1 Copy `backend/dev-certs/ca.pem` → `frontend-flutter/assets/certs/dev/ca.pem`
       (overwriting the scaffold placeholder)
- [x] 2.2 Confirm `frontend-flutter/assets/certs/prod/ca.pem` is unchanged and
       distinct (dev is NOT the prod placeholder — tracked separately)

## 3. Regression test
- [x] 3.1 Add `test/network/dev_ca_asset_test.dart`: dev asset parses as a
       pinned `SecurityContext`, prod asset parses as a distinct pinned
       `SecurityContext`, and dev bytes ≠ prod bytes
- [x] 3.2 `flutter test test/network/` passes (10/10, incl. the 3 new cases)

## 4. Verification
- [x] 4.1 `dart format --set-exit-if-changed .` clean
- [x] 4.2 `flutter analyze` clean
- [x] 4.3 `openssl` chain + SAN proof recorded in the PR body
