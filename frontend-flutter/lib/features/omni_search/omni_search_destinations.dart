// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

library;

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';

import '../characters/role_extract_screen.dart';
import '../costumes/costume_detail_screen.dart';
import '../scenes/scene_detail_screen.dart';
import '../shooting_days/shooting_days_screen.dart';
import '../shell/planning_location.dart';
import 'omni_search_model.dart';

/// THE single deep-link mapping point (design D4, tasks §3.2): every
/// search result row navigates through the same destination screens the
/// #610 navigation views use — no parallel route system. This change landed
/// AFTER the #610 redesign, so the targets ARE the redesigned screens.
///
/// The mapping is device-agnostic (a pure widget factory plus a push
/// helper) so the deep-link CONTRACT test (tasks 7.2) can exercise every
/// referenced destination directly and FAIL LOUDLY if the #610 redesign
/// renames or removes one — without mounting a shell.

/// The destination a result row opens. Pure widget factory entry: the
/// [RouteSettings] use the same [PlanningLocation] arguments the source
/// views push (the shell context strip deepens exactly the same way).
Widget omniSearchDestinationScreen({
  required SeasonView season,
  required OmniSearchHit hit,
}) => switch (hit) {
  SceneOmniHit(:final scene, :final episode) =>
    // Script-view semantics: scene detail with the hierarchy chain built
    // from the DTOs the hit carried (read-DTO join, never a second
    // projection lookup — CQRS boundary).
    SceneDetailScreen(
      seasonId: season.id,
      episodeId: episode.id,
      sceneId: scene.id,
    ),
  CharacterOmniHit(:final character) =>
    // Cast-view semantics (issue #611): the character row lands on the
    // role extract route.
    RoleExtractScreen(
      key: Key('role-extract-${character.id}'),
      season: season,
      characterId: character.id,
    ),
  CostumeOmniHit(:final costume) =>
    // The costume detail route — the costume detail/assignment context
    // (the same seam `CostumeDetailScreen` documents for routed callers).
    CostumeDetailScreen(season: season, costumeId: costume.id),
  ShootingDayOmniHit(:final episode) =>
    // Schedule-view semantics: the parent episode's day board.
    ShootingDaysScreen(episode: episode, seasonId: season.id),
};

/// The [PlanningLocation] the destination route carries (same as from the
/// originating view — one location contract).
PlanningLocation omniSearchDestinationLocation(
  SeasonView season,
  OmniSearchHit hit,
) => switch (hit) {
  SceneOmniHit(:final scene, :final episode, :final block) =>
    PlanningLocation.scene(season, block, episode, scene),
  CharacterOmniHit() => PlanningLocation.season(season),
  CostumeOmniHit() => PlanningLocation.season(season),
  ShootingDayOmniHit(:final episode, :final block) => PlanningLocation.episode(
    season,
    block,
    episode,
  ),
};

/// Pushes [hit]'s destination (fire-and-forget navigation, no result
/// consumed — the same rule the view rows follow).
void pushOmniSearchDestination(
  BuildContext context,
  SeasonView season,
  OmniSearchHit hit,
) {
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          arguments: omniSearchDestinationLocation(season, hit),
        ),
        builder: (_) => omniSearchDestinationScreen(season: season, hit: hit),
      ),
    ),
  );
}
