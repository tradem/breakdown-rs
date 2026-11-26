<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 975 — Migrate the client off the deprecated `package:flutter/material.dart`

## Why

Flutter 3.50.1 (pinned since #966) deprecates the SDK's Material entry point in
favour of the `material_ui` package:

```dart
@Deprecated('Use package:material_ui/material_ui.dart instead. '
    'This feature was deprecated after v3.47.0-0.0.pre.')
library material;
```

`flutter analyze --no-fatal-infos` reported **196 `deprecated_member_use`
hints** on the pinned toolchain (0 on 3.47.6), so the CI gate stayed green while
the whole app sat on a deprecated entry point. Doing nothing is a time bomb: the
day the SDK deletes `flutter/material.dart`, ~194 files break at once. Replacing
"on touch" does not converge at that size, so it has to be one deliberate
change (this one).

Baseline, measured on this branch before the migration (`analyze --no-fatal-infos`):

| Hint | Count |
|---|---|
| `'package:flutter/material.dart' is deprecated …` (one per import) | 194 |
| `'GlobalMaterialLocalizations' is deprecated …` (gen-l10n delegate list) | 1 |
| `'GlobalCupertinoLocalizations' is deprecated …` (same list) | 1 |
| **Total** | **196** |

## What changes

- **`material_ui: ^1.11.1` becomes a direct dependency** (it was already in
  `pubspec.lock` as a transitive dependency, so the lock diff is one
  `dependency:` line).
- **194 imports** in `lib/**` (110), `test/**` (73) and `integration_test/**`
  (11) move from `package:flutter/material.dart` to
  `package:material_ui/material_ui.dart`. Nothing else in those lines changes.
- **`lib/l10n/app_localizations_delegates.dart` (new)** replaces the generated
  `AppLocalizations.localizationsDelegates` at all 31 call sites. This is not
  cosmetic — see "The two real breakages" below.
- **`lib/design/components/legacy_material_subtree.dart` (new)** hosts the one
  remaining legacy-material import, wrapping the `flutter_code_editor` body of
  the XML prompt editor.
- **Six goldens** are regenerated (4 scene-shoots board, 2 AI-config
  "checking"), each with a measured, documented reason (see below).

## What does NOT change

The issue's fourth acceptance criterion asks for exactly this distinction, so it
is stated rather than implied. Only the **material** and **cupertino** libraries
were extracted from the SDK; the rest stays on the Flutter SDK and was left
alone:

| Import | Files | Action |
|---|---|---|
| `package:flutter/foundation.dart` | 39 | untouched |
| `package:flutter/services.dart` | 14 | untouched |
| `package:flutter/widgets.dart` | 4 | untouched (`material_ui` re-exports it, so a migrated file that imported both had its `material.dart` line swapped and keeps working) |
| `package:flutter/semantics.dart`, `…/scheduler.dart` | 2 | untouched |
| `package:flutter_test/flutter_test.dart` | — | untouched (not a Material import) |
| `package:flutter/cupertino.dart` | 0 | never imported by this app |

`analysis_options.yaml` gains **no** ignore and no exclude: the migration is
verified by the hint count, not suppressed.

## The two real breakages (and why the delegate list had to move too)

1. **The generated delegate list is unusable, twice over.** `flutter gen-l10n`
   hardcodes `import 'package:flutter_localizations/flutter_localizations.dart'`
   and emits `GlobalMaterialLocalizations.delegate` /
   `GlobalCupertinoLocalizations.delegate` from it. Those two are the *only*
   hints the migration cannot remove (generated output, drift-checked, never
   hand-edited). Worse, that delegate provides the **legacy**
   `MaterialLocalizations` type, which is a *different type* from
   `material_ui`'s: after the import swap a `material_ui` app resolved it as
   missing and fell back to English, with every German widget test throwing
   "Warning: This application's locale, de, is not supported by all of its
   localization delegates / A MaterialLocalizations delegate that supports the
   de locale was not found" (384 failing widget tests before this was fixed).
   `appLocalizationsDelegates` supplies `AppLocalizations.delegate` plus
   `GlobalMaterialLocalizations.delegates` (material_ui's own trio: cupertino,
   material, widgets), so German Material copy and `MaterialLocalizations.of`
   keep working — including `lib/l10n/locale_formatters.dart`, which formats
   dates through it.
2. **`flutter_code_editor` is still a legacy-material package.** Its
   `CodeField` builds a legacy `TextField`, which asserts on a legacy `Material`
   ancestor and needs a legacy `Theme` + legacy `MaterialLocalizations`; inside
   a `material_ui` tree every `ai_config_screen_test` case failed with "No
   Material widget found" (746 exceptions). `legacyMaterialSubtree()` wraps the
   editor body in `MaterialUiCompatibilityBridge` (theme + localizations, mapped
   from the ambient modern theme) plus a transparent legacy `Material`. It is
   the only file that imports legacy material, carries the two documented
   `// ignore: deprecated_member_use` markers, and is deleted the moment
   `flutter_code_editor` migrates upstream.

## Deviation from "must not move a pixel" — measured, not assumed

The issue's third criterion assumes a pure re-import. Taking `material_ui`
1.11.1 also takes *that package's* behaviour, which differs from the SDK's
bundled Material copy in two places. Each diff was measured pixel-by-pixel
before accepting it:

| Golden set | Diff | Cause |
|---|---|---|
| `scene_shoots_board_{light,dark}_{android,macos}.png` (4) | 2304 px = 3 full-width hairlines (0.24 %) at the dropdown underline; **no layout change** | `material_ui`'s `DropdownButtonFormField` passes the field's disabled state to its `InputDecorator` (`enabled: _enabled && widget._inputDecoration!.enabled`). The fixture has no pieces, so the "An Stück hängen" picker is disabled and its underline now paints `onSurface@12 %` instead of `outline`. Verified in the package source and by reverting only that widget's parent state — the other 99.76 % of the image is byte-identical. |
| `settings_ai_config_checking_{light,dark}.png` (2) | 93 px confined to the spinner box (735,27)–(753,45) | The harness pushed the screen as a route and captured after 400 ms; Material 3's page transition runs **450 ms**, so `captureImage`'s `!debugNeedsPaint` assert tripped on a mid-transition frame. The harness now pumps one deterministic 200 ms step past it; the captured spinner frame therefore rotates slightly. |
| `easter_eggs_{light,dark}.png` (2) | ~6000 px confined to the walking cat's band | Same 450 ms transition; the extra deterministic step lands the cat at a different phase in its repeating cycle. |

No golden other than those eight pixels-worth of areas changed, and `flutter
test` is green (2547 tests).

## Residual: 2 hints that this change cannot remove

`flutter analyze --no-fatal-infos` on the pinned SDK now reports **2** hints,
both in `lib/l10n/generated/app_localizations.dart` (lines 90–91), both emitted
by `flutter_tools`' hardcoded `gen_l10n_templates.dart`. Removing them requires
either hand-editing generated output (forbidden; the `flutter gen-l10n` drift
gate would fail) or a project-level ignore/exclude (explicitly rejected by the
issue's fifth criterion). Tracked as a follow-up: drop them when
`flutter gen-l10n` emits the `material_ui` delegates.

## Risks / rollback

- **Behaviour:** the import swap is type-identical for the framework's
  widget/rendering layer (`material_ui` re-exports `package:flutter/widgets.dart`),
  so no widget in `lib/` had to change shape; the two functional seams (legacy
  editor subtree, delegate list) are covered by the existing widget/golden
  suites.
- **Rollback:** revert the commit. The only lock-level effect is
  `material_ui` becoming a direct (not transitive) dependency.
