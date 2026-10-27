// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Repository boundary tests for the fundus (issue #625, tasks §2.5): the
// project-scoped fetch snapshot-replaces the cache on success, a fetch error
// never mutates the cache, and the cache-read/clear paths translate a
// throwing DAO into `Left(ProblemError)` — never a throw (AGENTS.md §5).

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/cache_ttl.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/piece_domains_cache_dao.dart';
import 'package:frontend_flutter/data/fundus_repository.dart';

PieceView _piece(String id, {List<String> repertoire = const ['s1']}) =>
    PieceView(
      (b) => b
        ..name = 'Fundus-Piece'
        ..id = id
        ..notes = 'Jacke'
        ..details.replace(BuiltList<PieceDetailView>())
        ..photos.replace(BuiltList<PiecePhotoView>())
        ..seasonIds.replace(BuiltList<String>(repertoire))
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

void main() {
  late CacheDatabase db;
  late FundusPieceCacheDao dao;

  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
    dao = FundusPieceCacheDao(db);
  });

  tearDown(() => db.close());

  test('listByProject on Right snapshot-replaces the project slice', () async {
    final repo = FundusRepository(
      BreakdownApi(
        dio: Dio(),
        interceptors: [
          _ListPiecesInterceptor(
            rows: [
              _piece('k1'),
              _piece('k2', repertoire: ['s2']),
            ],
          ),
        ],
      ),
      dao,
    );

    final result = await repo.listByProject('project-1');
    expect(result.isRight(), isTrue);

    final cached = await repo.readCachedFresh('project-1');
    expect(cached.isRight(), isTrue);
    expect(
      cached.fold((_) => const <String>[], (v) => v.rows.map((c) => c.id)),
      ['k1', 'k2'],
    );
  });

  test('listByProject on Err leaves the cache untouched', () async {
    await dao.applySnapshotForProject('project-1', [
      _piece('k1'),
    ], DateTime.utc(2026, 1, 1, 10));
    final repo = FundusRepository(
      BreakdownApi(
        dio: Dio(),
        interceptors: [
          _ListPiecesInterceptor(
            exception: DioException(
              requestOptions: RequestOptions(path: '/v1/pieces'),
              type: DioExceptionType.badResponse,
              response: Response<dynamic>(
                requestOptions: RequestOptions(path: '/v1/pieces'),
                statusCode: 500,
              ),
            ),
          ),
        ],
      ),
      dao,
    );

    final result = await repo.listByProject('project-1');
    expect(result.isLeft(), isTrue);

    final cached = await repo.readCachedFresh('project-1');
    expect(
      cached.fold((_) => const <String>[], (v) => v.rows.map((c) => c.id)),
      ['k1'],
    );
  });

  test(
    'readCachedFresh translates a throwing DAO into Left(cache.read_failed)',
    () async {
      final repo = FundusRepository(BreakdownApi(), _ThrowingFundusDao(db));
      final result = await repo.readCachedFresh('project-1');
      expect(result.fold((e) => e.code, (_) => null), 'cache.read_failed');
    },
  );

  test(
    'clearCache translates a throwing DAO into Left(cache.clear_failed)',
    () async {
      final repo = FundusRepository(BreakdownApi(), _ThrowingFundusDao(db));
      final result = await repo.clearCache('project-1');
      expect(result.fold((e) => e.code, (_) => null), 'cache.clear_failed');
    },
  );

  test(
    'isCacheStale translates a throwing DAO into Left(cache.read_failed)',
    () async {
      final repo = FundusRepository(BreakdownApi(), _ThrowingFundusDao(db));
      final result = await repo.isCacheStale('project-1');
      expect(result.fold((e) => e.code, (_) => null), 'cache.read_failed');
    },
  );
}

/// Interceptor that short-circuits `GET /v1/pieces` without a real network
/// call, resolving with serialized [rows] or rejecting with [exception].
class _ListPiecesInterceptor extends Interceptor {
  _ListPiecesInterceptor({this.rows, this.exception})
    : assert(rows != null || exception != null);

  final List<PieceView>? rows;
  final DioException? exception;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (exception != null) {
      handler.reject(exception!);
      return;
    }
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: rows!
            .map((v) => serializers.serializeWith(PieceView.serializer, v))
            .toList(),
      ),
    );
  }
}

/// DAO fake whose reads/writes fail at the executor level, exercising the
/// repository's `Left(ProblemError)` translation.
class _ThrowingFundusDao extends FundusPieceCacheDao {
  _ThrowingFundusDao(super.db);

  @override
  Future<({List<PieceView> rows, bool stale})> readByProjectFresh(
    String projectId, {
    Duration ttl = kCacheTtl,
    Clock clock = Clock.system,
  }) async => throw StateError('simulated executor failure');

  @override
  Future<void> clearProject(String projectId) async =>
      throw StateError('simulated executor failure');

  @override
  Future<bool> isProjectExpired(
    String projectId,
    Duration ttl, {
    Clock clock = Clock.system,
  }) async => throw StateError('simulated executor failure');
}
