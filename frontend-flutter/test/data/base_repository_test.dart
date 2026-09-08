// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/base_repository.dart';

class _ProbeRepository extends BaseRepository {
  _ProbeRepository() : super(BreakdownApi());
}

Future<Response<T>> _nullBody<T>() async =>
    Response<T>(data: null, requestOptions: RequestOptions(path: '/x'));

/// Probe repository that returns one full page then errors on the second
/// call, verifying that [fetchAllPages] short-circuits on a mid-stream
/// failure instead of returning a partial snapshot.
class _FailingAfterOnePage extends BaseRepository {
  _FailingAfterOnePage() : super(BreakdownApi());

  int _calls = 0;

  @override
  Future<Result<List<T>>> runList<T>(
    Future<Response<BuiltList<T>>> Function() call, {
    String dtoInvalidCode = 'dto.invalid',
  }) async {
    _calls++;
    if (_calls == 1) {
      return Right(List<T>.from(List.generate(100, (i) => _block('a$i'))));
    }
    return const Left(ProblemError(code: 'transport.connectionError'));
  }
}

BlockView _block(String id) => BlockView(
  (b) => b
    ..id = id
    ..number = 1
    ..seasonId = 's'
    ..seriesId = 'series-1'
    ..startDate = '2026-01-01'
    ..endDate = '2026-01-31'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

void main() {
  group('BaseRepository null-body discipline (no-throw rule)', () {
    test('run maps a null body to dto.invalid instead of throwing', () async {
      final repo = _ProbeRepository();
      final res = await repo.run<IdVersionResponse>(
        _nullBody<IdVersionResponse>,
      );
      expect(res.isLeft(), isTrue);
      expect(res.fold((e) => e.code, (_) => 'right'), 'dto.invalid');
    });

    test('run passes a decoded body through as Right', () async {
      final repo = _ProbeRepository();
      final ack = IdVersionResponse(
        (b) => b
          ..id = 'n1'
          ..version = 1,
      );
      final res = await repo.run<IdVersionResponse>(
        () async => Response<IdVersionResponse>(
          data: ack,
          requestOptions: RequestOptions(path: '/x'),
        ),
      );
      expect(res.isRight(), isTrue);
    });

    test('runList maps a null body to the custom dto code', () async {
      final repo = _ProbeRepository();
      final res = await repo.runList<BlockView>(
        _nullBody<BuiltList<BlockView>>,
        dtoInvalidCode: 'block.dto_invalid',
      );
      expect(res.isLeft(), isTrue);
      expect(res.fold((e) => e.code, (_) => 'right'), 'block.dto_invalid');
    });
  });

  group('BaseRepository.fetchAllPages (issue #385)', () {
    test(
      'combines every page until a partial page terminates the loop',
      () async {
        final repo = _ProbeRepository();
        final pages = {
          0: List.generate(100, (i) => _block('a$i')),
          100: List.generate(100, (i) => _block('b$i')),
          200: List.generate(17, (i) => _block('c$i')),
        };
        // Record the actual limit/offset args the loop sends.
        final requestedArgs = <({int limit, int offset})>[];

        final res = await repo.fetchAllPages<BlockView>(({
          required limit,
          required offset,
        }) async {
          requestedArgs.add((limit: limit, offset: offset));
          final page = pages[offset] ?? const [];
          return Response(
            data: BuiltList<BlockView>(page),
            requestOptions: RequestOptions(path: '/x'),
          );
        }, pageSize: 100);

        expect(res.isRight(), isTrue);
        final rows = res.getOrElse((_) => const []);
        expect(rows.length, 217); // 100 + 100 + 17
        expect(rows.take(100).map((r) => r.id).first, 'a0');
        expect(rows.skip(100).take(100).map((r) => r.id).first, 'b0');
        expect(rows.skip(200).map((r) => r.id).first, 'c0');
        // Assert the loop paged with the correct offsets.
        expect(requestedArgs, [
          (limit: 100, offset: 0),
          (limit: 100, offset: 100),
          (limit: 100, offset: 200),
        ]);
      },
    );

    test('a single full page followed by an empty page terminates', () async {
      final repo = _ProbeRepository();
      final pages = {
        0: List.generate(100, (i) => _block('a$i')),
        100: const <BlockView>[],
      };
      final requestedArgs = <({int limit, int offset})>[];

      final res = await repo.fetchAllPages<BlockView>(({
        required limit,
        required offset,
      }) async {
        requestedArgs.add((limit: limit, offset: offset));
        final page = pages[offset] ?? const [];
        return Response(
          data: BuiltList<BlockView>(page),
          requestOptions: RequestOptions(path: '/x'),
        );
      }, pageSize: 100);

      expect(res.isRight(), isTrue);
      expect(res.getOrElse((_) => const []).length, 100);
      expect(requestedArgs, [
        (limit: 100, offset: 0),
        (limit: 100, offset: 100),
      ]);
    });

    test('returns the first page only when it is already partial', () async {
      final repo = _ProbeRepository();
      final pages = {0: List.generate(30, (i) => _block('a$i'))};
      final requestedArgs = <({int limit, int offset})>[];

      final res = await repo.fetchAllPages<BlockView>(({
        required limit,
        required offset,
      }) async {
        requestedArgs.add((limit: limit, offset: offset));
        final page = pages[offset] ?? const [];
        return Response(
          data: BuiltList<BlockView>(page),
          requestOptions: RequestOptions(path: '/x'),
        );
      }, pageSize: 100);

      expect(res.isRight(), isTrue);
      expect(res.getOrElse((_) => const []).length, 30);
      expect(requestedArgs, [(limit: 100, offset: 0)]);
    });

    test(
      'short-circuits on a mid-stream error, returning no partial rows',
      () async {
        final repo = _FailingAfterOnePage();

        final res = await repo.fetchAllPages<BlockView>(
          ({required limit, required offset}) async => Response(
            data: BuiltList<BlockView>([]),
            requestOptions: RequestOptions(path: '/x'),
          ),
          pageSize: 100,
        );

        expect(res.isLeft(), isTrue);
        expect(res.fold((e) => e.code, (_) => ''), 'transport.connectionError');
      },
    );

    test('rejects non-positive pageSize with a ProblemError', () async {
      final repo = _ProbeRepository();

      final res = await repo.fetchAllPages<BlockView>(
        ({required limit, required offset}) async => Response(
          data: BuiltList<BlockView>([]),
          requestOptions: RequestOptions(path: '/x'),
        ),
        pageSize: 0,
      );

      expect(res.isLeft(), isTrue);
      expect(
        res.fold((e) => e.code, (_) => ''),
        'pagination.invalid_page_size',
      );
    });
  });
}
