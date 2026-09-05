// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/cache_ttl.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/src/network/api_client.dart';

BlockView _block(String id, {int number = 1}) => BlockView(
  (b) => b
    ..id = id
    ..number = number
    ..seasonId = 'season-1'
    ..seriesId = 'series-1'
    ..startDate = '2026-01-01'
    ..endDate = '2026-01-31'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

void main() {
  // Issue #366 — the hierarchy representative: loading staleness is
  // TTL-based. A fresh season cache served while a normal refetch is in
  // flight is NOT stale; an expired cache served while loading IS stale.
  // Episodes / scenes / categories share the identical selector shape.
  group('blocksView loading staleness is TTL-based (issue #366)', () {
    late CacheDatabase db;

    setUp(() => db = CacheDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<ProviderContainer> buildLoadingContainer({
      required DateTime cachedAt,
      required DateTime now,
    }) async {
      await BlockCacheDao(db)
          .applySnapshotForSeason('season-1', [_block('b1')], cachedAt);
      final container = ProviderContainer(
        overrides: [
          apiDioProvider.overrideWithValue(Dio()),
          cacheDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(Clock.fixed(now)),
          // The fetch never resolves: the controller stays AsyncLoading.
          blocksListFetchProvider(
            'season-1',
          ).overrideWith((ref) => Completer<Result<List<BlockView>>>().future),
        ],
      );
      addTearDown(container.dispose);
      // Pin the auto-dispose controller chain so rebuilds propagate.
      final sub = container.listen(
        blocksViewControllerProvider('season-1'),
        (_, _) {},
      );
      addTearDown(sub.close);
      // Drain the fire-and-forget cache seed (bounded, never wall-clock).
      for (
        var i = 0;
        i < 200 && container.read(blocksPrevRowsProvider('season-1')).isEmpty;
        i++
      ) {
        await pumpEventQueue();
      }
      return container;
    }

    test('loading with a fresh cache serves rows without stale', () async {
      final now = DateTime.utc(2026, 6, 1, 12);
      final container = await buildLoadingContainer(
        cachedAt: now,
        now: now.add(const Duration(hours: 1)),
      );

      expect(
        container.read(blocksViewControllerProvider('season-1')),
        isA<AsyncLoading>(),
      );
      // Settle the TTL check first: the view reads its (async) value and
      // rebuilds once it resolves.
      expect(
        await container.read(blocksCacheStaleProvider('season-1').future),
        isFalse,
      );
      final view = container.read(blocksViewProvider('season-1'));
      expect(view.rows.map((b) => b.id).toList(), ['b1']);
      expect(view.isStale, isFalse);
      expect(view.error, isNull);
    });

    test('loading with an expired cache marks rows stale', () async {
      final cachedAt = DateTime.utc(2026, 6, 1, 12);
      final container = await buildLoadingContainer(
        cachedAt: cachedAt,
        now: cachedAt.add(kCacheTtl).add(const Duration(minutes: 1)),
      );

      expect(
        container.read(blocksViewControllerProvider('season-1')),
        isA<AsyncLoading>(),
      );
      // Settle the TTL check first (see above).
      expect(
        await container.read(blocksCacheStaleProvider('season-1').future),
        isTrue,
      );
      final view = container.read(blocksViewProvider('season-1'));
      expect(view.rows.map((b) => b.id).toList(), ['b1']);
      expect(view.isStale, isTrue);
      expect(view.error, isNull);
    });
  });
}
