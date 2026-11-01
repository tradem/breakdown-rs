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
/// It is also the ONE place that decides *which* figure is the primary one
/// ([costPrimaryFigure], issues #761/#768), so the jobs-list line and the
/// job-status hero cannot disagree about the number that matters.
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

/// Which component of a `known` snapshot is the PRIMARY figure — the fact that
/// must never be decided twice (issues #761/#768).
enum CostPrimaryKind {
  /// The explicit total the wire publishes: the figure the user actually pays,
  /// summed over every priced component (`CostTotal.status == known`).
  total,

  /// The **extraction** token component — the fallback whenever the snapshot
  /// publishes no honest total (every pre-#768 row).
  tokenCost,

  /// The hardware-energy component (chosen by the user's `energy` preference,
  /// or when it is the only priced figure in the snapshot).
  energyCost,
}

/// The primary figure of [cost] under [preference]: its nano amount, its
/// currency (never converted — design D2) and WHICH component it is, so callers
/// can label it truthfully.
class CostPrimaryFigure {
  const CostPrimaryFigure({
    required this.nano,
    required this.currency,
    required this.kind,
  });

  final int nano;
  final Currency currency;
  final CostPrimaryKind kind;
}

/// Resolves the primary figure of [cost] for [preference] (pure, Tier-1
/// testable).
///
/// This is the single source of truth for the "which number is primary?"
/// question: the jobs-list cost line (`aiJobCostCompactCopy`) and the
/// job-status hero (`aiCostHero`) both call it, so the two surfaces cannot
/// claim different primary amounts (issues #761/#768).
///
/// The order is deliberate:
///
/// 1. `energy` preference AND a recorded energy component → the energy figure
///    (`effective_capped_nano`, i.e. the value the provider actually billed —
///    never the uncapped `raw_energy_nano`);
/// 2. the explicit total, but ONLY when `CostTotal.status == known` — an
///    `incomplete` / `mixed_currency` total is refused by the server and is
///    never reconstructed here (no rate substitution, no conversion);
/// 3. the extraction token component;
/// 4. the energy component (a snapshot that priced nothing else).
///
/// `null` means "nothing priced to show": `unknown` / `not_applicable`
/// snapshots (the callers render their own honest copy — never `0`) and the
/// defensive shapes that carry a priced component without a currency.
CostPrimaryFigure? costPrimaryFigure(
  CostBreakdown cost,
  CostDisplayPreference preference,
) {
  // built_value `EnumClass` constants are not analyzer-exhaustive: explicit
  // branches, never a `switch` that could fall through.
  if (cost.status == CostStatus.unknown ||
      cost.status == CostStatus.notApplicable) {
    return null;
  }
  final currency = cost.currency;
  if (currency == null) return null;
  final energy = cost.energyCost;
  if (preference == CostDisplayPreference.energy && energy != null) {
    return CostPrimaryFigure(
      nano: energy.effectiveCappedNano,
      currency: currency,
      kind: CostPrimaryKind.energyCost,
    );
  }
  final total = cost.total;
  final totalNano = total?.totalNano;
  if (total != null &&
      total.status == CostTotalStatus.known &&
      totalNano != null) {
    return CostPrimaryFigure(
      nano: totalNano,
      // The total carries its own currency; a snapshot that omits it falls back
      // to the snapshot currency rather than rendering an unconverted guess.
      currency: total.currency ?? currency,
      kind: CostPrimaryKind.total,
    );
  }
  final token = cost.tokenCost;
  if (token != null) {
    return CostPrimaryFigure(
      nano: token.totalNano,
      currency: currency,
      kind: CostPrimaryKind.tokenCost,
    );
  }
  if (energy != null) {
    return CostPrimaryFigure(
      nano: energy.effectiveCappedNano,
      currency: currency,
      kind: CostPrimaryKind.energyCost,
    );
  }
  return null;
}
