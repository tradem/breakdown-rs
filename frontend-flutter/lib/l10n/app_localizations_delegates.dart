// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;

import 'generated/app_localizations.dart';

/// The `localizationsDelegates` list every `MaterialApp` in this project
/// installs: the generated app catalog plus the framework's material,
/// cupertino and widgets delegates.
///
/// **Why not `AppLocalizations.localizationsDelegates` (issue #975).** The
/// list `flutter gen-l10n` emits is now unusable, in two independent ways:
///
/// 1. It names `GlobalMaterialLocalizations` / `GlobalCupertinoLocalizations`
///    from `package:flutter_localizations`, which are deprecated since Flutter
///    3.50 in favour of the `material_ui` / `cupertino_ui` copies — the
///    hardcoded generator template keeps them, so those two hints cannot be
///    removed from project code (they are the only `deprecated_member_use`
///    hits the migration leaves behind).
/// 2. The deprecated delegates satisfy the **legacy** `MaterialLocalizations`
///    type, which is a different type from `material_ui`'s. A `material_ui`
///    app therefore resolved them as *missing* and fell back to English,
///    emitting "A MaterialLocalizations delegate that supports the de locale
///    was not found" on every German widget test. This list fixes that.
///
/// `GlobalMaterialLocalizations.delegates` (from `material_ui`) is exactly the
/// trio needed — cupertino, material, widgets, in that order — so the app does
/// not have to import `cupertino_ui` (which only `material_ui` re-exports
/// indirectly). Our own catalog stays first.
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ];
