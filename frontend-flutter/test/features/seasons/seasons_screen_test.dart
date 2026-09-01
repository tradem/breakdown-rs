// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.8-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/features/seasons/seasons_controller.dart';
import 'package:frontend_flutter/features/seasons/seasons_screen.dart';
import 'package:frontend_flutter/features/seasons/seasons_state.dart';

import 'seasons_test_fakes.dart';

const _conflict = ProblemError(code: 'seasons.conflict', status: 409);
const _networkDown = ProblemError(code: 'transport.connectionError');
const _listUnavailable = ProblemError(
  code: 'transport.seasons_list_unavailable',
);

/// Pumps a bounded number of frames (never `pumpAndSettle` while an
/// indeterminate spinner may be on screen — that would hang the settle loop).
Future<void> pumpFrames(WidgetTester tester, {int n = 6}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// Drives the manual scheduler until the predicate holds (deterministic;
/// bounded — no wall-clock gating, AGENTS.md §6).
Future<void> drive(
  WidgetTester tester,
  ManualReconciliationScheduler scheduler,
  bool Function() done,
) async {
  for (var i = 0; i < kMaxReconcileAttempts * 4 && !done(); i++) {
    scheduler.advanceAll();
    await pumpFrames(tester, n: 2);
  }
}

void main() {
  late CacheDatabase db;
  late FakeSeasonRepository repo;
  late ValueNotifier<Result<List<SeasonView>>> holder;
  late ManualReconciliationScheduler scheduler;
  late ProviderContainer container;

  /// Container with dev-auth session (or signed out for [realOidcConfig]),
  /// fake create, holder-driven projection writing the in-memory Drift cache.
  void setupContainer({
    AppConfig config = devAuthConfig,
    List<SeasonView> initialRows = const [],
    bool failInitialFetch = false,
  }) {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db));
    holder = ValueNotifier<Result<List<SeasonView>>>(
      failInitialFetch ? const Left(_listUnavailable) : Right(initialRows),
    );
    scheduler = ManualReconciliationScheduler();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        if (!config.devAuthMode) ...[
          dioProvider.overrideWithValue(Dio()),
          tokenStoreProvider.overrideWithValue(FakeTokenStore(null)),
        ],
        cacheDatabaseProvider.overrideWithValue(db),
        seasonRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
        seasonsListFetchProvider.overrideWith((ref) async {
          final r = ref.watch(seasonRepositoryProvider);
          return r.fetchAndCacheList(() async => holder.value);
        }),
      ],
    );
    addTearDown(container.dispose);
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    // A phone-tall test surface (the 600px default clips the bottom sheet).
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SeasonsScreen()),
      ),
    );
    // Settle the route / FAB entrance animations; the screen itself has no
    // indeterminate animation until a create is in flight.
    await tester.pumpAndSettle();
  }

  /// Drag the form until the submit button's center is on-screen (the sheet
  /// is scrollable; `ensureVisible` only reveals the button's edge).
  Future<void> revealSubmit(WidgetTester tester) async {
    final submit = find.byKey(const Key('create-submit'));
    final scroll = find.byType(SingleChildScrollView);
    for (var i = 0; i < 8; i++) {
      final center = tester.getCenter(submit);
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      if (center.dy < size.height - 30) return;
      await tester.drag(scroll, const Offset(0, -60));
      await pumpFrames(tester, n: 2);
    }
    fail('create-submit never became visible');
  }

  /// Open the sheet, fill the form, submit.
  Future<void> submitCreate(
    WidgetTester tester, {
    required String seriesId,
    required String number,
    required String title,
  }) async {
    await tester.tap(find.byKey(const Key('season-add-fab')));
    await tester.pumpAndSettle(); // sheet slide-in
    await tester.enterText(find.byKey(const Key('create-series-id')), seriesId);
    await tester.enterText(find.byKey(const Key('create-number')), number);
    await tester.enterText(find.byKey(const Key('create-title')), title);
    await revealSubmit(tester);
    await tester.tap(find.byKey(const Key('create-submit')));
    // Dispatch (microtasks) then jump past the sheet's slide-down; the
    // optimistic row's spinner may animate indefinitely afterwards, so this
    // must not be pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('SeasonsScreen rendering (tasks 3.1/3.2)', () {
    testWidgets('renders projected rows from the cache + FAB when authed', (
      tester,
    ) async {
      setupContainer(initialRows: [season('a', number: 1, title: 'Spring')]);
      await pumpScreen(tester);

      expect(find.text('Seasons'), findsOneWidget);
      expect(find.byKey(const Key('season-a')), findsOneWidget);
      expect(find.text('Spring'), findsOneWidget);
      // AUTHZ-GATE (dev-auth session): the create FAB is visible.
      expect(find.byKey(const Key('season-add-fab')), findsOneWidget);
    });

    testWidgets('empty projection shows the empty state', (tester) async {
      setupContainer();
      await pumpScreen(tester);
      expect(find.text('No seasons yet'), findsOneWidget);
    });

    testWidgets('AUTHZ-GATE: signed out → FAB hidden (task 3.3)', (
      tester,
    ) async {
      setupContainer(config: realOidcConfig);
      await pumpScreen(tester);
      expect(find.byKey(const Key('season-add-fab')), findsNothing);
    });
  });

  group('Create Season sheet (task 3.2)', () {
    testWidgets('FAB opens the form and submits a command', (tester) async {
      setupContainer();
      await pumpScreen(tester);

      await submitCreate(
        tester,
        seriesId: 'series-1',
        number: '2',
        title: 'Summer',
      );

      // Command dispatched; the optimistic overlay row renders (controller
      // state only — the Drift cache stays empty while unprojected).
      expect(repo.createCalls, 1);
      expect(find.byKey(const Key('overlay-n1')), findsOneWidget);
      expect(find.text('Summer'), findsOneWidget);
      // The sheet closed.
      expect(find.byKey(const Key('create-submit')), findsNothing);
    });

    testWidgets('invalid number blocks submission', (tester) async {
      setupContainer();
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('season-add-fab')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('create-number')), 'x');
      await revealSubmit(tester);
      await tester.tap(find.byKey(const Key('create-submit')));
      await pumpFrames(tester);

      expect(repo.createCalls, 0);
      expect(find.text('A whole number is required'), findsOneWidget);
    });
  });

  group('Failure paths in the UI (tasks 5.4/5.5)', () {
    testWidgets('POST network failure → banner keyed on code, no phantom row', (
      tester,
    ) async {
      setupContainer();
      repo.createResult = const Left(_networkDown);
      await pumpScreen(tester);

      await submitCreate(tester, seriesId: 's1', number: '1', title: 'Ghost');

      expect(find.byKey(const Key('create-error-banner')), findsOneWidget);
      expect(find.textContaining('Network problem'), findsOneWidget);
      // No phantom optimistic row.
      expect(find.byKey(const Key('overlay-n1')), findsNothing);
      expect(find.text('Ghost'), findsNothing);
    });

    testWidgets('409 conflict → banner keyed on code, nothing to revert', (
      tester,
    ) async {
      setupContainer(initialRows: [season('a', number: 1, title: 'Spring')]);
      repo.createResult = const Left(_conflict);
      await pumpScreen(tester);

      await submitCreate(tester, seriesId: 's1', number: '1', title: 'Dup');

      expect(find.byKey(const Key('create-error-banner')), findsOneWidget);
      expect(find.textContaining('already exists'), findsOneWidget);
      // No overlay was ever created (the 2xx never happened).
      expect(find.byKey(const Key('overlay-n1')), findsNothing);
      // The pre-existing projected row is untouched.
      expect(find.byKey(const Key('season-a')), findsOneWidget);

      // Dismiss clears the banner.
      await tester.tap(find.byKey(const Key('create-error-dismiss')));
      await pumpFrames(tester);
      expect(find.byKey(const Key('create-error-banner')), findsNothing);
    });
  });

  group('Reconciliation + pull-to-refresh in the UI (tasks 5.6/4.3)', () {
    testWidgets('retry exhaustion retains a stale overlay with warning', (
      tester,
    ) async {
      setupContainer();
      await pumpScreen(tester);
      await submitCreate(
        tester,
        seriesId: 'series-1',
        number: '2',
        title: 'Later',
      );

      // Drain the bounded retry budget deterministically.
      await drive(
        tester,
        scheduler,
        () => container
            .read(seasonsControllerProvider)
            .overlays
            .any((o) => o.status == OverlayStatus.stale),
      );

      final overlay = container.read(seasonsControllerProvider).overlays.single;
      expect(overlay.status, OverlayStatus.stale);

      // Stale UI: warning copy + non-spinner icon, row still visible.
      expect(find.byKey(const Key('overlay-n1')), findsOneWidget);
      expect(find.textContaining('catching up'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.byKey(const Key('overlay-spinner')), findsNothing);

      // Pull-to-refresh retries: projection catches up, overlay is dropped.
      holder.value = Right([season('n1', number: 2, title: 'Later')]);
      await tester.drag(
        find.byKey(const Key('seasons-list')),
        const Offset(0, 300),
      );
      await drive(
        tester,
        scheduler,
        () => find.byKey(const Key('overlay-n1')).evaluate().isEmpty,
      );

      expect(find.byKey(const Key('overlay-n1')), findsNothing);
      expect(find.byKey(const Key('season-n1')), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
    });
  });

  testWidgets('SeasonsScreen golden (projected + stale overlay)', (
    tester,
  ) async {
    setupContainer(
      initialRows: [
        season('a', number: 1, title: 'Spring'),
        season('b', number: 2, title: 'Summer'),
      ],
    );
    await pumpScreen(tester);
    await submitCreate(
      tester,
      seriesId: 'series-1',
      number: '3',
      title: 'Autumn',
    );

    // Drive to the settled stale state (no animated spinner in the frame).
    await drive(
      tester,
      scheduler,
      () => container
          .read(seasonsControllerProvider)
          .overlays
          .any((o) => o.status == OverlayStatus.stale),
    );
    await pumpFrames(tester);

    await expectLater(
      find.byType(SeasonsScreen),
      matchesGoldenFile('goldens/seasons_screen.png'),
    );
  });
}
