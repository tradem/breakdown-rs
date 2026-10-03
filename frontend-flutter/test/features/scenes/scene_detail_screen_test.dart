// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

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
import 'package:frontend_flutter/data/costume_repository.dart';
import 'package:frontend_flutter/data/scene_repository.dart';
import 'package:frontend_flutter/data/shooting_day_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/characters/characters_controller.dart';
import 'package:frontend_flutter/features/costumes/costumes_controller.dart';
import 'package:frontend_flutter/features/scenes/scene_detail_screen.dart';
import 'package:frontend_flutter/features/scenes/scenes_controller.dart';
import 'package:frontend_flutter/features/shooting_days/shooting_days_controller.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';

import '../seasons/seasons_test_fakes.dart';

const _conflict = ProblemError(
  code: 'concurrency.version-mismatch',
  status: 409,
);

SceneView _scene({
  String id = 'scene-1',
  List<String> characters = const [],
  List<String> days = const [],
  int version = 1,
  List<SceneCostumeBeatView> beats = const [],
}) => SceneView(
  (b) => b
    ..id = id
    ..episodeId = 'episode-1'
    ..assignedCharacters.replace(characters)
    ..isScheduleSet = days.isNotEmpty
    ..location = 'Studio A'
    ..sceneNumber = 7
    ..shootingDayIds.replace(days)
    ..costumeBeats.replace(beats)
    ..summary = 'Night shoot'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version,
);

SceneCostumeBeatView _beat(
  String characterId,
  int order, {
  String costumeId = 'costume-1',
  String? characterName = 'Ada',
  String? categoryName = 'Jacke',
  String? note,
}) => SceneCostumeBeatView(
  (b) => b
    ..characterId = characterId
    ..costumeId = costumeId
    ..characterName = characterName
    ..costumeCategoryName = categoryName
    ..order = order
    ..note = note,
);

CostumeView _costume(String id, {String? subject, String? categoryName}) =>
    CostumeView(
      (b) => b
        ..id = id
        ..notes = ''
        ..categoryName = categoryName
        ..details.replace([
          CostumeDetailView(
            (d) => d
              ..id = 'd-$id'
              ..subject = subject
              ..text = '',
          ),
        ])
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
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

SeasonMembershipDto _membership({
  List<String> capabilities = const ['assign_costumes'],
}) => SeasonMembershipDto(
  (b) => b
    ..seasonId = 'season-1'
    ..hasActiveCostumeRoleInSeason = true
    ..capabilities.replace(capabilities),
);

class _FakeSceneRepository extends SceneRepository {
  _FakeSceneRepository(super.api, super.cache);

  Result<int>? nextWrite;
  int addCalls = 0;
  int updateCalls = 0;
  int removeCalls = 0;
  int clearCalls = 0;
  int? lastVersion;

  @override
  Future<Result<int>> addCostumeBeat(
    String id,
    AddSceneCostumeBeatRequest request,
  ) {
    addCalls++;
    lastVersion = request.version;
    return Future.value(nextWrite ?? const Right(2));
  }

  @override
  Future<Result<int>> updateCostumeBeat(
    String id,
    String characterId,
    int order,
    UpdateSceneCostumeBeatRequest request,
  ) {
    updateCalls++;
    lastVersion = request.version;
    return Future.value(nextWrite ?? const Right(2));
  }

  @override
  Future<Result<int>> removeCostumeBeat(
    String id,
    String characterId,
    int order,
    int version,
  ) {
    removeCalls++;
    lastVersion = version;
    return Future.value(nextWrite ?? const Right(2));
  }

  @override
  Future<Result<int>> clearCostumeBeats(
    String id,
    String characterId,
    int version,
  ) {
    clearCalls++;
    lastVersion = version;
    return Future.value(nextWrite ?? const Right(2));
  }
}

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

  late _FakeSceneRepository sceneRepo;

  Future<void> setupContainer({
    SceneView? scene,
    List<CharacterView> characterRows = const [],
    List<ShootingDayView> dayRows = const [],
    List<int>? scenesFetchLog,
    List<String> membershipCapabilities = const ['assign_costumes'],
    List<CostumeView> costumeRows = const [],
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    sceneRepo = _FakeSceneRepository(BreakdownApi(), SceneCacheDao(db));
    characters = _FakeCharacterRepository(
      BreakdownApi(),
      CharacterCacheDao(db),
    );
    days = _FakeShootingDayRepository(BreakdownApi(), ShootingDayCacheDao(db));
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        sceneRepositoryProvider.overrideWithValue(sceneRepo),
        characterRepositoryProvider.overrideWithValue(characters),
        shootingDayRepositoryProvider.overrideWithValue(days),
        reconciliationSchedulerProvider.overrideWith(
          (ref) => ManualReconciliationScheduler(),
        ),
        membershipFetchProvider('season-1').overrideWith(
          (ref) async =>
              Right(_membership(capabilities: membershipCapabilities)),
        ),
        costumeRepositoryProvider.overrideWithValue(
          CostumeRepository(BreakdownApi(), CostumeCacheDao(db)),
        ),
        costumesListFetchProvider('season-1')
            .overrideWith((ref) async => Right(costumeRows)),
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

  // Issue #549 (Gap 5) — the reports entry lives on the day board, and the
  // day board is reachable only from a scheduled day. So a 0-day scene gave
  // the user no reports affordance AND no reason to expect one. The empty
  // state now names the Soll/Ist report as what becomes available. The
  // second test is the guard: the hint must never leak onto a scene that
  // already has days (that would put the hint on every scene).
  group('SceneDetailScreen report-provenance empty state (issue #549)', () {
    testWidgets('scene with no shooting day names the Soll/Ist report', (
      tester,
    ) async {
      await setupContainer(scene: _scene(), dayRows: []);
      await pumpDetail(tester);

      expect(
        find.byKey(const Key('scene-shooting-days-empty')),
        findsOneWidget,
      );
      // Semantic: the copy itself, not just the presence of a subtitle slot.
      expect(
        find.textContaining('planned-vs-actual (Soll/Ist) report'),
        findsOneWidget,
      );
      // It names a LATER affordance, so it must not invent one now: no
      // season-level report entry, no reports-open key on this screen.
      expect(find.byKey(const Key('reports-open')), findsNothing);
    });

    testWidgets('the hint is ABSENT once the scene has a shooting day', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(days: ['d-1']),
        dayRows: [_day('d-1', label: '1. Tag')],
      );
      await pumpDetail(tester);

      expect(find.byKey(const Key('scene-shooting-days-empty')), findsNothing);
      expect(
        find.textContaining('planned-vs-actual (Soll/Ist) report'),
        findsNothing,
      );
    });
  });

  // Issue #550 — defensive client-side dedup. The read-model fan-out is fixed
  // backend-side; these tests pin that the screen degrades gracefully if a
  // future regression ever ships duplicated ids again: the header count and
  // the picker must never contradict each other (the reported symptom was
  // "Drehtage (2)" while the schedule button stayed permanently disabled).
  group('SceneDetailScreen duplicated read-model ids (issue #550)', () {
    testWidgets('duplicated shooting day ids render one row and one count', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(days: ['d-1', 'd-1']),
        dayRows: [
          _day('d-1', label: '1. Tag'),
          _day('d-2', label: '2. Tag'),
        ],
      );
      await pumpDetail(tester);

      // Count reflects the distinct days, not the fan-out length.
      expect(find.text('Shooting days (1)'), findsOneWidget);
      // The day renders exactly once — no duplicated row, no duplicated
      // day-board entry key.
      expect(find.byKey(const Key('scene-shooting-day-d-1')), findsOneWidget);
      expect(find.byKey(const Key('open-day-board-d-1')), findsOneWidget);
      // ...and the picker still offers the unscheduled day: count and
      // availability cannot contradict each other.
      await tester.tap(
        find.byKey(const Key('scene-shooting-day-schedule-scene-1')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('schedule-day-d-2')), findsOneWidget);
    });

    testWidgets('duplicated character ids render one row and one count', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(characters: ['c-1', 'c-1']),
        characterRows: [
          _character('c-1', name: 'Ada'),
          _character('c-2', name: 'Bob'),
        ],
      );
      await pumpDetail(tester);

      expect(find.text('Characters (1)'), findsOneWidget);
      expect(find.byKey(const Key('scene-character-c-1')), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      // The assign button stays enabled for the not-yet-assigned character.
      await tester.tap(find.byKey(const Key('scene-character-assign-scene-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assign-character-c-2')), findsOneWidget);
    });
  });
  // Issue #546 — the scene COSTUMES section (tasks 5.1–5.3): one row per
  // (character, beat), change arrow, empty-state affordance, picker dispatch,
  // AUTHZ-GATE denial before the network call, optimistic-after-2xx with the
  // version fence, and 409 → refetch with keyed copy.
  group('SceneDetailScreen costume beats (issue #546)', () {
    testWidgets('renders one beat row with the tile-identity label + cue', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(
          characters: ['ch-1'],
          beats: [_beat('ch-1', 0, note: 'Trench, guanti')],
        ),
        characterRows: [_character('ch-1')],
        costumeRows: [_costume('costume-1', subject: 'Mantel')],
      );
      await pumpDetail(tester);
      expect(
        find.byKey(const Key('scene-costume-beat-ch-1-0')),
        findsOneWidget,
      );
      // Tile-identity discipline: the label comes from the SAME helper as the
      // costume grid tile (detail subject), never from a random detail.
      expect(find.text('Mantel'), findsOneWidget);
      expect(find.text('Trench, guanti'), findsOneWidget);
      expect(find.text('Costumes (1)'), findsOneWidget);
    });

    testWidgets('two beats render the change sequence with the arrow', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(
          characters: ['ch-1'],
          beats: [
            _beat('ch-1', 0, costumeId: 'costume-1'),
            _beat('ch-1', 1, costumeId: 'costume-2', note: 'Wandel'),
          ],
        ),
        characterRows: [_character('ch-1')],
        costumeRows: [
          _costume('costume-1', subject: 'Mantel'),
          _costume('costume-2', subject: 'Hut'),
        ],
      );
      await pumpDetail(tester);
      expect(
        find.byKey(const Key('scene-costume-beat-ch-1-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('scene-costume-beat-ch-1-1')),
        findsOneWidget,
      );
      // The `→` prefix marks the change from the previous beat of the
      // character; order 0 carries none.
      expect(find.byKey(const Key('scene-costume-arrow-ch-1-0')), findsNothing);
      expect(
        find.byKey(const Key('scene-costume-arrow-ch-1-1')),
        findsOneWidget,
      );
      expect(find.text('Costumes (2)'), findsOneWidget);
    });

    testWidgets('empty-state affordance for a character without a beat', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(characters: ['ch-1']),
        characterRows: [_character('ch-1')],
        costumeRows: [_costume('costume-1', subject: 'Mantel')],
      );
      await pumpDetail(tester);
      expect(find.byKey(const Key('scene-costume-empty-ch-1')), findsOneWidget);
      expect(
        find.byKey(const Key('scene-costume-assign-ch-1')),
        findsOneWidget,
      );
      // No add-change affordance without an existing beat.
      expect(
        find.byKey(const Key('scene-costume-add-change-ch-1')),
        findsNothing,
      );
    });

    testWidgets(
      'picker dispatches add with the version echo + optimistic row',
      (tester) async {
        await setupContainer(
          scene: _scene(characters: ['ch-1']),
          characterRows: [_character('ch-1')],
          costumeRows: [
            _costume('costume-1', subject: 'Mantel'),
            _costume('costume-9', subject: 'Hut'),
          ],
        );
        await pumpDetail(tester);
        await tester.tap(find.byKey(const Key('scene-costume-assign-ch-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('pick-costume-costume-9')));
        // Pump PAST the sheet's exit animation with a FIXED duration —
        // never `pumpAndSettle`: the reconciling optimistic overlay shows
        // an indeterminate spinner (deterministic-tests rule, AGENTS §6).
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        await _pumpFrames(tester);
        expect(sceneRepo.addCalls, 1);
        // Version echo: the acted-on scene's version rides the request body.
        expect(sceneRepo.lastVersion, 1);
        // Optimistic-after-2xx: the beat row renders immediately from the
        // overlay — the fake projection still serves the pre-command scene
        // (version 1 < acked 2), so the version fence retains the overlay.
        expect(
          find.byKey(const Key('scene-costume-beat-ch-1-0')),
          findsOneWidget,
        );
        expect(find.text('Hut'), findsOneWidget);
        expect(find.text('Costumes (1)'), findsOneWidget);
      },
    );

    testWidgets('AUTHZ-GATE denial blocks BEFORE the network call', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(characters: ['ch-1']),
        characterRows: [_character('ch-1')],
        costumeRows: [_costume('costume-9', subject: 'Hut')],
        membershipCapabilities: const [],
      );
      await pumpDetail(tester);
      await tester.tap(find.byKey(const Key('scene-costume-assign-ch-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-costume-costume-9')));
      await _pumpFrames(tester);
      // The capability check denied before any network call: fake repo call
      // count of zero (provable non-issue of the request).
      expect(sceneRepo.addCalls, 0);
      // Localized 403 narrative keyed on the gate code: a signed-in user
      // WITHOUT the capability gets the forbidden narrative (not the
      // sign-in copy).
      expect(
        find.text('You need an active costume role in this season.'),
        findsOneWidget,
      );
    });

    testWidgets('409 conflict refetches the projection with keyed copy', (
      tester,
    ) async {
      final fetchLog = <int>[];
      await setupContainer(
        scene: _scene(characters: ['ch-1']),
        characterRows: [_character('ch-1')],
        costumeRows: [_costume('costume-9', subject: 'Hut')],
        scenesFetchLog: fetchLog,
      );
      await pumpDetail(tester);
      final baseline = fetchLog.length;
      sceneRepo.nextWrite = const Left(_conflict);
      await tester.tap(find.byKey(const Key('scene-costume-assign-ch-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-costume-costume-9')));
      await _pumpFrames(tester);
      expect(sceneRepo.addCalls, 1);
      // Conflict copy renders keyed on `code`…
      expect(
        find.text('Changed elsewhere — refresh and try again.'),
        findsOneWidget,
      );
      // …and the projection refetches so the next action echoes the current
      // version (never an automatic re-dispatch).
      expect(fetchLog.length, greaterThan(baseline));
    });

    testWidgets('removing the ONLY beat dispatches clear-all', (tester) async {
      await setupContainer(
        scene: _scene(characters: ['ch-1'], beats: [_beat('ch-1', 0)]),
        characterRows: [_character('ch-1')],
        costumeRows: [_costume('costume-1', subject: 'Mantel')],
      );
      await pumpDetail(tester);
      await tester.tap(find.byKey(const Key('scene-costume-remove-ch-1-0')));
      await tester.pumpAndSettle();
      // Confirm-first: no dispatch before confirmation.
      expect(sceneRepo.clearCalls, 0);
      expect(sceneRepo.removeCalls, 0);
      await tester.tap(
        find.byKey(const Key('scene-costume-remove-confirm-ch-1-0')),
      );
      await _pumpFrames(tester);
      // The single remaining beat IS the clear-all ("no costume in this
      // scene") — the dedicated route, not a per-order removal.
      expect(sceneRepo.clearCalls, 1);
      expect(sceneRepo.removeCalls, 0);
      // Optimistic empty state appears immediately.
      expect(find.byKey(const Key('scene-costume-empty-ch-1')), findsOneWidget);
    });

    testWidgets('removing one of two beats dispatches the per-order removal', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(
          characters: ['ch-1'],
          beats: [
            _beat('ch-1', 0, costumeId: 'costume-1'),
            _beat('ch-1', 1, costumeId: 'costume-2'),
          ],
        ),
        characterRows: [_character('ch-1')],
        costumeRows: [
          _costume('costume-1', subject: 'Mantel'),
          _costume('costume-2', subject: 'Hut'),
        ],
      );
      await pumpDetail(tester);
      await tester.tap(find.byKey(const Key('scene-costume-remove-ch-1-0')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('scene-costume-remove-confirm-ch-1-0')),
      );
      await _pumpFrames(tester);
      expect(sceneRepo.removeCalls, 1);
      expect(sceneRepo.clearCalls, 0);
    });

    testWidgets('SceneDetailScreen golden (costumes section, German)', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(
          characters: ['ch-1', 'ch-2'],
          beats: [
            _beat('ch-1', 0, note: 'Trench, guanti'),
            _beat('ch-1', 1, costumeId: 'costume-2'),
          ],
        ),
        characterRows: [
          _character('ch-1'),
          _character('ch-2', name: 'Bea'),
        ],
        costumeRows: [
          _costume('costume-1', subject: 'Mantel', categoryName: 'Jacke'),
          _costume('costume-2', subject: 'Hut', categoryName: 'Accessoires'),
        ],
      );
      // The golden harness renders the German template locale (AGENTS.md §6).
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppThemes.light(),
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const SceneDetailScreen(
              seasonId: 'season-1',
              episodeId: 'episode-1',
              sceneId: 'scene-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(SceneDetailScreen),
        matchesGoldenFile('goldens/scene_detail_screen.png'),
      );
    });
  });

  // CodeRabbit #4172169333 (Major): the aggregate computes the dense
  // order as max(existing)+1 — after a removal the surviving orders KEEP
  // their positions ([0, 2] stays [0, 2]), so a count-based optimistic
  // order would collide with the persisted one (duplicate row keys AND a
  // wrong remove dispatch).
  testWidgets('optimistic order continues at max+1 after a removal gap', (
    tester,
  ) async {
    await setupContainer(
      scene: _scene(
        characters: ['ch-1'],
        beats: [
          _beat('ch-1', 0, costumeId: 'costume-1'),
          _beat('ch-1', 2, costumeId: 'costume-3'),
        ],
      ),
      characterRows: [_character('ch-1')],
      costumeRows: [
        _costume('costume-1', subject: 'Mantel'),
        _costume('costume-9', subject: 'Hut'),
        _costume('costume-3', subject: 'Schuhe'),
      ],
    );
    await pumpDetail(tester);
    await tester.tap(find.byKey(const Key('scene-costume-add-change-ch-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-costume-costume-9')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    // The optimistic beat renders at order 3 (max 2 + 1) — the same
    // position the aggregate will assign — so the row keys stay unique.
    expect(find.byKey(const Key('scene-costume-beat-ch-1-3')), findsOneWidget);
    expect(find.text('Costumes (3)'), findsOneWidget);
  });

  // CodeRabbit #4172169329: a SECOND command must build its optimistic
  // beats from the freshest state — the acted-on scene snapshot still
  // omits the first (unprojected) beat, so building from it would drop
  // the first acknowledged change.
  testWidgets('second command builds on the freshest overlay beats', (
    tester,
  ) async {
    await setupContainer(
      scene: _scene(characters: ['ch-1']),
      characterRows: [_character('ch-1')],
      costumeRows: [
        _costume('costume-9', subject: 'Hut'),
        _costume('costume-3', subject: 'Schuhe'),
      ],
    );
    await pumpDetail(tester);
    // First beat: acked version 2, optimistic row 0.
    await tester.tap(find.byKey(const Key('scene-costume-assign-ch-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-costume-costume-9')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('scene-costume-beat-ch-1-0')), findsOneWidget);
    // Second beat: the controller must source the freshest beats (the
    // version-2 overlay), not the stale acted-on snapshot — the new beat
    // lands at order 1 and row 0 survives. Fixed pumps throughout: the
    // first overlay is still reconciling (indeterminate spinner), so
    // pumpAndSettle would never settle (AGENTS §6 deterministic tests).
    await tester.tap(find.byKey(const Key('scene-costume-add-change-ch-1')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('pick-costume-costume-3')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('scene-costume-beat-ch-1-0')), findsOneWidget);
    expect(find.byKey(const Key('scene-costume-beat-ch-1-1')), findsOneWidget);
    expect(sceneRepo.addCalls, 2);
    // The version fence echoed the freshest known version (2 from the
    // first ack), not the screen-rendered snapshot's 1.
    expect(sceneRepo.lastVersion, 2);
  });
}
