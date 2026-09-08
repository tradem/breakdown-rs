// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark (pi)

// Widget tests + goldens (`flutter-shoot-day-execution` 2.4): the day
// board across {light,dark} × {android,macOS} (macOS via
// `debugDefaultTargetPlatformOverride` on Linux — the repo's golden
// convention, no Apple hardware needed), per-status cards, wrapped-day
// read-only state, 409 conflicts, denial narratives, notes UI flows,
// wrap dialog, and continuity strip states. Semantic finders throughout
// (never `find.byType` alone for layout).

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:one_of/one_of.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';
import 'package:frontend_flutter/data/cache/scene_shoot_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/costume_repository.dart';
import 'package:frontend_flutter/data/photo_repository.dart';
import 'package:frontend_flutter/data/scene_shoot_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/costumes/costumes_controller.dart';
import 'package:frontend_flutter/features/scene_shoots/scene_shoots_controller.dart';
import 'package:frontend_flutter/features/scene_shoots/scene_shoots_screen.dart';
import 'package:frontend_flutter/features/scene_shoots/scene_shoots_state.dart';
import 'package:frontend_flutter/features/shooting_days/shooting_days_controller.dart';

import '../seasons/seasons_test_fakes.dart';

const _scope = SceneShootDayScope(
  dayId: 'day-1',
  sceneId: 'scene-1',
  seasonId: 'season-1',
);

SceneShootView _shoot(
  String id, {
  SceneShootStatus status = SceneShootStatus.planned,
  int version = 1,
  List<SerializedNote> notes = const [],
  List<String> continuityIds = const [],
}) => SceneShootView(
  (b) => b
    ..id = id
    ..shootingDayId = 'day-1'
    ..sceneId = 'scene-1'
    ..plannedOrder = 'a0'
    ..status = status
    ..notes.replace(BuiltList<SerializedNote>(notes))
    ..continuityPhotoIds.replace(BuiltList<String>(continuityIds))
    ..updatedAt = DateTime.utc(2026, 5, 1)
    ..version = version,
);

SerializedNote _note(String id, String body) => SerializedNote(
  (n) => n
    ..id = id
    ..body = body,
);

ShootingDayView _day({DateTime? wrappedAt, int version = 1}) => ShootingDayView(
  (b) => b
    ..id = 'day-1'
    ..episodeId = 'episode-1'
    ..orderKey = 'a0'
    ..source_.replace(
      ShootingDaySource((s) => s..oneOf = OneOf.fromValue1(value: 'Manual')),
    )
    ..label = 'Day 1'
    ..archived = false
    ..wrappedAt = wrappedAt
    ..updatedAt = DateTime.utc(2026, 5, 1)
    ..version = version,
);

SceneView _scene() => SceneView(
  (b) => b
    ..id = 'scene-1'
    ..episodeId = 'episode-1'
    ..assignedCharacters.replace(const <String>[])
    ..isScheduleSet = true
    ..shootingDayIds.replace(const <String>['day-1'])
    ..updatedAt = DateTime.utc(2026, 5, 1)
    ..version = 1,
);

SeasonMembershipDto _membership(List<String> caps) => SeasonMembershipDto(
  (b) => b
    ..seasonId = 'season-1'
    ..hasActiveCostumeRoleInSeason = caps.isNotEmpty
    ..capabilities.replace(caps),
);

class _FakeSceneShootRepository extends SceneShootRepository {
  _FakeSceneShootRepository(super.api, super.cache);

  Result<int>? nextWrite;
  int startCalls = 0;
  int finishCalls = 0;
  int skipCalls = 0;
  int wrapCalls = 0;
  int linkCalls = 0;
  int unlinkCalls = 0;
  int addNoteCalls = 0;
  int updateNoteCalls = 0;
  int removeNoteCalls = 0;
  int actualOrderCalls = 0;
  int replanCalls = 0;
  int? lastWrapVersion;
  String? lastNoteBody;
  String? lastOrderKey;

  Future<Result<int>> _ack() async {
    final scripted = nextWrite;
    if (scripted != null) return scripted;
    return const Right<ProblemError, int>(2);
  }

  @override
  Future<Result<int>> start(
    String a,
    String b,
    String c,
    StartSceneShootRequest r,
  ) {
    startCalls++;
    return _ack();
  }

  @override
  Future<Result<int>> finish(
    String a,
    String b,
    String c,
    FinishSceneShootRequest r,
  ) {
    finishCalls++;
    return _ack();
  }

  @override
  Future<Result<int>> skip(
    String a,
    String b,
    String c,
    SkipSceneShootRequest r,
  ) {
    skipCalls++;
    return _ack();
  }

  @override
  Future<Result<int>> wrap(String a, WrapShootingDayRequest r) {
    wrapCalls++;
    lastWrapVersion = r.version;
    return _ack();
  }

  @override
  Future<Result<int>> linkContinuityPhoto(
    String a,
    String b,
    String c,
    LinkContinuityPhotoRequest r,
  ) {
    linkCalls++;
    return _ack();
  }

  @override
  Future<Result<int>> unlinkContinuityPhoto(
    String a,
    String b,
    String c,
    String d,
    int e,
  ) {
    unlinkCalls++;
    return _ack();
  }

  @override
  Future<Result<int>> addNote(
    String a,
    String b,
    String c,
    AddNoteRequest request,
  ) {
    addNoteCalls++;
    lastNoteBody = request.body;
    return _ack();
  }

  @override
  Future<Result<int>> updateNote(
    String a,
    String b,
    String c,
    String d,
    UpdateNoteRequest request,
  ) {
    updateNoteCalls++;
    lastNoteBody = request.body;
    return _ack();
  }

  @override
  Future<Result<int>> removeNote(
    String a,
    String b,
    String c,
    String d,
    VersionRequest r,
  ) {
    removeNoteCalls++;
    return _ack();
  }

  @override
  Future<Result<int>> setActualOrder(
    String a,
    String b,
    String c,
    SetActualOrderRequest request,
  ) {
    actualOrderCalls++;
    lastOrderKey = request.actualOrder;
    return _ack();
  }

  @override
  Future<Result<int>> replan(
    String a,
    String b,
    String c,
    ReplanSceneShootRequest request,
  ) {
    replanCalls++;
    lastOrderKey = request.plannedOrder;
    return _ack();
  }
}

/// Pumps a bounded number of frames (never `pumpAndSettle` while an
/// indeterminate spinner may be on screen).
Future<void> _pumpFrames(WidgetTester tester, {int n = 6}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late CacheDatabase db;
  late _FakeSceneShootRepository repo;
  late ValueNotifier<Result<List<SceneShootView>>> holder;
  late ValueNotifier<Result<SeasonMembershipDto>> membershipHolder;
  late ValueNotifier<ShootingDaysView> daysHolder;
  late ManualReconciliationScheduler scheduler;
  late ProviderContainer container;

  Future<void> setupContainer({
    List<SceneShootView> initialRows = const [],
    Result<List<SceneShootView>>? initialFetch,
    List<String> capabilities = const ['upload_continuity_photos'],
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _FakeSceneShootRepository(BreakdownApi(), SceneShootCacheDao(db));
    holder = ValueNotifier<Result<List<SceneShootView>>>(
      initialFetch ?? Right(initialRows),
    );
    membershipHolder = ValueNotifier<Result<SeasonMembershipDto>>(
      Right(_membership(capabilities)),
    );
    daysHolder = ValueNotifier<ShootingDaysView>(
      const ShootingDaysView(rows: [], isStale: false),
    );
    scheduler = ManualReconciliationScheduler();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        sceneShootRepositoryProvider.overrideWithValue(repo),
        // The board derives finality from the live day projection;
        // tests drive it through daysHolder (empty by default, so the
        // entry DTO wins) and invalidate to publish updates.
        shootingDaysViewProvider('episode-1')
            .overrideWith((ref) => daysHolder.value),
        // The continuity strip reads bytes through this provider; the
        // board tests link no resolvable photos, so it is never called.
        costumePhotoRepositoryProvider.overrideWithValue(
          PhotoRepository(BreakdownApi()),
        ),
        costumeRepositoryProvider.overrideWithValue(
          CostumeRepository(BreakdownApi(), CostumeCacheDao(db)),
        ),
        costumesListFetchProvider('season-1')
            .overrideWith((ref) async => const Right([])),
        reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
        membershipFetchProvider('season-1')
            .overrideWith((ref) async => membershipHolder.value),
        sceneShootsListFetchProvider(_scope).overrideWith((ref) async {
          final dao = SceneShootCacheDao(ref.watch(cacheDatabaseProvider));
          return holder.value.match(
            (err) => Left<ProblemError, List<SceneShootView>>(err),
            (rows) async {
              await dao.applySnapshotForDay(
                'day-1',
                rows,
                DateTime.utc(2026, 5, 1),
              );
              return Right<ProblemError, List<SceneShootView>>(rows);
            },
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();
  }

  Future<void> pumpScreen(WidgetTester tester, {ShootingDayView? day}) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: SceneShootsScreen(
            day: day ?? _day(),
            scene: _scene(),
            seasonId: 'season-1',
          ),
        ),
      ),
    );
    await _pumpFrames(tester, n: 8);
  }

  group('SceneShootsScreen states (2.4, semantic finders)', () {
    testWidgets('statuses: every lifecycle state renders its chip', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [
          _shoot('ssh-planned'),
          _shoot('ssh-scheduled', status: SceneShootStatus.scheduled),
          _shoot('ssh-progress', status: SceneShootStatus.inProgress),
          _shoot('ssh-shot', status: SceneShootStatus.shot),
          _shoot('ssh-skipped', status: SceneShootStatus.skipped),
        ],
      );
      await pumpScreen(tester);
      // Semantic pair: card keys plus the human-readable status copy.
      // The board is a lazy list — scroll each chip into view first.
      expect(find.byKey(const Key('scene-shoots-list')), findsOneWidget);
      for (final label in [
        'Planned',
        'Scheduled',
        'In progress',
        'Shot',
        'Skipped',
      ]) {
        await tester.scrollUntilVisible(find.text(label), 200);
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('actions: only the valid transitions offer buttons', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [
          _shoot('ssh-1'),
          _shoot('ssh-2', status: SceneShootStatus.inProgress),
          _shoot('ssh-3', status: SceneShootStatus.shot),
        ],
      );
      await pumpScreen(tester);
      // Planned: start + skip. In progress: finish + skip. Shot: none.
      expect(find.byKey(const Key('scene-shoot-start-ssh-1')), findsOneWidget);
      expect(find.byKey(const Key('scene-shoot-skip-ssh-1')), findsOneWidget);
      expect(find.byKey(const Key('scene-shoot-finish-ssh-1')), findsNothing);
      expect(find.byKey(const Key('scene-shoot-finish-ssh-2')), findsOneWidget);
      expect(find.byKey(const Key('scene-shoot-start-ssh-3')), findsNothing);
      expect(find.byKey(const Key('scene-shoot-finish-ssh-3')), findsNothing);
      expect(find.byKey(const Key('scene-shoot-skip-ssh-3')), findsNothing);
    });

    testWidgets('empty: honest empty state with plan affordance', (
      tester,
    ) async {
      await setupContainer(initialRows: []);
      await pumpScreen(tester);
      expect(
        find.text('No scene shoots planned for this day yet.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('scene-shoots-plan-first')), findsOneWidget);
    });

    testWidgets('error: fetch failure renders keyed copy + retry', (
      tester,
    ) async {
      await setupContainer(
        initialFetch: const Left(
          ProblemError(code: 'transport.connectionError'),
        ),
      );
      await pumpScreen(tester);
      expect(find.textContaining('transport.connectionError'), findsOneWidget);
      expect(find.byKey(const Key('scene-shoots-retry')), findsOneWidget);
    });

    testWidgets('409: conflict banner, single dispatch, no auto-retry', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [_shoot('ssh-1', status: SceneShootStatus.inProgress)],
      );
      await pumpScreen(tester);
      repo.nextWrite = const Left(
        ProblemError(code: 'scene_shoot.version_conflict'),
      );
      await tester.tap(find.byKey(const Key('scene-shoot-finish-ssh-1')));
      await _pumpFrames(tester, n: 10);
      expect(repo.finishCalls, 1);
      expect(
        find.byKey(const Key('scene-shoot-command-error-banner')),
        findsOneWidget,
      );
      expect(
        find.text('Changed elsewhere — refresh and try again.'),
        findsOneWidget,
      );
    });

    testWidgets('wrapped: read-only board with finality banner', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [_shoot('ssh-1', status: SceneShootStatus.shot)],
      );
      await pumpScreen(tester, day: _day(wrappedAt: DateTime.utc(2026, 5, 2)));
      expect(
        find.byKey(const Key('scene-shoots-wrapped-banner')),
        findsOneWidget,
      );
      expect(
        find.text('This day is wrapped — execution is final and read-only.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('scene-shoot-start-ssh-1')), findsNothing);
      expect(find.byKey(const Key('scene-shoots-wrap')), findsNothing);
    });

    testWidgets('in-session wrap updates banner, actions and version', (
      tester,
    ) async {
      // The entry DTO is unwrapped, but the live day projection carries
      // the wrap: the board flips to read-only without re-entry.
      await setupContainer(initialRows: [_shoot('ssh-1')]);
      await pumpScreen(tester);
      expect(find.byKey(const Key('scene-shoots-wrap')), findsOneWidget);
      daysHolder.value = ShootingDaysView(
        rows: [_day(wrappedAt: DateTime.utc(2026, 5, 2), version: 6)],
        isStale: false,
      );
      container.invalidate(shootingDaysViewProvider('episode-1'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const Key('scene-shoots-wrapped-banner')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('scene-shoot-start-ssh-1')), findsNothing);
      expect(find.byKey(const Key('scene-shoots-wrap')), findsNothing);
    });

    testWidgets('wrap dispatches the live version, never the entry DTO', (
      tester,
    ) async {
      // Entry DTO at version 1, live projection at version 6 unwrapped:
      // the confirmed wrap must echo 6. A regression to the entry
      // version would pass every read-only assertion above.
      await setupContainer(initialRows: [_shoot('ssh-1')]);
      await pumpScreen(tester);
      // Publish the unwrapped live day at version 6 (entry DTO is v1).
      daysHolder.value = ShootingDaysView(
        rows: [_day(version: 6)],
        isStale: false,
      );
      container.invalidate(shootingDaysViewProvider('episode-1'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('scene-shoots-wrap')));
      await _pumpFrames(tester, n: 30);
      await tester.tap(find.byKey(const Key('wrap-confirm-button')));
      await _pumpFrames(tester, n: 10);
      expect(repo.wrapCalls, 1);
      expect(repo.lastWrapVersion, 6);
    });

    testWidgets('denial: viewer sees the 403 narrative, no capture', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [_shoot('ssh-1')],
        capabilities: const [],
      );
      await pumpScreen(tester);
      expect(
        find.byKey(const Key('continuity-denied-narrative')),
        findsOneWidget,
      );
      expect(
        find.text(
          'You need an active costume role in this season to manage '
          'continuity photos.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('continuity-capture-camera-ssh-1')),
        findsNothing,
      );
    });
  });

  group('SceneShootsScreen notes UI (2.2 remainder)', () {
    testWidgets('notes render with bodies; edit flow dispatches', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [
          _shoot('ssh-1', notes: [_note('n-1', 'scar on left cheek')]),
        ],
      );
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('scene-shoot-notes-ssh-1')));
      await _pumpFrames(tester, n: 30);
      expect(find.text('scar on left cheek'), findsOneWidget);
      await tester.tap(find.byKey(const Key('scene-shoot-note-edit-n-1')));
      await _pumpFrames(tester, n: 30);
      expect(find.byKey(const Key('note-editor-dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('note-editor-field')),
        'scar on right cheek',
      );
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('note-editor-save')));
      await _pumpFrames(tester, n: 10);
      expect(repo.updateNoteCalls, 1);
      expect(repo.lastNoteBody, 'scar on right cheek');
    });

    testWidgets('delete flow confirms first, then dispatches', (tester) async {
      await setupContainer(
        initialRows: [
          _shoot('ssh-1', notes: [_note('n-1', 'temporary mark')]),
        ],
      );
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('scene-shoot-notes-ssh-1')));
      await _pumpFrames(tester, n: 30);
      await tester.tap(find.byKey(const Key('scene-shoot-note-delete-n-1')));
      await _pumpFrames(tester, n: 30);
      // Confirm-first: no dispatch before confirmation.
      expect(repo.removeNoteCalls, 0);
      expect(
        find.byKey(const Key('note-delete-confirm-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('note-delete-confirm-button')));
      await _pumpFrames(tester, n: 10);
      expect(repo.removeNoteCalls, 1);
    });
  });

  group('SceneShootsScreen wrap dialog (2.1 finality)', () {
    testWidgets('cancel issues no call; confirm wraps', (tester) async {
      await setupContainer(initialRows: [_shoot('ssh-1')]);
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('scene-shoots-wrap')));
      await _pumpFrames(tester, n: 12);
      expect(find.byKey(const Key('wrap-confirm-dialog')), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      await tester.tap(find.byKey(const Key('wrap-cancel-button')));
      await _pumpFrames(tester);
      expect(repo.wrapCalls, 0);
      await tester.tap(find.byKey(const Key('scene-shoots-wrap')));
      await _pumpFrames(tester, n: 12);
      await tester.tap(find.byKey(const Key('wrap-confirm-button')));
      await _pumpFrames(tester, n: 10);
      expect(repo.wrapCalls, 1);
    });
  });

  group('SceneShootsScreen order menu (3.2 affordance)', () {
    testWidgets('actual-order dialog dispatches the typed key', (tester) async {
      await setupContainer(initialRows: [_shoot('ssh-1'), _shoot('ssh-2')]);
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('scene-shoot-menu-ssh-2')));
      await _pumpFrames(tester, n: 30);
      await tester.tap(find.byKey(const Key('scene-shoot-actual-order-ssh-2')));
      await _pumpFrames(tester, n: 30);
      expect(find.byKey(const Key('order-key-dialog')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('order-key-field')), 'a0!');
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('order-key-save')));
      await _pumpFrames(tester, n: 10);
      expect(repo.actualOrderCalls, 1);
      expect(repo.lastOrderKey, 'a0!');
    });

    testWidgets('replan dialog dispatches the typed key', (tester) async {
      await setupContainer(initialRows: [_shoot('ssh-1')]);
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('scene-shoot-menu-ssh-1')));
      await _pumpFrames(tester, n: 30);
      await tester.tap(find.byKey(const Key('scene-shoot-replan-ssh-1')));
      await _pumpFrames(tester, n: 30);
      expect(find.byKey(const Key('order-key-dialog')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('order-key-field')), 'a9');
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('order-key-save')));
      await _pumpFrames(tester, n: 10);
      expect(repo.replanCalls, 1);
      expect(repo.lastOrderKey, 'a9');
    });
  });

  group('SceneShootsScreen continuity strip (2.3 states)', () {
    testWidgets('orphan ids render neutral chips with unlink', (tester) async {
      await setupContainer(
        initialRows: [
          _shoot('ssh-1', continuityIds: ['ph-orphan']),
        ],
      );
      await pumpScreen(tester);
      expect(find.byKey(const Key('continuity-strip-ssh-1')), findsOneWidget);
      expect(
        find.byKey(const Key('continuity-orphan-ph-orphan')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('continuity-orphan-unlink-ph-orphan')),
      );
      await _pumpFrames(tester, n: 30);
      expect(
        find.byKey(const Key('continuity-unlink-confirm-ph-orphan')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('continuity-unlink-confirm-ph-orphan')),
      );
      // Double-tap guard: the second tap lands on the disabled button
      // (no second command with the same shoot version).
      await tester.tap(
        find.byKey(const Key('continuity-unlink-confirm-ph-orphan')),
      );
      await _pumpFrames(tester, n: 10);
      expect(repo.unlinkCalls, 1);
    });

    testWidgets('capture requires a picked costume', (tester) async {
      await setupContainer(initialRows: [_shoot('ssh-1')]);
      await pumpScreen(tester);
      // Empty costume projection: picker has no entries, capture disabled,
      // the hint explains why picking matters.
      expect(
        find.byKey(const Key('continuity-costume-hint-ssh-1')),
        findsOneWidget,
      );
    });
  });

  group('SceneShootsScreen goldens (2.4, board state)', () {
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
              home: SceneShootsScreen(
                day: _day(),
                scene: _scene(),
                seasonId: 'season-1',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(SceneShootsScreen),
          matchesGoldenFile('goldens/$golden'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    Future<void> setupBoard() => setupContainer(
      initialRows: [
        _shoot('ssh-1', notes: [_note('n-1', 'scar on left cheek')]),
        _shoot('ssh-2', status: SceneShootStatus.inProgress, version: 2),
        _shoot('ssh-3', status: SceneShootStatus.shot, version: 3),
        _shoot('ssh-4', status: SceneShootStatus.skipped, version: 2),
      ],
    );

    testWidgets('golden light android', (tester) async {
      await setupBoard();
      await pumpGolden(
        tester,
        golden: 'scene_shoots_board_light_android.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden dark android', (tester) async {
      await setupBoard();
      await pumpGolden(
        tester,
        golden: 'scene_shoots_board_dark_android.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden light macos', (tester) async {
      await setupBoard();
      await pumpGolden(
        tester,
        golden: 'scene_shoots_board_light_macos.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.macOS,
      );
    });

    testWidgets('golden dark macos', (tester) async {
      await setupBoard();
      await pumpGolden(
        tester,
        golden: 'scene_shoots_board_dark_macos.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.macOS,
      );
    });
  });
}
