// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

/// The one file that still speaks the **legacy** Material API (issue #975).
///
/// Everything hand-written imports `package:material_ui/material_ui.dart`
/// since Flutter 3.50 deprecated `package:flutter/material.dart`. The single
/// exception is `flutter_code_editor` — the engine under the XML prompt editor
/// (`lib/design/components/xml_prompt_editor.dart`) — which still builds a
/// legacy `TextField` and therefore needs three things a `material_ui` app does
/// not provide: a legacy `Material` ancestor, a legacy `Theme`, and legacy
/// `MaterialLocalizations`. Without them it throws "No Material widget found",
/// and its test subtree degenerates into "ScrollController not attached to any
/// scroll views".
///
/// [legacyMaterialSubtree] supplies exactly those three, wrapping the legacy
/// editor in `MaterialUiCompatibilityBridge` (which maps the ambient
/// `material_ui` theme onto the legacy `ThemeData` and installs the legacy
/// localizations) plus a transparent legacy `Material` for the ancestor check.
///
/// The two `// ignore: deprecated_member_use` markers below are the *only*
/// suppression this migration adds, and they are deliberately file-local rather
/// than an `analysis_options.yaml`-wide ignore: they mark genuinely deprecated
/// API that cannot be avoided yet. This file disappears — together with the
/// wrapper calls — as soon as `flutter_code_editor` migrates upstream; a new
/// legacy importer anywhere else is a review reject, not a precedent.
library;

// ignore: deprecated_member_use
import 'package:flutter/material.dart' as legacy;
import 'package:material_ui/material_ui.dart';

/// Wraps a legacy-material [child] so it resolves the theme, the localizations
/// and the `Material` ancestor its widgets assert on.
///
/// Presentation must not change: the bridge maps the ambient modern
/// `ThemeData` onto the legacy one, and `MaterialType.transparency` paints
/// nothing, so the wrapped subtree renders as it did before the migration
/// (the XML prompt editor's goldens are the witness).
Widget legacyMaterialSubtree({required Widget child}) {
  // ignore: deprecated_member_use
  return MaterialUiCompatibilityBridge(
    child: legacy.Material(
      type: legacy.MaterialType.transparency,
      child: child,
    ),
  );
}
