<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Tasks: 374-explicit-null-unschedule

## 1. Repository (raw explicit-null PATCH)

- [ ] 1.1 Add `unschedule(id, version:)` + `renameToNull(id, version:)` and a
      shared `_patchExplicitNull` raw-Dio helper in
      `lib/data/shooting_day_repository.dart`
- [ ] 1.2 Delete `buildUnscheduleRequest`; require non-null `label` on
      `buildRenameRequest`

## 2. Controller routing

- [ ] 2.1 Generalize `_singleIntent` to closure-based `_intent(day, send)`
- [ ] 2.2 Route `unschedule` and `rename(label: null)` to the raw paths

## 3. Tests

- [ ] 3.1 Tier-1 unit: `test/unit/shooting_day_explicit_null_test.dart`
      (literal null on the wire, Ok + Err branches)
- [ ] 3.2 Tier-2 flows: fake overrides + unschedule confirm / empty-rename
      routing tests

## 4. Validation

- [ ] 4.1 `dart format --set-exit-if-changed .` clean
- [ ] 4.2 `flutter analyze` clean
- [ ] 4.3 `flutter test` green
- [ ] 4.4 No hand edits to `vendor/breakdown_api/` (openapi.yaml unchanged)
