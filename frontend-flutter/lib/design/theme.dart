// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)

import 'package:material_ui/material_ui.dart';

import 'package:frontend_flutter/design/gen/design_tokens.g.dart';
import 'package:frontend_flutter/design/header_metrics.dart';
import 'package:frontend_flutter/design/navigation_bar_metrics.dart';
import 'package:frontend_flutter/design/spacing.dart';

/// Design tokens for the Breakdown client (spec `flutter-design-tokens`).
///
/// The seed is sourced from the generated DTCG tokens
/// (`design/tokens/color.json` → `design_tokens.g.dart`, rebuilt by
/// `scripts/build-tokens.sh`) — hand-edits to the generated file are
/// forbidden. Both M3 themes are derived from this single token via
/// [ColorScheme.fromSeed]; this file is the ONLY place that may contain
/// `Color(...)` literals besides the generated artifact — widgets
/// introduced by the login-and-app-shell change must use
/// `Theme.of(context)` color-scheme roles or [AppSpacing] tokens
/// (machine-checkable at review).
abstract final class AppTokens {
  /// Seed color token for [ColorScheme.fromSeed] (light AND dark).
  /// Delegates to the generated `color.brand.seed` DTCG token.
  static const Color seedColor = DesignTokens.colorBrandSeed;
}

/// Light and dark Material 3 themes built from [AppTokens.seedColor].
///
/// [App] passes both as `theme`/`darkTheme` with
/// `themeMode: ThemeMode.system`, so a system brightness change re-renders
/// without an app restart (spec scenario "System switches to dark mode").
/// Default M3 system-contrast scheme; no per-widget color overrides.
abstract final class AppThemes {
  static ThemeData light() =>
      _theme(ColorScheme.fromSeed(seedColor: AppTokens.seedColor));

  static ThemeData dark() => _theme(
    ColorScheme.fromSeed(
      seedColor: AppTokens.seedColor,
      brightness: Brightness.dark,
    ),
  );

  /// Builds the theme pair with the app-bar and bottom-bar roles resolved once
  /// per scheme.
  ///
  /// Issue #824: every pushed screen's header takes its height and title style
  /// from this theme (via `Theme.of(context).appBarTheme`), so the 41 call
  /// sites stop being independent layout decisions and no screen declares a
  /// `toolbarHeight` literal of its own.
  ///
  /// Issue #991: the compact shell's bottom bar is a translucent glass surface,
  /// and its two color decisions are composed by [NavigationBarMetrics] from
  /// this file's scheme — the shell wraps the bar in a `GlassBottomBar` but
  /// never picks a color itself.
  static ThemeData _theme(ColorScheme scheme) => ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    appBarTheme: _appBarTheme(scheme),
    navigationBarTheme: _navigationBarTheme(scheme),
  );

  /// The header role: token-derived height ([HeaderMetrics.toolbarHeight]),
  /// the type scale's title style, a leading-aligned title, and the M3
  /// scroll-under tint instead of a raised bar.
  static AppBarTheme _appBarTheme(ColorScheme scheme) => AppBarTheme(
    toolbarHeight: HeaderMetrics.toolbarHeight,
    backgroundColor: scheme.surface,
    foregroundColor: scheme.onSurface,
    surfaceTintColor: scheme.surfaceTint,
    elevation: DesignTokens.elevationLevel0,
    scrolledUnderElevation: DesignTokens.elevationLevel2,
    titleTextStyle: HeaderMetrics.titleStyle(scheme.onSurface),
    centerTitle: false,
    titleSpacing: AppSpacing.space16,
  );

  /// The compact bottom-bar role: a translucent **glass** surface (issue #991).
  ///
  /// The bar itself paints NOTHING opaque — no `surfaceContainer` fill, no
  /// elevation, no shadow, no surface tint. M3's default paints all four, and
  /// any one of them hides the content scrolling behind the bar. What remains
  /// is the tint ([NavigationBarMetrics.tint]), which is translucent on
  /// purpose: the shell puts a `BackdropFilter` behind the bar and extends the
  /// body under it, so the tint is composited over blurred content.
  ///
  /// The indicator pill and the label/icon colors are deliberately NOT set: the
  /// M3 defaults (`secondaryContainer` / `onSurface` / `onSurfaceVariant` /
  /// `onSecondaryContainer`) are already opaque and already carry their own
  /// contrast contract against the tint, which
  /// `test/design/navigation_bar_metrics_test.dart` measures at the
  /// worst-case blurred backdrop. Only the bar *background* becomes
  /// translucent.
  static NavigationBarThemeData _navigationBarTheme(ColorScheme scheme) =>
      NavigationBarThemeData(
        // Token-derived, and the same value `Scaffold(extendBody: true)` uses
        // for the body's bottom inset — the bar and its reservation cannot
        // drift apart.
        height: NavigationBarMetrics.height,
        backgroundColor: NavigationBarMetrics.tint(scheme),
        elevation: DesignTokens.elevationLevel0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      );
}
