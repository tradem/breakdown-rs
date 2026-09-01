<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

# Proposal: Replace the Flutter dev CA placeholder with the real dev CA

## Why
The Flutter dev flavor pins `assets/certs/dev/ca.pem` as its exclusive
TLS trust anchor (AGENTS.md §5 / ADR-024, D4 — fail-closed, no system
roots). That file is the scaffold's placeholder (`CN=breakdown-dev-ca`, a
self-signed cert with no `O=Breakdown RS` and no leaf chain to the real
dev services). Meanwhile issue #311 (now closed) made the backend dev
setup generate a real dev CA at `backend/dev-certs/ca.pem` that signs
both the dev IdP (Logto HTTPS on `:3301`) and the API HTTPS on `:3000`,
with leaf SANs for `localhost` and `10.0.2.2` (Android emulator loopback).

Until the placeholder is swapped for the real dev CA, the pinned dev
client cannot actually establish HTTPS to the dev IdP/API, and the only
workable dev transport is the documented D1 exception
(`--dart-define=DEV_IDP_INSECURE=1`, dev-flavor-only). Closing this gap
makes the D1 primary (HTTPS + dev CA) the real dev default.

## What changes
- Copy `backend/dev-certs/ca.pem` (the real dev CA from
  `backend/scripts/generate-dev-certs.sh`) over
  `frontend-flutter/assets/certs/dev/ca.pem`.
- Leave `frontend-flutter/assets/certs/prod/ca.pem` as its own separate
  placeholder — the prod flavor keeps its distinct pinned CA; the dev CA
  must never be promoted into the prod asset.
- Add a focused unit test (`test/network/dev_ca_asset_test.dart`) asserting
  the dev asset is a valid, parseable pinned CA, the prod asset remains a
  distinct valid CA, and dev is not byte-identical to prod.

## Dependencies
- **Depends on:** issue #311 (backend dev CA generation) — the source
  `backend/dev-certs/ca.pem` now exists via
  `backend/scripts/generate-dev-certs.sh`.
- **Unblocks:** the D1 primary dev transport (HTTPS + dev CA) becoming the
  default dev path; removes the need for the `DEV_IDP_INSECURE` exception
  in ordinary local dev.

## Non-goals
- No backend cert regeneration is part of this change (the backend script
  owns `backend/dev-certs/`; those artifacts are gitignored dev secrets).
- No prod CA generation or promotion; prod stays a separate placeholder.
- No API-shape, pinning-logic, or `api_client.dart` changes — only the
  dev asset bytes and a regression test.
