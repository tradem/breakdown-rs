// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Tier-1 unit tests (issue #369): deterministic fault-injection coverage for
// the costume-domain cache paths. A scriptable DAO fake wraps a REAL DAO over
// an in-memory Drift database and throws on demand (write / read / clear), so
// every `cache.*_failed` branch in [CostumeRepository],
// [CharacterRepository] and [ShootingDayRepository] resolves to its
// documented `Left` code. Cache-untouched-on-failure is asserted against the
// wrapped real DAO. Headless and deterministic: fake clock, no wall-clock
// budget, no real network (scriptable Dio interceptor), no Flutter imports.
//
// Why this seam: a closed in-memory database does not reliably produce DAO
// faults (reads resolve instead of throwing — verified during the
// `flutter-costume-domains` implementation), so the defensive `on Object`
// branches had no deterministic trigger. The fake injects the fault BEFORE
// the operation reaches the database, which is exactly the failure surface
// the repositories must map to `Left(cache.*_failed)`.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:one_of/one_of.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';
import 'package:frontend_flutter/data/character_repository.dart';
import 'package:frontend_flutter/data/costume_repository.dart';
import 'package:frontend_flutter/data/shooting_day_repository.dart';

// --- Fixtures (same wire form as costume_domain_repositories_test.dart) -----

CostumeView _costume(String id, {int version = 1}) => CostumeView(
  (b) => b
    ..id = id
    ..notes = 'notes'
    ..details.replace(BuiltList<CostumeDetailView>())
    ..photos.replace(BuiltList<CostumePhotoView>())
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version,
);

CharacterView _character(String id) => CharacterView(
  (b) => b
    ..id = id
    ..seasonId = 'season-1'
    ..name = 'Name'
    ..category = serializers.deserializeWith(
      CharacterCategory.serializer,
      'main_cast',
    )!
    ..measurements.replace(
      CharacterMeasurements(
        (m) => m
          ..height = 'h'
          ..weight = 'w'
          ..chest = 'c'
          ..waist = 'wa'
          ..hips = 'hi'
          ..shoeSize = 's'
          ..hatSize = 'ha',
      ),
    )
    ..contact.replace(ContactInfo((c) => c..email = 'a@b.c'))
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

ShootingDayView _day(String id) => ShootingDayView(
  (b) => b
    ..id = id
    ..episodeId = 'ep-1'
    ..orderKey = '!'
    ..source_.replace(
      ShootingDaySource((s) => s..oneOf = OneOf.fromValue1(value: 'Manual')),
    )
    ..archived = false
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

/// Serializes a list of views to the wire form the generated client
/// deserializes (`response.data`).
Object _wireList<T>(List<T> views, Serializer<T> serializer) =>
    serializers.serialize(
      BuiltList<T>(views),
      specifiedType: FullType(BuiltList, [FullType(T)]),
    )!;

Object _wire<T>(T view, Serializer<T> serializer) =>
    serializers.serializeWith(serializer, view)!;

// --- Fake transport ---------------------------------------------------------

/// Scriptable interceptor: resolves every request with [respond], or rejects
/// with [problem] (RFC 9457 problem+json, stable `code`).
class _ScriptInterceptor extends Interceptor {
  _ScriptInterceptor({this.respond});

  final Object? Function(RequestOptions options)? respond;
  int calls = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    calls++;
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: respond?.call(options),
      ),
    );
  }
}

BreakdownApi _api(_ScriptInterceptor i) =>
    BreakdownApi(dio: Dio(), interceptors: [i]);

/// Fixed fake clock — deterministic tests never read the wall clock.
final Clock _clock = Clock.fixed(DateTime.utc(2026, 1, 2));

void _expectLeftCode(Result<Object?> result, String code) {
  expect(result.isLeft(), isTrue, reason: 'expected Left($code)');
  result.fold((l) => expect(l.code, code), (_) => fail('expected Left($code)'));
}

void _expectRight(Result<Object?> result) =>
    result.fold((l) => fail('expected Right, got Left(${l.code})'), (_) {});

// --- Deterministic fault seam ----------------------------------------------

/// The injected failure. A private exception type so the repositories'
/// `on Object` catch-all is exercised (no specific typed catch exists).
class _InjectedFault implements Exception {
  const _InjectedFault();

  @override
  String toString() => 'InjectedCacheFault';
}

/// Scripted fault phase: which cache operation the DAO fake throws on.
enum _FaultPhase { none, write, read, clear }

/// Scriptable DAO fake wrapping a real [CostumeCacheDao].
///
/// Every operation delegates to [real] unless [phase] matches, in which case
/// the fake throws [_InjectedFault] BEFORE touching the database. The real
/// DAO stays directly readable, so "cache untouched on failure" is asserted
/// against genuine persisted state, not the fake's memory.
class _FaultCostumeCacheDao implements CostumeCacheDao {
  _FaultCostumeCacheDao(this.real);

  final CostumeCacheDao real;

  _FaultPhase phase = _FaultPhase.none;

  @override
  Future<void> applySnapshotForSeason(
    String seasonId,
    List<CostumeView> views,
    DateTime cachedAt,
  ) async {
    if (phase == _FaultPhase.write) throw const _InjectedFault();
    await real.applySnapshotForSeason(seasonId, views, cachedAt);
  }

  @override
  Future<void> upsert(
    String seasonId,
    CostumeView view,
    DateTime cachedAt,
  ) async {
    if (phase == _FaultPhase.write) throw const _InjectedFault();
    await real.upsert(seasonId, view, cachedAt);
  }

  @override
  Future<List<CostumeView>> readBySeason(String seasonId) async {
    if (phase == _FaultPhase.read) throw const _InjectedFault();
    return real.readBySeason(seasonId);
  }

  @override
  Future<CostumeView?> readById(String seasonId, String id) =>
      real.readById(seasonId, id);

  @override
  Future<bool> isSeasonExpired(
    String seasonId,
    Duration ttl, {
    Clock clock = Clock.system,
  }) => real.isSeasonExpired(seasonId, ttl, clock: clock);

  @override
  Future<void> clearSeason(String seasonId) async {
    if (phase == _FaultPhase.clear) throw const _InjectedFault();
    await real.clearSeason(seasonId);
  }
}

/// Scriptable DAO fake wrapping a real [CharacterCacheDao]
/// (same seam contract as [_FaultCostumeCacheDao]).
class _FaultCharacterCacheDao implements CharacterCacheDao {
  _FaultCharacterCacheDao(this.real);

  final CharacterCacheDao real;

  _FaultPhase phase = _FaultPhase.none;

  @override
  Future<void> upsert(CharacterView view, DateTime cachedAt) async {
    if (phase == _FaultPhase.write) throw const _InjectedFault();
    await real.upsert(view, cachedAt);
  }

  @override
  Future<void> applySnapshotForSeason(
    String seasonId,
    List<CharacterView> views,
    DateTime cachedAt,
  ) async {
    if (phase == _FaultPhase.write) throw const _InjectedFault();
    await real.applySnapshotForSeason(seasonId, views, cachedAt);
  }

  @override
  Future<List<CharacterView>> readBySeason(String seasonId) async {
    if (phase == _FaultPhase.read) throw const _InjectedFault();
    return real.readBySeason(seasonId);
  }

  @override
  Future<CharacterView?> readById(String id) => real.readById(id);

  @override
  Future<bool> isSeasonExpired(
    String seasonId,
    Duration ttl, {
    Clock clock = Clock.system,
  }) => real.isSeasonExpired(seasonId, ttl, clock: clock);

  @override
  Future<void> clearSeason(String seasonId) async {
    if (phase == _FaultPhase.clear) throw const _InjectedFault();
    await real.clearSeason(seasonId);
  }
}

/// Scriptable DAO fake wrapping a real [ShootingDayCacheDao]
/// (same seam contract as [_FaultCostumeCacheDao], episode-scoped).
class _FaultShootingDayCacheDao implements ShootingDayCacheDao {
  _FaultShootingDayCacheDao(this.real);

  final ShootingDayCacheDao real;

  _FaultPhase phase = _FaultPhase.none;

  @override
  Future<void> upsert(ShootingDayView view, DateTime cachedAt) async {
    if (phase == _FaultPhase.write) throw const _InjectedFault();
    await real.upsert(view, cachedAt);
  }

  @override
  Future<void> applySnapshotForEpisode(
    String episodeId,
    List<ShootingDayView> views,
    DateTime cachedAt,
  ) async {
    if (phase == _FaultPhase.write) throw const _InjectedFault();
    await real.applySnapshotForEpisode(episodeId, views, cachedAt);
  }

  @override
  Future<List<ShootingDayView>> readByEpisodeOrdered(String episodeId) async {
    if (phase == _FaultPhase.read) throw const _InjectedFault();
    return real.readByEpisodeOrdered(episodeId);
  }

  @override
  Future<ShootingDayView?> readById(String id) => real.readById(id);

  @override
  Future<bool> isEpisodeExpired(
    String episodeId,
    Duration ttl, {
    Clock clock = Clock.system,
  }) => real.isEpisodeExpired(episodeId, ttl, clock: clock);

  @override
  Future<void> clearEpisode(String episodeId) async {
    if (phase == _FaultPhase.clear) throw const _InjectedFault();
    await real.clearEpisode(episodeId);
  }
}

// --- Tests ------------------------------------------------------------------

void main() {
  group('CostumeRepository cache-fault mapping', () {
    late CacheDatabase db;
    late _FaultCostumeCacheDao dao;
    late CostumeCacheDao realDao;

    setUp(() {
      db = CacheDatabase();
      realDao = CostumeCacheDao(db);
      dao = _FaultCostumeCacheDao(realDao);
      addTearDown(db.close);
    });

    /// Network fixture resolving `listCostumes` with the given rows.
    _ScriptInterceptor listOk(List<CostumeView> rows) => _ScriptInterceptor(
      respond: (_) => _wireList(rows, CostumeView.serializer),
    );

    test('listBySeason Ok applies the snapshot', () async {
      final repo = CostumeRepository(_api(listOk([_costume('c-1')])), dao);
      _expectRight(await repo.listBySeason('s-1', clock: _clock));
      expect((await realDao.readBySeason('s-1')).map((c) => c.id), ['c-1']);
    });

    test(
      'listBySeason write-fault → Left(cache.write_failed), cache untouched',
      () async {
        // Seed via a fault-free fetch first.
        await CostumeRepository(
          _api(listOk([_costume('c-1')])),
          dao,
        ).listBySeason('s-1', clock: _clock);
        expect((await realDao.readBySeason('s-1')).map((c) => c.id), ['c-1']);

        // Refetch different rows while writes are faulted: nothing lands —
        // the old snapshot survives, the new row never appears.
        dao.phase = _FaultPhase.write;
        final res = await CostumeRepository(
          _api(listOk([_costume('c-2')])),
          dao,
        ).listBySeason('s-1', clock: _clock);
        _expectLeftCode(res, 'cache.write_failed');
        expect((await realDao.readBySeason('s-1')).map((c) => c.id), ['c-1']);
      },
    );

    test('readCached Ok returns the cached rows', () async {
      await CostumeRepository(
        _api(listOk([_costume('c-1')])),
        dao,
      ).listBySeason('s-1', clock: _clock);
      final repo = CostumeRepository(_api(_ScriptInterceptor()), dao);
      final res = await repo.readCached('s-1');
      _expectRight(res);
      expect(
        res.fold((_) => <String>[], (rows) => rows.map((c) => c.id).toList()),
        ['c-1'],
      );
    });

    test('readCached read-fault → Left(cache.read_failed)', () async {
      await CostumeRepository(
        _api(listOk([_costume('c-1')])),
        dao,
      ).listBySeason('s-1', clock: _clock);
      dao.phase = _FaultPhase.read;
      final transport = _ScriptInterceptor();
      _expectLeftCode(
        await CostumeRepository(_api(transport), dao).readCached('s-1'),
        'cache.read_failed',
      );
      // Pure Drift read: no network call on the faulted path either.
      expect(transport.calls, 0);
    });

    test('getAndCache Ok upserts the row', () async {
      final ok = _ScriptInterceptor(
        respond: (_) => _wire(_costume('c-9'), CostumeView.serializer),
      );
      final repo = CostumeRepository(_api(ok), dao);
      _expectRight(await repo.getAndCache('s-1', 'c-9', clock: _clock));
      expect(await realDao.readById('s-1', 'c-9'), isNotNull);
    });

    test(
      'getAndCache write-fault → Left(cache.write_failed), nothing written',
      () async {
        dao.phase = _FaultPhase.write;
        final ok = _ScriptInterceptor(
          respond: (_) => _wire(_costume('c-9'), CostumeView.serializer),
        );
        final repo = CostumeRepository(_api(ok), dao);
        _expectLeftCode(
          await repo.getAndCache('s-1', 'c-9', clock: _clock),
          'cache.write_failed',
        );
        expect(await realDao.readById('s-1', 'c-9'), isNull);
      },
    );

    test('clearCache Ok empties the season scope', () async {
      await CostumeRepository(
        _api(listOk([_costume('c-1')])),
        dao,
      ).listBySeason('s-1', clock: _clock);
      _expectRight(
        await CostumeRepository(
          _api(_ScriptInterceptor()),
          dao,
        ).clearCache('s-1'),
      );
      expect(await realDao.readBySeason('s-1'), isEmpty);
    });

    test(
      'clearCache clear-fault → Left(cache.clear_failed), rows survive',
      () async {
        await CostumeRepository(
          _api(listOk([_costume('c-1')])),
          dao,
        ).listBySeason('s-1', clock: _clock);
        dao.phase = _FaultPhase.clear;
        _expectLeftCode(
          await CostumeRepository(
            _api(_ScriptInterceptor()),
            dao,
          ).clearCache('s-1'),
          'cache.clear_failed',
        );
        expect((await realDao.readBySeason('s-1')).map((c) => c.id), ['c-1']);
      },
    );
  });

  group('CharacterRepository cache-fault mapping', () {
    late CacheDatabase db;
    late _FaultCharacterCacheDao dao;
    late CharacterCacheDao realDao;

    setUp(() {
      db = CacheDatabase();
      realDao = CharacterCacheDao(db);
      dao = _FaultCharacterCacheDao(realDao);
      addTearDown(db.close);
    });

    _ScriptInterceptor listOk(List<CharacterView> rows) => _ScriptInterceptor(
      respond: (_) => _wireList(rows, CharacterView.serializer),
    );

    test('listBySeason Ok applies the snapshot', () async {
      final repo = CharacterRepository(_api(listOk([_character('ch-1')])), dao);
      _expectRight(await repo.listBySeason('season-1', clock: _clock));
      expect((await realDao.readBySeason('season-1')).map((c) => c.id), [
        'ch-1',
      ]);
    });

    test(
      'listBySeason write-fault → Left(cache.write_failed), cache untouched',
      () async {
        await CharacterRepository(
          _api(listOk([_character('ch-1')])),
          dao,
        ).listBySeason('season-1', clock: _clock);
        dao.phase = _FaultPhase.write;
        final res = await CharacterRepository(
          _api(listOk([_character('ch-2')])),
          dao,
        ).listBySeason('season-1', clock: _clock);
        _expectLeftCode(res, 'cache.write_failed');
        expect((await realDao.readBySeason('season-1')).map((c) => c.id), [
          'ch-1',
        ]);
      },
    );

    test('readCached Ok returns the cached rows', () async {
      await CharacterRepository(
        _api(listOk([_character('ch-1')])),
        dao,
      ).listBySeason('season-1', clock: _clock);
      final res = await CharacterRepository(
        _api(_ScriptInterceptor()),
        dao,
      ).readCached('season-1');
      _expectRight(res);
      expect(
        res.fold((_) => <String>[], (rows) => rows.map((c) => c.id).toList()),
        ['ch-1'],
      );
    });

    test('readCached read-fault → Left(cache.read_failed)', () async {
      await CharacterRepository(
        _api(listOk([_character('ch-1')])),
        dao,
      ).listBySeason('season-1', clock: _clock);
      dao.phase = _FaultPhase.read;
      final transport = _ScriptInterceptor();
      _expectLeftCode(
        await CharacterRepository(_api(transport), dao).readCached('season-1'),
        'cache.read_failed',
      );
      // Pure Drift read: no network call on the faulted path either.
      expect(transport.calls, 0);
    });

    test('clearCache Ok empties the season scope', () async {
      await CharacterRepository(
        _api(listOk([_character('ch-1')])),
        dao,
      ).listBySeason('season-1', clock: _clock);
      _expectRight(
        await CharacterRepository(
          _api(_ScriptInterceptor()),
          dao,
        ).clearCache('season-1'),
      );
      expect(await realDao.readBySeason('season-1'), isEmpty);
    });

    test(
      'clearCache clear-fault → Left(cache.clear_failed), rows survive',
      () async {
        await CharacterRepository(
          _api(listOk([_character('ch-1')])),
          dao,
        ).listBySeason('season-1', clock: _clock);
        dao.phase = _FaultPhase.clear;
        _expectLeftCode(
          await CharacterRepository(
            _api(_ScriptInterceptor()),
            dao,
          ).clearCache('season-1'),
          'cache.clear_failed',
        );
        expect((await realDao.readBySeason('season-1')).map((c) => c.id), [
          'ch-1',
        ]);
      },
    );
  });

  group('ShootingDayRepository cache-fault mapping', () {
    late CacheDatabase db;
    late _FaultShootingDayCacheDao dao;
    late ShootingDayCacheDao realDao;

    setUp(() {
      db = CacheDatabase();
      realDao = ShootingDayCacheDao(db);
      dao = _FaultShootingDayCacheDao(realDao);
      addTearDown(db.close);
    });

    _ScriptInterceptor listOk(List<ShootingDayView> rows) => _ScriptInterceptor(
      respond: (_) => _wireList(rows, ShootingDayView.serializer),
    );

    test('listByEpisode Ok applies the snapshot in server order', () async {
      final repo = ShootingDayRepository(_api(listOk([_day('d-1')])), dao);
      _expectRight(await repo.listByEpisode('ep-1', clock: _clock));
      expect((await realDao.readByEpisodeOrdered('ep-1')).map((d) => d.id), [
        'd-1',
      ]);
    });

    test(
      'listByEpisode write-fault → Left(cache.write_failed), cache untouched',
      () async {
        await ShootingDayRepository(
          _api(listOk([_day('d-1')])),
          dao,
        ).listByEpisode('ep-1', clock: _clock);
        dao.phase = _FaultPhase.write;
        final res = await ShootingDayRepository(
          _api(listOk([_day('d-2')])),
          dao,
        ).listByEpisode('ep-1', clock: _clock);
        _expectLeftCode(res, 'cache.write_failed');
        expect((await realDao.readByEpisodeOrdered('ep-1')).map((d) => d.id), [
          'd-1',
        ]);
      },
    );

    test('readCached Ok returns the cached rows in order', () async {
      await ShootingDayRepository(
        _api(listOk([_day('d-1')])),
        dao,
      ).listByEpisode('ep-1', clock: _clock);
      final res = await ShootingDayRepository(
        _api(_ScriptInterceptor()),
        dao,
      ).readCached('ep-1');
      _expectRight(res);
      expect(
        res.fold((_) => <String>[], (rows) => rows.map((d) => d.id).toList()),
        ['d-1'],
      );
    });

    test('readCached read-fault → Left(cache.read_failed)', () async {
      await ShootingDayRepository(
        _api(listOk([_day('d-1')])),
        dao,
      ).listByEpisode('ep-1', clock: _clock);
      dao.phase = _FaultPhase.read;
      final transport = _ScriptInterceptor();
      _expectLeftCode(
        await ShootingDayRepository(_api(transport), dao).readCached('ep-1'),
        'cache.read_failed',
      );
      // Pure Drift read: no network call on the faulted path either.
      expect(transport.calls, 0);
    });

    test('clearCache Ok empties the episode scope', () async {
      await ShootingDayRepository(
        _api(listOk([_day('d-1')])),
        dao,
      ).listByEpisode('ep-1', clock: _clock);
      _expectRight(
        await ShootingDayRepository(
          _api(_ScriptInterceptor()),
          dao,
        ).clearCache('ep-1'),
      );
      expect(await realDao.readByEpisodeOrdered('ep-1'), isEmpty);
    });

    test(
      'clearCache clear-fault → Left(cache.clear_failed), rows survive',
      () async {
        await ShootingDayRepository(
          _api(listOk([_day('d-1')])),
          dao,
        ).listByEpisode('ep-1', clock: _clock);
        dao.phase = _FaultPhase.clear;
        _expectLeftCode(
          await ShootingDayRepository(
            _api(_ScriptInterceptor()),
            dao,
          ).clearCache('ep-1'),
          'cache.clear_failed',
        );
        expect((await realDao.readByEpisodeOrdered('ep-1')).map((d) => d.id), [
          'd-1',
        ]);
      },
    );
  });
}
