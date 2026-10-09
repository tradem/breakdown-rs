// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/active_block.dart';
import '../../core/problem_error.dart';
import '../../core/result.dart';
import '../blocks/blocks_controller.dart';
import '../episodes/episodes_controller.dart';
import 'shooting_days_controller.dart';

part 'season_schedule_controller.g.dart';

/// One shooting day of the season-wide schedule view (issue #610, view
/// "Schedule/Dispo") plus the episode DTO that scopes it — the row label
/// names the episode, and the day-board push carries it as navigation
/// context (CQRS boundary, no second projection lookup).
@immutable
class ScheduleDayRow {
  const ScheduleDayRow({
    required this.day,
    required this.block,
    required this.episode,
  });

  final ShootingDayView day;
  final BlockView block;
  final EpisodeView episode;
}

/// The season-wide schedule composition.
@immutable
class SeasonSchedule {
  const SeasonSchedule({
    required this.rows,
    this.failedEpisodes = const [],
    this.failedBlocks = const [],
  });

  const SeasonSchedule.empty()
    : rows = const [],
      failedEpisodes = const [],
      failedBlocks = const [];

  final List<ScheduleDayRow> rows;

  /// Episode ids whose shooting days could not be read.
  final List<String> failedEpisodes;

  /// Block ids whose episode read failed — their days are UNKNOWN, not
  /// empty, so they are tracked at their own level (never stuffed into
  /// [failedEpisodes], which would count episodes the user never saw).
  final List<String> failedBlocks;

  bool get isPartial => failedEpisodes.isNotEmpty || failedBlocks.isNotEmpty;

  bool get isEmpty => rows.isEmpty;
}

/// Merges per-episode day parts into calendar order (pure, unit-tested).
///
/// Days sort by their projected `date` first (the Dispo view is "which
/// scenes are up on which day"), falling back to the episode number and the
/// server's `order_key` for undated days — an undated day keeps a stable
/// place after the dated ones instead of jumping to the top.
List<ScheduleDayRow> mergeScheduleParts(Iterable<ScheduleEpisodePart> parts) {
  final rows = <ScheduleDayRow>[
    for (final part in parts)
      for (final day in part.days)
        ScheduleDayRow(day: day, block: part.block, episode: part.episode),
  ];
  rows.sort((a, b) {
    final ad = a.day.date;
    final bd = b.day.date;
    if (ad == null && bd == null) {
      final byEpisode = a.episode.number.compareTo(b.episode.number);
      if (byEpisode != 0) return byEpisode;
      return a.day.orderKey.compareTo(b.day.orderKey);
    }
    if (ad == null) return 1;
    if (bd == null) return -1;
    final byDate = ad.compareTo(bd);
    if (byDate != 0) return byDate;
    return a.day.orderKey.compareTo(b.day.orderKey);
  });
  return rows;
}

/// Per-episode shooting days read for the schedule view.
@immutable
class ScheduleEpisodePart {
  const ScheduleEpisodePart({
    required this.block,
    required this.episode,
    required this.days,
  });

  final BlockView block;
  final EpisodeView episode;
  final List<ShootingDayView> days;
}

/// Composes the active season's shooting-day board (issue #610).
///
/// `GET /v1/episodes/{id}/shooting-days` is episode-scoped, so the season
/// view composes blocks → episodes → days through the existing
/// authenticated seams. Failure semantics mirror the Script composition:
/// an unreadable block list is a `Left` (the view errors), a failed episode
/// read or a failed day read yields a visible partial-load notice — at the
/// level that actually failed.
///
/// A sticky block scope for THIS season narrows the board to that block; a
/// scope from another season is ignored (same reuse rule as the scope chip).
@riverpod
Future<Result<SeasonSchedule>> seasonScheduleFetch(
  Ref ref,
  SeasonView season,
) async {
  final scope = ref.watch(activeBlockProvider);
  final blocksResult = await ref.watch(
    blocksListFetchProvider(season.id).future,
  );
  return blocksResult.match(
    (error) async => Left<ProblemError, SeasonSchedule>(error),
    (blocks) async {
      final scoped = scope != null && scope.seasonId == season.id;
      final relevantBlocks = scoped
          ? blocks.where((block) => block.id == scope.blockId).toList()
          : blocks;

      final parts = <ScheduleEpisodePart>[];
      final failedEpisodes = <String>[];
      final failedBlocks = <String>[];
      for (final block in relevantBlocks) {
        final episodesResult = await ref.watch(
          episodesListFetchProvider(block.id, season.id).future,
        );
        // A block whose episodes could NOT be read is tracked as a failed
        // block: its shooting days are unknown, not empty.
        final episodes = episodesResult.match((_) {
          failedBlocks.add(block.id);
          return const <EpisodeView>[];
        }, (rows) => rows);
        for (final episode in episodes) {
          final daysResult = await ref.watch(
            shootingDaysListFetchProvider(episode.id).future,
          );
          daysResult.match(
            (_) => failedEpisodes.add(episode.id),
            (days) => parts.add(
              ScheduleEpisodePart(block: block, episode: episode, days: days),
            ),
          );
        }
      }

      return Right<ProblemError, SeasonSchedule>(
        SeasonSchedule(
          rows: mergeScheduleParts(parts),
          failedEpisodes: failedEpisodes,
          failedBlocks: failedBlocks,
        ),
      );
    },
  );
}
