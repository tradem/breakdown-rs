<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# 657 — Backend health-status 'online quality' pill at the top of the user drawer

## Why

Issue #657: the account drawer (#653) is the app's identity/status surface,
but it says nothing about backend health. A user looking at stale reads or a
failing command has no way to tell "device offline" (covered by the #654
offline pill) from "backend degraded/unhealthy". A color-coded, labeled
health pill at the top of the drawer gives an at-a-glance quality signal.

## What Changes

- **Health source (settled decision):** the pill polls the EXISTING public
  readiness surface `GET /v1/health` (token-free by design — a container
  probe must not need an OIDC token; aggregate `HealthStatus` =
  `Healthy`/`Degraded`/`Unhealthy`, HTTP 503 when unhealthy). The generated
  Dart client already ships `getHealth()`; NO backend change and NO
  OpenAPI-client regen. Probes ride `apiClientProvider` (pinned-CA Dio,
  follows the runtime base-URL override) with `validateStatus: (_) => true`
  so a 503 body still deserializes into a `HealthReport`.
- **Tiers (settled decision: 4, distinguish server-unhealthy):**
  `BackendHealthTier { healthy, degraded, unhealthy, offline }`:
  - `Healthy` report → healthy (green icon, `colorSemanticSuccess*` token)
  - `Degraded` report → degraded (amber, `colorSemanticWarning*` token)
  - `Unhealthy` report (HTTP 503) → unhealthy ("Backend gestört")
  - transport failure / timeout / unparsable answer → offline
    ("Backend nicht erreichbar") — deterministic mapping, never an
    `AsyncError` crash (no silent failure).
- **Polling (battery-friendly, mirrors #654):** first poll when the drawer
  opens (the drawer child builds lazily, so nothing polls before that);
  after a healthy answer the next poll waits a conservative 60 s interval;
  degraded/unhealthy/offline outcomes re-probe on exponential backoff
  (15 s base, ×2, capped at 10 min — same schedule shape as
  `connectivityProbeBackoff`). A generation counter cancels stale chains;
  while the passive connectivity signal reports offline, NO health probes
  run at all and the tier maps to offline directly (no request storms).
- **State (Riverpod, Decision D3):** keep-alive
  `BackendHealthController` exposing `BackendHealthTier?` (null = no data
  yet → the pill slot stays empty instead of flashing a wrong tier). Probe
  and delay seams are `@riverpod` providers so tests override them — no
  wall-clock sleeps (deterministic-tests hard rule).
- **UI:** `BackendHealthPill` at the TOP of the `AccountDrawer` children
  (above the identity header). Color coding rides the EXISTING DTCG
  semantic status tokens (`DesignTokens.colorSemanticSuccess/Warning/Error`
  Light/Dark by brightness) on a neutral `surfaceContainerHighest` container
  — no hardcoded colors, both M3 schemes readable, state never conveyed by
  color alone (icon + localized label always name the tier).
- **l10n:** `healthPillHealthy` / `healthPillDegraded` /
  `healthPillUnhealthy` / `healthPillOffline` added to `app_de.arb`
  (template) and `app_en.arb` with de/en key parity; `flutter gen-l10n`.

## Impact

- `pubspec.yaml`: version bump `0.4.0-alpha.24+75` → `0.4.0-alpha.25+76`
  (per-feature-PR bump convention).
- New: `lib/src/health/backend_health_providers.dart` (+ codegen
  `backend_health_providers.g.dart`), `lib/features/shell/backend_health_pill.dart`.
- Modified: `lib/features/shell/account_drawer.dart` (pill slot in the
  drawer header), `lib/l10n/app_{de,en}.arb` (+ generated l10n output).
- Tests: `test/unit/backend_health_providers_test.dart` (tier mapping,
  backoff schedule, controller state machine, connectivity pause),
  `test/features/shell/backend_health_pill_test.dart` (widget + golden per
  tier, German template locale, light and dark),
  `test/features/shell/profile_menu_test.dart` (health seams overridden;
  pill-visible assertion in the drawer).
- Follow-up (out of scope): `docs/design/screens/` drawer wireframe update
  and glossary rows — the #653 drawer spec still describes the replaced
  profile sheet; tracked separately.
