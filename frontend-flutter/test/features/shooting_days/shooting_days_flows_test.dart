// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

// Tier-2 flow tests for `ShootingDaysScreen` (Task 8.3 coverage): create
// sheet submit (append key + Manual), rename sheet, reschedule via the
// Material date picker, archive confirm-first, reorder move up/down as
// single-intent PATCHes, error dismiss.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:one_of/one_of.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/shooting_day_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/shooting_days/shooting_days_controller.dart';
import 'package:frontend_flutter/features/shooting_days/shooting_days_screen.dart';

import '../seasons/seasons_test_fakes.dart';

ShootingDayView _day(
  String id, {
  String orderKey = '!',
  String? label,
  Date? date,
  int version = 1,
}) => ShootingDayView(
  (b) => b
    ..id = id
    ..episodeId = 'episode-1'
    ..orderKey = orderKey
    ..source_.replace(
      ShootingDaySource((s) => s..oneOf = OneOf.fromValue1(value: 'Manual')),
    )
    ..label = label
    ..date = date
    ..archived = false
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version,
);

EpisodeView _episode() => EpisodeView(
  (b) => b
    ..id = 'episode-1'
    ..blockId = 'block-1'
    ..number = 1
    ..seriesId = 'series-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

class _FakeShootingDayRepository extends ShootingDayRepository {
  _FakeShootingDayRepository(super.api, super.cache);

  int createCalls = 0;
  int updateCalls = 0;
  int archiveCalls = 0;
  CreateShootingDayRequest? lastCreate;

  @override
  Future<Result<IdVersionResponse>> create(
    String episodeId,
    CreateShootingDayRequest request,
  ) {
    createCalls++;
    lastCreate = request;
    return Future.value(
      Right(
        IdVersionResponse(
          (b) => b
            ..id = 'd-new-$createCalls'
            ..version = 1,
        ),
      ),
    );
  }

  String? lastUpdateId;
  UpdateShootingDayRequest? lastUpdate;

  @override
  Future<Result<int>> update(String id, UpdateShootingDayRequest request) {
    updateCalls++;
    lastUpdateId = id;
    lastUpdate = request;
    return Future.value(const Right(2));
  }

  @override
  Future<Result<int>> archive(String id, VersionRequest version) {
    archiveCalls++;
    return Future.value(const Right(2));
  }
}

Future<void> _pumpFrames(WidgetTester tester, {int n = 6}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late CacheDatabase db;
  late _FakeShootingDayRepository repo;
  late ValueNotifier<Result<List<ShootingDayView>>> holder;
  late ProviderContainer container;

  Future<void> setupContainer({
    List<ShootingDayView> initialRows = const [],
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _FakeShootingDayRepository(BreakdownApi(), ShootingDayCacheDao(db));
    holder = ValueNotifier<Result<List<ShootingDayView>>>(Right(initialRows));
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        shootingDayRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith(
          (ref) => ManualReconciliationScheduler(),
        ),
        shootingDaysListFetchProvider('episode-1').overrideWith((ref) async {
          final dao = ShootingDayCacheDao(ref.watch(cacheDatabaseProvider));
          return holder.value.match((err) => Left(err), (rows) async {
            final ordered = rows.toList()
              ..sort((a, b) => a.orderKey.compareTo(b.orderKey));
            await dao.applySnapshotForEpisode(
              'episode-1',
              ordered,
              DateTime.utc(2026, 1, 1),
            );
            return Right(ordered);
          });
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ShootingDaysScreen(episode: _episode())),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ShootingDaysScreen flows (8.3)', () {
    testWidgets('create sheet: label submit carries append key', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [_day('d-1', orderKey: '!', label: '1. Tag')],
      );
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('shooting-day-add-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('create-shooting-day-label')),
        '2. Tag',
      );
      await tester.tap(find.byKey(const Key('create-shooting-day-submit')));
      await _pumpFrames(tester);
      expect(repo.createCalls, 1);
      // Append-after-last over the episode projection (shared rule).
      expect(repo.lastCreate!.orderKey.compareTo('!') > 0, isTrue);
      expect(find.byKey(const Key('overlay-d-new-1')), findsOneWidget);
    });

    testWidgets('rename sheet dispatches single-intent rename', (tester) async {
      await setupContainer(initialRows: [_day('d-1', label: 'Old')]);
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('shooting-day-menu-d-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shooting-day-rename-d-1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('rename-shooting-day-label')),
        'New',
      );
      await tester.tap(find.byKey(const Key('rename-shooting-day-submit')));
      await _pumpFrames(tester);
      expect(repo.updateCalls, 1);
    });

    testWidgets('reschedule via Material date picker', (tester) async {
      await setupContainer(initialRows: [_day('d-1', label: 'Day')]);
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('shooting-day-menu-d-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shooting-day-reschedule-d-1')));
      await tester.pumpAndSettle();
      // The Material date dialog renders; confirm the default month.
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      await tester.tap(find.text('OK'));
      await _pumpFrames(tester);
      expect(repo.updateCalls, 1);
    });

    testWidgets('archive confirm-first, then dispatch', (tester) async {
      await setupContainer(initialRows: [_day('d-1', label: 'Day')]);
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('shooting-day-menu-d-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shooting-day-archive-d-1')));
      await tester.pumpAndSettle();
      expect(repo.archiveCalls, 0);
      await tester.tap(
        find.byKey(const Key('shooting-day-archive-confirm-d-1')),
      );
      await _pumpFrames(tester);
      expect(repo.archiveCalls, 1);
    });

    testWidgets('move down issues single new key', (tester) async {
      await setupContainer(
        initialRows: [
          _day('d-1', orderKey: 'a', label: 'First'),
          _day('d-2', orderKey: 'b', label: 'Second'),
        ],
      );
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('shooting-day-menu-d-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shooting-day-down-d-1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('shooting-day-down-d-1')));
      await _pumpFrames(tester);
      expect(repo.updateCalls, 1);
      // Append edge past 'b': the shared append rule (unique, ordered).
      expect(repo.lastUpdateId, 'd-1');
      expect(repo.lastUpdate!.orderKey, 'c');
      await tester.tap(find.byKey(const Key('shooting-day-menu-d-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shooting-day-up-d-2')));
      await _pumpFrames(tester);
      expect(repo.updateCalls, 2);
      // Prepend edge below 'a': midpoint('', 'a') == 'A' (unique, ordered).
      expect(repo.lastUpdateId, 'd-2');
      expect(repo.lastUpdate!.orderKey, 'A');
    });

    testWidgets('midpoint reorder lands strictly between neighbors', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [
          _day('d-1', orderKey: 'a', label: 'First'),
          _day('d-2', orderKey: 'c', label: 'Second'),
          _day('d-3', orderKey: 'e', label: 'Third'),
        ],
      );
      await pumpScreen(tester);
      // Move d-3 (e) above d-2 (c): strictly between 'a' and 'c' → 'b'.
      await tester.tap(find.byKey(const Key('shooting-day-menu-d-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shooting-day-up-d-3')));
      await _pumpFrames(tester);
      expect(repo.lastUpdateId, 'd-3');
      expect(repo.lastUpdate!.orderKey, 'b');
    });

    testWidgets('dense floor move issues no duplicate key', (tester) async {
      await setupContainer(
        initialRows: [
          _day('d-1', orderKey: '!', label: 'First'),
          _day('d-2', orderKey: '"', label: 'Second'),
        ],
      );
      await pumpScreen(tester);
      // Prepend below '!' is inexpressible: no command, explanatory copy.
      await tester.tap(find.byKey(const Key('shooting-day-menu-d-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shooting-day-up-d-2')));
      await _pumpFrames(tester);
      expect(repo.updateCalls, 0);
      expect(find.textContaining('leave no room'), findsOneWidget);
    });

    testWidgets('320px tile: title stays usable, actions behind menu', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [
          _day('d-1', orderKey: 'a', label: 'First'),
          // Dated, unarchived middle row: all six actions available.
          _day('d-2', orderKey: 'b', label: 'Second', date: Date(2026, 5, 1)),
          _day('d-3', orderKey: 'c', label: 'Third'),
        ],
      );
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: ShootingDaysScreen(episode: _episode())),
        ),
      );
      await tester.pumpAndSettle();
      // Title space survives: exactly one overflow control per row.
      expect(find.text('Second'), findsOneWidget);
      expect(find.byKey(const Key('shooting-day-menu-d-2')), findsOneWidget);
      expect(find.byKey(const Key('shooting-day-rename-d-2')), findsNothing);
      await tester.tap(find.byKey(const Key('shooting-day-menu-d-2')));
      await tester.pumpAndSettle();
      // All six actions reachable through the menu.
      for (final key in [
        'shooting-day-up-d-2',
        'shooting-day-down-d-2',
        'shooting-day-rename-d-2',
        'shooting-day-reschedule-d-2',
        'shooting-day-unschedule-d-2',
        'shooting-day-archive-d-2',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget);
      }
    });

    testWidgets('command error dismisses', (tester) async {
      await setupContainer(initialRows: [_day('d-1', label: 'Day')]);
      await pumpScreen(tester);
      container
          .read(shootingDaysCommandErrorProvider('episode-1').notifier)
          .set(const ProblemError(code: 'transport.x'));
      await _pumpFrames(tester);
      expect(
        find.byKey(const Key('shooting-day-command-error-banner')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('shooting-day-command-error-dismiss')),
      );
      await _pumpFrames(tester);
      expect(
        find.byKey(const Key('shooting-day-command-error-banner')),
        findsNothing,
      );
    });
  });
}
