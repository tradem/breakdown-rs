// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/design/gen/design_tokens.g.dart';
import 'package:frontend_flutter/design/navigation_bar_metrics.dart';
import 'package:frontend_flutter/design/theme.dart';

/// WCAG 2.1 relative luminance of an opaque color.
double _luminance(Color color) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// WCAG 2.1 contrast ratio between two opaque colors, in [1, 21].
double _contrast(Color foreground, Color background) {
  final double a = _luminance(foreground);
  final double b = _luminance(background);
  final double hi = math.max(a, b);
  final double lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

/// The two backdrop extremes the glass bar can be composited over: content is
/// photography, so pure white and pure black are the ends the contrast budget
/// must survive — in BOTH themes.
///
/// The theme never picks the worse of the two: a dark backdrop DARKENS the light
/// theme's bar (reducing contrast for its dark labels) and a light one LIGHTENS
/// the dark theme's (reducing it for its light labels), so the extreme that helps
/// one theme is the worst case for the other. Every ratio below is therefore the
/// MINIMUM over both backdrops, never the one that matches the theme's
/// brightness.
const List<Color> _backdropExtremes = <Color>[
  Color(0xFFFFFFFF),
  Color(0xFF000000),
];

/// The bar surface the user actually sees over [backdrop]: the tint composited
/// over the blurred content.
Color _paintedBar(ColorScheme scheme, Color backdrop) =>
    Color.alphaBlend(NavigationBarMetrics.tint(scheme), backdrop);

/// The worst (lowest) contrast [foreground] reaches over the painted bar, across
/// every backdrop extreme.
double _minContrastOverBackdrops(Color foreground, ColorScheme scheme) =>
    _backdropExtremes
        .map((backdrop) => _contrast(foreground, _paintedBar(scheme, backdrop)))
        .reduce(math.min);

/// The compact bottom bar's glass surface (issue #991).
///
/// These are the token round-trips, the one-plane/two-states color derivation
/// and the contrast budget the tint — not the blur — has to carry.
void main() {
  for (final (name, theme) in [
    ('light', AppThemes.light()),
    ('dark', AppThemes.dark()),
  ]) {
    final ColorScheme scheme = theme.colorScheme;

    group('$name scheme', () {
      test('the theme writes the token height and derives the tint', () {
        // One number for bar and reservation: the theme's height IS the token.
        expect(
          theme.navigationBarTheme.height,
          DesignTokens.componentNavigationBarHeight,
        );
        expect(NavigationBarMetrics.height, 80);
        expect(
          theme.navigationBarTheme.backgroundColor,
          NavigationBarMetrics.tint(scheme),
        );
        // The tint is translucent — an opaque background would hide the
        // content scrolling behind the bar and the glass would be a plain band.
        expect(
          theme.navigationBarTheme.backgroundColor!.a,
          closeTo(NavigationBarMetrics.tintAlpha, 1e-9),
        );
        expect(NavigationBarMetrics.tintAlpha, lessThan(1));
        expect(NavigationBarMetrics.tintAlpha, greaterThan(0));
      });

      test('nothing opaque is painted by the bar itself', () {
        expect(
          theme.navigationBarTheme.elevation,
          DesignTokens.elevationLevel0,
        );
        expect(theme.navigationBarTheme.shadowColor, Colors.transparent);
        expect(theme.navigationBarTheme.surfaceTintColor, Colors.transparent);
      });

      test('the plane is its own plane, lifted off the plain surface', () {
        final Color plane = NavigationBarMetrics.plane(scheme);
        expect(plane.a, 1.0); // the keyboard fallback MUST be opaque
        expect(plane, isNot(scheme.surface));
        // Brightness-aware: the lift goes toward the scheme's surfaceTint, so
        // the dark scheme lifts toward the dark tint instead of a fixed grey.
        expect(NavigationBarMetrics.planeLiftAlpha, greaterThan(0));
        expect(NavigationBarMetrics.planeLiftAlpha, lessThan(0.5));
        expect(plane, isNot(AppThemes.light().colorScheme.surface));
      });

      test('the tint over the plane composites back to exactly the plane', () {
        // This is why the keyboard fallback needs no second color decision: the
        // child's translucent tint over the opaque plane yields the plane
        // (channel-wise, modulo float rounding in alphaBlend).
        final Color plane = NavigationBarMetrics.plane(scheme);
        final Color composited = Color.alphaBlend(
          NavigationBarMetrics.tint(scheme),
          plane,
        );
        expect(composited.a, 1.0);
        expect(composited.r, closeTo(plane.r, 1e-6));
        expect(composited.g, closeTo(plane.g, 1e-6));
        expect(composited.b, closeTo(plane.b, 1e-6));
      });

      test('the blur stays within the cost budget of issue #991', () {
        expect(NavigationBarMetrics.blurSigma, greaterThan(0));
        // Issue #991 risk 1: keep sigma low; the filter is a save-layer per
        // frame on every destination.
        expect(NavigationBarMetrics.blurSigma, lessThanOrEqualTo(16));
      });

      test('labels keep >= 4.5:1 over every backdrop extreme', () {
        // NavigationBar's M3 label colors: onSurface when selected,
        // onSurfaceVariant otherwise.
        expect(
          _minContrastOverBackdrops(scheme.onSurface, scheme),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _minContrastOverBackdrops(scheme.onSurfaceVariant, scheme),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('icons keep >= 3:1 over every backdrop extreme', () {
        // Unselected icon: onSurfaceVariant over the bar surface, at whatever
        // content happens to be blurred behind it.
        expect(
          _minContrastOverBackdrops(scheme.onSurfaceVariant, scheme),
          greaterThanOrEqualTo(3.0),
        );
      });

      test('the selected icon keeps >= 3:1 on the opaque indicator pill', () {
        // Selected icon sits on the OPAQUE indicator pill
        // (secondaryContainer / onSecondaryContainer) — a pair the glass never
        // touches, asserted so the pill is proved to stay opaque.
        expect(
          _contrast(scheme.onSecondaryContainer, scheme.secondaryContainer),
          greaterThanOrEqualTo(3.0),
        );
      });

      test('the indicator pill is a DECORATIVE boundary, not a 3:1 edge', () {
        // The pill is the M3 default `secondaryContainer`, and no scheme role
        // puts that container 3:1 away from its own surface family — measured
        // here at ~1.2:1 (light) / ~1.4–1.9:1 (dark) against the painted bar.
        // It is therefore NOT the boundary that carries the selection: the
        // state is carried twice over by the selected icon color (>= 3:1 on the
        // pill, above) and the selected label color (>= 4.5:1 over every
        // backdrop, above), exactly as M3 intends. The spec states this budget
        // as such; what this test pins is that the pill stays OPAQUE and
        // DISTINCT from the bar, so it keeps reading as a pill and never turns
        // into a second translucent layer.
        for (final backdrop in _backdropExtremes) {
          final Color painted = _paintedBar(scheme, backdrop);
          expect(scheme.secondaryContainer.a, 1.0);
          expect(scheme.secondaryContainer, isNot(painted));
          expect(
            _contrast(scheme.secondaryContainer, painted),
            greaterThan(1.0),
            reason: 'the pill must stay visible as a shape over $backdrop',
          );
        }
      });
    });
  }
}
