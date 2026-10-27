// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: space-bunny-free (opencode-go)

import 'package:flutter/material.dart';

/// Shared Material icon vocabulary for the app shell and piece cards.
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

  /// Scene mood icons for the canonical set shorthand (`I/T`, `A/N`, `I/D`,
  /// `I/M`, `I/AB`, the `A/*` counterparts, combined `I/A/T` — issue #721).
  ///
  /// Returns `(interior/exterior icon, time-of-day icon)` or `null` when the
  /// value is not a parsable shorthand (including `null` itself — a scene
  /// without a mood simply renders no icons). The combined `I/A` component of
  /// the only canonical three-component value `I/A/T` resolves to the
  /// sensor-door icon instead of the plain interior/exterior pair.
  ///
  /// Glossary rule: the icons REINFORCE the visible `I/T` text label and
  /// never replace it — always render them next to the text, never alone.
  static (IconData, IconData)? forSceneMood(String? mood) {
    final value = mood?.trim().toUpperCase();
    if (value == null || value.isEmpty) {
      return null;
    }
    final parts = value.split('/');
    if (parts.isEmpty || parts.length > 3) {
      return null;
    }
    final IconData location;
    if (parts.length == 3) {
      if (parts[0] != 'I' || parts[1] != 'A') {
        return null;
      }
      location = Icons.sensor_door_outlined;
    } else if (parts.first == 'I') {
      location = Icons.home_outlined;
    } else if (parts.first == 'A') {
      location = Icons.park_outlined;
    } else {
      return null;
    }
    final IconData time;
    switch (parts.last) {
      case 'T':
        time = Icons.wb_sunny_outlined;
      case 'N':
        time = Icons.dark_mode_outlined;
      case 'D' || 'M':
        time = Icons.wb_twilight_outlined;
      case 'AB':
        time = Icons.bedtime_outlined;
      default:
        return null;
    }
    return (location, time);
  }
}
