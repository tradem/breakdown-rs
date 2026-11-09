// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

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
import 'package:frontend_flutter/design/components/ai_score_stars.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/piece_domains_cache_dao.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/character_repository.dart';
import 'package:frontend_flutter/data/piece_repository.dart';
import 'package:frontend_flutter/data/scene_repository.dart';
import 'package:frontend_flutter/data/shooting_day_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/characters/characters_controller.dart';
import 'package:frontend_flutter/features/pieces/pieces_controller.dart';
import 'package:frontend_flutter/features/outfits/outfits_controller.dart';
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
  List<SceneOutfitBeatView> beats = const [],
  String? mood,
}) => SceneView(
  (b) => b
    ..id = id
    ..episodeId = 'episode-1'
    ..assignedCharacters.replace(characters)
    ..isScheduleSet = days.isNotEmpty
    ..location = 'Studio A'
    ..mood = mood
    ..sceneNumber = 7
    ..shootingDayIds.replace(days)
    ..outfitBeats.replace(beats)
    ..summary = 'Night shoot'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version,
);

SceneOutfitBeatView _beat(
  String characterId,
  int order, {
  String pieceId = 'piece-1',
  String? categoryName = 'Jacke',
  String? note,
}) => SceneOutfitBeatView(
  (b) => b
    ..characterId = characterId
    ..outfitId = pieceId
    ..outfitName = categoryName
    ..order = order
    ..note = note,
);

/// AI-extracted provenance (issue #834): the badge source discriminator.
SceneSourceBuilder _aiSource() => SceneSource(
  (s) => s
    ..oneOf = OneOf.fromValue2<String, SceneSourceOneOf>(
      value: SceneSourceOneOf(
        (d) => d
          ..aiExtracted = SceneSourceOneOfAiExtracted(
            (d2) => d2..documentId = 'job-1',
          ).toBuilder(),
      ),
    ),
).toBuilder();

SceneView _sceneAi() => SceneView(
  (b) => b
    ..id = 'scene-1'
    ..episodeId = 'episode-1'
    ..isScheduleSet = false
    ..location = 'Studio A'
    ..sceneNumber = 7
    ..summary = 'Night shoot'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1
    ..source_ = _aiSource(),
);

SceneView _sceneNoSummary() => SceneView(
  (b) => b
    ..id = 'scene-1'
    ..episodeId = 'episode-1'
    ..isScheduleSet = false
    ..location = 'Studio A'
    ..sceneNumber = 7
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

SceneView _sceneScored() => SceneView(
  (b) => b
    ..id = 'scene-1'
    ..episodeId = 'episode-1'
    ..isScheduleSet = false
    ..location = 'Studio A'
    ..sceneNumber = 7
    ..summary = 'Night shoot'
    ..sceneScore = 0.55
    ..synopsisScore = 0.82
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

/// A mood OUTSIDE the canonical set (issue #834): the editor must keep it
/// selectable and echo it verbatim.
SceneView _sceneCustomMood() => SceneView(
  (b) => b
    ..id = 'scene-1'
    ..episodeId = 'episode-1'
    ..isScheduleSet = false
    ..location = 'Studio A'
    ..mood = 'X/Y'
    ..sceneNumber = 7
    ..summary = 'Night shoot'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 4,
);

OutfitView _outfit(String id, {String name = 'Alltagslook'}) => OutfitView(
  (b) => b
    ..id = id
    ..characterId = 'ch-1'
    ..name = name
    ..notes = ''
    ..pieces.replace(const [])
    ..photos.replace(const [])
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

PieceView _piece(String id, {String? subject, String? categoryName}) =>
    PieceView(
      (b) => b
        ..name = 'Fundus-Piece'
        ..id = id
        ..notes = ''
        ..categoryName = categoryName
        ..details.replace([
          PieceDetailView(
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

/// The parent episode the detail screen is navigated from (issue #669:
/// the day empty-state's quick-create affordance is sourced from this
/// read DTO — no second projection lookup).
EpisodeView _episode() => EpisodeView(
  (b) => b
    ..id = 'episode-1'
    ..blockId = 'block-1'
    ..number = 1
    ..projectId = 'series-1'
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

  /// Issue #834: the update-details dispatch log — the LAST request the
  /// controller sent, for the version-echo and mood-preservation asserts.
  UpdateSceneDetailsRequest? lastUpdateDetails;

  @override
  Future<Result<int>> updateDetails(
    String id,
    UpdateSceneDetailsRequest request,
  ) {
    updateCalls++;
    lastVersion = request.version;
    lastUpdateDetails = request;
    // Realistic ack: the NEXT aggregate version after the echoed one — the
    // details overlay's optimistic fence (`row.version < overlay.version`)
    // only holds when the ack advances the version (CodeRabbit #868 flow).
    return Future.value(nextWrite ?? Right((request.version) + 1));
  }

  @override
  Future<Result<int>> addOutfitBeat(
    String id,
    AddSceneOutfitBeatRequest request,
  ) {
    addCalls++;
    lastVersion = request.version;
    return Future.value(nextWrite ?? const Right(2));
  }

  @override
  Future<Result<int>> updateOutfitBeat(
    String id,
    String characterId,
    int order,
    UpdateSceneOutfitBeatRequest request,
  ) {
    updateCalls++;
    lastVersion = request.version;
    return Future.value(nextWrite ?? const Right(2));
  }

  @override
  Future<Result<int>> removeOutfitBeat(
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
  Future<Result<int>> clearOutfitBeats(
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

    /// Issue #669 enable-path: a live holder the day-list fetch override
    /// reads on every (re)run — updating it + invalidating the fetch
    /// provider simulates the projection reconciling a newly created day,
    /// deterministically (no wall-clock, no real network).
    ValueNotifier<List<ShootingDayView>>? dayRowsLive,
    List<int>? scenesFetchLog,
    List<String> membershipCapabilities = const ['assign_costumes'],
    List<PieceView> pieceRows = const [],
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
        pieceRepositoryProvider.overrideWithValue(
          PieceRepository(BreakdownApi(), PieceCacheDao(db)),
        ),
        piecesListFetchProvider('season-1')
            .overrideWith((ref) async => Right(pieceRows)),
        // A scene casts an OUTFIT: the picker reads the character's looks.
        characterOutfitsProvider('ch-1').overrideWith(
          (ref) async => Right(<OutfitView>[_outfit('outfit-9', name: 'Hut')]),
        ),
        scenesListFetchProvider('episode-1').overrideWith((ref) async {
          scenesFetchLog?.add(1);
          return Right(scene == null ? [] : [scene]);
        }),
        charactersListFetchProvider('season-1')
            .overrideWith((ref) async => Right(characterRows)),
        shootingDaysListFetchProvider('episode-1')
            .overrideWith((ref) async => Right(dayRowsLive?.value ?? dayRows)),
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
        child: MaterialApp(
          home: SceneDetailScreen(
            seasonId: 'season-1',
            // Issue #669: the screen carries the parent EpisodeView the
            // user navigated from (quick-create affordance in the day
            // empty state is sourced from this DTO, never a re-fetch).
            episode: _episode(),
            sceneId: 'scene-1',
          ),
        ),
      ),
    );
    await _pumpFrames(tester, n: 30);
  }

  /// Issue #834: every section is COLLAPSED by default — a test asserting
  /// section content expands the section first (one tap on the section
  /// header card).
  Future<void> expandSection(WidgetTester tester, String sectionKey) async {
    // A scene that never resolved renders no sections at all — a tap would
    // throw on the empty finder.
    final header = find.byKey(Key(sectionKey));
    if (header.evaluate().isEmpty) return;
    await tester.tap(header.first);
    await tester.pumpAndSettle();
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
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-characters-scene-1');
      expect(find.text('Ada'), findsOneWidget);
      expect(find.byKey(const Key('scene-character-ch-1')), findsOneWidget);
    });

    testWidgets('empty assignment renders explicit empty state', (
      tester,
    ) async {
      await setupContainer(scene: _scene());
      await pumpDetail(tester);
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-characters-scene-1');
      expect(find.byKey(const Key('scene-characters-empty')), findsOneWidget);
    });

    testWidgets('assign carries picked id + scene version', (tester) async {
      await setupContainer(
        scene: _scene(),
        characterRows: [_character('ch-9', name: 'Bea')],
      );
      await pumpDetail(tester);
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-characters-scene-1');
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
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-characters-scene-1');
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
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-characters-scene-1');
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
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-characters-scene-1');
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
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-characters-scene-1');
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
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-shooting-days-scene-1');
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
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-shooting-days-scene-1');
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
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-shooting-days-scene-1');
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

  // Issue #669 — a fresh script import creates scenes but NO shooting days
  // (days come from the schedule import or manual quick-create), so every
  // imported scene had an empty picker candidate list: the schedule button
  // was permanently disabled AND silent — the user could not know why or
  // what to do next.
  group('SceneDetailScreen empty day candidates hint (issue #669)', () {
    testWidgets(
      'days exist but ALL ineligible (scheduled/archived): factual note, '
      'NO create affordance (CodeRabbit review)',
      (tester) async {
        // One day, already scheduled on this scene → candidates empty but
        // the episode HAS a shooting day. The hint must not claim "no
        // shooting day in this episode yet" and must not offer creating
        // another one.
        await setupContainer(
          scene: _scene(days: ['d-1']),
          dayRows: [_day('d-1', label: '1. Tag')],
        );
        await pumpDetail(tester);
        // Issue #834: the section is collapsed by default — expand first.
        await expandSection(tester, 'scene-shooting-days-scene-1');

        final button = tester.widget<FilledButton>(
          find.byKey(const Key('scene-shooting-day-schedule-scene-1')),
        );
        expect(button.onPressed, isNull);
        expect(
          find.byKey(const Key('scene-shooting-day-no-candidates-scene-1')),
          findsOneWidget,
        );
        expect(
          find.textContaining('already scheduled or archived'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('scene-shooting-day-create-scene-1')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'imported episode with 0 shooting days: button disabled WITH inline '
      'hint and quick-create affordance',
      (tester) async {
        await setupContainer(scene: _scene(), dayRows: const []);
        await pumpDetail(tester);
        // Issue #834: the section is collapsed by default — expand first.
        await expandSection(tester, 'scene-shooting-days-scene-1');

        // The schedule button stays disabled (nothing to pick).
        final button = tester.widget<FilledButton>(
          find.byKey(const Key('scene-shooting-day-schedule-scene-1')),
        );
        expect(button.onPressed, isNull);
        // …but the state explains itself: inline hint naming the missing
        // prerequisite + the direct quick-create path.
        expect(
          find.byKey(const Key('scene-shooting-day-no-candidates-scene-1')),
          findsOneWidget,
        );
        expect(
          find.textContaining('No shooting day in this episode yet'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('scene-shooting-day-create-scene-1')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'after a day exists (projection reconciles) the button enables and '
      'the hint disappears',
      (tester) async {
        final dayRowsLive = ValueNotifier<List<ShootingDayView>>(const []);
        addTearDown(dayRowsLive.dispose);
        await setupContainer(scene: _scene(), dayRowsLive: dayRowsLive);
        await pumpDetail(tester);
        // Issue #834: the section is collapsed by default — expand first.
        await expandSection(tester, 'scene-shooting-days-scene-1');
        expect(
          find.byKey(const Key('scene-shooting-day-no-candidates-scene-1')),
          findsOneWidget,
        );

        // The quick-create sheet shares the same episode-scoped controller
        // store the section watches — a created day reconciles the view
        // provider and re-enables the picker without a full screen reload.
        await tester.tap(
          find.byKey(const Key('scene-shooting-day-create-scene-1')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        // Dismiss the sheet (no Cupertino back button on a modal sheet —
        // pop the topmost route programmatically).
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );
        navigator.pop();
        await tester.pumpAndSettle();

        // The day projection reconciles the created day (deterministic:
        // the live fetch holder updates + the fetch provider re-runs —
        // exactly what a real refetch cycle does, without wall-clock).
        dayRowsLive.value = [_day('d-new', label: 'Neuer Tag')];
        container.invalidate(shootingDaysListFetchProvider('episode-1'));
        await _pumpFrames(tester, n: 30);

        final button = tester.widget<FilledButton>(
          find.byKey(const Key('scene-shooting-day-schedule-scene-1')),
        );
        expect(button.onPressed, isNotNull);
        expect(
          find.byKey(const Key('scene-shooting-day-no-candidates-scene-1')),
          findsNothing,
        );
      },
    );

    testWidgets('days present: no hint, button enabled (no regression)', (
      tester,
    ) async {
      await setupContainer(scene: _scene(), dayRows: [_day('d-1')]);
      await pumpDetail(tester);
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-shooting-days-scene-1');

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('scene-shooting-day-schedule-scene-1')),
      );
      expect(button.onPressed, isNotNull);
      expect(
        find.byKey(const Key('scene-shooting-day-no-candidates-scene-1')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('scene-shooting-day-create-scene-1')),
        findsNothing,
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
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-shooting-days-scene-1');

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
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-shooting-days-scene-1');

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
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-shooting-days-scene-1');

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
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-characters-scene-1');

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
  group('SceneDetailScreen piece beats (issue #546)', () {
    testWidgets('renders one beat row with the tile-identity label + cue', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(
          characters: ['ch-1'],
          beats: [
            _beat('ch-1', 0, note: 'Trench, guanti', categoryName: 'Hut'),
          ],
        ),
        characterRows: [_character('ch-1')],
        pieceRows: [_piece('piece-1', subject: 'Mantel')],
      );
      await pumpDetail(tester);
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-pieces-scene-1');
      expect(find.byKey(const Key('scene-piece-beat-ch-1-0')), findsOneWidget);
      // The beat casts an OUTFIT, so its label is the look's joined name.
      expect(find.text('Hut'), findsOneWidget);
      expect(find.text('Trench, guanti'), findsOneWidget);
      expect(find.text('Looks (1)'), findsOneWidget);
    });

    testWidgets('two beats render the change sequence with the arrow', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(
          characters: ['ch-1'],
          beats: [
            _beat('ch-1', 0, pieceId: 'piece-1', categoryName: 'Mantel'),
            _beat(
              'ch-1',
              1,
              pieceId: 'piece-2',
              note: 'Wandel',
              categoryName: 'Kleid',
            ),
          ],
        ),
        characterRows: [_character('ch-1')],
        pieceRows: [
          _piece('piece-1', subject: 'Mantel'),
          _piece('piece-2', subject: 'Hut'),
        ],
      );
      await pumpDetail(tester);
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-pieces-scene-1');
      expect(find.byKey(const Key('scene-piece-beat-ch-1-0')), findsOneWidget);
      expect(find.byKey(const Key('scene-piece-beat-ch-1-1')), findsOneWidget);
      // The `→` prefix marks the change from the previous beat of the
      // character; order 0 carries none.
      expect(find.byKey(const Key('scene-piece-arrow-ch-1-0')), findsNothing);
      expect(find.byKey(const Key('scene-piece-arrow-ch-1-1')), findsOneWidget);
      expect(find.text('Looks (2)'), findsOneWidget);
    });

    testWidgets('empty-state affordance for a character without a beat', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(characters: ['ch-1']),
        characterRows: [_character('ch-1')],
        pieceRows: [_piece('piece-1', subject: 'Mantel')],
      );
      await pumpDetail(tester);
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-pieces-scene-1');
      expect(find.byKey(const Key('scene-piece-empty-ch-1')), findsOneWidget);
      expect(find.byKey(const Key('scene-piece-assign-ch-1')), findsOneWidget);
      // No add-change affordance without an existing beat.
      expect(
        find.byKey(const Key('scene-piece-add-change-ch-1')),
        findsNothing,
      );
    });

    testWidgets(
      'picker dispatches add with the version echo + optimistic row',
      (tester) async {
        await setupContainer(
          scene: _scene(characters: ['ch-1']),
          characterRows: [_character('ch-1')],
          pieceRows: [
            _piece('piece-1', subject: 'Mantel'),
            _piece('piece-9', subject: 'Hut'),
          ],
        );
        await pumpDetail(tester);
        // Issue #834: the section is collapsed by default — expand first.
        await expandSection(tester, 'scene-pieces-scene-1');
        await tester.tap(find.byKey(const Key('scene-piece-assign-ch-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('pick-outfit-outfit-9')));
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
          find.byKey(const Key('scene-piece-beat-ch-1-0')),
          findsOneWidget,
        );
        expect(find.text('Hut'), findsOneWidget);
        expect(find.text('Looks (1)'), findsOneWidget);
      },
    );

    testWidgets('AUTHZ-GATE denial blocks BEFORE the network call', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(characters: ['ch-1']),
        characterRows: [_character('ch-1')],
        pieceRows: [_piece('piece-9', subject: 'Hut')],
        membershipCapabilities: const [],
      );
      await pumpDetail(tester);
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-pieces-scene-1');
      await tester.tap(find.byKey(const Key('scene-piece-assign-ch-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-outfit-outfit-9')));
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
        pieceRows: [_piece('piece-9', subject: 'Hut')],
        scenesFetchLog: fetchLog,
      );
      await pumpDetail(tester);
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-pieces-scene-1');
      final baseline = fetchLog.length;
      sceneRepo.nextWrite = const Left(_conflict);
      await tester.tap(find.byKey(const Key('scene-piece-assign-ch-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-outfit-outfit-9')));
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
        pieceRows: [_piece('piece-1', subject: 'Mantel')],
      );
      await pumpDetail(tester);
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-pieces-scene-1');
      await tester.tap(find.byKey(const Key('scene-piece-remove-ch-1-0')));
      await tester.pumpAndSettle();
      // Confirm-first: no dispatch before confirmation.
      expect(sceneRepo.clearCalls, 0);
      expect(sceneRepo.removeCalls, 0);
      await tester.tap(
        find.byKey(const Key('scene-piece-remove-confirm-ch-1-0')),
      );
      await _pumpFrames(tester);
      // The single remaining beat IS the clear-all ("no piece in this
      // scene") — the dedicated route, not a per-order removal.
      expect(sceneRepo.clearCalls, 1);
      expect(sceneRepo.removeCalls, 0);
      // Optimistic empty state appears immediately.
      expect(find.byKey(const Key('scene-piece-empty-ch-1')), findsOneWidget);
    });

    testWidgets('removing one of two beats dispatches the per-order removal', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(
          characters: ['ch-1'],
          beats: [
            _beat('ch-1', 0, pieceId: 'piece-1', categoryName: 'Mantel'),
            _beat('ch-1', 1, pieceId: 'piece-2'),
          ],
        ),
        characterRows: [_character('ch-1')],
        pieceRows: [
          _piece('piece-1', subject: 'Mantel'),
          _piece('piece-2', subject: 'Hut'),
        ],
      );
      await pumpDetail(tester);
      // Issue #834: the section is collapsed by default — expand first.
      await expandSection(tester, 'scene-pieces-scene-1');
      await tester.tap(find.byKey(const Key('scene-piece-remove-ch-1-0')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('scene-piece-remove-confirm-ch-1-0')),
      );
      await _pumpFrames(tester);
      expect(sceneRepo.removeCalls, 1);
      expect(sceneRepo.clearCalls, 0);
    });

    testWidgets('SceneDetailScreen golden (pieces section, German)', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(
          characters: ['ch-1', 'ch-2'],
          beats: [
            _beat('ch-1', 0, note: 'Trench, guanti'),
            _beat('ch-1', 1, pieceId: 'piece-2'),
          ],
        ),
        characterRows: [
          _character('ch-1'),
          _character('ch-2', name: 'Bea'),
        ],
        pieceRows: [
          _piece('piece-1', subject: 'Mantel', categoryName: 'Jacke'),
          _piece('piece-2', subject: 'Hut', categoryName: 'Accessoires'),
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
            home: SceneDetailScreen(
              seasonId: 'season-1',
              episode: _episode(),
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
          _beat('ch-1', 0, pieceId: 'piece-1', categoryName: 'Mantel'),
          _beat('ch-1', 2, pieceId: 'piece-3'),
        ],
      ),
      characterRows: [_character('ch-1')],
      pieceRows: [
        _piece('piece-1', subject: 'Mantel'),
        _piece('piece-9', subject: 'Hut'),
        _piece('piece-3', subject: 'Schuhe'),
      ],
    );
    await pumpDetail(tester);
    // Issue #834: the section is collapsed by default — expand first.
    await expandSection(tester, 'scene-pieces-scene-1');
    await tester.tap(find.byKey(const Key('scene-piece-add-change-ch-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-outfit-outfit-9')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    // The optimistic beat renders at order 3 (max 2 + 1) — the same
    // position the aggregate will assign — so the row keys stay unique.
    expect(find.byKey(const Key('scene-piece-beat-ch-1-3')), findsOneWidget);
    expect(find.text('Looks (3)'), findsOneWidget);
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
      pieceRows: [
        _piece('piece-9', subject: 'Hut'),
        _piece('piece-3', subject: 'Schuhe'),
      ],
    );
    await pumpDetail(tester);
    // Issue #834: the section is collapsed by default — expand first.
    await expandSection(tester, 'scene-pieces-scene-1');
    // First beat: acked version 2, optimistic row 0.
    await tester.tap(find.byKey(const Key('scene-piece-assign-ch-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-outfit-outfit-9')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('scene-piece-beat-ch-1-0')), findsOneWidget);
    // Second beat: the controller must source the freshest beats (the
    // version-2 overlay), not the stale acted-on snapshot — the new beat
    // lands at order 1 and row 0 survives. Fixed pumps throughout: the
    // first overlay is still reconciling (indeterminate spinner), so
    // pumpAndSettle would never settle (AGENTS §6 deterministic tests).
    await tester.tap(find.byKey(const Key('scene-piece-add-change-ch-1')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('pick-outfit-outfit-9')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('scene-piece-beat-ch-1-0')), findsOneWidget);
    expect(find.byKey(const Key('scene-piece-beat-ch-1-1')), findsOneWidget);
    expect(sceneRepo.addCalls, 2);
    // The version fence echoed the freshest known version (2 from the
    // first ack), not the screen-rendered snapshot's 1.
    expect(sceneRepo.lastVersion, 2);
  });

  // -------------------------------------------------------------------------
  // Issue #834 — redesign: compact header, divider-free collapsed sections,
  // synopsis + ratings, edit sheet.
  // -------------------------------------------------------------------------

  group('SceneDetailScreen redesign (issue #834) — shell', () {
    testWidgets('app bar reads Szene {n}, never the summary', (tester) async {
      await setupContainer(scene: _scene());
      await pumpDetail(tester);
      expect(find.text('Scene 7'), findsOneWidget);
      // The summary is page content (synopsis section), not the title.
      expect(find.byKey(const Key('scene-synopsis-text')), findsOneWidget);
    });

    testWidgets('sections are collapsed by default, counts stay visible', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(characters: ['ch-1'], days: ['d-1']),
        characterRows: [_character('ch-1')],
        dayRows: [_day('d-1')],
      );
      await pumpDetail(tester);
      // Collapsed: no character/day rows in the tree…
      expect(find.byKey(const Key('scene-character-ch-1')), findsNothing);
      expect(find.byKey(const Key('scene-shooting-day-d-1')), findsNothing);
      // …but the header counts tell the story. The day section sits below
      // the fold: the ListView builds slivers lazily, so DRAG it into the
      // viewport before asserting (skipOffstage cannot find unbuilt
      // children).
      expect(find.text('Characters (1)'), findsOneWidget);
      expect(find.text('Shooting days (1)'), findsOneWidget);
    });

    testWidgets('no Divider renders in any expansion state', (tester) async {
      await setupContainer(scene: _scene(characters: ['ch-1']));
      await pumpDetail(tester);
      expect(find.byType(Divider), findsNothing);
      // Expand every section, assert again (the M3 ExpansionTile used to
      // draw its default top+bottom borders while expanded — issue #834).
      for (final key in [
        'scene-characters-scene-1',
        'scene-pieces-scene-1',
        'scene-shooting-days-scene-1',
      ]) {
        await expandSection(tester, key);
      }
      expect(find.byType(Divider), findsNothing);
      // The M3 ExpansionTile paints its divider LINES from `shape` — not
      // from `Divider` widgets. If the shape default ever returns, the
      // lines reappear without any Divider in the tree (CodeRabbit #868):
      // assert the borderless CONFIG in both states.
      for (final tile in tester.widgetList<ExpansionTile>(
        find.byType(ExpansionTile),
      )) {
        expect(tile.shape, const Border());
        expect(tile.collapsedShape, const Border());
      }
      // And each section owns a stable, UNIQUE PageStorageKey so an
      // expanded section survives scroll-out/in of the retained viewport.
      final storageKeys = tester
          .widgetList<ExpansionTile>(find.byType(ExpansionTile))
          .map((t) => t.key)
          .whereType<PageStorageKey>()
          .map((k) => k.value)
          .toSet();
      expect(storageKeys, hasLength(3));
    });

    testWidgets('header block: numeral, location, mood + schedule chips', (
      tester,
    ) async {
      await setupContainer(
        scene: _scene(characters: const []),
        // SceneMoodLabel only shows icons next to parseable moods; the
        // text label renders either way.
      );
      await pumpDetail(tester);
      expect(find.byKey(const Key('scene-detail-header')), findsOneWidget);
      expect(
        find.byKey(const Key('scene-detail-header-location')),
        findsOneWidget,
      );
      expect(find.text('Unscheduled'), findsOneWidget);
      // A manual scene shows NO provenance badge (no false attribution).
      expect(find.byKey(const Key('scene-ai-badge-scene-1')), findsNothing);
    });

    testWidgets('AI-extracted scene renders the provenance badge', (
      tester,
    ) async {
      await setupContainer(scene: _sceneAi());
      await pumpDetail(tester);
      expect(find.byKey(const Key('scene-ai-badge-scene-1')), findsOneWidget);
      expect(
        find.byKey(const Key('scene-synopsis-ai-badge-scene-1')),
        findsOneWidget,
      );
    });
  });

  group('SceneDetailScreen redesign (issue #834) — synopsis + ratings', () {
    testWidgets('synopsis renders in full, empty state stays honest', (
      tester,
    ) async {
      await setupContainer(scene: _scene());
      await pumpDetail(tester);
      expect(find.byKey(const Key('scene-synopsis-text')), findsOneWidget);
      expect(find.text('Night shoot'), findsOneWidget);
    });

    testWidgets('missing synopsis renders the explicit empty state', (
      tester,
    ) async {
      await setupContainer(scene: _sceneNoSummary());
      await pumpDetail(tester);
      expect(find.byKey(const Key('scene-synopsis-empty')), findsOneWidget);
      expect(find.text('No synopsis'), findsOneWidget);
    });

    testWidgets('scores render as stars', (tester) async {
      await setupContainer(scene: _sceneScored());
      await pumpDetail(tester);
      expect(
        find.byKey(const Key('scene-synopsis-rating-synopsis')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('scene-synopsis-rating-scene')),
        findsOneWidget,
      );
      // Both score rows render, and the score sits under the KEYED row —
      // a swap would now fail (CodeRabbit #868; the bucket math itself is
      // covered by the AiScoreStars unit tests).
      double? scoreUnderRow(String rowKey) {
        final row = find.byKey(Key(rowKey));
        final starsWidgets = tester
            .widgetList<AiScoreStars>(
              find.descendant(of: row, matching: find.byType(AiScoreStars)),
            )
            .toList();
        return starsWidgets.isEmpty ? null : starsWidgets.first.score;
      }

      expect(scoreUnderRow('scene-synopsis-rating-synopsis'), 0.82);
      expect(scoreUnderRow('scene-synopsis-rating-scene'), 0.55);
    });

    testWidgets('null scores render no stars at all', (tester) async {
      await setupContainer(scene: _scene());
      await pumpDetail(tester);
      // Honest absence (issue #834): an unscored scene shows no star
      // widget — never a fabricated rating.
      expect(find.byKey(const Key('ai-score-stars')), findsNothing);
      expect(
        find.byKey(const Key('scene-synopsis-rating-synopsis')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('scene-synopsis-rating-scene')),
        findsNothing,
      );
    });
  });

  group('SceneDetailScreen redesign (issue #834) — edit sheet', () {
    testWidgets('the sheet echoes the acted-on version', (tester) async {
      await setupContainer(scene: _scene(version: 4));
      await pumpDetail(tester);
      await tester.tap(find.byKey(const Key('scene-detail-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('scene-edit-location')),
        'Set C',
      );
      await tester.tap(find.byKey(const Key('scene-edit-save')));
      await tester.pumpAndSettle();
      expect(sceneRepo.updateCalls, 1);
      expect(sceneRepo.lastVersion, 4);
      // Optimistic DETAILS overlay (issue #834): the edited location stays
      // visible even though the projection still serves the pre-edit row —
      // the version-fenced overlay holds the saved state until catch-up.
      expect(find.text('Set C'), findsWidgets);
    });

    testWidgets('a non-canonical mood survives the editor untouched', (
      tester,
    ) async {
      await setupContainer(scene: _sceneCustomMood());
      await pumpDetail(tester);
      await tester.tap(find.byKey(const Key('scene-detail-edit')));
      await tester.pumpAndSettle();
      // The stored value renders as its own selected chip next to the
      // canonical set…
      expect(find.byKey(const Key('scene-edit-mood-X/Y')), findsOneWidget);
      // …and a save that touches only the location echoes it verbatim.
      await tester.enterText(
        find.byKey(const Key('scene-edit-location')),
        'Set B',
      );
      await tester.tap(find.byKey(const Key('scene-edit-save')));
      await tester.pumpAndSettle();
      expect(sceneRepo.lastUpdateDetails, isNotNull);
      expect(sceneRepo.lastUpdateDetails!.details.mood, 'X/Y');
    });

    testWidgets('picking a canonical mood chip replaces the custom value', (
      tester,
    ) async {
      await setupContainer(scene: _sceneCustomMood());
      await pumpDetail(tester);
      await tester.tap(find.byKey(const Key('scene-detail-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scene-edit-mood-I/T')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scene-edit-save')));
      await tester.pumpAndSettle();
      expect(sceneRepo.lastUpdateDetails!.details.mood, 'I/T');
    });

    testWidgets('version conflict: sheet stays open, projection refreshes', (
      tester,
    ) async {
      final fetchLog = <int>[];
      await setupContainer(scene: _scene(), scenesFetchLog: fetchLog);
      await pumpDetail(tester);
      final baseline = fetchLog.length;
      sceneRepo.nextWrite = const Left(_conflict);
      await tester.tap(find.byKey(const Key('scene-detail-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scene-edit-save')));
      await tester.pumpAndSettle();
      // The localized retry narrative renders INSIDE the sheet — the draft
      // survives (CodeRabbit #868).
      expect(find.byKey(const Key('scene-edit-error')), findsOneWidget);
      expect(
        find.text(
          'The scene changed in the meantime. '
          'Refresh the view and try again.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('scene-edit-sheet')), findsOneWidget);
      // The conflict refreshed the projection WITHOUT resubmitting.
      expect(fetchLog.length, greaterThan(baseline));
      expect(sceneRepo.updateCalls, 1);
    });

    testWidgets('failed save keeps the draft and a retry succeeds', (
      tester,
    ) async {
      await setupContainer(scene: _scene());
      await pumpDetail(tester);
      // First save fails (network), then succeeds on retry.
      sceneRepo.nextWrite = const Left(
        ProblemError(code: 'transport.timeout', status: 0),
      );
      await tester.tap(find.byKey(const Key('scene-detail-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('scene-edit-location')),
        'Set D',
      );
      await tester.tap(find.byKey(const Key('scene-edit-save')));
      await tester.pumpAndSettle();
      // The sheet stays open, the error renders inside and the DRAFT
      // survives — the user does not retype their edit.
      expect(find.byKey(const Key('scene-edit-error')), findsOneWidget);
      expect(find.text('Set D'), findsWidgets);
      sceneRepo.nextWrite = null;
      await tester.tap(find.byKey(const Key('scene-edit-save')));
      await tester.pumpAndSettle();
      expect(sceneRepo.updateCalls, 2);
      expect(sceneRepo.lastUpdateDetails!.details.location, 'Set D');
      // Success closes the sheet.
      expect(find.byKey(const Key('scene-edit-sheet')), findsNothing);
    });

    testWidgets('an unparseable number is rejected before saving', (
      tester,
    ) async {
      await setupContainer(scene: _scene());
      await pumpDetail(tester);
      await tester.tap(find.byKey(const Key('scene-detail-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('scene-edit-number')), '7a');
      await tester.tap(find.byKey(const Key('scene-edit-save')));
      await tester.pumpAndSettle();
      // The sheet stays open with the field error; nothing was dispatched
      // and the stored number is NOT silently cleared.
      expect(
        find.text(
          'Enter a valid whole number — the stored number was not changed.',
        ),
        findsOneWidget,
      );
      expect(sceneRepo.updateCalls, 0);
      // Fixing the input saves successfully.
      await tester.enterText(find.byKey(const Key('scene-edit-number')), '12');
      await tester.tap(find.byKey(const Key('scene-edit-save')));
      await tester.pumpAndSettle();
      expect(sceneRepo.updateCalls, 1);
      expect(sceneRepo.lastUpdateDetails!.details.sceneNumber, 12);
    });

    testWidgets('deselecting a mood chip clears the field value', (
      tester,
    ) async {
      await setupContainer(scene: _scene(mood: 'I/T'));
      await pumpDetail(tester);
      await tester.tap(find.byKey(const Key('scene-detail-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scene-edit-mood-I/T')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scene-edit-save')));
      await tester.pumpAndSettle();
      // The deselected chip's value must not be secretly submitted
      // (CodeRabbit #868): no mood left.
      expect(sceneRepo.lastUpdateDetails!.details.mood, isNull);
    });

    testWidgets('both overlays stay visible during projection lag', (
      tester,
    ) async {
      // The CodeRabbit #868 follow-up: a beat ack (v3) AFTER a details ack
      // (v2) while the projection is still at v1 must not hide the saved
      // details — the chained merge bumped the row version to 3 and the
      // details fence skipped a still-pending overlay.
      await setupContainer(
        scene: _scene(characters: ['ch-1'], beats: [_beat('ch-1', 0)]),
        characterRows: [_character('ch-1')],
      );
      await pumpDetail(tester);
      if (find
          .byKey(const Key('scene-piece-add-change-ch-1'))
          .evaluate()
          .isEmpty) {
        await expandSection(tester, 'scene-pieces-scene-1');
      }

      // 1) Details ack (v2): the fake echoes request.version + 1.
      await tester.tap(find.byKey(const Key('scene-detail-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('scene-edit-summary')),
        'Geänderte Synopsis',
      );
      await tester.tap(find.byKey(const Key('scene-edit-save')));
      await tester.pumpAndSettle();
      expect(find.text('Geänderte Synopsis'), findsOneWidget);

      // 2) Beat ack (v3, newer than the details overlay).
      sceneRepo.nextWrite = const Right(3);
      await tester.tap(find.byKey(const Key('scene-piece-add-change-ch-1')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('pick-outfit-outfit-9')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // The projection STILL serves the pre-edit v1 row (the fetch override
      // never changes) — both optimistic overlays must render: the new beat
      // AND the saved synopsis. The old chained merge bumped the row version
      // to 3 and flashed the OLD synopsis back.
      expect(find.byKey(const Key('scene-piece-beat-ch-1-1')), findsOneWidget);
      expect(find.text('Geänderte Synopsis'), findsOneWidget);
    });

    testWidgets(
      'a stored mood with surrounding whitespace is echoed verbatim',
      (tester) async {
        await setupContainer(scene: _scene(mood: ' X/Y '));
        await pumpDetail(tester);
        await tester.tap(find.byKey(const Key('scene-detail-edit')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('scene-edit-location')),
          'Set E',
        );
        await tester.tap(find.byKey(const Key('scene-edit-save')));
        await tester.pumpAndSettle();
        // The editor never trims a stored value it did not touch
        // (CodeRabbit #868).
        expect(sceneRepo.lastUpdateDetails!.details.mood, ' X/Y ');
      },
    );
  });
}
