// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

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

/// Formats a wire date (`yyyy-MM-dd`, the OpenAPI `Date` shape the read
/// DTOs carry as a string) for display in the active locale — the date is
/// data, never a protocol value the user should read verbatim (issue #832).
///
/// An unparsable value falls back to the raw string: a data defect stays
/// visible instead of being silently replaced by a placeholder.
String formatWireDate(BuildContext context, String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  return formatMediumDate(
    context,
    DateTime(parsed.year, parsed.month, parsed.day),
  );
}

/// Formats a timestamp's time of day (e.g. `07:10`) in the active locale.
///
/// Used where the *window* of a repeated condition matters and the date alone
/// would hide it (issue #822: three provider failures over 17 minutes). The
/// date is still shown by the caller when the window spans days; this helper
/// only ever answers "at what time".
String formatClock(BuildContext context, DateTime value) {
  final locale = l10nOf(context).localeName;
  try {
    return DateFormat.Hm(locale).format(value.toLocal());
  } catch (_) {
    return MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(value.toLocal()));
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
