// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: hy3 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/season_repository.dart';
import 'package:frontend_flutter/features/seasons/seasons_view_widget.dart';
import 'package:frontend_flutter/src/network/api_client.dart';

SeasonView _season(String id, {String? title}) => SeasonView(
  (b) => b
    ..id = id
    ..number = 1
    ..seriesId = 'series-1'
    ..title = title
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

void main() {
  // Task 4.3 — stale indicator + disabled write FAB on offline error.
  testWidgets('renders stale banner and disables FAB when offline', (
    tester,
  ) async {
    final db = CacheDatabase(NativeDatabase.memory());
    final repo = SeasonRepository(BreakdownApi(), SeasonCacheDao(db));
    // Seed a previously-cached row (last seen before going offline).
    await repo.fetchAndCacheList(
      () async => Right([_season('s1', title: 'Spring')]),
    );

    final holder = ValueNotifier<Result<List<SeasonView>>>(
      const Left(ProblemError(code: 'transport.offline')),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Transport is never exercised here (fetch is holder-driven);
          // the override satisfies the fail-closed composition default.
          apiDioProvider.overrideWithValue(Dio()),
          cacheDatabaseProvider.overrideWithValue(db),
          seasonsListFetchProvider.overrideWith((ref) async {
            final r = ref.watch(seasonRepositoryProvider);
            return r.fetchAndCacheList(() async => holder.value);
          }),
        ],
        child: MaterialApp(home: const SeasonsViewWidget()),
      ),
    );
    await tester.runAsync(() async {
      await tester.pumpAndSettle();
    });

    // Cached rows still render (offline cold start, Task 4.1).
    expect(find.text('Spring'), findsOneWidget);
    // Stale indicator is shown.
    expect(find.byKey(const Key('stale-banner')), findsOneWidget);
    // Error / retry affordance is shown.
    expect(find.byKey(const Key('error-banner')), findsOneWidget);
    expect(find.byKey(const Key('retry-button')), findsOneWidget);

    // Write FAB is disabled while offline (Task 4.2).
    final fab = tester.widget<FloatingActionButton>(
      find.byKey(const Key('season-add-fab')),
    );
    expect(fab.onPressed, isNull);

    await db.close();
  });
}
