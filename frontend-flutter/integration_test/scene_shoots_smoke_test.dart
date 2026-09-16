// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Tier-4 integration smoke (`flutter-shoot-day-execution` 4.1, on
// device/emulator, dev-auth): the full Soll-Ist execution day — plan a
// shoot on the empty board, the second shoot arrives via the projection
// (planned through the scene-scheduling path), start → finish one, skip
// the other, wrap with the guarded confirm dialog, and assert the board
// is read-only final afterwards (no mutation actions, finality banner).
//
// Runs against scriptable fakes (no backend needed): the device exercises
// the real screen, controller, optimistic-after-2xx overlays and the
// bounded-retry reconciliation with a zero-lag fake projector. Run via
// `flutter test integration_test/scene_shoots_smoke_test.dart` against a
// device/emulator; not part of the headless `flutter test` pass.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:integration_test/integration_test.dart';
import 'package:one_of/one_of.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/cache_generation.dart';
import 'package:frontend_flutter/data/cache/cache_ttl.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';
import 'package:frontend_flutter/data/cache/scene_shoot_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/costume_repository.dart';
import 'package:frontend_flutter/data/photo_repository.dart';
import 'package:frontend_flutter/data/scene_shoot_repository.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/costumes/costumes_controller.dart';
import 'package:frontend_flutter/features/scene_shoots/scene_shoots_controller.dart';
import 'package:frontend_flutter/features/scene_shoots/scene_shoots_screen.dart';
import 'package:frontend_flutter/features/scene_shoots/scene_shoots_state.dart';
import 'package:frontend_flutter/features/shooting_days/shooting_days_controller.dart';

const _scope = SceneShootDayScope(
  dayId: 'day-1',
  sceneId: 'scene-1',
  seasonId: 'season-1',
);

final _t = DateTime.utc(2026, 5, 1);

SceneShootView _shoot(
  String id, {
  required String sceneId,
  String plannedOrder = 'a0',
  SceneShootStatus status = SceneShootStatus.planned,
  int version = 1,
}) => SceneShootView(
  (b) => b
    ..id = id
    ..shootingDayId = 'day-1'
    ..sceneId = sceneId
    ..plannedOrder = plannedOrder
    ..status = status
    ..notes.replace(BuiltList<SerializedNote>())
    ..continuityPhotoIds.replace(BuiltList<String>())
    ..updatedAt = _t
    ..version = version,
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
    ..updatedAt = _t
    ..version = version,
);

SceneView _scene(String id) => SceneView(
  (b) => b
    ..id = id
    ..episodeId = 'episode-1'
    ..assignedCharacters.replace(const <String>[])
    ..isScheduleSet = true
    ..shootingDayIds.replace(const <String>['day-1'])
    ..updatedAt = _t
    ..version = 1,
);

SeasonMembershipDto _membership() => SeasonMembershipDto(
  (b) => b
    ..seasonId = 'season-1'
    ..hasActiveCostumeRoleInSeason = true
    ..capabilities.replace(['upload_continuity_photos']),
);

/// Shared mutable read-model double: the day board (the fake projector's
/// in-memory snapshot) and the shooting day (finality source). Commands
/// mutate both synchronously — a zero-lag projector, deterministic by
/// construction (AGENTS.md §6: no wall-clock/sleep assertions).
class _World {
  final List<SceneShootView> board = [];

  /// The live shooting-day projection; the entry DTO stays at v1 while
  /// the wrap echoes this version (never the entry version).
  int dayVersion = 1;
  DateTime? wrappedAt;

  int planCalls = 0;
  int startCalls = 0;
  int finishCalls = 0;
  int skipCalls = 0;
  int wrapCalls = 0;
  String? lastPlannedOrder;
  int? lastStartVersion;
  int? lastFinishVersion;
  int? lastSkipVersion;
  int? lastWrapVersion;

  SceneShootView _rebuild(SceneShootView shoot, SceneShootStatus status) =>
      shoot.rebuild(
        (b) => b
          ..status = status
          ..version = shoot.version + 1
          ..updatedAt = _t,
      );

  /// Server order: `COALESCE(actual_order, planned_order) ASC`.
  List<SceneShootView> ordered() {
    final rows = [...board];
    rows.sort(
      (a, b) => (a.actualOrder ?? a.plannedOrder).compareTo(
        b.actualOrder ?? b.plannedOrder,
      ),
    );
    return rows;
  }

  ShootingDayView day() => _day(wrappedAt: wrappedAt, version: dayVersion);
}

class _E2eSceneShootRepository extends SceneShootRepository {
  _E2eSceneShootRepository(super.api, super.cache, this.world);

  final _World world;

  @override
  Future<Result<List<SceneShootView>>> listByDay(
    String dayId,
    String sceneId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async => Right(world.ordered());

  @override
  Future<Result<List<SceneShootView>>> readCached(String dayId) async =>
      Right(world.ordered());

  @override
  Future<bool> isCacheStale(
    String dayId, {
    Clock clock = Clock.system,
    Duration ttl = kCacheTtl,
  }) async => false;

  @override
  Future<Result<IdVersionResponse>> plan(
    String dayId,
    String sceneId,
    PlanSceneShootRequest request,
  ) async {
    world.planCalls++;
    world.lastPlannedOrder = request.plannedOrder;
    final id = 'ssh-${world.planCalls}';
    world.board.add(
      _shoot(id, sceneId: sceneId, plannedOrder: request.plannedOrder),
    );
    return Right(
      IdVersionResponse(
        (b) => b
          ..id = id
          ..version = 1,
      ),
    );
  }

  @override
  Future<Result<int>> start(
    String dayId,
    String sceneId,
    String shootId,
    StartSceneShootRequest request,
  ) async {
    world.startCalls++;
    world.lastStartVersion = request.version;
    return Right(_apply(shootId, SceneShootStatus.inProgress));
  }

  @override
  Future<Result<int>> finish(
    String dayId,
    String sceneId,
    String shootId,
    FinishSceneShootRequest request,
  ) async {
    world.finishCalls++;
    world.lastFinishVersion = request.version;
    return Right(_apply(shootId, SceneShootStatus.shot));
  }

  @override
  Future<Result<int>> skip(
    String dayId,
    String sceneId,
    String shootId,
    SkipSceneShootRequest request,
  ) async {
    world.skipCalls++;
    world.lastSkipVersion = request.version;
    return Right(_apply(shootId, SceneShootStatus.skipped));
  }

  @override
  Future<Result<int>> wrap(String dayId, WrapShootingDayRequest request) async {
    world.wrapCalls++;
    world.lastWrapVersion = request.version;
    world.wrappedAt = _t;
    world.dayVersion++;
    return Right(world.dayVersion);
  }

  int _apply(String shootId, SceneShootStatus status) {
    final i = world.board.indexWhere((s) => s.id == shootId);
    world.board[i] = world._rebuild(world.board[i], status);
    return world.board[i].version;
  }
}

/// Pumps a bounded number of frames (never `pumpAndSettle` while an
/// indeterminate reconciliation may be running).
Future<void> _pumpFrames(WidgetTester tester, {int n = 12}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const devConfig = AppConfig(
    flavor: Flavor.dev,
    apiBase: 'http://10.0.2.2:3000',
    oidcIss: '',
    devAuthSub: 'dev-e2e',
    oidcAudience: '',
    oidcClientId: '',
    oidcRedirectUri: '',
    devIdpInsecure: '',
    appVersion: '1.0.0+1',
    defaultSeriesId: 'series-e2e',
  );

  late CacheDatabase db;
  late _World world;
  late _E2eSceneShootRepository repo;
  late ValueNotifier<ShootingDaysView> daysHolder;
  late ProviderContainer container;

  setUp(() async {
    db = CacheDatabase();
    world = _World();
    repo = _E2eSceneShootRepository(
      BreakdownApi(),
      SceneShootCacheDao(db),
      world,
    );
    daysHolder = ValueNotifier<ShootingDaysView>(
      // The live day projection starts at v3 (unwrapped) — the wrap must
      // echo 3, never the entry DTO's v1.
      const ShootingDaysView(rows: [], isStale: false),
    );
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        sceneShootRepositoryProvider.overrideWithValue(repo),
        // The board derives finality from the live day projection;
        // tests drive it through daysHolder (empty by default, so the
        // entry DTO wins) and invalidate to publish updates.
        shootingDaysViewProvider('episode-1')
            .overrideWith((ref) => daysHolder.value),
        costumePhotoRepositoryProvider.overrideWithValue(
          PhotoRepository(BreakdownApi()),
        ),
        costumeRepositoryProvider.overrideWithValue(
          CostumeRepository(BreakdownApi(), CostumeCacheDao(db)),
        ),
        costumesListFetchProvider('season-1')
            .overrideWith((ref) async => const Right([])),
        membershipFetchProvider('season-1')
            .overrideWith((ref) async => Right(_membership())),
      ],
    );
    await container.read(authSessionControllerProvider.notifier).signIn();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppThemes.light(),
          home: SceneShootsScreen(
            day: _day(),
            scene: _scene('scene-1'),
            seasonId: 'season-1',
          ),
        ),
      ),
    );
    await _pumpFrames(tester);
  }

  testWidgets('full execution day: plan → start/finish/skip → wrap → final', (
    tester,
  ) async {
    await pumpScreen(tester);

    // Empty board: honest empty state with the plan affordance.
    expect(
      find.text('No scene shoots planned for this day yet.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('scene-shoots-plan-first')), findsOneWidget);

    // -- Plan the first shoot (empty-board affordance, appended key a0) --
    await tester.tap(find.byKey(const Key('scene-shoots-plan-first')));
    await _pumpFrames(tester);
    expect(world.planCalls, 1);
    expect(world.lastPlannedOrder, 'a0');
    expect(find.byKey(const Key('scene-shoot-card-ssh-1')), findsOneWidget);
    expect(find.text('Planned'), findsOneWidget);

    // -- The second shoot arrives via the projection: it was planned for
    // scene-2 through the scene-scheduling path (not the board affordance,
    // which only exists on an empty day). Publish the projection update.
    world.board.add(_shoot('ssh-2', sceneId: 'scene-2', plannedOrder: 'a1'));
    container.invalidate(sceneShootsListFetchProvider(_scope));
    await _pumpFrames(tester);
    expect(find.byKey(const Key('scene-shoot-card-ssh-1')), findsOneWidget);
    expect(find.byKey(const Key('scene-shoot-card-ssh-2')), findsOneWidget);
    // Both planned — the sequence renders in server order (a0 → a1);
    // the card keys already assert the pair, so no chip text here (two
    // 'Planned' chips would make the finder ambiguous).

    // -- Start ssh-1: version echo 1, status flips to In progress. --
    await tester.tap(find.byKey(const Key('scene-shoot-start-ssh-1')));
    await _pumpFrames(tester);
    expect(world.startCalls, 1);
    expect(world.lastStartVersion, 1);
    expect(find.byKey(const Key('scene-shoot-start-ssh-1')), findsNothing);
    await tester.scrollUntilVisible(find.text('In progress'), 200);
    expect(find.text('In progress'), findsOneWidget);

    // -- Finish ssh-1: version echo 2 (the reconciled row's), Shot. --
    await tester.tap(find.byKey(const Key('scene-shoot-finish-ssh-1')));
    await _pumpFrames(tester);
    expect(world.finishCalls, 1);
    expect(world.lastFinishVersion, 2);
    await tester.scrollUntilVisible(find.text('Shot'), 200);
    expect(find.text('Shot'), findsOneWidget);

    // -- Skip ssh-2: version echo 1, Skipped. --
    await tester.tap(find.byKey(const Key('scene-shoot-skip-ssh-2')));
    await _pumpFrames(tester);
    expect(world.skipCalls, 1);
    expect(world.lastSkipVersion, 1);
    await tester.scrollUntilVisible(find.text('Skipped'), 200);
    expect(find.text('Skipped'), findsOneWidget);

    // -- Wrap: guarded day-level action with finality copy (D3). The
    // live day projection is at v3 — the confirmed wrap echoes 3, never
    // the entry DTO's v1.
    daysHolder.value = ShootingDaysView(
      rows: [_day(version: 3)],
      isStale: false,
    );
    container.invalidate(shootingDaysViewProvider('episode-1'));
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const Key('scene-shoots-wrap')));
    await _pumpFrames(tester);
    expect(find.byKey(const Key('wrap-confirm-dialog')), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    await tester.tap(find.byKey(const Key('wrap-confirm-button')));
    await _pumpFrames(tester);
    expect(world.wrapCalls, 1);
    expect(world.lastWrapVersion, 3);

    // Publish the wrapped day projection: the board flips to read-only
    // finality without re-entry (D2 — finality follows the projection).
    daysHolder.value = ShootingDaysView(
      rows: [_day(wrappedAt: _t, version: world.dayVersion)],
      isStale: false,
    );
    container.invalidate(shootingDaysViewProvider('episode-1'));
    await _pumpFrames(tester);

    // Read-only finality: finality banner, no wrap action, no mutation
    // buttons, statuses intact.
    expect(
      find.byKey(const Key('scene-shoots-wrapped-banner')),
      findsOneWidget,
    );
    expect(
      find.text('This day is wrapped — execution is final and read-only.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('scene-shoots-wrap')), findsNothing);
    expect(find.byKey(const Key('scene-shoots-plan-first')), findsNothing);
    expect(find.byKey(const Key('scene-shoot-start-ssh-1')), findsNothing);
    expect(find.byKey(const Key('scene-shoot-finish-ssh-1')), findsNothing);
    expect(find.byKey(const Key('scene-shoot-skip-ssh-1')), findsNothing);
    expect(find.byKey(const Key('scene-shoot-skip-ssh-2')), findsNothing);
    await tester.scrollUntilVisible(find.text('Shot'), 200);
    expect(find.text('Shot'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Skipped'), 200);
    expect(find.text('Skipped'), findsOneWidget);

    // Every command dispatched exactly once (no auto-retry storms).
    expect(world.planCalls, 1);
    expect(world.startCalls, 1);
    expect(world.finishCalls, 1);
    expect(world.skipCalls, 1);
    expect(world.wrapCalls, 1);
  });
}
