// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:material_ui/material_ui.dart';

import 'package:frontend_flutter/design/gen/design_tokens.g.dart';

/// The compact morphology's **glass bottom bar**: its one consumer-side seam
/// (issue #991), mirroring [HeaderMetrics] for the pushed-screen header.
///
/// Every value the bar paints is read here from the
/// `component.navigationBar.*` DTCG tokens (`design/tokens/component.json`),
/// so no call site re-derives an alpha, a blur radius or a height
/// (`frontend-flutter/AGENTS.md` §9). The two *colors* are composed here — the
/// one place besides `theme.dart` allowed to hold a color decision — from the
/// current scheme, never from a literal: [plane] is the surface role lifted
/// toward `scheme.surfaceTint` (brightness-aware by construction, so dark mode
/// lifts toward the dark tint instead of a fixed grey), and [tint] is that
/// plane at the token's opacity.
///
/// `theme.dart` writes [height] and [tint] into the app's
/// `NavigationBarThemeData`; the shell wraps the bar in a `GlassBottomBar`
/// (blur) and lets the body extend under it. The bar's *painted* height —
/// [height] plus the system bottom inset the bar's internal `SafeArea` adds —
/// is deliberately NOT recomputed anywhere: `Scaffold(extendBody: true)`
/// already hands the body a `MediaQuery` bottom padding of the laid-out bar
/// height, which is what scrollables use to keep their last row reachable.
abstract final class NavigationBarMetrics {
  /// The bar's own height (80 dp), written into
  /// `NavigationBarThemeData.height` so the theme and the framework agree on
  /// one number.
  static const double height = DesignTokens.componentNavigationBarHeight;

  /// `BackdropFilter` blur radius (sigma) behind the bar.
  static const double blurSigma = DesignTokens.componentNavigationBarBlurSigma;

  /// Opacity of the glass tint painted over the blurred backdrop. It — not the
  /// blur — carries the contrast budget of the labels and the indicator.
  static const double tintAlpha = DesignTokens.componentNavigationBarTintAlpha;

  /// How far the bar's plane lifts away from the plain surface toward the
  /// scheme's `surfaceTint` role, so the glass reads as its own plane.
  static const double planeLiftAlpha =
      DesignTokens.componentNavigationBarPlaneLiftAlpha;

  /// The **opaque** glass plane for [scheme] (the keyboard-open state, and the
  /// base [tint] is derived from).
  static Color plane(ColorScheme scheme) => Color.alphaBlend(
    scheme.surfaceTint.withValues(alpha: planeLiftAlpha),
    scheme.surface,
  );

  /// The **translucent** tint the `NavigationBar` itself paints over the
  /// blurred backdrop. Composited over the opaque [plane] it yields exactly
  /// that plane again (the tint is the plane at an alpha), which is why the
  /// keyboard fallback needs no second color decision.
  static Color tint(ColorScheme scheme) =>
      plane(scheme).withValues(alpha: tintAlpha);
}
