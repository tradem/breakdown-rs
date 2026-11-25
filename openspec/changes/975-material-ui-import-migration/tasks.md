<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — 975 material_ui import migration

## 1. Evidence (before)

- [x] 1.1 `flutter analyze --no-fatal-infos` on the pinned 3.50.1 → **196**
      hints, all `deprecated_member_use`: 194 `package:flutter/material.dart`
      imports + the two `GlobalMaterialLocalizations` /
      `GlobalCupertinoLocalizations` uses in the generated l10n delegate list.
- [x] 1.2 Import inventory (`lib/`, `test/`, `integration_test/`): material 194,
      foundation 39, services 14, widgets 4, semantics 1, scheduler 1 — only
      the Material (and the unused Cupertino) entry point is deprecated.

## 2. Migration

- [x] 2.1 `material_ui: ^1.11.1` declared as a direct dependency (the lock only
      flips `transitive` → `"direct main"`).
- [x] 2.2 194 `package:flutter/material.dart` imports swapped to
      `package:material_ui/material_ui.dart` (110 `lib/`, 73 `test/`,
      11 `integration_test/`). Foundation/services/widgets/semantics/scheduler
      imports left untouched.
- [x] 2.3 `lib/l10n/app_localizations_delegates.dart` added; the 31
      `AppLocalizations.localizationsDelegates` call sites (app + tests) use it.
      Required, not cosmetic: the generated list names the *deprecated* legacy
      delegates, which satisfy a different `MaterialLocalizations` type and made
      every German widget test fall back to English.
- [x] 2.4 `lib/design/components/legacy_material_subtree.dart` added and wired
      around `flutter_code_editor`'s `CodeField` in
      `lib/design/components/xml_prompt_editor.dart` (legacy `Material` ancestor
      + bridged theme/localizations). Sole remaining legacy-material importer.

## 3. Generated artifacts

- [x] 3.1 `flutter gen-l10n` → **no diff** (`lib/l10n/generated/` untouched,
      drift gate clean).
- [x] 3.2 No `build_runner` output affected (no annotation/drift change).
- [x] 3.3 `vendor/breakdown_api/` untouched (`backend/openapi.yaml` unchanged).

## 4. Goldens

- [x] 4.1 `scene_shoots_board_{light,dark}_{android,macos}.png` regenerated:
      3 hairlines per image (disabled `DropdownButtonFormField` underline now
      receives the disabled state from `material_ui`'s widget).
- [x] 4.2 `settings_ai_config_checking_{light,dark}.png` regenerated: the
      harness pumps one deterministic 200 ms step past Material 3's 450 ms page
      transition; only the spinner box changes.
- [x] 4.3 `easter_eggs_{light,dark}.png` regenerated: same transition step, only
      the walking cat's phase changes.
- [x] 4.4 Every diff measured (bbox + pixel count) and recorded in the proposal;
      no other golden moved.

## 5. Validation

- [x] 5.1 `dart format --set-exit-if-changed lib test integration_test` → clean.
- [x] 5.2 `flutter analyze --no-fatal-infos` → **2** hints (both in generated
      `lib/l10n/generated/app_localizations.dart`, generator-owned; see the
      proposal's "Residual" section).
- [x] 5.3 `flutter test` → 2547 tests, 0 failures (baseline on `main`: 2549
      tests, 0 failures).
- [x] 5.4 `tool/breakdown_lints_runner` → no violations.
- [x] 5.5 `scripts/add-spdx-headers.sh --check` → clean for every touched file.

## 6. Follow-ups

- [ ] 6.1 File the upstream follow-up: drop the last 2 hints once
      `flutter gen-l10n` emits the `material_ui` delegates (its template
      hardcodes `flutter_localizations`).
- [ ] 6.2 Drop `lib/design/components/legacy_material_subtree.dart` (and its two
      `// ignore:` markers) when `flutter_code_editor` ships a
      `material_ui`-based release; latest published is still 0.3.5 and still
      imports `package:flutter/material.dart`.
