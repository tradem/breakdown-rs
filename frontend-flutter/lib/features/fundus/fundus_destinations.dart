// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

library;

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';

import '../pieces/piece_detail_screen.dart';
import '../shell/planning_location.dart';

/// THE single deep-link mapping point for the fundus surface (issue #625,
/// design D5) — mirroring the OmniSearch `SearchDestination` contract: every
/// row navigates through the SAME piece detail screen the piece list
/// uses, no parallel route system. The mapping is a pure function so the
/// contract test can exercise it without mounting the destination.

/// The repertoire season the piece detail screen is scoped to: the active
/// season when it is in the piece's repertoire, else the first
/// project-resident repertoire season. `null` only when the repertoire does
/// not intersect the project seasons (an inert tap rather than a wrong
/// scope).
SeasonView? fundusDetailSeason({
  required PieceView piece,
  required SeasonView activeSeason,
  required List<SeasonView> projectSeasons,
}) {
  final byId = {for (final s in projectSeasons) s.id: s};
  if (piece.seasonIds.contains(activeSeason.id)) {
    return byId[activeSeason.id] ?? activeSeason;
  }
  for (final id in piece.seasonIds) {
    final season = byId[id];
    if (season != null) return season;
  }
  return null;
}

/// The destination a fundus row opens.
Widget fundusDestinationScreen({
  required SeasonView detailSeason,
  required PieceView piece,
}) => PieceDetailScreen(season: detailSeason, pieceId: piece.id);

/// The [PlanningLocation] the destination route carries (same as from the
/// piece list — one location contract).
PlanningLocation fundusDestinationLocation(SeasonView detailSeason) =>
    PlanningLocation.season(detailSeason);

/// Pushes the destination (fire-and-forget navigation, no result consumed —
/// the same rule the view rows follow).
void pushFundusDestination(
  BuildContext context,
  SeasonView detailSeason,
  PieceView piece,
) {
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          arguments: fundusDestinationLocation(detailSeason),
        ),
        builder: (_) =>
            fundusDestinationScreen(detailSeason: detailSeason, piece: piece),
      ),
    ),
  );
}
