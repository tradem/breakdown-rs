// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:material_ui/material_ui.dart';

/// Extends [base] by the ambient bottom inset (issue #991).
///
/// The compact shell's `Scaffold(extendBody: true)` delivers the glass bottom
/// bar's reservation as `MediaQuery.padding.bottom`, and Flutter folds that
/// inset into a scrollable's padding ONLY when the scrollable passes no
/// `padding` of its own (`BoxScrollView.buildSlivers`, and the same rule for a
/// `CustomScrollView`'s slivers). A screen that states its own
/// `EdgeInsets.all(16)` therefore opts out of the reservation and lets its last
/// row rest BEHIND the bar — the failure issue #991's "scroll under" change
/// introduced for every consumer that used to be physically bounded above the
/// bar.
///
/// So a scrollable inside the shell passes its own padding through here: [base]
/// is counted once, the ambient inset is added once at the bottom. The inset is
/// whatever the shell derived (bar's painted height, plus the plus action's
/// clearance on the destination that renders it), never a literal — a screen
/// outside the shell composites over a zero inset and is unaffected.
EdgeInsets withBottomInset(BuildContext context, EdgeInsets base) =>
    base.copyWith(bottom: base.bottom + MediaQuery.paddingOf(context).bottom);
