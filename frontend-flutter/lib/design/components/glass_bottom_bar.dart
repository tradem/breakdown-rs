// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import 'package:frontend_flutter/design/navigation_bar_metrics.dart';

/// The compact morphology's **glass bar surface** (issue #991): a blurred,
/// tinted backdrop behind the shell's `NavigationBar`, so content scrolls
/// *under* a translucent bar instead of a permanent opaque band.
///
/// Three things make the effect visible, and all three live outside this
/// widget — dropping one silently degrades the bar to a flat tinted strip:
///
/// 1. the bar paints **nothing opaque**: `theme.dart`'s
///    `NavigationBarThemeData` supplies the translucent tint and pins
///    elevation/shadow/surface-tint off;
/// 2. the compact `Scaffold` sets `extendBody: true`, so the body really runs
///    behind the bar (a transparent bar over the Scaffold's own background
///    would only reveal that background);
/// 3. the body's bottom inset is the laid-out bar height (which `Scaffold`
///    provides for an extended body), so no list row hides under the bar.
///
/// This widget owns only the blur and the keyboard fallback. It deliberately
/// does NOT own the bar's color: a color decision belongs in `theme.dart` /
/// [NavigationBarMetrics], never in a shell call site.
///
/// Semantics are untouched — the bar keeps its `Tab N of 3` traversal, its
/// per-destination keys and its 48 dp touch targets; the blur is purely
/// decorative, with the tint (not the blur) carrying the contrast budget.
class GlassBottomBar extends StatelessWidget {
  const GlassBottomBar({super.key, required this.child});

  /// The bar itself — the shell's `NavigationBar`, which paints the tinted
  /// background.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Issue #991 resolved question 3: while the keyboard is open the bar falls
    // back to OPAQUE. A translucent bar over live text fields reads as a hole
    // in the layout, and Android may reveal content under it in a way that
    // looks unintended. The child's tint is the plane at `tintAlpha`, so
    // compositing it over that same opaque plane yields exactly the plane —
    // one color decision, two states, no second literal.
    //
    // The blur is dropped with it: an opaque bar has nothing to blur, and the
    // filter is the most expensive widget in the shell (a save-layer per
    // frame on every destination), so the fallback is also the cheap path.
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      return ColoredBox(
        color: NavigationBarMetrics.plane(scheme),
        child: child,
      );
    }
    final double sigma = NavigationBarMetrics.blurSigma;
    // ClipRect is mandatory: an unclipped BackdropFilter blurs an unbounded
    // region, and the bar is the only thing bounding the effect here.
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      ),
    );
  }
}
