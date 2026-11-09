// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Header token tests (issue #824, relaxed non-goal in issue #838): the
// pushed-screen header's height, title size and padding are DTCG component
// tokens (`design/tokens/component.json`), carried by the theme, and never
// chosen or re-derived by a screen or by the metrics class.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/design/gen/design_tokens.g.dart';
import 'package:frontend_flutter/design/header_metrics.dart';
import 'package:frontend_flutter/design/spacing.dart';
import 'package:frontend_flutter/design/theme.dart';

void main() {
  group('HeaderMetrics (issue #824, component tokens since #838)', () {
    test('the component tokens alias the type and spacing primitives', () {
      // The alias round-trip: retuning the primitive flows into the header
      // token, so the component group cannot silently drift from the scale.
      expect(
        DesignTokens.componentAppBarTitleFontSize,
        DesignTokens.typographyFontSizeTitleLarge,
      );
      expect(
        DesignTokens.componentAppBarTitleLineHeight,
        DesignTokens.typographyLineHeightTitleLarge,
      );
      expect(
        DesignTokens.componentAppBarVerticalPadding,
        DesignTokens.sizeSpace8,
      );
      expect(DesignTokens.componentAppBarVerticalPadding, AppSpacing.space8);
    });

    test('HeaderMetrics reads the component tokens, it derives nothing', () {
      expect(HeaderMetrics.fontSize, DesignTokens.componentAppBarTitleFontSize);
      expect(
        HeaderMetrics.lineHeight,
        DesignTokens.componentAppBarTitleLineHeight,
      );
      expect(
        HeaderMetrics.verticalPadding,
        DesignTokens.componentAppBarVerticalPadding,
      );
      expect(HeaderMetrics.toolbarHeight, DesignTokens.componentAppBarHeight);
    });

    test('the height token keeps the 48dp interactive floor', () {
      // The clamp that #824 applied in code is now the token's decision: the
      // content sum (28 + 2 × 8 = 44) is under the Material floor the leading
      // back button's touch target needs, and the token stays above both.
      const contentSum =
          DesignTokens.componentAppBarTitleLineHeight +
          2 * DesignTokens.componentAppBarVerticalPadding;
      expect(contentSum, 44);
      expect(HeaderMetrics.toolbarHeight, 48);
      expect(
        HeaderMetrics.toolbarHeight,
        greaterThanOrEqualTo(kMinInteractiveDimension),
      );
      expect(HeaderMetrics.toolbarHeight, greaterThanOrEqualTo(contentSum));
    });

    test('the weight matches the typography token', () {
      // `FontWeight` has no const constructor mapping from the token's
      // double; the two are pinned equal here instead of being re-derived at
      // runtime by a switch.
      expect(DesignTokens.typographyFontWeightTitleLarge, 400.0);
      expect(HeaderMetrics.fontWeight, FontWeight.w400);
      expect(HeaderMetrics.fontWeight.value, 400);
    });

    test('the title style carries the token size and line height', () {
      final style = HeaderMetrics.titleStyle(const Color(0xFF102030));
      expect(style.color, const Color(0xFF102030));
      expect(style.fontSize, HeaderMetrics.fontSize);
      expect(style.fontWeight, HeaderMetrics.fontWeight);
      expect(
        style.height,
        closeTo(
          DesignTokens.componentAppBarTitleLineHeight /
              DesignTokens.componentAppBarTitleFontSize,
          1e-9,
        ),
      );
    });
  });

  group('AppThemes app-bar role (issue #824)', () {
    for (final entry in {
      'light': AppThemes.light(),
      'dark': AppThemes.dark(),
    }.entries) {
      test(
        '${entry.key}: the header height and title style come from tokens',
        () {
          final appBar = entry.value.appBarTheme;
          expect(appBar.toolbarHeight, HeaderMetrics.toolbarHeight);
          expect(appBar.centerTitle, isFalse);
          expect(appBar.titleSpacing, AppSpacing.space16);
          expect(appBar.elevation, DesignTokens.elevationLevel0);
          expect(appBar.scrolledUnderElevation, DesignTokens.elevationLevel2);
          expect(appBar.titleTextStyle?.fontSize, HeaderMetrics.fontSize);
          expect(appBar.titleTextStyle?.fontWeight, HeaderMetrics.fontWeight);
          expect(
            appBar.titleTextStyle?.color,
            entry.value.colorScheme.onSurface,
          );
          // The bar's surface roles resolve per brightness, so a dark theme
          // does not inherit the light bar.
          expect(appBar.backgroundColor, entry.value.colorScheme.surface);
          expect(appBar.foregroundColor, entry.value.colorScheme.onSurface);
        },
      );
    }

    test('light and dark header roles actually differ', () {
      expect(
        AppThemes.light().appBarTheme.backgroundColor,
        isNot(AppThemes.dark().appBarTheme.backgroundColor),
      );
    });
  });
}
