// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_localizations_provider.dart';

/// Centralized formatting for values owned by the client UI.
///
/// The app initializes `intl` date symbols during bootstrap. The Material
/// fallback keeps isolated widget previews/tests deterministic when they do
/// not run the production bootstrap; the production path always uses the
/// resolved application locale.
String formatMediumDate(BuildContext context, DateTime date) {
  final locale = l10nOf(context).localeName;
  try {
    return DateFormat.yMMMd(locale).format(date);
  } catch (_) {
    return MaterialLocalizations.of(context).formatMediumDate(date);
  }
}

String formatDecimal(BuildContext context, num value) {
  final locale = l10nOf(context).localeName;
  try {
    return NumberFormat.decimalPattern(locale).format(value);
  } catch (_) {
    return value.toString();
  }
}
