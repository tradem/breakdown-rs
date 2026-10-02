// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

// Tier-2 widget + golden tests for `ReportsIndexScreen`
// (`flutter-reports-index`): rows in server order, per-day finality from
// `wrapped_at` (no aggregate verdict), empty state, pending (optimistic)
// row exclusion, row tap → day-scoped `ReportsScreen`, and the
// zero-request denial matrix. Goldens across {light,dark} × {android,macOS}:
// loaded, empty, denied — the same matrix #549 extended for the report
// screen.

import 'dart:async';
import 'dart:io';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:one_of/one_of.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/scene_shoot_cache_dao.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/scene_shoot_repository.dart';
import 'package:frontend_flutter/data/shooting_day_repository.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/reports/reports_index_screen.dart';
import 'package:frontend_flutter/features/scene_shoots/scene_shoots_controller.dart';
import 'package:frontend_flutter/features/shooting_days/shooting_days_controller.dart';
import 'package:frontend_flutter/features/shooting_days/shooting_days_state.dart';

import '../seasons/seasons_test_fakes.dart';

ShootingDayView _day(
  String id, {
  String orderKey = '!',
  String? label,
  Date? date,
  DateTime? wrappedAt,
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
    ..version = 1
    ..wrappedAt = wrappedAt,
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

SeasonMembershipDto _membership({required bool active}) => SeasonMembershipDto(
  (b) => b
    ..seasonId = 'season-1'
    ..hasActiveCostumeRoleInSeason = active
    ..capabilities.replace(const <String>[]),
);

/// Report repository double: every call is counted so the AUTHZ-GATE tests
/// can assert the index issues ZERO report requests — before and after a
/// row push (task 5.3).
class _CountingReportsRepository extends SceneShootRepository {
  _CountingReportsRepository(super.api, super.cache);

  int jsonCalls = 0;
  int pdfCalls = 0;

  @override
  Future<Result<SollIstReport>> fetchSollIstReport(String id) async {
    jsonCalls++;
    return const Left(ProblemError(code: 'transport.network'));
  }

  @override
  Future<Result<List<DispoRow>>> fetchDispoReport(String id) async {
    jsonCalls++;
    return const Left(ProblemError(code: 'transport.network'));
  }

  @override
  Future<Result<List<ShootDayRow>>> fetchShootDayReport(String id) async {
    jsonCalls++;
    return const Left(ProblemError(code: 'transport.network'));
  }

  @override
  Future<Result<File>> dispoReportPdf(
    String id, {
    required Directory tempDir,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    pdfCalls++;
    return const Left(ProblemError(code: 'transport.network'));
  }

  @override
  Future<Result<File>> shootDayReportPdf(
    String id, {
    required Directory tempDir,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    pdfCalls++;
    return const Left(ProblemError(code: 'transport.network'));
  }

  @override
  Future<Result<File>> plannedVsActualReportPdf(
    String id, {
    required Directory tempDir,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    pdfCalls++;
    return const Left(ProblemError(code: 'transport.network'));
  }
}

enum MembershipMode { allowed, denied, unknownCap, loading, error }

Future<void> _pumpFrames(WidgetTester tester, {int n = 8}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// The loaded golden fixture: a mixed-finality day pair (one open, one
/// wrapped), in server order.
List<ShootingDayView> _loadedRows() => [
  _day('d-1', orderKey: 'a', label: 'Tag 1', date: Date(2026, 5, 1)),
  _day(
    'd-2',
    orderKey: 'b',
    label: 'Tag 2',
    wrappedAt: DateTime.utc(2026, 5, 2),
  ),
];

void main() {
  late CacheDatabase db;
  late _CountingReportsRepository repo;
  late ValueNotifier<Result<List<ShootingDayView>>> holder;
  late ManualReconciliationScheduler scheduler;
  late ProviderContainer container;

  // Counts the day-list fetch-seam invocations (the index shares the day
  // list's controller — a denied membership must cause NO refresh beyond
  // the initial read).
  int dayListFetches = 0;

  Future<void> setupContainer({
    MembershipMode membership = MembershipMode.allowed,
    List<ShootingDayView> initialRows = const [],
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _CountingReportsRepository(BreakdownApi(), SceneShootCacheDao(db));
    holder = ValueNotifier<Result<List<ShootingDayView>>>(Right(initialRows));
    dayListFetches = 0;
    scheduler = ManualReconciliationScheduler();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        sceneShootRepositoryProvider.overrideWithValue(repo),
        shootingDayRepositoryProvider.overrideWithValue(
          ShootingDayRepository(BreakdownApi(), ShootingDayCacheDao(db)),
        ),
        reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
        // The day-list fetch seam is overridden with a sync holder (the
        // index itself issues NO fetch of its own; this is only the state
        // it projects from). Counted: a denied membership must not trigger
        // any refresh beyond the initial read (task 5.3).
        shootingDaysListFetchProvider('episode-1').overrideWith((ref) async {
          dayListFetches++;
          final dao = ShootingDayCacheDao(ref.watch(cacheDatabaseProvider));
          return holder.value.match((err) => Left(err), (rows) async {
            // Faithful double: the server returns ORDER BY order_key ASC
            // (the client itself never re-sorts).
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
        // AUTHZ-GATE membership seam (same override family as the
        // day-scoped report screen's tests).
        if (membership == MembershipMode.loading)
          membershipFetchProvider('season-1').overrideWith(
            (ref) => Completer<Result<SeasonMembershipDto>>().future,
          )
        else
          membershipFetchProvider('season-1').overrideWith((ref) async {
            switch (membership) {
              case MembershipMode.allowed:
                return Right(_membership(active: true));
              case MembershipMode.denied:
                return Right(_membership(active: false));
              case MembershipMode.unknownCap:
                // A backend the client is newer than: an unknown capability
                // string rides along while the FLAG stays true — the gate
                // follows the flag only and is never enabled/disabled by
                // the unknown string.
                return Right(
                  SeasonMembershipDto(
                    (b) => b
                      ..seasonId = 'season-1'
                      ..hasActiveCostumeRoleInSeason = true
                      ..capabilities.replace(const <String>['future_cap_x']),
                  ),
                );
              case MembershipMode.error:
                return const Left(ProblemError(code: 'transport.network'));
              case MembershipMode.loading:
                return Right(_membership(active: true));
            }
          }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    TargetPlatform? platform,
  }) async {
    if (platform != null) {
      debugDefaultTargetPlatformOverride = platform;
    }
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppThemes.light(),
          darkTheme: AppThemes.dark(),
          locale: const Locale('de'),
          supportedLocales: const [Locale('de'), Locale('en')],
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          themeMode: brightness == Brightness.light
              ? ThemeMode.light
              : ThemeMode.dark,
          home: ReportsIndexScreen(episode: _episode(), seasonId: 'season-1'),
        ),
      ),
    );
    await _pumpFrames(tester);
  }

  group('ReportsIndexScreen states (semantic finders)', () {
    testWidgets('rows render from state in server order (never re-sorted)', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [
          _day('d-b', orderKey: 'b', label: 'Tag B'),
          _day(
            'd-a',
            orderKey: 'a',
            label: 'Tag A',
            wrappedAt: DateTime.utc(2026, 5, 2),
          ),
        ],
      );
      await pumpScreen(tester);

      expect(find.byKey(const Key('reports-index-screen')), findsOneWidget);
      expect(find.text('Tag B'), findsOneWidget);
      expect(find.text('Tag A'), findsOneWidget);
      // Server order (order_key ASC): a before b.
      final aTile = tester.getTopLeft(
        find.byKey(const Key('report-index-day-d-a')),
      );
      final bTile = tester.getTopLeft(
        find.byKey(const Key('report-index-day-d-b')),
      );
      expect(aTile.dy < bTile.dy, isTrue);
    });

    testWidgets('a row tap pushes ReportsScreen for that day', (tester) async {
      await setupContainer(initialRows: [_day('d-1', label: 'Tag 1')]);
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('report-index-day-d-1')));
      await _pumpFrames(tester);

      // The existing day-scoped report screen is pushed; its own fetches
      // (failing in the fake) are ITS requests — the index issued none
      // before the push (asserted in the denial tests below).
      expect(find.byKey(const Key('soll-ist-report-screen')), findsOneWidget);
    });

    testWidgets('no report content renders on the index', (tester) async {
      await setupContainer(
        initialRows: [
          _day('d-1', label: 'Tag 1', wrappedAt: DateTime.utc(2026, 5, 2)),
        ],
      );
      await pumpScreen(tester);

      expect(find.byKey(const Key('soll-ist-report-screen')), findsNothing);
      for (final key in [
        'soll-ist-flag-moved',
        'soll-ist-flag-missing',
        'soll-ist-counts',
        'report-pdf-fetch-dispo',
      ]) {
        expect(find.byKey(Key(key)), findsNothing);
      }
    });

    testWidgets('per-day finality: wrapped → abschließend, open → offen', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [
          _day('d-1', label: 'Tag 1', wrappedAt: DateTime.utc(2026, 5, 2)),
          _day('d-2', label: 'Tag 2'),
        ],
      );
      await pumpScreen(tester);

      // One chip per row, keyed by the day id so a tree-shuffled row still
      // fails the test.
      expect(
        find.descendant(
          of: find.byKey(const Key('report-index-day-d-1')),
          matching: find.byKey(const Key('report-index-finality-d-1')),
        ),
        findsOneWidget,
      );
      expect(find.text('Abschließend'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('report-index-day-d-2')),
          matching: find.byKey(const Key('report-index-finality-d-2')),
        ),
        findsOneWidget,
      );
      expect(find.text('Offen'), findsOneWidget);
    });

    testWidgets('no aggregate verdict on a mixed wrapped/open list', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [
          _day('d-1', label: 'Tag 1', wrappedAt: DateTime.utc(2026, 5, 2)),
          _day('d-2', label: 'Tag 2'),
        ],
      );
      await pumpScreen(tester);

      // Only the two per-row chips exist — no summary line, no aggregate
      // "x of y complete" figure anywhere on the screen.
      expect(
        find.byKey(const Key('report-index-finality-d-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('report-index-finality-d-2')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reports-index-summary')), findsNothing);
    });

    testWidgets('empty state renders and offers no report link', (
      tester,
    ) async {
      await setupContainer(initialRows: const []);
      await pumpScreen(tester);

      expect(find.byKey(const Key('report-index-empty')), findsOneWidget);
      expect(find.byKey(const Key('report-index-day-d-1')), findsNothing);
    });

    testWidgets('pending (optimistic) day is absent from the index', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [_day('d-projected', label: 'Projected')],
      );
      // An optimistic overlay on a NEW day id (command acknowledged, not
      // yet projected): the index must not list a row whose finality is
      // unknown — the day list is the place to watch it reconcile.
      container
          .read(shootingDaysOverlaysProvider('episode-1').notifier)
          .add(
            ShootingDayOverlay(
              id: 'd-optimistic',
              label: 'Unprojected',
              orderKey: 'z',
              status: OverlayStatus.acknowledged,
            ),
          );
      await pumpScreen(tester);

      expect(
        find.byKey(const Key('report-index-day-d-projected')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('report-index-day-d-optimistic')),
        findsNothing,
      );
    });

    testWidgets(
      'denied membership renders the 403 narrative with zero requests',
      (tester) async {
        await setupContainer(membership: MembershipMode.denied);
        await pumpScreen(tester);

        expect(find.byKey(const Key('reports-index-denied')), findsOneWidget);
        // Localized 403 copy keyed on `report.forbidden` (never the server's
        // localized detail).
        expect(
          find.text('Du hast keinen Zugriff auf diese Berichte.'),
          findsOneWidget,
        );
        // Zero report requests issued from the index (task 5.3).
        expect(repo.jsonCalls, 0);
        expect(repo.pdfCalls, 0);
      },
    );

    testWidgets('membership pending renders neither denial nor a fetch', (
      tester,
    ) async {
      await setupContainer(membership: MembershipMode.loading);
      await pumpScreen(tester);

      // D3: a loading gate is never reported as forbidden — and no report
      // request leaves the device while the gate is unresolved.
      expect(find.byKey(const Key('reports-index-denied')), findsNothing);
      expect(repo.jsonCalls, 0);
      expect(repo.pdfCalls, 0);
    });

    testWidgets('membership error denies locally with zero requests', (
      tester,
    ) async {
      await setupContainer(membership: MembershipMode.error);
      await pumpScreen(tester);

      expect(find.byKey(const Key('reports-index-denied')), findsOneWidget);
      expect(repo.jsonCalls, 0);
      expect(repo.pdfCalls, 0);
    });

    testWidgets('unknown capability string never enables the gate', (
      tester,
    ) async {
      await setupContainer(membership: MembershipMode.unknownCap);
      await pumpScreen(tester);

      // The gate follows the backend-computed flag only: with the flag
      // true the index renders its rows (no denial), and the unknown
      // string contributed nothing to that decision.
      expect(find.byKey(const Key('reports-index-denied')), findsNothing);
    });

    testWidgets('a denied member tapping a row still issues zero requests', (
      tester,
    ) async {
      await setupContainer(
        membership: MembershipMode.denied,
        initialRows: [_day('d-1', label: 'Tag 1')],
      );
      await pumpScreen(tester);

      // The denial banner is visible; a denied member's interaction never
      // triggers a day-list refresh or a report fetch (task 5.3).
      expect(find.byKey(const Key('reports-index-denied')), findsOneWidget);
      expect(repo.jsonCalls, 0);
      expect(repo.pdfCalls, 0);
      expect(dayListFetches, 1);
    });

    testWidgets('fetch failure shows the code-keyed error state with retry', (
      tester,
    ) async {
      await setupContainer();
      holder.value = const Left(ProblemError(code: 'transport.network'));
      await pumpScreen(tester);

      expect(find.byKey(const Key('reports-index-error')), findsOneWidget);
      expect(find.byKey(const Key('reports-index-error-text')), findsOneWidget);
      expect(find.byKey(const Key('reports-index-retry')), findsOneWidget);
    });
  });

  group('ReportsIndex goldens ({light,dark} x {android,macOS})', () {
    // The same matrix #549 extended for the report screen: loaded (mixed
    // finality rows), empty (day-less scope), denied (403 AUTHZ-GATE
    // narrative, zero requests).
    Future<void> golden(
      WidgetTester tester,
      String name, {
      required Brightness brightness,
      required TargetPlatform platform,
      MembershipMode membership = MembershipMode.allowed,
      List<ShootingDayView>? initialRows,
      // Semantic pre-conditions checked BEFORE the pixel comparison, so a
      // wrong-but-stable render can never be blessed as a golden.
      void Function()? assertState,
    }) async {
      try {
        await setupContainer(
          membership: membership,
          initialRows: initialRows ?? _loadedRows(),
        );
        await pumpScreen(tester, brightness: brightness, platform: platform);
        assertState?.call();
        await expectLater(
          find.byType(ReportsIndexScreen),
          matchesGoldenFile('goldens/reports_index_$name.png'),
        );
      } finally {
        // Reset before the test ends (foundation invariant check) — same
        // convention as the shooting-days goldens.
        debugDefaultTargetPlatformOverride = null;
      }
    }

    final variants = <String, void Function()>{
      'loaded': () {},
      'empty': () {
        expect(find.byKey(const Key('report-index-empty')), findsOneWidget);
      },
      'denied': () {
        expect(find.byKey(const Key('reports-index-denied')), findsOneWidget);
      },
    };

    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
        final suffix =
            '${brightness == Brightness.light ? 'light' : 'dark'}_'
            '${platform == TargetPlatform.android ? 'android' : 'macos'}';
        for (final entry in variants.entries) {
          testWidgets('golden $suffix ${entry.key}', (tester) async {
            await golden(
              tester,
              '${entry.key}_$suffix',
              brightness: brightness,
              platform: platform,
              membership: entry.key == 'denied'
                  ? MembershipMode.denied
                  : MembershipMode.allowed,
              initialRows: entry.key == 'empty' ? const [] : _loadedRows(),
              assertState: entry.value,
            );
          });
        }
      }
    }
  });
}
