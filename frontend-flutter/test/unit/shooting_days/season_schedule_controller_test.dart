// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny (opencode-go)

// Tier 1 unit tests for the season-wide schedule composition (issue #610,
// view "Schedule/Dispo"): pure merge logic plus the provider's Ok/Err/
// partial branches against fake fetch seams.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:one_of/one_of.dart';

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/features/episodes/episodes_controller.dart';
import 'package:frontend_flutter/features/shooting_days/season_schedule_controller.dart';
import 'package:frontend_flutter/features/shooting_days/shooting_days_controller.dart';

BlockView _block(String id, int number) => BlockView(
  (b) => b
    ..id = id
    ..number = number
    ..seasonId = 'season-1'
    ..projectId = 'project-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

EpisodeView _episode(String id, int number, String blockId) => EpisodeView(
  (b) => b
    ..id = id
    ..number = number
    ..blockId = blockId
    ..projectId = 'project-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

ShootingDayView _day(
  String id,
  String episodeId, {
  required String orderKey,
  Date? date,
  String? label,
}) => ShootingDayView(
  (b) => b
    ..id = id
    ..episodeId = episodeId
    ..orderKey = orderKey
    ..date = date
    ..label = label
    ..archived = false
    ..source_.replace(
      ShootingDaySource((s) => s..oneOf = OneOf.fromValue1(value: 'Manual')),
    )
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

SeasonView _season() => SeasonView(
  (b) => b
    ..archived = false
    ..id = 'season-1'
    ..number = 1
    ..projectId = 'project-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

void main() {
  group('mergeScheduleParts (pure)', () {
    test('sorts days by calendar date ACROSS episodes', () {
      final rows = mergeScheduleParts([
        ScheduleEpisodePart(
          block: _block('b-1', 1),
          episode: _episode('e-2', 2, 'b-1'),
          days: [_day('d-3', 'e-2', orderKey: 'a', date: Date(2026, 3, 2))],
        ),
        ScheduleEpisodePart(
          block: _block('b-1', 1),
          episode: _episode('e-1', 1, 'b-1'),
          days: [
            _day('d-1', 'e-1', orderKey: 'a', date: Date(2026, 3, 1)),
            _day('d-2', 'e-1', orderKey: 'b', date: Date(2026, 3, 1)),
          ],
        ),
      ]);

      expect(rows.map((r) => r.day.id).toList(), ['d-1', 'd-2', 'd-3']);
    });

    test('an undated day keeps a stable place AFTER the dated ones', () {
      final rows = mergeScheduleParts([
        ScheduleEpisodePart(
          block: _block('b-1', 1),
          episode: _episode('e-1', 1, 'b-1'),
          days: [
            _day('d-none', 'e-1', orderKey: 'a'),
            _day('d-1', 'e-1', orderKey: 'b', date: Date(2026, 3, 1)),
          ],
        ),
      ]);

      expect(rows.map((r) => r.day.id).toList(), ['d-1', 'd-none']);
    });

    test('no parts yields no rows (not a crash)', () {
      expect(mergeScheduleParts(const []), isEmpty);
    });
  });

  group('seasonScheduleFetchProvider', () {
    late ProviderContainer container;

    Result<List<BlockView>> blocksResult = Right(const []);
    Result<List<EpisodeView>> episodesResult = Right(const []);
    Result<List<ShootingDayView>> daysResult = Right(const []);

    Future<void> setUpContainer() async {
      container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          blocksListFetchProvider('season-1')
              .overrideWith((ref) async => blocksResult),
          episodesListFetchProvider(
            'b-1',
            'season-1',
          ).overrideWith((ref) async => episodesResult),
          shootingDaysListFetchProvider('e-1')
              .overrideWith((ref) async => daysResult),
        ],
      );
      addTearDown(container.dispose);
    }

    test('Ok: composes the season days in calendar order', () async {
      blocksResult = Right([_block('b-1', 1)]);
      episodesResult = Right([_episode('e-1', 1, 'b-1')]);
      daysResult = Right([
        _day('d-2', 'e-1', orderKey: 'b', date: Date(2026, 3, 2)),
        _day('d-1', 'e-1', orderKey: 'a', date: Date(2026, 3, 1)),
      ]);
      await setUpContainer();

      final result = await container.read(
        seasonScheduleFetchProvider(_season()).future,
      );

      final schedule = result.getRight().toNullable()!;
      expect(schedule.isPartial, isFalse);
      expect(schedule.rows.map((r) => r.day.id).toList(), ['d-1', 'd-2']);
      // The parent DTOs travel with the row (day-board push context).
      expect(schedule.rows.first.episode.id, 'e-1');
      expect(schedule.rows.first.block.id, 'b-1');
    });

    test('Err: an unreadable block list surfaces as Left', () async {
      blocksResult = const Left(ProblemError(code: 'blocks.network'));
      await setUpContainer();

      final result = await container.read(
        seasonScheduleFetchProvider(_season()).future,
      );

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable()!.code, 'blocks.network');
    });

    test('partial: a failing EPISODE-LIST read degrades visibly too', () async {
      // CodeRabbit review (PR #620): a failed `episodesListFetch` used to
      // collapse to `[]` with no partial marker — the board then claimed to
      // be complete while silently omitting a whole block.
      blocksResult = Right([_block('b-1', 1)]);
      episodesResult = const Left(ProblemError(code: 'episodes.network'));
      await setUpContainer();

      final result = await container.read(
        seasonScheduleFetchProvider(_season()).future,
      );

      final schedule = result.getRight().toNullable()!;
      expect(schedule.isPartial, isTrue);
      expect(schedule.failedBlocks, ['b-1']);
      expect(schedule.failedEpisodes, isEmpty);
    });

    test('partial: a failing episode degrades visibly', () async {
      blocksResult = Right([_block('b-1', 1)]);
      episodesResult = Right([_episode('e-1', 1, 'b-1')]);
      daysResult = const Left(ProblemError(code: 'shooting_days.forbidden'));
      await setUpContainer();

      final result = await container.read(
        seasonScheduleFetchProvider(_season()).future,
      );

      final schedule = result.getRight().toNullable()!;
      expect(schedule.isPartial, isTrue);
      expect(schedule.failedEpisodes, ['e-1']);
    });
  });
}
