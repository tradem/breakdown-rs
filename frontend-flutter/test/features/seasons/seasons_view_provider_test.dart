// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: hy3 (opencode-go)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/cache/seasons_view.dart';
import 'package:frontend_flutter/data/season_repository.dart';
import 'package:frontend_flutter/src/network/api_client.dart';

SeasonView _season(String id, {int number = 1, String? title}) => SeasonView(
  (b) => b
    ..id = id
    ..number = number
    ..seriesId = 'series-1'
    ..title = title
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

const _offline = ProblemError(code: 'transport.offline');

/// Builds a container whose list fetch is backed by [holder] (so tests can
/// flip the fetch result between steps) and whose cache is the in-memory [db].
ProviderContainer buildContainer(
  CacheDatabase db,
  ValueNotifier<Result<List<SeasonView>>> holder, {
  SeasonRepository? repository,
  void Function()? onFetch,
}) {
  return ProviderContainer(
    overrides: [
      // Transport is never exercised here (fetch is holder-driven);
      // the override satisfies the fail-closed composition default.
      apiDioProvider.overrideWithValue(Dio()),
      cacheDatabaseProvider.overrideWithValue(db),
      if (repository != null)
        seasonRepositoryProvider.overrideWithValue(repository),
      seasonsListFetchProvider.overrideWith((ref) async {
        onFetch?.call();
        final repo = ref.watch(seasonRepositoryProvider);
        return repo.fetchAndCacheList(() async => holder.value);
      }),
    ],
  );
}

/// Keeps the controller alive (so a later `invalidateSelf` re-runs it) and
/// resolves with its settled state without throwing on fetch errors. This
/// avoids the bare-container `.future` hang for async notifiers.
Future<AsyncValue<SeasonsView>> settle(ProviderContainer container) {
  final done = Completer<AsyncValue<SeasonsView>>();
  container.listen(seasonsViewControllerProvider, (prev, next) {
    if (next is AsyncData || next is AsyncError) {
      if (!done.isCompleted) done.complete(next);
    }
  });
  return done.future;
}

void main() {
  group('seasonsView provider (offline + reconciliation)', () {
    late CacheDatabase db;

    setUp(() => db = CacheDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    // Task 4.1 — cold-start offline renders last cached rows with a stale
    // indicator and surfaces the error (no blank screen).
    test('offline cold start renders cached rows + stale + error', () async {
      final repo = SeasonRepository(BreakdownApi(), SeasonCacheDao(db));
      await repo.fetchAndCacheList(
        () async => Right([_season('s1', title: 'Spring'), _season('s2')]),
      );

      final holder = ValueNotifier<Result<List<SeasonView>>>(Left(_offline));
      final container = buildContainer(db, holder);
      await settle(container);

      final view = container.read(seasonsView);
      expect(view.rows.map((s) => s.id).toList(), ['s1', 's2']);
      expect(view.isStale, isTrue);
      expect(view.error, isNotNull);
    });

    // Task 4.4 — fetch errors but cache has rows: the raw provider emits an
    // AsyncError AND the derived `seasonsView` retains non-empty stale rows
    // (jointly satisfies Task 3.3 ∧ Task 4.1).
    test(
      'fetch error surfaces AsyncError while retaining stale rows',
      () async {
        final repo = SeasonRepository(BreakdownApi(), SeasonCacheDao(db));
        await repo.fetchAndCacheList(() async => Right([_season('s1')]));

        final holder = ValueNotifier<Result<List<SeasonView>>>(Left(_offline));
        final container = buildContainer(db, holder);
        await settle(container);

        // The raw controller is in AsyncError (3.3: not silently discarded).
        expect(
          container.read(seasonsViewControllerProvider),
          isA<AsyncError>(),
        );
        // The derived selector still exposes the retained rows + the error.
        final view = container.read(seasonsView);
        expect(view.rows, hasLength(1));
        expect(view.error, isNotNull);
      },
    );

    // Task 4.5 — a successful refetch updates the retained snapshot; a later
    // failed refetch preserves the LATEST good snapshot, not the initial one.
    test(
      'prevRows keeps the latest successful snapshot across a later failure',
      () async {
        final holder = ValueNotifier<Result<List<SeasonView>>>(
          Right([_season('a')]),
        );
        final container = buildContainer(db, holder);
        await settle(container);
        expect(container.read(seasonsView).rows.map((s) => s.id).toList(), [
          'a',
        ]);

        // Step 2: successful refetch -> [a, b]; snapshot must advance.
        holder.value = Right([_season('a'), _season('b')]);
        container.invalidate(seasonsListFetchProvider);
        container.invalidate(seasonsViewControllerProvider);
        await settle(container);
        expect(container.read(seasonsView).rows.map((s) => s.id).toList(), [
          'a',
          'b',
        ]);

        // Step 3: failed refetch must retain [a, b], NOT fall back to [a].
        holder.value = Left(_offline);
        container.invalidate(seasonsListFetchProvider);
        container.invalidate(seasonsViewControllerProvider);
        await settle(container);
        expect(
          container.read(seasonsViewControllerProvider),
          isA<AsyncError>(),
        );
        final view = container.read(seasonsView);
        expect(view.rows.map((s) => s.id).toList(), ['a', 'b']);
        expect(view.error, isNotNull);
      },
    );

    // Task 3.2 — on-write-invalidate: a successful command refetches the
    // affected read projection.
    test('createSeason triggers a refetch of the read projection', () async {
      var fetchCalls = 0;
      final holder = ValueNotifier<Result<List<SeasonView>>>(
        Right([_season('a')]),
      );
      final container = buildContainer(
        db,
        holder,
        repository: _FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db)),
        onFetch: () => fetchCalls++,
      );
      await settle(container);
      final before = fetchCalls;

      final res = await container
          .read(seasonsViewControllerProvider.notifier)
          .createSeason(
            CreateSeasonRequest(
              (b) => b
                ..number = 1
                ..seriesId = 'series-1'
                ..title = 'New',
            ),
          );
      expect(res.isRight(), isTrue);

      // The invalidate inside createSeason must re-run the list fetch.
      await settle(container);
      expect(fetchCalls, greaterThan(before));
    });
  });
}

/// Fake repository whose write commands succeed without touching the network,
/// so the on-write-invalidate path can be exercised deterministically.
class _FakeSeasonRepository extends SeasonRepository {
  _FakeSeasonRepository(super.api, super.cache);

  @override
  Future<Result<IdVersionResponse>> create(CreateSeasonRequest request) =>
      Future.value(
        Right<ProblemError, IdVersionResponse>(
          IdVersionResponse(
            (b) => b
              ..id = 'new'
              ..version = 1,
          ),
        ),
      );
}
