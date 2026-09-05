// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter/material.dart';

/// Design tokens for the Breakdown client (spec `flutter-design-tokens`).
///
/// The teal seed preserves today's app identity; both M3 themes are derived
/// from this single token via [ColorScheme.fromSeed]. This file is the ONLY
/// place that may contain `Color(...)` literals — widgets introduced by the
/// login-and-app-shell change must use `Theme.of(context)` color-scheme
/// roles or [AppSpacing] tokens (machine-checkable at review).
abstract final class AppTokens {
  /// Seed color token for [ColorScheme.fromSeed] (light AND dark).
  static const Color seedColor = Colors.teal;
}

/// Light and dark Material 3 themes built from [AppTokens.seedColor].
///
/// [App] passes both as `theme`/`darkTheme` with
/// `themeMode: ThemeMode.system`, so a system brightness change re-renders
/// without an app restart (spec scenario "System switches to dark mode").
/// Default M3 system-contrast scheme; no per-widget color overrides.
abstract final class AppThemes {
  static ThemeData light() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppTokens.seedColor),
  );

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppTokens.seedColor,
      brightness: Brightness.dark,
    ),
  );
}
