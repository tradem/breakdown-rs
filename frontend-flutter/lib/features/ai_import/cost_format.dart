// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';

/// Pure display formatting for AI-import cost values (issue #675).
///
/// All math is INTEGER string manipulation over nano-units ($10⁻⁹ of the
/// currency major unit) — zero floating-point arithmetic, mirroring the
/// backend's integer nano-currency doctrine (design D2). Formatting never
/// rounds a displayed figure to `0`: small non-zero rates keep their
/// sub-cent digits (up to 6 decimals, trailing zeros trimmed), so a
/// non-free import NEVER renders as `$0.00` (spec: honest unknown/zero
/// semantics — `unknown` renders localized copy, never a fabricated zero).
///
/// Tier-1 pure: no widget, no I/O, deterministic.

/// The display symbol for [currency] (`$` for USD, `€` for EUR).
String costCurrencySymbol(Currency currency) =>
    currency == Currency.EUR ? '€' : r'$';

/// Formats [nano] nano-units of [currency] as a display string, e.g.
/// `1450000000` → `$1.45`, `292500000` → `$0.2925`, `3625000` → `$0.003625`.
///
/// Up to 6 sub-unit decimals are kept (nano precision is 9; the last 3
/// digits of a per-job total are far below any displayable relevance for
/// the curated rates), trailing zeros are trimmed, and a whole number
/// renders without a decimal point. A non-zero amount whose first 6
/// decimals are all zero keeps full nano precision instead — it must never
/// render as a fabricated `$0` (small energy costs can land below 1000
/// nano).
String formatNanoCurrency(int nano, Currency currency) {
  final symbol = costCurrencySymbol(currency);
  final negative = nano < 0;
  final abs = negative ? -nano : nano;
  final major = abs ~/ 1000000000;
  final frac = '${abs % 1000000000}'.padLeft(9, '0');
  var frac6 = (major == 0 && abs != 0 && frac.startsWith('000000'))
      ? frac
      : frac.substring(0, 6);
  while (frac6.isNotEmpty && frac6.endsWith('0')) {
    frac6 = frac6.substring(0, frac6.length - 1);
  }
  final sign = negative ? '-' : '';
  return frac6.isEmpty ? '$sign$symbol$major' : '$sign$symbol$major.$frac6';
}

/// Formats [millijoules] as a watt-hour decimal string (1 Wh = 3.6 × 10⁶ mJ),
/// e.g. `45000000` → `12.5`, `3600000` → `1`. Integer math with half-up
/// rounding to hundredths of a Wh — no floats, trailing zeros trimmed.
String formatMillijoulesAsWh(int millijoules) {
  final negative = millijoules < 0;
  final abs = negative ? -millijoules : millijoules;
  // Hundredths of a Wh, half-up: (mJ × 100 + 1.8×10⁶) ~/ 3.6×10⁶.
  final hundredths = (abs * 100 + 1800000) ~/ 3600000;
  final whole = hundredths ~/ 100;
  final frac = '${hundredths % 100}'.padLeft(2, '0');
  // '00' → ''; '10' → '1'; '01' stays '01' (a leading zero is significant).
  final fracTrimmed = frac == '00'
      ? ''
      : (frac.endsWith('0') ? frac.substring(0, 1) : frac);
  final sign = negative ? '-' : '';
  return fracTrimmed.isEmpty ? '$sign$whole' : '$sign$whole.$fracTrimmed';
}
