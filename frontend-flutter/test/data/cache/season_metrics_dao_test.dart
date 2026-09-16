// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/drift.dart'
    show QueryRow, ResultSetImplementation, Selectable, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/cache_ttl.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/relative_time.dart';
import 'package:frontend_flutter/data/cache/season_metrics_dao.dart';

/// Deterministic "now" for the TTL verdicts (AGENTS.md §6: injected clock,
/// never wall-clock gating).
final _now = DateTime.utc(2026, 1, 2, 12);
final _clock = Clock.fixed(_now);

BlockView _block(String id, {String seasonId = 'season-1'}) => BlockView(
  (b) => b
    ..id = id
    ..number = 1
    ..seasonId = seasonId
    ..seriesId = 'series-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

EpisodeView _episode(String id, {String blockId = 'block-1'}) => EpisodeView(
  (b) => b
    ..id = id
    ..blockId = blockId
    ..number = 1
    ..seriesId = 'series-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

SceneView _scene(String id, {String episodeId = 'episode-1'}) => SceneView(
  (b) => b
    ..id = id
    ..episodeId = episodeId
    ..assignedCharacters.replace(const [])
    ..isScheduleSet = false
    ..shootingDayIds.replace(const [])
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

CostumeView _costume(String id) => CostumeView(
  (b) => b
    ..id = id
    ..notes = ''
    ..details.replace(const [])
    ..photos.replace(const [])
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

/// The injected fault (private exception type, exercising the DAO's
/// `on Object` catch-all).
class _InjectedFault implements Exception {}

/// Fault seam: a [CacheDatabase] whose `customSelect` always throws — a
/// deterministic DAO-read failure (a closed in-memory database does not
/// reliably fault reads; same lesson as the costume fault tests).
class _FaultSelectDatabase extends CacheDatabase {
  _FaultSelectDatabase(super.executor);

  @override
  Selectable<QueryRow> customSelect(
    String query, {
    List<Variable> variables = const [],
    Set<ResultSetImplementation> readsFrom = const {},
  }) => throw _InjectedFault();
}

void main() {
  late CacheDatabase db;

  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
  });

  SeasonMetricsDao dao() => SeasonMetricsDao(db);

  test('empty cache → Ok branch with an empty map', () async {
    final res = await dao().readAll(clock: _clock);
    expect(res.isRight(), isTrue);
    expect(res.getRight().toNullable(), isEmpty);
  });

  test(
    'blocks counted per season; scenes/costumes null when uncached',
    () async {
      await BlockCacheDao(db).upsert(_block('b1'), _now);
      final res = await dao().readAll(clock: _clock);
      final metrics = res.getRight().toNullable()!;
      expect(metrics['season-1']?.blockCount, 1);
      expect(metrics['season-1']?.sceneCount, isNull);
      expect(metrics['season-1']?.costumeCount, isNull);
    },
  );

  test('scenes counted through the episode→block join chain', () async {
    final blocks = BlockCacheDao(db);
    final episodes = EpisodeCacheDao(db);
    final scenes = SceneCacheDao(db);
    await blocks.upsert(_block('b1'), _now);
    await episodes.upsert(_episode('e1', blockId: 'b1'), _now);
    await episodes.upsert(_episode('e2', blockId: 'b1'), _now);
    await scenes.upsert(_scene('s1', episodeId: 'e1'), _now);
    await scenes.upsert(_scene('s2', episodeId: 'e2'), _now);

    final metrics = (await dao().readAll(clock: _clock))
        .getRight()
        .toNullable()!;
    expect(metrics['season-1']?.sceneCount, 2);
  });

  test('costumes counted per season snapshot scope', () async {
    await CostumeCacheDao(db).upsert('season-1', _costume('c1'), _now);
    await CostumeCacheDao(db).upsert('season-1', _costume('c2'), _now);
    await CostumeCacheDao(db).upsert('season-2', _costume('c3'), _now);

    final metrics = (await dao().readAll(clock: _clock))
        .getRight()
        .toNullable()!;
    expect(metrics['season-1']?.costumeCount, 2);
    expect(metrics['season-2']?.costumeCount, 1);
  });

  test('empty-season case: a season cached elsewhere but with no '
      'contributing rows has no map entry (metadata omitted)', () async {
    // Only season-2 has rows; a rendered season-1 (no rows anywhere)
    // must be absent from the map — never a zero-count fabrication.
    await BlockCacheDao(db).upsert(_block('b1', seasonId: 'season-2'), _now);
    final metrics = (await dao().readAll(clock: _clock))
        .getRight()
        .toNullable()!;
    expect(metrics.keys, ['season-2']);
  });

  test(
    'stale verdict: oldest contributing source rules (conservative)',
    () async {
      final fresh = _now.subtract(const Duration(hours: 1));
      // Strictly older than the 24h TTL.
      final expired = _now
          .subtract(kCacheTtl)
          .subtract(const Duration(minutes: 5));
      final blocks = BlockCacheDao(db);
      await blocks.upsert(_block('b1'), expired);
      await CostumeCacheDao(db).upsert('season-1', _costume('c1'), fresh);

      final metrics = (await dao().readAll(clock: _clock))
          .getRight()
          .toNullable()!;
      final m = metrics['season-1']!;
      expect(m.blockCount, 1);
      expect(m.costumeCount, 1);
      expect(
        m.cachedAt,
        DateTime.fromMillisecondsSinceEpoch(
          expired.millisecondsSinceEpoch,
          isUtc: true,
        ),
      );
      expect(m.isStale, isTrue);
    },
  );

  test('fresh sources → isStale false', () async {
    await BlockCacheDao(db).upsert(_block('b1'), _now);
    final metrics = (await dao().readAll(clock: _clock))
        .getRight()
        .toNullable()!;
    expect(metrics['season-1']!.isStale, isFalse);
  });

  test(
    'scene staleness includes the join chain (episode older than scene)',
    () async {
      // A fresh scene row must not mask an expired EPISODE row in the join
      // chain (review fix: cachedAt = oldest contributing source).
      final blocks = BlockCacheDao(db);
      final episodes = EpisodeCacheDao(db);
      final scenes = SceneCacheDao(db);
      // Strictly older than the 24h TTL.
      final expired = _now
          .subtract(kCacheTtl)
          .subtract(const Duration(minutes: 5));
      await blocks.upsert(_block('b1'), _now);
      await episodes.upsert(_episode('e1', blockId: 'b1'), expired);
      await scenes.upsert(_scene('s1', episodeId: 'e1'), _now);

      final metrics = (await dao().readAll(clock: _clock))
          .getRight()
          .toNullable()!;
      final m = metrics['season-1']!;
      expect(m.sceneCount, 1);
      expect(m.blockCount, 1);
      expect(m.isStale, isTrue);
    },
  );

  test('Err branch: a failed DAO read resolves Left, never throws', () async {
    // Deterministic fault seam: a closed in-memory database does NOT
    // reliably fault DAO reads (reads resolve instead of throwing — see
    // the costume fault tests), so the fault is injected at the executor
    // boundary (_FaultSelectDatabase).
    final faultDb = _FaultSelectDatabase(NativeDatabase.memory());
    addTearDown(faultDb.close);
    final res = await SeasonMetricsDao(faultDb).readAll(clock: _clock);
    expect(res.isLeft(), isTrue);
    expect(res.getLeft().toNullable()?.code, 'cache.read_failed');
  });

  group('relativeTimeSince (task 2.3, deterministic via Clock.fixed)', () {
    test('buckets: just now / minutes / hours / days', () {
      expect(relativeTimeSince(_now, clock: _clock), 'gerade eben');
      expect(
        relativeTimeSince(
          _now.subtract(const Duration(minutes: 5)),
          clock: _clock,
        ),
        'vor 5 min',
      );
      expect(
        relativeTimeSince(
          _now.subtract(const Duration(hours: 2)),
          clock: _clock,
        ),
        'vor 2 h',
      );
      expect(
        relativeTimeSince(
          _now.subtract(const Duration(days: 3)),
          clock: _clock,
        ),
        'vor 3 d',
      );
    });

    test('bucket boundaries (60 s / 60 min / 24 h)', () {
      expect(
        relativeTimeSince(
          _now.subtract(const Duration(minutes: 1)),
          clock: _clock,
        ),
        'vor 1 min',
      );
      expect(
        relativeTimeSince(
          _now.subtract(const Duration(hours: 1)),
          clock: _clock,
        ),
        'vor 1 h',
      );
      expect(
        relativeTimeSince(
          _now.subtract(const Duration(hours: 24)),
          clock: _clock,
        ),
        'vor 1 d',
      );
    });
  });
}
