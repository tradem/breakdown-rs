// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'generated/app_localizations.dart';
import 'generated/app_localizations_de.dart';
import 'generated/app_localizations_en.dart';

/// The catalog available to non-widget layers.
///
/// The default is the German template used by standalone widget tests and
/// composition-root previews. [App] overrides this provider from the locale
/// resolved by `MaterialApp`, so controllers never read the device locale on
/// their own.
final appLocalizationsProvider = Provider<AppLocalizations>(
  (ref) => AppLocalizationsDe(),
);

/// Returns the catalog for [context]. Small preview/test trees that do not
/// install the app localization delegates use English for stable existing
/// widget-test expectations; the real app always installs the delegates,
/// where unsupported locales fall back to the German template.
AppLocalizations l10nOf(BuildContext context) =>
    Localizations.of<AppLocalizations>(context, AppLocalizations) ??
    AppLocalizationsEn();
