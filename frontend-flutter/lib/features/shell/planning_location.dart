// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';

/// Where in the Season → Block → Episode → Scene hierarchy the user is
///
/// A plain `const` **sealed ladder** — deliberately NOT freezed, NOT a wire
/// DTO, no `build_runner` round-trip: this is a navigation concern and must
/// never become a projection type. It holds the ancestor read DTOs it was
/// built from and derives labels in one place instead of ten screens.
///
/// The key property is the **typed deepening ladder**: each step requires
/// the previous one, so a non-contiguous chain (e.g. an episode without its
/// block) is a compile error instead of a runtime surprise. Deepening goes
/// through the typed subclasses (`SeasonLocation.withBlock`,
/// `BlockLocation.withEpisode`, `EpisodeLocation.withScene`) so a runtime
/// extension keeps the contiguity guarantee of the constructors.
///
/// **Why the DTOs and not pre-rendered label strings:** the CQRS boundary
/// requires that context comes "from the DTO the user acted on — never from
/// a second projection lookup" (AGENTS.md §1). Holding the DTOs keeps the
/// location buildable with zero extra reads; holding strings would force a
/// re-derivation path that invites a second lookup.
///
/// This file is tier-1 pure: no Flutter, no l10n import — copy flows in via
/// [PlanningLocationCopy] (production adapter: `location_strip.dart`).
///
/// The location travels in `RouteSettings.arguments` of every hierarchy
/// push (`planning_location_route_observer.dart` resolves it from the
/// topmost route of a navigator). Season-direct screens (costumes,
/// characters, costume categories, character detail) take the **season
/// level only** — they are not part of the block/episode chain and must not
/// pretend to be.

/// One hierarchy segment's level — the strip maps it to a glossary icon.
enum PlanningLevel { season, block, episode, scene }

/// The localized copy the location needs to render labels.
///
/// Kept as an interface (not `AppLocalizations`) so the ladder stays
/// unit-testable without Flutter imports; tests supply a fake.
abstract interface class PlanningLocationCopy {
  /// Season title or the number fallback (`seasonsDefaultTitle`).
  String seasonLabel(String? title, int number);

  /// `Block {n}` (`blockTileLabel`).
  String blockLabel(int number);

  /// Episode name or `Episode {n}` (`episodeTileLabel`).
  String episodeLabel(int number, String? name);

  /// Scene summary or `Szene {n}` (`sceneTileLabel`).
  String sceneLabel(int? sceneNumber, String? summary);
}

/// One rendered strip segment: its hierarchy level (icon source) and label.
typedef PlanningSegment = (PlanningLevel, String);

sealed class PlanningLocation {
  const PlanningLocation();

  const factory PlanningLocation.season(SeasonView season) = SeasonLocation;

  const factory PlanningLocation.block(SeasonView season, BlockView block) =
      BlockLocation;

  const factory PlanningLocation.episode(
    SeasonView season,
    BlockView block,
    EpisodeView episode,
  ) = EpisodeLocation;

  const factory PlanningLocation.scene(
    SeasonView season,
    BlockView block,
    EpisodeView episode,
    SceneView scene,
  ) = SceneLocation;

  /// The season every level is anchored to (the chip's foreign-season
  /// check reads it).
  String get seasonId;

  /// Labels top-down (season first). The strip maps levels to icons.
  List<PlanningSegment> segments(PlanningLocationCopy copy);

  /// The flattened path for the strip's merged semantics node.
  String pathLabel(PlanningLocationCopy copy, {String separator = ' → '}) =>
      segments(copy).map((s) => s.$2).join(separator);
}

/// Viewing a season's blocks (`BlocksScreen`) — or any season-direct screen.
class SeasonLocation extends PlanningLocation {
  const SeasonLocation(this.season);

  final SeasonView season;

  @override
  String get seasonId => season.id;

  @override
  List<PlanningSegment> segments(PlanningLocationCopy copy) => [
    (PlanningLevel.season, copy.seasonLabel(season.title, season.number)),
  ];

  /// Requires this season — a contiguous deepening, not a loose constructor.
  BlockLocation withBlock(BlockView block) => BlockLocation(season, block);

  @override
  bool operator ==(Object other) =>
      other is SeasonLocation && other.season == season;

  @override
  int get hashCode => Object.hash('season', season);

  @override
  String toString() => 'SeasonLocation(${season.id})';
}

/// Viewing a block's episodes (`EpisodesScreen`).
class BlockLocation extends PlanningLocation {
  const BlockLocation(this.season, this.block);

  final SeasonView season;
  final BlockView block;

  @override
  String get seasonId => season.id;

  @override
  List<PlanningSegment> segments(PlanningLocationCopy copy) => [
    (PlanningLevel.season, copy.seasonLabel(season.title, season.number)),
    (PlanningLevel.block, copy.blockLabel(block.number)),
  ];

  EpisodeLocation withEpisode(EpisodeView episode) =>
      EpisodeLocation(season, block, episode);

  @override
  bool operator ==(Object other) =>
      other is BlockLocation && other.season == season && other.block == block;

  @override
  int get hashCode => Object.hash('block', season, block);

  @override
  String toString() => 'BlockLocation(${season.id}, ${block.id})';
}

/// Viewing an episode's scenes (`ScenesScreen`) or its shooting days.
class EpisodeLocation extends PlanningLocation {
  const EpisodeLocation(this.season, this.block, this.episode);

  final SeasonView season;
  final BlockView block;
  final EpisodeView episode;

  @override
  String get seasonId => season.id;

  @override
  List<PlanningSegment> segments(PlanningLocationCopy copy) => [
    (PlanningLevel.season, copy.seasonLabel(season.title, season.number)),
    (PlanningLevel.block, copy.blockLabel(block.number)),
    (PlanningLevel.episode, copy.episodeLabel(episode.number, episode.name)),
  ];

  SceneLocation withScene(SceneView scene) =>
      SceneLocation(season, block, episode, scene);

  @override
  bool operator ==(Object other) =>
      other is EpisodeLocation &&
      other.season == season &&
      other.block == block &&
      other.episode == episode;

  @override
  int get hashCode => Object.hash('episode', season, block, episode);

  @override
  String toString() =>
      'EpisodeLocation(${season.id}, ${block.id}, '
      '${episode.id})';
}

/// Viewing a scene's detail or its shooting-day board.
class SceneLocation extends PlanningLocation {
  const SceneLocation(this.season, this.block, this.episode, this.scene);

  final SeasonView season;
  final BlockView block;
  final EpisodeView episode;
  final SceneView scene;

  @override
  String get seasonId => season.id;

  @override
  List<PlanningSegment> segments(PlanningLocationCopy copy) => [
    (PlanningLevel.season, copy.seasonLabel(season.title, season.number)),
    (PlanningLevel.block, copy.blockLabel(block.number)),
    (PlanningLevel.episode, copy.episodeLabel(episode.number, episode.name)),
    (PlanningLevel.scene, copy.sceneLabel(scene.sceneNumber, scene.summary)),
  ];

  @override
  bool operator ==(Object other) =>
      other is SceneLocation &&
      other.season == season &&
      other.block == block &&
      other.episode == episode &&
      other.scene == scene;

  @override
  int get hashCode => Object.hash('scene', season, block, episode, scene);

  @override
  String toString() =>
      'SceneLocation(${season.id}, ${block.id}, '
      '${episode.id}, ${scene.id})';
}

/// Extracts a location from a route's `RouteSettings.arguments` — null for
/// every non-hierarchy route (tab roots, sheets, config screens), which is
/// the strip's "hidden" contract. Tolerant: a wrong-typed argument is not a
/// crash, it is "no location".
PlanningLocation? locationFromArguments(Object? arguments) =>
    arguments is PlanningLocation ? arguments : null;
