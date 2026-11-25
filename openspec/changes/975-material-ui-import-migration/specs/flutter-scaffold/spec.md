<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-scaffold Delta (975-material-ui-import-migration)

## ADDED Requirements

### Requirement: Material Widgets Are Imported From `material_ui`, Not The SDK

Every hand-written Dart file under `frontend-flutter/lib/`, `test/` and
`integration_test/` SHALL import Material Design widgets from
`package:material_ui/material_ui.dart`, because `package:flutter/material.dart`
is deprecated since Flutter 3.50 (the pinned toolchain) — *"This feature was
deprecated after v3.47.0-0.0.pre. Try replacing the use of the deprecated member
with the replacement"*. `material_ui` SHALL be declared as a DIRECT dependency
in `pubspec.yaml`; a transitive-only dependency is a defect, since the package
is now imported by project code.

Only the Material (and Cupertino, which this app does not import) libraries were
extracted from the SDK. `package:flutter/foundation.dart`,
`package:flutter/services.dart`, `package:flutter/widgets.dart`,
`package:flutter/scheduler.dart`, `package:flutter/semantics.dart` and
`package:flutter_test/flutter_test.dart` remain SDK imports and SHALL NOT be
rewritten.

`analysis_options.yaml` SHALL NOT carry an `ignore`/`exclude` for
`deprecated_member_use`: the migration is proven by the hint count, never
suppressed.

#### Scenario: A new widget imports the deprecated entry point
- **WHEN** a contributor adds `import 'package:flutter/material.dart';` to a new
  widget.
- **THEN** `flutter analyze` reports `deprecated_member_use` and review sends the
  file back to `package:material_ui/material_ui.dart`.

#### Scenario: A legacy third-party widget needs the old API
- **WHEN** a dependency still builds legacy Material widgets
  (`flutter_code_editor` today).
- **THEN** exactly one adapter file imports the legacy entry point, wraps the
  legacy subtree in the compatibility bridge (legacy `Material` ancestor +
  bridged theme/localizations), carries a per-line
  `// ignore: deprecated_member_use` with the reason and the deletion
  condition, and no other file imports it.

### Requirement: Localizations Delegates Come From `material_ui`

The `localizationsDelegates` list installed by every `MaterialApp` in the app
and its tests SHALL come from `lib/l10n/app_localizations_delegates.dart`, not
from the `flutter gen-l10n`-generated `AppLocalizations.localizationsDelegates`.

The generated list names the DEPRECATED
`GlobalMaterialLocalizations`/`GlobalCupertinoLocalizations` from
`package:flutter_localizations`; those provide the *legacy*
`MaterialLocalizations` type, which is a different type from `material_ui`'s, so
a `material_ui` app resolves them as missing and silently falls back to English.
The project list therefore supplies `AppLocalizations.delegate` plus
`GlobalMaterialLocalizations.delegates` (material_ui's cupertino + material +
widgets trio).

Generated output stays generated: `lib/l10n/generated/**` SHALL NOT be
hand-edited, and the `flutter gen-l10n` drift gate SHALL stay clean.

#### Scenario: A German device renders Material copy in German
- **WHEN** the app runs with `locale: Locale('de')` (goldens included).
- **THEN** `MaterialLocalizations.of(context)` resolves the German catalog (no
  "a MaterialLocalizations delegate that supports the de locale was not found"
  warning), and date formatting through `lib/l10n/locale_formatters.dart` uses
  the German patterns.

#### Scenario: A new screen installs the generated delegate list
- **WHEN** a screen or test passes `AppLocalizations.localizationsDelegates`.
- **THEN** the German-locale widget tests fail with the unsupported-locale
  warning, which is the signal to use `appLocalizationsDelegates` instead.
