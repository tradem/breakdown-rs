// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/costume_category_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/costume_categories/costume_categories_controller.dart';
import 'package:frontend_flutter/features/costume_categories/costume_categories_state.dart';

import '../seasons/seasons_test_fakes.dart';

const _networkDown = ProblemError(code: 'transport.connectionError');
const _versionConflict = ProblemError(code: 'concurrency.conflict');
const _gone = ProblemError(code: 'season.not-found', status: 404);

CostumeCategoryView _category(
  String id, {
  String orderKey = '!',
  bool archived = false,
  int version = 1,
}) => CostumeCategoryView(
  (b) => b
    ..id = id
    ..seasonId = 'season-1'
    ..name = 'Cat $id'
    ..orderKey = orderKey
    ..archived = archived
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version,
);

class _FakeCategoryRepository extends CostumeCategoryRepository {
  _FakeCategoryRepository(super.api, super.cache);

  Result<List<CostumeCategoryView>>? nextList;
  Result<IdVersionResponse>? nextCreate;
  Result<int>? nextWrite;
  CreateCostumeCategoryRequest? lastCreateRequest;

  @override
  Future<Result<List<T>>> runList<T>(
    Future<Response<BuiltList<T>>> Function() call, {
    String dtoInvalidCode = 'dto.invalid',
  }) async {
    final scripted = nextList;
    if (T == CostumeCategoryView && scripted != null) {
      return scripted as Result<List<T>>;
    }
    return super.runList(call, dtoInvalidCode: dtoInvalidCode);
  }

  @override
  Future<Result<IdVersionResponse>> create(
    String seasonId,
    CreateCostumeCategoryRequest request,
  ) {
    lastCreateRequest = request;
    final scripted = nextCreate;
    if (scripted != null) return Future.value(scripted);
    return Future.value(
      Right<ProblemError, IdVersionResponse>(
        IdVersionResponse(
          (b) => b
            ..id = 'n1'
            ..version = 1,
        ),
      ),
    );
  }

  @override
  Future<Result<int>> update(String id, UpdateCostumeCategoryRequest request) {
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right<ProblemError, int>(2));
  }

  @override
  Future<Result<int>> archive(String id, VersionRequest version) {
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right<ProblemError, int>(2));
  }
}

Future<_Fixture> _buildFixture() async {
  final db = CacheDatabase(NativeDatabase.memory());
  final repo = _FakeCategoryRepository(
    BreakdownApi(),
    CostumeCategoryCacheDao(db),
  );
  final scheduler = ManualReconciliationScheduler();
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(devAuthConfig),
      cacheDatabaseProvider.overrideWithValue(db),
      costumeCategoryRepositoryProvider.overrideWithValue(repo),
      reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(db.close);
  await container.read(authSessionControllerProvider.notifier).signIn();
  return _Fixture(container, db, repo, scheduler);
}

class _Fixture {
  _Fixture(this.container, this.db, this.repo, this.scheduler);
  final ProviderContainer container;
  final CacheDatabase db;
  final _FakeCategoryRepository repo;
  final ManualReconciliationScheduler scheduler;

  CostumeCategoriesController get controller =>
      container.read(costumeCategoriesControllerProvider('season-1').notifier);

  CostumeCategoriesScreenState get state =>
      container.read(costumeCategoriesControllerProvider('season-1'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CostumeCategoriesController.create', () {
    test('derives the order key from the complete projection', () async {
      final ctx = await _buildFixture();
      // Archived rows are hidden at render time but count for derivation.
      ctx.repo.nextList = Right([
        _category('c1', orderKey: '!'),
        _category('c2', orderKey: '"', archived: true),
      ]);
      await ctx.controller.refresh();
      expect(ctx.controller.deriveNextOrderKey(), '#');

      final res = await ctx.controller.create(name: 'Hats');
      expect(res.isRight(), isTrue);
      // The POST carries the appended successor of the greatest key of the
      // COMPLETE projection (archived `"` included → `#`).
      expect(ctx.repo.lastCreateRequest?.orderKey, '#');
      expect(ctx.repo.lastCreateRequest?.seasonId, 'season-1');
    });

    test('first create in an empty list carries `!`', () async {
      final ctx = await _buildFixture();
      ctx.repo.nextList = const Right([]);
      await ctx.controller.create(name: 'First');
      expect(ctx.repo.lastCreateRequest?.orderKey, '!');
    });

    test('reconciliation drops the overlay once projected', () async {
      final ctx = await _buildFixture();
      ctx.repo.nextList = Right([_category('n1', orderKey: '!')]);
      await ctx.controller.create(name: 'Hats');
      await ctx.controller.reconcile();
      expect(ctx.state.overlays, isEmpty);
    });
  });

  group('CostumeCategoriesController failure paths', () {
    test('network failure before 2xx: no overlay, Err keyed on code', () async {
      final ctx = await _buildFixture();
      ctx.repo.nextList = const Right([]);
      ctx.repo.nextCreate = const Left(_networkDown);
      final res = await ctx.controller.create(name: 'Hats');
      expect(res.isLeft(), isTrue);
      expect(ctx.state.overlays, isEmpty);
      expect(ctx.state.commandError?.code, 'transport.connectionError');
    });

    test(
      'rename echoes the read row version; 409 surfaces keyed copy',
      () async {
        final ctx = await _buildFixture();
        ctx.repo.nextList = Right([_category('c1', version: 4)]);
        await ctx.controller.refresh();
        ctx.repo.nextWrite = const Left(_versionConflict);
        final res = await ctx.controller.rename(
          category: _category('c1', version: 4),
          name: 'Caps',
        );
        expect(res.isLeft(), isTrue);
        // 409 → keyed copy, no silent overwrite, no overlay.
        expect(ctx.state.commandError?.code, 'concurrency.conflict');
        expect(ctx.state.overlays, isEmpty);
      },
    );

    test(
      'archive success reconciles; toggle reveals the archived row',
      () async {
        final ctx = await _buildFixture();
        ctx.repo.nextList = Right([_category('c1')]);
        await ctx.controller.refresh();
        expect(ctx.state.showArchived, isFalse);

        // Server marks the row archived; the bounded refetch confirms it.
        ctx.repo.nextList = Right([_category('c1', archived: true)]);
        final res = await ctx.controller.archive(category: _category('c1'));
        expect(res.isRight(), isTrue);
        await ctx.controller.refresh();
        // Hidden by default…
        expect(
          ctx.state.rows.whereType<ProjectedCostumeCategoryRow>(),
          isEmpty,
        );
        // …revealed by the toggle.
        ctx.controller.toggleArchivedVisibility();
        expect(ctx.state.showArchived, isTrue);
        expect(
          ctx.state.rows
              .whereType<ProjectedCostumeCategoryRow>()
              .single
              .category
              .id,
          'c1',
        );
      },
    );

    test('deleted parent (404) surfaces the not-found branch', () async {
      final ctx = await _buildFixture();
      ctx.repo.nextList = const Left(_gone);
      await ctx.controller.refresh();
      expect(ctx.state.notFound?.code, 'season.not-found');
    });
  });
}
