// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)

import 'package:flutter/material.dart';

/// Shared Material icon vocabulary for the app shell and costume cards.
///
/// Keeping these values in one source prevents a category tile from drifting
/// away from the icon family used by the navigation shell. Category names
/// are user-defined, so unknown names use the deterministic checkroom
/// fallback until a server-owned icon key is available.
abstract final class BreakdownMaterialIcons {
  static const shellHomeOutline = Icons.home_outlined;
  static const shellHomeFilled = Icons.home;
  static const shellPlanenOutline = Icons.edit_calendar_outlined;
  static const shellPlanenFilled = Icons.edit_calendar;
  static const shellCostumesOutline = Icons.checkroom_outlined;
  static const shellCostumesFilled = Icons.checkroom;
  static const shellMore = Icons.more_horiz;

  static IconData forCostumeCategory(String? categoryName) {
    final normalized = categoryName?.trim().toLowerCase();
    return switch (normalized) {
      'oberteil' || 'top' || 'tops' => Icons.checkroom_outlined,
      'unterteil' || 'bottom' || 'bottoms' => Icons.vertical_align_bottom,
      'schuhe' || 'shoes' || 'footwear' => Icons.ice_skating_outlined,
      'jacke' || 'jacket' || 'jackets' => Icons.dry_cleaning_outlined,
      'accessoires' || 'accessories' => Icons.watch_outlined,
      _ => Icons.style_outlined,
    };
  }
}
