// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:flutter/material.dart';

import 'gen/design_tokens.g.dart';

/// The one header metric every pushed screen's app bar uses (issue #824).
///
/// Every value here is a generated DTCG component token
/// (`design/tokens/component.json` → `design_tokens.g.dart`, rebuilt by
/// `scripts/build-tokens.sh`); the header is the first component that carries
/// its own token group, which relaxes the design-token foundation's
/// component-token non-goal for exactly this surface (issue #838).
///
/// The height used to be DERIVED in this file: one title line ([lineHeight],
/// the `typography.lineHeight.titleLarge` token) plus two [verticalPadding]
/// steps = 44 dp, clamped up to the Material [kMinInteractiveDimension] floor
/// (48 dp) because the leading back button's touch target lives inside the bar.
/// That clamp is the decision no primitive can express, so it now lives in the
/// token source as `component.appBar.height` (48 dp) instead of being
/// recomputed here; the derivation survives only as documentation in the token
/// description, and `test/design/header_metrics_test.dart` pins the invariant
/// that the content sum never outgrows the height.
///
/// A dedicated token is why a designer can retune the header without a code
/// change, and why raising a typography token is no longer silently absorbed
/// by the `max(...)` floor with nothing to review.
abstract final class HeaderMetrics {
  /// Font size of the header title (`component.appBar.titleFontSize`, 22 sp —
  /// itself an alias of `typography.fontSize.titleLarge`).
  static const double fontSize = DesignTokens.componentAppBarTitleFontSize;

  /// Line height of the header title (`component.appBar.titleLineHeight`,
  /// 28 dp — an alias of `typography.lineHeight.titleLarge`).
  static const double lineHeight = DesignTokens.componentAppBarTitleLineHeight;

  /// The title's weight. `typography.fontWeight.titleLarge` is `400.0`, which
  /// has no const constructor mapping to [FontWeight]; the token and this
  /// weight are asserted equal in `test/design/header_metrics_test.dart`
  /// instead of being re-derived with a runtime switch.
  static const FontWeight fontWeight = FontWeight.w400;

  /// Breathing room above and below the title line
  /// (`component.appBar.verticalPadding`, an alias of `spacing.8`).
  static const double verticalPadding =
      DesignTokens.componentAppBarVerticalPadding;

  /// The bar's actual height (`component.appBar.height`, 48 dp): one title
  /// line plus both padding steps (44 dp) clamped up to the Material
  /// interactive-dimension minimum the back button needs — stated once in the
  /// token source, read here, never re-derived at a call site.
  static const double toolbarHeight = DesignTokens.componentAppBarHeight;

  /// The header title style, from the header's type tokens. Every app bar gets
  /// it from `Theme.of(context).appBarTheme.titleTextStyle`; widgets do not
  /// re-declare it.
  static TextStyle titleStyle(Color color) => TextStyle(
    color: color,
    fontSize: fontSize,
    height: lineHeight / fontSize,
    fontWeight: fontWeight,
  );
}
