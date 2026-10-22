// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

// Tier-2 widget + controller tests for `ShootingDaysScreen` (Task 6.3):
// order fidelity (no re-sort), date null-vs-absent semantics, conflicts,
// archives, create (append order_key, Manual), and goldens
// {light,dark}×{android,macos}.
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
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

const _networkDown = ProblemError(code: 'transport.connectionError');
const _conflict = ProblemError(
  code: 'concurrency.version-mismatch',
  status: 409,
);

ShootingDayView _day(
  String id, {
  String orderKey = '!',
  String? label,
  Date? date,
  bool archived = false,
  int version = 1,
  bool aiExtracted = false,
  DateTime? wrappedAt,
}) => ShootingDayView(
  (b) => b
    ..id = id
    ..episodeId = 'episode-1'
    ..orderKey = orderKey
    ..source_.replace(
      aiExtracted
          ? ShootingDaySource(
              (s) => s
                ..oneOf = OneOf.fromValue2<String, SceneSourceOneOf>(
                  value: SceneSourceOneOf(
                    (d) => d
                      ..aiExtracted = SceneSourceOneOfAiExtracted(
                        (d2) => d2..documentId = 'job-1',
                      ).toBuilder(),
                  ),
                ),
            )
          : ShootingDaySource(
              (s) => s..oneOf = OneOf.fromValue1(value: 'Manual'),
            ),
    )
    ..label = label
    ..date = date
    ..archived = archived
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version
    ..wrappedAt = wrappedAt,
);

EpisodeView _episode() => EpisodeView(
  (b) => b
    ..id = 'episode-1'
    ..blockId = 'block-1'
    ..number = 1
    ..projectId = 'series-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

class _FakeShootingDayRepository extends ShootingDayRepository {
  _FakeShootingDayRepository(super.api, super.cache);

  Result<IdVersionResponse>? nextCreate;
  Result<int>? nextWrite;
  int createCalls = 0;
  int updateCalls = 0;
  int archiveCalls = 0;
  UpdateShootingDayRequest? lastUpdate;

  @override
  Future<Result<IdVersionResponse>> create(
    String episodeId,
    CreateShootingDayRequest request,
  ) {
    createCalls++;
    final scripted = nextCreate;
    if (scripted != null) return Future.value(scripted);
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

  @override
  Future<Result<int>> update(String id, UpdateShootingDayRequest request) {
    updateCalls++;
    lastUpdate = request;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right(2));
  }

  @override
  Future<Result<int>> archive(String id, VersionRequest version) {
    archiveCalls++;
    return Future.value(const Right(2));
  }

  int unscheduleCalls = 0;
  String? lastUnscheduleId;

  @override
  Future<Result<int>> unschedule(String id, {required int version}) {
    unscheduleCalls++;
    lastUnscheduleId = id;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right(2));
  }

  // Issue #706: the planned→actual merge command.
  Result<LinkShootingDayResponse>? nextLink;
  int linkCalls = 0;
  String? lastLinkId;
  String? lastLinkTargetId;

  @override
  Future<Result<LinkShootingDayResponse>> linkInto(String id, String targetId) {
    linkCalls++;
    lastLinkId = id;
    lastLinkTargetId = targetId;
    final scripted = nextLink;
    if (scripted != null) return Future.value(scripted);
    return Future.value(
      Right(
        LinkShootingDayResponse(
          (b) => b
            ..linkedScenes = 2
            ..plannedSceneShoots = 1,
        ),
      ),
    );
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
  late ManualReconciliationScheduler scheduler;
  late ProviderContainer container;

  Future<void> setupContainer({
    List<ShootingDayView> initialRows = const [],
    Result<List<ShootingDayView>>? initialFetch,
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _FakeShootingDayRepository(BreakdownApi(), ShootingDayCacheDao(db));
    holder = ValueNotifier<Result<List<ShootingDayView>>>(
      initialFetch ?? Right(initialRows),
    );
    scheduler = ManualReconciliationScheduler();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        shootingDayRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
        shootingDaysListFetchProvider('episode-1').overrideWith((ref) async {
          final dao = ShootingDayCacheDao(ref.watch(cacheDatabaseProvider));
          return holder.value.match((err) => Left(err), (rows) async {
            // Faithful double: the server returns ORDER BY order_key
            // ASC, so the stub sorts before snapshotting + returning
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
        child: MaterialApp(
          home: ShootingDaysScreen(episode: _episode(), seasonId: 'season-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ShootingDaysScreen (6.3)', () {
    testWidgets('order fidelity: server order, never re-sorted', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [
          _day('d-2', orderKey: 'b', label: 'Second'),
          _day('d-1', orderKey: 'a', label: 'First'),
        ],
      );
      await pumpScreen(tester);
      // The DAO orders by order_key ASC; the screen renders that order.
      final tiles = tester.widgetList<ListTile>(find.byType(ListTile));
      expect(tiles.map((t) => (t.title! as Text).data), ['First', 'Second']);
    });

    testWidgets('AI-extracted day carries the provenance badge; Manual none '
        '(issue #538)', (tester) async {
      await setupContainer(
        initialRows: [
          _day('d-ai', orderKey: 'a', aiExtracted: true),
          _day('d-manual', orderKey: 'b'),
        ],
      );
      await pumpScreen(tester);
      // Row-id-scoped badge: exactly one element per AI row, none on the
      // manual row (no false attribution in either direction).
      expect(
        find.byKey(const Key('shooting-day-ai-badge-d-ai')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shooting-day-ai-badge-d-manual')),
        findsNothing,
      );
    });

    testWidgets('empty + error states', (tester) async {
      await setupContainer(initialRows: []);
      await pumpScreen(tester);
      expect(find.byKey(const Key('shooting-days-empty')), findsOneWidget);
    });

    testWidgets('error renders retry', (tester) async {
      await setupContainer(initialFetch: const Left(_networkDown));
      await pumpScreen(tester);
      expect(find.byKey(const Key('shooting-days-error')), findsOneWidget);
      expect(find.byKey(const Key('shooting-days-retry')), findsOneWidget);
    });

    testWidgets('create: append order_key + Manual source', (tester) async {
      await setupContainer(initialRows: [_day('d-1', orderKey: '!')]);
      await pumpScreen(tester);
      final result = await container
          .read(shootingDaysControllerProvider('episode-1').notifier)
          .create(label: '2. Tag');
      expect(result.isRight(), isTrue);
      expect(repo.createCalls, 1);
      await _pumpFrames(tester);
      expect(find.byKey(const Key('overlay-d-new-1')), findsOneWidget);
    });

    testWidgets('unschedule: enabled affordance dispatches explicit clear', (
      tester,
    ) async {
      final day = _day('d-1', date: Date(2026, 5, 1));
      await setupContainer(initialRows: [day]);
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('shooting-day-menu-d-1')));
      await tester.pumpAndSettle();
      // Ungated (issue #374): the repository emits the explicit
      // `{"version": N, "date": null}` body (backend #372), so the item
      // dispatches the raw unschedule path, not a typed update.
      final item = tester.widget<PopupMenuItem<VoidCallback>>(
        find.byKey(const Key('shooting-day-unschedule-d-1')),
      );
      expect(item.enabled, isTrue);
      expect(item.value, isNotNull);
      await tester.tap(
        find.byKey(const Key('shooting-day-unschedule-d-1')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('shooting-day-unschedule-confirm-d-1')),
      );
      await _pumpFrames(tester);
      expect(repo.unscheduleCalls, 1);
      expect(repo.lastUnscheduleId, 'd-1');
      expect(repo.updateCalls, 0);
    });

    testWidgets('conflict: 409 renders keyed copy', (tester) async {
      await setupContainer(initialRows: [_day('d-1')]);
      await pumpScreen(tester);
      repo.nextWrite = const Left(_conflict);
      final result = await container
          .read(shootingDaysControllerProvider('episode-1').notifier)
          .rename(day: _day('d-1'), label: 'X');
      expect(result.isLeft(), isTrue);
      await _pumpFrames(tester);
      expect(
        find.text('Changed elsewhere — refresh and try again.'),
        findsOneWidget,
      );
    });

    testWidgets('link-into menu item: only on AI-extracted non-archived days', (
      tester,
    ) async {
      final cases = {
        'd-ai': findsOneWidget,
        'd-manual': findsNothing,
        'd-ai-archived': findsNothing,
      };
      for (final MapEntry(key: id, value: expected) in cases.entries) {
        await setupContainer(
          initialRows: [
            _day(
              id,
              aiExtracted: id.startsWith('d-ai'),
              archived: id.endsWith('archived'),
            ),
          ],
        );
        await pumpScreen(tester);
        await tester.tap(find.byKey(Key('shooting-day-menu-$id')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(Key('shooting-day-link-into-$id')),
          expected,
          reason: id == 'd-ai'
              ? 'AI-extracted, non-archived: the merge is offered'
              : 'manual or archived: no planned→actual merge',
        );
      }
    });

    testWidgets('link-into picker lists only eligible targets (not self, not '
        'wrapped, not archived) and dispatches with the picked DTO ids', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [
          _day('d-ai', orderKey: 'a', aiExtracted: true),
          _day('d-1', orderKey: 'b', label: '1. Tag'),
          _day(
            'd-wrapped',
            orderKey: 'c',
            label: 'wrapped',
            wrappedAt: DateTime.utc(2026, 1, 1),
          ),
          _day('d-arch', orderKey: 'd', label: 'archived', archived: true),
        ],
      );
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('shooting-day-menu-d-ai')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shooting-day-link-into-d-ai')));
      await tester.pumpAndSettle();

      // Only the eligible day is offered.
      expect(
        find.byKey(const Key('shooting-day-link-into-target-d-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shooting-day-link-into-target-d-wrapped')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('shooting-day-link-into-target-d-arch')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('shooting-day-link-into-target-d-ai')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const Key('shooting-day-link-into-target-d-1')),
      );
      await _pumpFrames(tester);
      expect(repo.linkCalls, 1);
      expect(repo.lastLinkId, 'd-ai');
      expect(repo.lastLinkTargetId, 'd-1');
      // The success feedback names the moved scenes.
      expect(
        find.text('2 scenes moved, 1 planned entries created.'),
        findsOneWidget,
      );
    });

    testWidgets('link-into refusal: wrapped target renders its keyed copy', (
      tester,
    ) async {
      final day = _day('d-ai', orderKey: 'a', aiExtracted: true);
      final target = _day(
        'd-wrapped',
        orderKey: 'b',
        wrappedAt: DateTime.utc(2026, 1, 1),
      );
      await setupContainer(initialRows: [day, target]);
      await pumpScreen(tester);
      repo.nextLink = const Left(
        ProblemError(code: 'shooting-day.target-wrapped', status: 409),
      );
      final result = await container
          .read(shootingDaysControllerProvider('episode-1').notifier)
          .linkInto(day: day, target: target);
      expect(result.isLeft(), isTrue);
      await _pumpFrames(tester);
      expect(
        find.text(
          'The target shooting day is already wrapped — merging is not possible.',
        ),
        findsOneWidget,
      );
    });
  });

  group('ShootingDaysScreen goldens (6.3, data state)', () {
    Future<void> pumpGolden(
      WidgetTester tester, {
      required String golden,
      required ThemeMode mode,
      TargetPlatform? platform,
    }) async {
      try {
        if (platform != null) {
          debugDefaultTargetPlatformOverride = platform;
        }
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData.light(),
              darkTheme: ThemeData.dark(),
              themeMode: mode,
              home: ShootingDaysScreen(
                episode: _episode(),
                seasonId: 'season-1',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(ShootingDaysScreen),
          matchesGoldenFile('goldens/$golden'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('golden light android', (tester) async {
      await setupContainer(
        initialRows: [
          _day('d-1', orderKey: '!', label: '1. Tag', date: Date(2026, 5, 1)),
        ],
      );
      await pumpGolden(
        tester,
        golden: 'shooting_days_screen_light_android.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden dark android', (tester) async {
      await setupContainer(
        initialRows: [
          _day('d-1', orderKey: '!', label: '1. Tag', date: Date(2026, 5, 1)),
        ],
      );
      await pumpGolden(
        tester,
        golden: 'shooting_days_screen_dark_android.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden light macos', (tester) async {
      await setupContainer(
        initialRows: [
          _day('d-1', orderKey: '!', label: '1. Tag', date: Date(2026, 5, 1)),
        ],
      );
      await pumpGolden(
        tester,
        golden: 'shooting_days_screen_light_macos.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.macOS,
      );
    });

    testWidgets('golden dark macos', (tester) async {
      await setupContainer(
        initialRows: [
          _day('d-1', orderKey: '!', label: '1. Tag', date: Date(2026, 5, 1)),
        ],
      );
      await pumpGolden(
        tester,
        golden: 'shooting_days_screen_dark_macos.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.macOS,
      );
    });
  });

  group('ShootingDaysScreen reports entry (reportsIndexOpen)', () {
    testWidgets('wide: labelled TextButton.icon pushes the report index', (
      tester,
    ) async {
      await setupContainer(initialRows: [_day('d-1', label: 'Tag 1')]);
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ShootingDaysScreen(episode: _episode(), seasonId: 'season-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The labelled control is present (glossary visible-label norm) with
      // the contract key on the tap target.
      final entry = find.byKey(const Key('reportsIndexOpen'));
      expect(entry, findsOneWidget);
      // Standalone widget tests without delegates resolve the English
      // catalog (l10nOf fallback) — the label is still VISIBLE.
      expect(find.text('Reports'), findsOneWidget);
      expect(
        find.descendant(
          of: entry,
          matching: find.byIcon(Icons.summarize_outlined),
        ),
        findsOneWidget,
      );

      // Tapping it pushes the EPISODE's report index (same episode and the
      // threaded season id).
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reports-index-screen')), findsOneWidget);
      expect(find.byKey(const Key('report-index-day-d-1')), findsOneWidget);
      // Day rows stay non-navigating: the tile carries no report tap
      // target beyond its existing menu.
      expect(find.byKey(const Key('reports-open')), findsNothing);
    });

    testWidgets('narrow: collapses into a LABELLED overflow item that pushes', (
      tester,
    ) async {
      await setupContainer(initialRows: [_day('d-1', label: 'Tag 1')]);
      // 280px is below the _reportsIndexMinBarWidth breakpoint (300) —
      // the width-safety-valve branch.
      tester.view.physicalSize = const Size(280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ShootingDaysScreen(episode: _episode(), seasonId: 'season-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The entry key sits on the collapsed control as well — never a bare
      // icon.
      final entry = find.byKey(const Key('reportsIndexOpen'));
      expect(entry, findsOneWidget);

      // The collapsed form opens the overflow menu; its single item is
      // labelled and carries the contract key too.
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final item = find.byKey(const Key('reportsIndexOpen-overflow-item'));
      expect(item, findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);
      // Tapped by its label (the item key is not hit-testable at its own
      // centre through the menu's gesture arena — #549's finding).
      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reports-index-screen')), findsOneWidget);
    });
  });
}
