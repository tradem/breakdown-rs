// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

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

  // AI-import cost card (issues #761/#768 — every glyph below reinforces a
  // visible label; the glossary records the pairs and forbids icon-only
  // meaning). Grouped by role so the card cannot drift row by row.

  /// Card header ("Kosten dieses Imports").
  static const aiJobCostTitle = Icons.receipt_long_outlined;

  /// A priced money figure: the hero, the token cost and the Decision-Model
  /// money rows.
  static const aiJobCostToken = Icons.payments_outlined;

  /// The energy figure / energy consumption (never colour-only — the visible
  /// "Wh" / price text carries the meaning).
  static const aiJobCostEnergy = Icons.bolt_outlined;

  /// Extraction usage counts (`Tokens rein`, `Tokens raus`).
  static const aiJobCostUsageIn = Icons.input;
  static const aiJobCostUsageOut = Icons.output;

  /// Cache-hit count.
  static const aiJobCostCached = Icons.cached;

  /// The identity chips: the model and the provider that produced the rows.
  static const aiJobCostModel = Icons.smart_toy_outlined;
  static const aiJobCostProvider = Icons.cloud_outlined;

  /// The provider-degraded state (issue #822): the aggregated "the AI provider
  /// is currently failing" banner and its compact row form. The same glyph the
  /// glossary uses for an unreachable dependency — never colour-only, the
  /// visible label carries the meaning.
  static const aiJobProviderDegraded = Icons.cloud_off;

  /// The snapshot rate rows (`Eingabepreis` / `Ausgabepreis`).
  static const aiJobCostRate = Icons.price_change_outlined;

  /// The `price_as_of` row.
  static const aiJobCostPriceAsOf = Icons.event_outlined;

  /// The Decision-Model component group (issue #768).
  static const aiJobCostDecision = Icons.auto_awesome_outlined;

  /// The image component (issue #673 slot).
  static const aiJobCostImage = Icons.image_outlined;

  /// Informational notes: a refused total, an unpriced component, the energy
  /// cap.
  static const aiJobCostTotalNote = Icons.info_outline;

  /// The honest-unknown cost line (compact jobs list).
  static const aiJobCostUnknown = Icons.help_outline;

  /// A native import that billed no LLM (compact jobs list).
  static const aiJobCostNotApplicable = Icons.money_off_outlined;

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

  /// Scene mood icons for the set shorthand (`I/T`, `A/N`, `I/D`, `I/M`,
  /// `I/AB`, the `A/*` counterparts, and the MIXED forms such as `I/A/T` or
  /// `A/I/T` — issues #721, #834 follow-up).
  ///
  /// Returns the LOCATION icons (one per named location component, in the
  /// shorthand's own order) plus the time-of-day icon, or `null` when the value
  /// is not a parsable shorthand (including `null` itself — a scene without a
  /// mood simply renders no icons).
  ///
  /// A shorthand naming exactly the two DISTINCT locations `I` and `A` (either
  /// order — the canonical `I/A/T` from `INT./EXT.`, and the `A/I/T` a script
  /// uses for "shot outside, then inside") resolves to ONE sensor-door icon:
  /// the scene crosses the threshold, which is a single fact, not two. Every
  /// other combination renders one icon per component, e.g. `A/A/T` → two park
  /// icons.
  ///
  /// Glossary rule: the icons REINFORCE the visible `I/T` text label and never
  /// replace it — always render them next to the text, never alone.
  static ({List<IconData> locations, IconData time})? forSceneMood(String? mood) {
    final value = mood?.trim().toUpperCase();
    if (value == null || value.isEmpty) {
      return null;
    }
    final parts = value.split('/');
    // One time-of-day component plus 1..3 location components.
    if (parts.length < 2 || parts.length > 4) {
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
    final namedLocations = parts.sublist(0, parts.length - 1);
    if (namedLocations.any((part) => part != 'I' && part != 'A')) {
      return null;
    }
    final List<IconData> locations;
    if (namedLocations.length == 2 && namedLocations.toSet().length == 2) {
      locations = const [Icons.sensor_door_outlined];
    } else {
      locations = [
        for (final part in namedLocations)
          part == 'I' ? Icons.home_outlined : Icons.park_outlined,
      ];
    }
    return (locations: locations, time: time);
  }
}
