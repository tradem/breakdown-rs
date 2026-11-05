// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:flutter/material.dart';

/// Bottom clearance a docked/floating plus action needs so the last list row
/// never renders beneath it: the extended FAB's 56 height + its 16 margin
/// above the surface edge + 8 breathing room (issue #623, generalized by
/// #823 to every surface that carries the action).
const double kPlusActionFabBottomClearance = 80;

/// The quick-create **plus action** (issues #612 and #823).
///
/// One affordance, two homes: the Script destination's shell FAB and the
/// AI-import jobs screen's Import action. Both render through this widget so
/// the accessible contract and the FAB's own shape cannot drift:
///
/// * an explicit accessible **BUTTON** role — `FloatingActionButton.extended`
///   builds on `RawMaterialButton`/`InkWell`, which expose the tap action but
///   NOT the semantics button flag, so a screen reader would announce the
///   affordance without the „Schaltfläche" role (CodeRabbit review #623);
/// * a **visible label** ([label]) — icon-only affordances are forbidden
///   (glossary rule); the plus glyph reinforces the label, it never replaces
///   it;
/// * a caller-supplied [fabKey] on the [FloatingActionButton] itself, so
///   "one FAB" assertions stay unambiguous per surface
///   (`shell-plus-fab` / `ai-jobs-plus-fab`);
/// * the caller owns WHEN it renders — in particular the client-side
///   AUTHZ-GATE mirror (Decision D6): the quick-create sheet is
///   `Requirement::Authenticated`-gated UI, so a pending/erroring/signed-out
///   session renders no plus action at all. That gate stays at the call site
///   (and so does its `AUTHZ-GATE` comment) because the two surfaces are gated
///   independently.
class PlusActionFab extends StatelessWidget {
  const PlusActionFab({
    super.key,
    required this.fabKey,
    required this.label,
    required this.onPressed,
  });

  /// Key of the [FloatingActionButton] itself (the widget named by tests).
  ///
  /// Deliberately a separate parameter instead of the widget's own [key]: the
  /// key belongs on the FAB node, and reusing one key for both the wrapper and
  /// its child would make `find.byKey` match twice.
  final Key fabKey;

  /// The action's visible label — one of `shellPlusFabLabel` („Erstellen") or
  /// `navAiImport` („Import"), depending on the surface and what the action
  /// can actually do there.
  final String label;

  /// Opens the surface's quick-create sheet. The sheet pops and the chosen
  /// entry pushes the full-screen flow; this callback issues no request.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: FloatingActionButton.extended(
      key: fabKey,
      onPressed: onPressed,
      icon: const Icon(Icons.add),
      label: Text(label),
    ),
  );
}
