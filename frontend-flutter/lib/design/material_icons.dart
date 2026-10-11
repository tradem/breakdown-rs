// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)

import 'package:flutter/material.dart';

/// Shared Material icon vocabulary for the app shell and costume cards.
///
/// Keeping these values in one source prevents a category tile from drifting
/// away from the icon family used by the navigation shell. Category names
/// are user-defined, so unknown names use the deterministic style_outlined
/// fallback until a server-owned icon key is available.
abstract final class BreakdownMaterialIcons {
  // Navigation shell destinations (issue #610: three task-oriented views —
  // Cast | Script | Schedule/Dispo; glossary rows updated in the same
  // change). The former Season/Planen/Kleidung/Mehr pairs are retired with
  // their destinations, not kept as aliases.
  static const shellCastOutline = Icons.face_outlined;
  static const shellCastFilled = Icons.face;
  static const shellScriptOutline = Icons.menu_book_outlined;
  static const shellScriptFilled = Icons.menu_book;
  static const shellScheduleOutline = Icons.calendar_month_outlined;
  static const shellScheduleFilled = Icons.calendar_month;
  static const shellProfile = Icons.account_circle_outlined;

  // Hierarchy context strip segments (issue #548 — glossary:
  // icon + visible text per segment; icons reinforce only).
  static const locationSeason = Icons.video_collection_outlined;
  static const locationBlock = Icons.folder_outlined;
  static const locationEpisode = Icons.movie_creation_outlined;
  static const locationScene = Icons.view_agenda_outlined;

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
