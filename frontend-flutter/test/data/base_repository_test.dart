// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/data/base_repository.dart';

class _ProbeRepository extends BaseRepository {
  _ProbeRepository() : super(BreakdownApi());
}

Future<Response<T>> _nullBody<T>() async =>
    Response<T>(data: null, requestOptions: RequestOptions(path: '/x'));

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
}
