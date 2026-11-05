// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:flutter/material.dart';

import '../header_metrics.dart';

/// The one header for every pushed screen (issue #824).
///
/// A screen's app bar used to be a hand-rolled `AppBar(title: Text(...))` at
/// 41 sites: no shared height (every bar fell back to the untokenized M3
/// default of 56 dp), no title rule (a whole sentence in
/// `scene_detail_screen`'s title was clipped instead of ellipsized) and no
/// place that could have stopped the shell's status-bar inset being applied a
/// second time.
///
/// This widget is that place:
///
/// * **height** comes from the theme (`appBarTheme.toolbarHeight`, derived in
///   [HeaderMetrics] from the typography and spacing tokens) — the call site
///   never passes one;
/// * **title style** comes from the theme (`appBarTheme.titleTextStyle`);
/// * **text titles are single-line with an ellipsis** ([BreakdownAppBar]) so a
///   header can never be taller than its spec and long text is truncated
///   rather than clipped;
/// * the default **back affordance** is Material's, which keeps its 48 dp
///   touch target because the toolbar is never shorter than that floor.
///
/// Composite titles (a badge plus a label, a two-part inline header) use
/// [BreakdownAppBar.custom] and own their overflow rule, because a `Row` of
/// widgets has no single text to ellipsize.
class BreakdownAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// A text header — the common case. The text is rendered on one line with a
  /// trailing ellipsis.
  const BreakdownAppBar({
    super.key,
    required String title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
  }) : _label = title,
       _titleWidget = null;

  /// A composite header (badge + label). The caller owns the overflow rule.
  const BreakdownAppBar.custom({
    super.key,
    required Widget title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
  }) : _label = null,
       _titleWidget = title;

  /// The text form's label (null for a composite header).
  final String? _label;

  /// The composite form's title widget (null for a text header).
  final Widget? _titleWidget;

  /// Trailing actions — any widget (icon buttons, labeled text buttons, a
  /// switch row).
  final List<Widget>? actions;

  /// Replaces the automatically implied back button (e.g. the setup wizard's
  /// confirm-then-leave affordance).
  final Widget? leading;

  /// `false` suppresses the implied back button on a route that has one.
  final bool automaticallyImplyLeading;

  /// Matches [AppBar.preferredSize] for a bar without a `bottom`: the theme's
  /// toolbar height, i.e. [HeaderMetrics.toolbarHeight].
  static const Size _preferredSize = Size.fromHeight(
    HeaderMetrics.toolbarHeight,
  );

  @override
  Size get preferredSize => _preferredSize;

  @override
  Widget build(BuildContext context) => AppBar(
    title: _titleWidget ?? _SingleLineTitle(_label!),
    actions: actions,
    leading: leading,
    automaticallyImplyLeading: automaticallyImplyLeading,
  );
}

/// The header title text: one line, ellipsized. Kept as a private widget so a
/// screen cannot accidentally reintroduce a wrapping title.
class _SingleLineTitle extends StatelessWidget {
  const _SingleLineTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false);
}
