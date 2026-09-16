// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

/// Material 3 window size classes for the adaptive shell
/// (spec `flutter-navigation-shell`; breakpoints per the M3 canonical
/// definition: compact < 600dp, medium 600–839dp, expanded ≥ 840dp).
enum WindowSizeClass { compact, medium, expanded }

/// Compact/medium breakpoint (dp). Below it the shell renders a bottom
/// `NavigationBar`; from it a `NavigationRail`.
const double kMediumBreakpointDp = 600;

/// Medium/expanded breakpoint (dp). From it the shell renders a permanent
/// `NavigationDrawer`.
const double kExpandedBreakpointDp = 840;

/// Resolves the [WindowSizeClass] from a window width in logical pixels
/// (dp). Pure function — no Flutter dependency — so the shell widget maps
/// `MediaQuery.sizeOf(context).width` through it and unit tests exercise
/// the boundary values directly.
WindowSizeClass resolveWindowSizeClass(double widthDp) {
  if (widthDp < kMediumBreakpointDp) return WindowSizeClass.compact;
  if (widthDp < kExpandedBreakpointDp) return WindowSizeClass.medium;
  return WindowSizeClass.expanded;
}
