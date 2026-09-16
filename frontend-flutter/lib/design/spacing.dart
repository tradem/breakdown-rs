// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)

import 'package:frontend_flutter/design/gen/design_tokens.g.dart';

/// Named spacing tokens (logical px) for the shell and dialog surfaces
/// (spec `flutter-design-tokens`, design.md §5).
///
/// Values delegate to the generated DTCG dimension tokens
/// (`design/tokens/size.json` → `design_tokens.g.dart`, rebuilt by
/// `scripts/build-tokens.sh`) — the values' origin is the token source,
/// the public API (field names/types) is unchanged.
///
/// Widgets use these instead of numeric literals so spacing stays reviewable
/// and consistent. Existing screens are NOT retro-fitted here (honest scope
/// note — e.g. the seasons empty-state `SizedBox(height: 160)` stays until
/// `flutter-hierarchy-navigation` touches that area).
abstract final class AppSpacing {
  static const double space2 = DesignTokens.sizeSpace2;
  static const double space4 = DesignTokens.sizeSpace4;
  static const double space8 = DesignTokens.sizeSpace8;
  static const double space12 = DesignTokens.sizeSpace12;
  static const double space16 = DesignTokens.sizeSpace16;
  static const double space24 = DesignTokens.sizeSpace24;
  static const double space32 = DesignTokens.sizeSpace32;
}
