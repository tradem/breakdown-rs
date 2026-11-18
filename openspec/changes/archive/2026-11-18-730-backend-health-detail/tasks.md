<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 730 — Tasks

## 1. Probe carries the per-check breakdown

- [x] 1.1 `lib/src/health/backend_health_providers.dart`: add
      `BackendHealthCheck {name, status}` (client-side
      `BackendHealthCheckStatus`, no `breakdown_api` import in the widget
      layer) and `BackendHealthSnapshot {tier, checks}`;
      `BackendHealthReported` gains `checks`.
- [x] 1.2 `backendHealthChecksFromEntries(BuiltMap<String, HealthEntry>)`
      maps the wire `entries` (wire status → client status; the sanitized
      `description` is dropped on purpose) and
      `backendHealthChecksBySeverity` orders broken → degraded → healthy
      with wire order inside a bucket.
- [x] 1.3 Controller state becomes `BackendHealthSnapshot?`; the offline
      tier (transport **or** connectivity) publishes an EMPTY check list
      so stale dependency rows are never shown as current.

## 2. Tappable pill + detail sheet

- [x] 2.1 `lib/features/shell/backend_health_presentation.dart` (new):
      tier → (icon, label, color) and check → label/status/icon/color,
      all on the DTCG semantic status tokens.
- [x] 2.2 `lib/features/shell/backend_health_pill.dart`: whole pill is the
      tap target (`Material` + `InkWell`), semantics gain BUTTON role +
      `healthPillOpenHint` + the tap action; the label is `Flexible` so
      "Backend nicht erreichbar" cannot overflow a narrow drawer.
- [x] 2.3 `lib/features/shell/backend_health_detail_sheet.dart` (new):
      `showBackendHealthDetailSheet` (modal sheet, root navigator, drawer
      stays open) rendering the aggregate row, the severity-ordered
      dependency rows, and the pending/offline/no-entries bodies.

## 3. l10n

- [x] 3.1 Add 14 ARB keys (`healthPillOpenHint`, `healthDetailTitle`,
      `healthDetailDependencies`, `healthDetailNoDependencies`,
      `healthDetailOfflineBody`, `healthDetailPending`,
      `healthCheckDatabase|EventStore|Secrets|AiStorage|Other`,
      `healthCheckStatusHealthy|Degraded|Unhealthy`) to the German
      template and the English catalog in parity; run `flutter gen-l10n`
      (no untranslated keys).

## 4. Tests

- [x] 4.1 `test/unit/backend_health_providers_test.dart`: snapshot reads
      (`?.tier`), wire→check mapping, empty entries, severity ordering,
      reported checks reaching the state, unreachable/connectivity-offline
      dropping stale checks.
- [x] 4.2 `test/features/shell/backend_health_pill_test.dart`: snapshot
      override, icon found by key, BUTTON role/hint/tap-action assertions,
      tap opens the sheet (drawer content stays mounted), goldens
      regenerated — byte-identical to the #657 set.
- [x] 4.3 `test/features/shell/backend_health_detail_sheet_test.dart`
      (new): aggregate row, dependency labels + status words, no raw wire
      keys, ordering, merged announcements, unknown-key fallback,
      offline/empty/pending bodies, close affordance, 4 goldens
      (de, light + dark).
- [x] 4.4 `profile_menu_test.dart` / `app_shell_test.dart`: controller
      overrides use `BackendHealthSnapshot`.

## 5. Docs

- [x] 5.1 `docs/design/screens/backend-health-detail.md` (new screen spec
      + PlantUML Salt wireframe, validated by
      `scripts/check-design-diagrams.sh`).
- [x] 5.2 `docs/design/glossary.md`: pill + detail rows (icons, labels,
      logical copy keys) and the `Backend health` ARB inventory row
      (verified by `tool/check_glossary_catalog.py`).

## 6. Validation

- [x] 6.1 `dart format --set-exit-if-changed .`, `flutter analyze`,
      `flutter test`, `dart run build_runner build
      --delete-conflicting-outputs` (Riverpod provider regenerated).
- [x] 6.2 `pubspec.yaml` version bump (`0.4.0-beta.11+103` →
      `0.4.0-beta.12+104`).
