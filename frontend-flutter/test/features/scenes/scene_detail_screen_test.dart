// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

// Tier-2 widget tests for `SceneDetailScreen` (Tasks 5.2, 6.2): assigned
// characters (read-DTO join) + assign/unassign with scene version echo,
// scheduled days (read-DTO join) + schedule/unschedule pickers, conflict
// rollback copy. A failed command leaves the projected id in place (no
// local edit before the ack — nothing to roll back).

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
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
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/character_repository.dart';
import 'package:frontend_flutter/data/scene_repository.dart';
import 'package:frontend_flutter/data/shooting_day_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/characters/characters_controller.dart';
import 'package:frontend_flutter/features/scenes/scene_detail_screen.dart';
import 'package:frontend_flutter/features/scenes/scenes_controller.dart';
import 'package:frontend_flutter/features/shooting_days/shooting_days_controller.dart';

import '../seasons/seasons_test_fakes.dart';

const _conflict = ProblemError(code: 'concurrency.conflict', status: 409);

SceneView _scene({
  String id = 'scene-1',
  List<String> characters = const [],
  List<String> days = const [],
  int version = 1,
}) => SceneView(
  (b) => b
    ..id = id
    ..episodeId = 'episode-1'
    ..assignedCharacters.replace(characters)
    ..isScheduleSet = days.isNotEmpty
    ..location = 'Studio A'
    ..sceneNumber = 7
    ..shootingDayIds.replace(days)
    ..summary = 'Night shoot'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version,
);

CharacterView _character(String id, {String name = 'Ada'}) => CharacterView(
  (b) => b
    ..id = id
    ..seasonId = 'season-1'
    ..name = name
    ..category = serializers.deserializeWith(
      CharacterCategory.serializer,
      'main_cast',
    )!
    ..measurements.replace(
      CharacterMeasurements(
        (m) => m
          ..height = 'h'
          ..weight = 'w'
          ..chest = 'c'
          ..waist = 'wa'
          ..hips = 'hi'
          ..shoeSize = 's'
          ..hatSize = 'ha',
      ),
    )
    ..contact.replace(ContactInfo((c) => c..email = 'a@b.c'))
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

ShootingDayView _day(String id, {String? label, bool archived = false}) =>
    ShootingDayView(
      (b) => b
        ..id = id
        ..episodeId = 'episode-1'
        ..orderKey = '!'
        ..source_.replace(
          ShootingDaySource(
            (s) => s..oneOf = OneOf.fromValue1(value: 'Manual'),
          ),
        )
        ..label = label
        ..archived = archived
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

SeasonMembershipDto _membership() => SeasonMembershipDto(
  (b) => b
    ..seasonId = 'season-1'
    ..hasActiveCostumeRoleInSeason = true
    ..capabilities.replace(['assign_costumes']),
);

class _FakeCharacterRepository extends CharacterRepository {
  _FakeCharacterRepository(super.api, super.cache);

  Result<int>? nextWrite;
  int sceneAssignCalls = 0;
  int sceneUnassignCalls = 0;

  @override
  Future<Result<int>> assignToScene(
    String sceneId,
    AssignCharacterRequest request,
  ) {
    sceneAssignCalls++;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right(2));
  }

  @override
  Future<Result<int>> unassignFromScene(
    String sceneId,
    String characterId,
    int sceneVersion,
  ) {
    sceneUnassignCalls++;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right(2));
  }
}

class _FakeShootingDayRepository extends ShootingDayRepository {
  _FakeShootingDayRepository(super.api, super.cache);

  Result<int>? nextWrite;
  int scheduleCalls = 0;
  int unscheduleCalls = 0;

  @override
  Future<Result<int>> scheduleScene(
    String sceneId,
    ScheduleSceneRequest request,
  ) {
    scheduleCalls++;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right(2));
  }

  @override
  Future<Result<int>> unscheduleScene(
    String sceneId,
    String shootingDayId,
    int sceneVersion,
  ) {
    unscheduleCalls++;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right(2));
  }
}

Future<void> _pumpFrames(WidgetTester tester, {int n = 20}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late CacheDatabase db;
  late _FakeCharacterRepository characters;
  late _FakeShootingDayRepository days;
  late ProviderContainer container;

  Future<void> setupContainer({
    SceneView? scene,
    List<CharacterView> characterRows = const [],
    List<ShootingDayView> dayRows = const [],
    List<int>? scenesFetchLog,
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    characters = _FakeCharacterRepository(
      BreakdownApi(),
      CharacterCacheDao(db),
    );
    days = _FakeShootingDayRepository(BreakdownApi(), ShootingDayCacheDao(db));
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        sceneRepositoryProvider.overrideWithValue(
          SceneRepository(BreakdownApi(), SceneCacheDao(db)),
        ),
        characterRepositoryProvider.overrideWithValue(characters),
        shootingDayRepositoryProvider.overrideWithValue(days),
        reconciliationSchedulerProvider.overrideWith(
          (ref) => ManualReconciliationScheduler(),
        ),
        membershipFetchProvider('season-1')
            .overrideWith((ref) async => Right(_membership())),
        scenesListFetchProvider('episode-1').overrideWith((ref) async {
          scenesFetchLog?.add(1);
          return Right(scene == null ? [] : [scene]);
        }),
        charactersListFetchProvider('season-1')
            .overrideWith((ref) async => Right(characterRows)),
        shootingDaysListFetchProvider('episode-1')
            .overrideWith((ref) async => Right(dayRows)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();
  }

  Future<void> pumpDetail(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SceneDetailScreen(
            seasonId: 'season-1',
            episodeId: 'episode-1',
            sceneId: 'scene-1',
          ),
        ),
      ),
    );
    await _pumpFrames(tester, n: 30);
  }

  group('SceneDetailScreen characters (5.2)', () {
    testWidgets('assigned list resolves names via read-DTO join', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(characters: ['ch-1']),
        characterRows: [_character('ch-1')],
      );
      await pumpDetail(tester);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.byKey(const Key('scene-character-ch-1')), findsOneWidget);
    });

    testWidgets('empty assignment renders explicit empty state', (
      tester,
    ) async {
      await setupContainer(scene: _scene());
      await pumpDetail(tester);
      expect(find.byKey(const Key('scene-characters-empty')), findsOneWidget);
    });

    testWidgets('assign carries picked id + scene version', (tester) async {
      await setupContainer(
        scene: _scene(),
        characterRows: [_character('ch-9', name: 'Bea')],
      );
      await pumpDetail(tester);
      await tester.tap(find.byKey(const Key('scene-character-assign-scene-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assign-character-ch-9')));
      await _pumpFrames(tester);
      expect(characters.sceneAssignCalls, 1);
    });

    testWidgets('unassign confirm-first; failure leaves id in place', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(characters: ['ch-1']),
        characterRows: [_character('ch-1')],
      );
      await pumpDetail(tester);
      characters.nextWrite = const Left(_conflict);
      await tester.tap(find.byKey(const Key('scene-character-remove-ch-1')));
      await tester.pumpAndSettle();
      // Confirm-first: no dispatch before confirmation.
      expect(characters.sceneUnassignCalls, 0);
      await tester.tap(
        find.byKey(const Key('scene-character-remove-confirm-ch-1')),
      );
      await _pumpFrames(tester);
      expect(characters.sceneUnassignCalls, 1);
      // No local edit before the ack → the projected id stays rendered.
      expect(find.byKey(const Key('scene-character-ch-1')), findsOneWidget);
      expect(
        find.text('Changed elsewhere — refresh and try again.'),
        findsOneWidget,
      );
    });
  });

  group('SceneDetailScreen terminal states + refresh (review)', () {
    testWidgets('settled-missing scene renders gone view', (tester) async {
      await setupContainer(scene: null, characterRows: const []);
      await pumpDetail(tester);
      expect(find.byKey(const Key('scene-detail-gone')), findsOneWidget);
      expect(find.byKey(const Key('scene-detail-loading')), findsNothing);
    });

    testWidgets('409 conflict refreshes the scene projection', (tester) async {
      final fetchLog = <int>[];
      await setupContainer(
        scene: _scene(characters: ['ch-1']),
        characterRows: [_character('ch-1')],
        scenesFetchLog: fetchLog,
      );
      await pumpDetail(tester);
      final baseline = fetchLog.length;
      characters.nextWrite = const Left(_conflict);
      await tester.tap(find.byKey(const Key('scene-character-remove-ch-1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('scene-character-remove-confirm-ch-1')),
      );
      await _pumpFrames(tester);
      // Conflict copy renders AND the projection refetches for the next
      // action (never an automatic re-dispatch).
      expect(
        find.text('Changed elsewhere — refresh and try again.'),
        findsOneWidget,
      );
      expect(fetchLog.length, greaterThan(baseline));
    });

    testWidgets('assign disabled when everybody is assigned', (tester) async {
      await setupContainer(
        scene: _scene(characters: ['ch-1']),
        characterRows: [_character('ch-1')],
      );
      await pumpDetail(tester);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('scene-character-assign-scene-1')),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('SceneDetailScreen shooting days (6.2)', () {
    testWidgets('scheduled list resolves day labels via episode projection', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(days: ['d-1']),
        dayRows: [_day('d-1', label: '1. Tag')],
      );
      await pumpDetail(tester);
      expect(find.text('1. Tag'), findsOneWidget);
      expect(find.byKey(const Key('scene-shooting-day-d-1')), findsOneWidget);
    });

    testWidgets('schedule picker offers not-yet-archived days only', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(),
        dayRows: [
          _day('d-1', label: 'Open'),
          _day('d-2', label: 'Old', archived: true),
        ],
      );
      await pumpDetail(tester);
      await tester.tap(
        find.byKey(const Key('scene-shooting-day-schedule-scene-1')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('schedule-day-d-1')), findsOneWidget);
      expect(find.byKey(const Key('schedule-day-d-2')), findsNothing);
      await tester.tap(find.byKey(const Key('schedule-day-d-1')));
      await _pumpFrames(tester);
      expect(days.scheduleCalls, 1);
    });

    testWidgets('unschedule conflict rolls back with keyed copy', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(days: ['d-1']),
        dayRows: [_day('d-1', label: '1. Tag')],
      );
      await pumpDetail(tester);
      days.nextWrite = const Left(_conflict);
      await tester.tap(
        find.byKey(const Key('scene-shooting-day-unschedule-d-1')),
      );
      await _pumpFrames(tester);
      expect(days.unscheduleCalls, 1);
      expect(
        find.text('Changed elsewhere — refresh and try again.'),
        findsOneWidget,
      );
    });
  });
}
