// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:flutter/material.dart';

import 'gen/design_tokens.g.dart';
import 'spacing.dart';

/// The one header metric every pushed screen's app bar uses (issue #824).
///
/// The height is DERIVED, not picked: one title line ([lineHeight], the
/// `typography.lineHeight.titleLarge` token) plus two comfortable
/// [verticalPadding] steps. That sum is 44 dp, which is below the Material
/// interactive-dimension floor — and the leading back button's 48 dp touch
/// target lives inside this bar — so the effective height is clamped up to
/// [kMinInteractiveDimension]. With today's tokens this resolves to **48 dp**
/// around a 22 sp title instead of the untokenized M3 default of 56 dp.
///
/// The type values come from the DTCG typography tokens
/// (`design/tokens/typography.json` → `design_tokens.g.dart`, rebuilt by
/// `scripts/build-tokens.sh`); the vertical padding reuses the spacing scale.
/// A dedicated `component.appBar.height` token is deliberately NOT introduced
/// here — component tokens are a non-goal of the design-token foundation, so a
/// derived value in the theme layer is the honest place until such a token
/// exists.
abstract final class HeaderMetrics {
  /// Font size of the header title (`typography.fontSize.titleLarge`, 22 sp).
  static const double fontSize = DesignTokens.typographyFontSizeTitleLarge;

  /// Line height of the header title (`typography.lineHeight.titleLarge`,
  /// 28 dp) — the unit the bar height is built from.
  static const double lineHeight = DesignTokens.typographyLineHeightTitleLarge;

  /// The title's weight. `typography.fontWeight.titleLarge` is `400.0`, which
  /// has no const constructor mapping to [FontWeight]; the token and this
  /// weight are asserted equal in `test/design/header_metrics_test.dart`
  /// instead of being re-derived with a runtime switch.
  static const FontWeight fontWeight = FontWeight.w400;

  /// Breathing room above and below the title line (`spacing.8`).
  static const double verticalPadding = AppSpacing.space8;

  /// Title line plus both padding steps (44 dp with today's tokens).
  static const double contentHeight = lineHeight + 2 * verticalPadding;

  /// The bar's actual height: [contentHeight], never below the Material
  /// interactive-dimension minimum the back button needs (48 dp).
  static const double toolbarHeight = contentHeight < kMinInteractiveDimension
      ? kMinInteractiveDimension
      : contentHeight;

  /// The header title style, from the typography tokens. Every app bar gets
  /// it from `Theme.of(context).appBarTheme.titleTextStyle`; widgets do not
  /// re-declare it.
  static TextStyle titleStyle(Color color) => TextStyle(
    color: color,
    fontSize: fontSize,
    height: lineHeight / fontSize,
    fontWeight: fontWeight,
  );
}
