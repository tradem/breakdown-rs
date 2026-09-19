// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/episode_repository.dart';

EpisodeView _episode(
  String id, {
  required String blockId,
  required String seriesId,
  required int number,
}) => EpisodeView(
  (b) => b
    ..id = id
    ..blockId = blockId
    ..number = number
    ..seriesId = seriesId
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

void main() {
  group('EpisodeRepository.applySeriesSnapshotFrom', () {
    late CacheDatabase db;
    late EpisodeRepository repo;

    setUp(() {
      db = CacheDatabase(NativeDatabase.memory());
      repo = EpisodeRepository(BreakdownApi(), EpisodeCacheDao(db));
    });

    tearDown(() => db.close());

    test(
      'on Right stores per-block snapshots AND clears a cached block absent '
      'from the series snapshot (CodeRabbit #464 stale-episode fix)',
      () async {
        // First call seeds block A and block B episodes in the series cache.
        await repo.applySeriesSnapshotFrom(
          Right<ProblemError, List<EpisodeView>>([
            _episode('eA1', blockId: 'blockA', seriesId: 'series-1', number: 1),
            _episode('eB1', blockId: 'blockB', seriesId: 'series-1', number: 2),
          ]),
          seriesId: 'series-1',
        );
        expect(
          (await repo.readCached('blockB')).getRight().toNullable()!.length,
          1,
        );

        // The series snapshot now contains ONLY block A (block B's episodes
        // were all removed server-side). groupByBlock creates an entry only
        // for block A; block B must be cleared with an empty snapshot, not
        // keep its stale rows.
        await repo.applySeriesSnapshotFrom(
          Right<ProblemError, List<EpisodeView>>([
            _episode('eA2', blockId: 'blockA', seriesId: 'series-1', number: 3),
          ]),
          seriesId: 'series-1',
        );

        // Block A reflects the new snapshot (snapshot-replace), block B is
        // empty.
        final blockA = (await repo.readCached('blockA'))
            .getRight()
            .toNullable()!
            .map((e) => e.number)
            .toList();
        expect(blockA, [3]);
        final blockB = (await repo.readCached('blockB'))
            .getRight()
            .toNullable()!;
        expect(blockB, isEmpty);
      },
    );

    test('on Left leaves the cache untouched (no partial writes)', () async {
      await repo.applySeriesSnapshotFrom(
        Right<ProblemError, List<EpisodeView>>([
          _episode('eA1', blockId: 'blockA', seriesId: 'series-1', number: 1),
        ]),
        seriesId: 'series-1',
      );

      final res = await repo.applySeriesSnapshotFrom(
        const Left<ProblemError, List<EpisodeView>>(
          ProblemError(code: 'transport.down'),
        ),
        seriesId: 'series-1',
      );

      expect(res.isLeft(), isTrue);
      final cached = (await repo.readCached('blockA')).getRight().toNullable()!;
      expect(cached.map((e) => e.number).toList(), [1]);
    });
  });
}
