// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

/// Named spacing tokens (logical px) for the shell and dialog surfaces
/// (spec `flutter-design-tokens`, design.md §5).
///
/// Widgets use these instead of numeric literals so spacing stays reviewable
/// and consistent. Existing screens are NOT retro-fitted here (honest scope
/// note — e.g. the seasons empty-state `SizedBox(height: 160)` stays until
/// `flutter-hierarchy-navigation` touches that area).
abstract final class AppSpacing {
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space24 = 24;
  static const double space32 = 32;
}
