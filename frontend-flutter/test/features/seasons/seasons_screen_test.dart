// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: qwen3.8-flash (opencode-go)

import 'dart:async';

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
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/shell/shell_controller.dart';
import 'package:frontend_flutter/features/seasons/seasons_controller.dart';
import 'package:frontend_flutter/features/seasons/seasons_screen.dart';

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

  /// The held list-fetch seam (`holdInitialFetch: true`): stays pending
  /// until the test completes it, so the cold-start window is observable.
  late Completer<Result<List<SeasonView>>> heldFetch;

  /// Container with fake create and holder-driven projection writing the
  /// in-memory Drift cache. Dev-auth boots signed out at the login gate
  /// (spec `flutter-auth-shell`), so a dev-auth container resolves the
  /// permissive session explicitly — the `Continue` action the gate offers.
  /// [realOidcConfig] stays signed out (AUTHZ-GATE denial paths).
  ///
  /// [holdInitialFetch] keeps the list fetch in flight (a never-completing
  /// seam) so the cold-start skeleton window is observable; [seed] writes
  /// hierarchy/costume cache rows BEFORE the screen pumps (the metrics
  /// provider reads them on first build); [clock] pins the TTL clock for
  /// deterministic stale-indicator rendering.
  Future<void> setupContainer({
    AppConfig config = devAuthConfig,
    List<SeasonView> initialRows = const [],
    bool failInitialFetch = false,
    bool holdInitialFetch = false,
    void Function(CacheDatabase db)? seed,
    Clock? clock,
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    seed?.call(db);
    repo = FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db));
    holder = ValueNotifier<Result<List<SeasonView>>>(
      failInitialFetch ? const Left(_listUnavailable) : Right(initialRows),
    );
    scheduler = ManualReconciliationScheduler();
    heldFetch = Completer<Result<List<SeasonView>>>();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        if (clock != null) clockProvider.overrideWithValue(clock),
        if (!config.devAuthMode) ...[
          dioProvider.overrideWithValue(Dio()),
          tokenStoreProvider.overrideWithValue(FakeTokenStore(null)),
        ],
        cacheDatabaseProvider.overrideWithValue(db),
        seasonRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
        seasonsListFetchProvider.overrideWith((ref) async {
          final r = ref.watch(seasonRepositoryProvider);
          return holdInitialFetch
              // The never-completed (until the test completes it) seam
              // keeps the cold-start loading window observable.
              ? heldFetch.future
              : r.fetchAndCacheList(() async => holder.value);
        }),
      ],
    );
    addTearDown(container.dispose);
    if (config.devAuthMode) {
      await container.read(authSessionControllerProvider.notifier).signIn();
    }
  }

  Future<void> pumpScreen(WidgetTester tester, {ThemeData? theme}) async {
    // A phone-tall test surface (the 600px default clips the bottom sheet).
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme ?? AppThemes.light(),
          home: const SeasonsScreen(),
        ),
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
      await setupContainer(
        initialRows: [season('a', number: 1, title: 'Spring')],
      );
      await pumpScreen(tester);

      expect(find.text('Seasons'), findsOneWidget);
      expect(find.byKey(const Key('season-a')), findsOneWidget);
      expect(find.text('Spring'), findsOneWidget);
      // AUTHZ-GATE (dev-auth session): the create FAB is visible.
      expect(find.byKey(const Key('season-add-fab')), findsOneWidget);
    });

    testWidgets('empty projection shows the guided empty state', (
      tester,
    ) async {
      await setupContainer();
      await pumpScreen(tester);
      // Task 3.4: the bare 'No seasons yet' text became the guided empty
      // state (headline + guidance + setup/import CTAs).
      expect(find.byKey(const Key('seasons-empty-title')), findsOneWidget);
      expect(find.byKey(const Key('seasons-empty-guidance')), findsOneWidget);
      expect(find.byKey(const Key('seasons-empty-setup-cta')), findsOneWidget);
      expect(find.byKey(const Key('seasons-empty-import-cta')), findsOneWidget);
    });

    testWidgets('AUTHZ-GATE: signed out → FAB hidden (task 3.3)', (
      tester,
    ) async {
      await setupContainer(config: realOidcConfig);
      await pumpScreen(tester);
      expect(find.byKey(const Key('season-add-fab')), findsNothing);
    });
  });

  group('Create Season sheet (task 3.2)', () {
    testWidgets('FAB opens the form and submits a command', (tester) async {
      await setupContainer();
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
      await setupContainer();
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
      await setupContainer();
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
      await setupContainer(
        initialRows: [season('a', number: 1, title: 'Spring')],
      );
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
      await setupContainer();
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
    await setupContainer(
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

  group('Season cards (task 4.1)', () {
    final fixedClock = Clock.fixed(DateTime.utc(2026, 1, 2, 12));

    /// Seeds two blocks + one costume for season 'a'; the writes predate
    /// the pinned clock by MORE than the 24h TTL → stale indicator.
    void seedStale(CacheDatabase db) {
      final at = DateTime.utc(2026, 1, 1, 6); // > TTL before the clock
      BlockCacheDao(db)
        ..upsert(block('b1', seasonId: 'a'), at)
        ..upsert(block('b2', seasonId: 'a'), at);
      CostumeCacheDao(db).upsert('a', costume('c1'), at);
    }

    testWidgets('projected card renders cached metadata (counts)', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [season('a', number: 1, title: 'Spring')],
        seed: seedStale,
        clock: fixedClock,
      );
      await pumpScreen(tester);

      expect(find.byKey(const Key('season-a')), findsOneWidget);
      expect(find.text('Spring'), findsOneWidget);
      // Metadata line: cached counts joined (glossary seasons.meta.*).
      expect(find.textContaining('2 Blöcke'), findsOneWidget);
      expect(find.textContaining('1 Kostüme'), findsOneWidget);
    });

    testWidgets('projected card WITHOUT cached entry omits the metadata line', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [season('a', number: 1, title: 'Spring')],
        clock: fixedClock,
      );
      await pumpScreen(tester);

      expect(find.byKey(const Key('season-a')), findsOneWidget);
      expect(find.text('Spring'), findsOneWidget);
      // No counts anywhere (never fabricated).
      expect(find.textContaining('Blöcke'), findsNothing);
      // Fresh metadata → no stale indicator.
      expect(find.byIcon(Icons.history), findsNothing);
    });

    testWidgets('stale cached metadata renders the stale indicator', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [season('a', number: 1, title: 'Spring')],
        seed: seedStale,
        clock: fixedClock,
      );
      await pumpScreen(tester);

      // Glossary `seasons.stale`: history icon + relative-time reference.
      expect(find.byIcon(Icons.history), findsOneWidget);
      expect(find.textContaining('Stand:'), findsOneWidget);
      // The counts stay visible next to the indicator (team decision 4).
      expect(find.textContaining('Blöcke'), findsOneWidget);
    });

    testWidgets('optimistic overlay renders as a card with status copy', (
      tester,
    ) async {
      await setupContainer();
      await pumpScreen(tester);
      await submitCreate(
        tester,
        seriesId: 'series-1',
        number: '2',
        title: 'Autumn',
      );

      // Keys/semantics unchanged from the tile era.
      expect(find.byKey(const Key('overlay-n1')), findsOneWidget);
      expect(find.text('Autumn'), findsOneWidget);
      expect(find.text('Just created — syncing…'), findsOneWidget);
      expect(find.byKey(const Key('overlay-spinner')), findsOneWidget);
    });

    testWidgets('card tap sets the active season and jumps to Planen', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [season('a', number: 1, title: 'Spring')],
        clock: fixedClock,
      );
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('season-a')));
      // The active-season resolution converges asynchronously (the shell
      // controller rebuilds from the persisted reference); wait bounded.
      for (
        var i = 0;
        i < 20 &&
            container.read(shellControllerProvider).activeSeason?.id != 'a';
        i++
      ) {
        await pumpFrames(tester, n: 2);
      }
      final shell = container.read(shellControllerProvider);
      expect(shell.activeSeason?.id, 'a');
      expect(shell.selectedIndex, kPlanenTabIndex);
    });
  });

  group('Extended FAB + empty state (task 4.2)', () {
    testWidgets('extended FAB renders the visible label', (tester) async {
      await setupContainer();
      await pumpScreen(tester);

      final fab = find.byKey(const Key('season-add-fab'));
      expect(fab, findsOneWidget);
      expect(
        find.descendant(of: fab, matching: find.text('Season erstellen')),
        findsOneWidget,
      );
      // The add icon rides INSIDE the extended FAB (the empty state's
      // setup CTA carries its own, so scope the assertion to the FAB).
      expect(
        find.descendant(of: fab, matching: find.byIcon(Icons.add)),
        findsOneWidget,
      );
    });

    testWidgets('signed out: no FAB and the setup CTA is disabled', (
      tester,
    ) async {
      await setupContainer(config: realOidcConfig);
      await pumpScreen(tester);

      expect(find.byKey(const Key('season-add-fab')), findsNothing);
      final cta = find.byKey(const Key('seasons-empty-setup-cta'));
      expect(cta, findsOneWidget);
      // The gated entry never opens the create sheet (client-side gate).
      await tester.tap(cta);
      await pumpFrames(tester);
      expect(find.byKey(const Key('create-series-id')), findsNothing);
    });

    testWidgets('import CTA jumps to the Mehr tab (gate travels with the '
        'entry — no network call from the CTA)', (tester) async {
      await setupContainer();
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('seasons-empty-import-cta')));
      await pumpFrames(tester);

      expect(
        container.read(shellControllerProvider).selectedIndex,
        kMehrTabIndex,
      );
    });
  });

  testWidgets(
    'cold start shows the skeleton, no empty-state flash (task 4.3)',
    (tester) async {
      await setupContainer(holdInitialFetch: true);
      await pumpScreen(tester);

      // Loading window: skeleton renders, empty state does NOT.
      expect(find.byKey(const Key('seasons-skeleton')), findsOneWidget);
      expect(find.byKey(const Key('seasons-empty-title')), findsNothing);

      // Data resolves → cards replace the skeleton.
      heldFetch.complete(Right([season('a', number: 1, title: 'Spring')]));
      await pumpFrames(tester, n: 10);
      expect(find.byKey(const Key('seasons-skeleton')), findsNothing);
      expect(find.byKey(const Key('season-a')), findsOneWidget);
    },
  );

  group(
    'Goldens (task 4.4: light/dark × cards full/optimistic + empty + skeleton)',
    () {
      final fixedClock = Clock.fixed(DateTime.utc(2026, 1, 2, 12));

      /// Full card list: two projected cards (one with stale metadata),
      /// deterministic frame (no spinner, no animation).
      Future<void> pumpFull(WidgetTester tester, {required bool dark}) async {
        await setupContainer(
          initialRows: [
            season('a', number: 1, title: 'Spring'),
            season('b', number: 2, title: 'Summer'),
          ],
          seed: (db) {
            final at = DateTime.utc(2026, 1, 1, 6); // > TTL before the clock
            BlockCacheDao(db)
              ..upsert(block('b1', seasonId: 'a'), at)
              ..upsert(block('b2', seasonId: 'a'), at);
            CostumeCacheDao(db).upsert('a', costume('c1'), at);
          },
          clock: fixedClock,
        );
        await pumpScreen(
          tester,
          theme: dark ? AppThemes.dark() : AppThemes.light(),
        );
      }

      for (final dark in [false, true]) {
        final variant = dark ? 'dark' : 'light';

        testWidgets('seasons_home_${variant}_full', (tester) async {
          await pumpFull(tester, dark: dark);
          await expectLater(
            find.byType(SeasonsScreen),
            matchesGoldenFile('goldens/seasons_home_${variant}_full.png'),
          );
        });

        testWidgets('seasons_home_${variant}_empty', (tester) async {
          await setupContainer(clock: fixedClock);
          await pumpScreen(
            tester,
            theme: dark ? AppThemes.dark() : AppThemes.light(),
          );
          await expectLater(
            find.byType(SeasonsScreen),
            matchesGoldenFile('goldens/seasons_home_${variant}_empty.png'),
          );
        });

        testWidgets('seasons_home_${variant}_skeleton', (tester) async {
          await setupContainer(holdInitialFetch: true, clock: fixedClock);
          await pumpScreen(
            tester,
            theme: dark ? AppThemes.dark() : AppThemes.light(),
          );
          await expectLater(
            find.byType(SeasonsScreen),
            matchesGoldenFile('goldens/seasons_home_${variant}_skeleton.png'),
          );
        });

        testWidgets('seasons_home_${variant}_optimistic', (tester) async {
          await setupContainer(
            initialRows: [
              season('a', number: 1, title: 'Spring'),
              season('b', number: 2, title: 'Summer'),
            ],
            clock: fixedClock,
          );
          await pumpScreen(
            tester,
            theme: dark ? AppThemes.dark() : AppThemes.light(),
          );
          await submitCreate(
            tester,
            seriesId: 'series-1',
            number: '3',
            title: 'Autumn',
          );
          // Drive to the settled stale state (no animated spinner in the
          // frame — the syncing spinner is not golden-safe).
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
            matchesGoldenFile('goldens/seasons_home_${variant}_optimistic.png'),
          );
        });
      }
    },
  );
}
