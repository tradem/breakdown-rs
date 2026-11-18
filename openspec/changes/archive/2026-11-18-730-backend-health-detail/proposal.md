<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 730 — Tappable backend health pill + per-dependency health detail sheet

## Why

Issue #730: the account drawer's backend health pill (#657) names a tier
but cannot be tapped, so a user who sees "Backend gestört" has no way to
find out **which** dependency the backend reports as broken. The #657
proposal deferred exactly this ("the pill only scopes the coarse tier"),
and the reporting beta tester hit the case it was deferred for: a dev
stack with AI import enabled but the Garage overlay not booted flips the
aggregate report to `Unhealthy` while the rest of the app works.

The per-check evidence is **already on the wire**: `GET /v1/health`
returns `HealthReport.entries` — one `HealthEntry` (status, duration,
tags, static sanitized description) per registered check (`postgres`,
`sierradb`, `vault`, and `garage` when `AI_IMPORT_ENABLED=true`). The
client's probe simply dropped the map.

## What Changes

- **Pill becomes the tap target (whole pill):** `BackendHealthPill` is
  wrapped in a `Material` + `InkWell` (ink response = the visible cue) and
  its semantics node gains `button: true`, a localized open hint and the
  tap action (the `excludeSemantics` pattern from #662 drops the ink
  well's own action, so the wrapper must carry it). No chevron is added —
  the compact #657 chip keeps its shape and the existing pill/drawer
  goldens stay byte-identical.
- **Detail surface (settled decision: modal bottom sheet over the OPEN
  drawer):** tapping the pill opens
  `showBackendHealthDetailSheet` (`showModalBottomSheet`,
  `useRootNavigator: true`). The drawer deliberately stays open: it is the
  autoDispose health controller's only keeping-alive listener (#657
  battery rule), so popping it first would stop the poll loop and blank
  the data. Dismissing the sheet returns to the open drawer; the pill
  keeps polling underneath, so the sheet stays live. A full-screen route
  and an inline drawer expansion were considered and rejected (lifecycle
  loss / drawer crowding).
- **Probe carries the per-check breakdown:** `BackendHealthReported` gains
  a `checks` list, `backendHealthChecksFromEntries` maps the wire
  `entries` map onto a client-side `BackendHealthCheck {name, status}`
  model (own enum — the widget layer never imports `package:breakdown_api`),
  and the controller state becomes `BackendHealthSnapshot {tier, checks}`
  (one value object instead of a second provider: one probe, one schedule).
  Offline (transport failure **or** passive connectivity) publishes an
  EMPTY check list — nothing was measured, stale rows are never presented
  as current.
- **Localized copy only (settled decision):** the backend's static English
  `description` is deliberately **not** rendered. The sheet shows
  functional, topology-free German labels per known check key
  (`Datenbank`, `Ereignisspeicher`, `Geheimnisverwaltung`,
  `KI-Dateispeicher`), a generic fallback label for unknown keys
  (`Weitere Abhängigkeit` — a raw key is never printed), and localized
  status words (`bereit` / `eingeschränkt` / `gestört`) with the DTCG
  status-token icons. Color is never the sole carrier.
- **Ordering:** broken dependencies first, then degraded, then healthy;
  wire order is kept inside a bucket (three explicit passes, not
  `List.sort`, which is unstable).
- **Shared presentation:** the tier → (icon, label, color) mapping moves
  into `backend_health_presentation.dart` so the pill and the sheet's
  aggregate row cannot tell different stories.

## Impact

- **Specs:** `flutter-backend-health` (new capability: the pill contract
  incl. its tap target, and the detail sheet contract). Design docs:
  `docs/design/screens/backend-health-detail.md` (new screen spec +
  Salt wireframe) and glossary rows/copy keys
  (`health.pill.*`, `health.detail.*`, `health.check.*`).
- **Code:** `lib/src/health/backend_health_providers.dart` (snapshot model,
  per-check mapping, severity ordering, probe + controller state),
  `lib/features/shell/backend_health_pill.dart` (tappable),
  `lib/features/shell/backend_health_presentation.dart` (new),
  `lib/features/shell/backend_health_detail_sheet.dart` (new),
  `lib/features/shell/account_drawer.dart` (comment only).
- **l10n:** 14 new ARB keys (`healthPillOpenHint`, `healthDetail*`,
  `healthCheck*`), de template + en in parity; generated output
  regenerated; existing `healthPill*` keys reused unchanged.
- **API contract:** none — `backend/openapi.yaml` untouched, no client
  regen (`HealthReport`/`HealthEntry` already shipped; the client only
  started reading `entries`).
- **Tests:** `test/unit/backend_health_providers_test.dart` (snapshot
  reads + new per-check group), `test/features/shell/backend_health_pill_test.dart`
  (snapshot override, icon key, BUTTON role/hint/tap-action, tap → sheet),
  `test/features/shell/backend_health_detail_sheet_test.dart` (new),
  `profile_menu_test.dart` / `app_shell_test.dart` overrides updated.
  Goldens: 4 new sheet goldens; the pill/drawer goldens are unchanged.
