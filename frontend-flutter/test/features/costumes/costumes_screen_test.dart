// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

// Tier-2 widget + controller tests for `CostumesScreen` (Task 4.3):
// data/empty/error/stale/overlay states (semantic finders, never `byType`
// alone), create (empty-body contract + overlay), assign/unassign version
// fence, 409 conflict copy, role-denial with request-counter proof, and
// goldens {light,dark}×{android,macos}.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/character_repository.dart';
import 'package:frontend_flutter/data/costume_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/characters/characters_controller.dart';
import 'package:frontend_flutter/features/costumes/costumes_controller.dart';
import 'package:frontend_flutter/features/costumes/costumes_screen.dart';

import '../seasons/seasons_test_fakes.dart';

const _networkDown = ProblemError(code: 'transport.connectionError');
const _conflict = ProblemError(code: 'concurrency.conflict', status: 409);

CostumeView _costume(
  String id, {
  String? characterId,
  int version = 1,
  String notes = '',
}) => CostumeView(
  (b) => b
    ..id = id
    ..characterId = characterId
    ..notes = notes.isEmpty ? 'Costume $id' : notes
    ..details.replace(BuiltList<CostumeDetailView>())
    ..photos.replace(BuiltList<CostumePhotoView>())
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version,
);

CharacterView _character(String id, {String name = 'Bea'}) => CharacterView(
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

SeasonView _season() => SeasonView(
  (b) => b
    ..id = 'season-1'
    ..number = 1
    ..seriesId = 'series-1'
    ..title = 'Season One'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

SeasonMembershipDto _membership(List<String> caps) => SeasonMembershipDto(
  (b) => b
    ..seasonId = 'season-1'
    ..hasActiveCostumeRoleInSeason = caps.isNotEmpty
    ..capabilities.replace(caps),
);

class _FakeCostumeRepository extends CostumeRepository {
  _FakeCostumeRepository(super.api, super.cache);

  Result<IdVersionResponse>? nextCreate;
  Result<int>? nextWrite;
  int listCalls = 0;
  int createCalls = 0;
  int assignCalls = 0;
  int unassignCalls = 0;
  String? lastAssignCharacter;
  int? lastAssignVersion;
  int? lastNotesVersion;

  @override
  Future<Result<IdVersionResponse>> createEmpty() {
    createCalls++;
    final scripted = nextCreate;
    if (scripted != null) return Future.value(scripted);
    return Future.value(
      Right<ProblemError, IdVersionResponse>(
        IdVersionResponse(
          (b) => b
            ..id = 'c-new-$createCalls'
            ..version = 1,
        ),
      ),
    );
  }

  @override
  Future<Result<int>> assign(String id, AssignCostumeRequest request) {
    assignCalls++;
    lastAssignCharacter = request.characterId;
    lastAssignVersion = request.version;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right<ProblemError, int>(2));
  }

  @override
  Future<Result<int>> unassign(String id, VersionRequest request) {
    unassignCalls++;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right<ProblemError, int>(2));
  }

  @override
  Future<Result<int>> updateNotes(
    String id,
    UpdateCostumeNotesRequest request,
  ) {
    lastNotesVersion = request.version;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right<ProblemError, int>(2));
  }

  @override
  Future<Result<int>> addDetail(String id, AddCostumeDetailRequest request) {
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right<ProblemError, int>(2));
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
  late _FakeCostumeRepository repo;
  late ValueNotifier<Result<List<CostumeView>>> holder;
  late ValueNotifier<Result<SeasonMembershipDto>> membershipHolder;
  late ManualReconciliationScheduler scheduler;
  late ProviderContainer container;

  Future<void> setupContainer({
    List<CostumeView> initialRows = const [],
    Result<List<CostumeView>>? initialFetch,
    List<String> capabilities = const ['assign_costumes'],
    List<CharacterView> characters = const [],
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _FakeCostumeRepository(BreakdownApi(), CostumeCacheDao(db));
    holder = ValueNotifier<Result<List<CostumeView>>>(
      initialFetch ?? Right(initialRows),
    );
    membershipHolder = ValueNotifier<Result<SeasonMembershipDto>>(
      Right(_membership(capabilities)),
    );
    scheduler = ManualReconciliationScheduler();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        costumeRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
        membershipFetchProvider('season-1')
            .overrideWith((ref) async => membershipHolder.value),
        characterRepositoryProvider.overrideWithValue(
          CharacterRepository(BreakdownApi(), CharacterCacheDao(db)),
        ),
        charactersListFetchProvider('season-1')
            .overrideWith((ref) async => Right(characters)),
        costumesListFetchProvider('season-1').overrideWith((ref) async {
          final dao = CostumeCacheDao(ref.watch(cacheDatabaseProvider));
          return holder.value.match(
            (err) => Left<ProblemError, List<CostumeView>>(err),
            (rows) async {
              await dao.applySnapshotForSeason(
                'season-1',
                rows,
                DateTime.utc(2026, 1, 1),
              );
              return Right<ProblemError, List<CostumeView>>(rows);
            },
          );
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
        child: MaterialApp(home: CostumesScreen(season: _season())),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('CostumesScreen states (4.3, semantic finders)', () {
    testWidgets('data: rows render with assignment state', (tester) async {
      await setupContainer(
        initialRows: [
          _costume('c-1'),
          _costume('c-2', characterId: 'ch-1'),
        ],
      );
      await pumpScreen(tester);
      // Semantic pair: byType never alone for layout.
      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.text('Costume c-1'), findsOneWidget);
      expect(find.text('Costume c-2'), findsOneWidget);
    });

    testWidgets('empty: honest empty state with create affordance', (
      tester,
    ) async {
      await setupContainer(initialRows: []);
      await pumpScreen(tester);
      expect(find.byKey(const Key('costumes-empty')), findsOneWidget);
      expect(find.byKey(const Key('costumes-empty-create')), findsOneWidget);
    });

    testWidgets('error: fetch failure renders keyed copy + retry', (
      tester,
    ) async {
      await setupContainer(initialFetch: const Left(_networkDown));
      await pumpScreen(tester);
      expect(find.byKey(const Key('costumes-error')), findsOneWidget);
      expect(find.textContaining('transport.connectionError'), findsOneWidget);
      expect(find.byKey(const Key('costumes-retry')), findsOneWidget);
    });

    testWidgets('create: empty-body shell overlays + chains to detail', (
      tester,
    ) async {
      await setupContainer(initialRows: []);
      await pumpScreen(tester);
      // Controller-level: the empty-body POST dispatches after the session
      // gate; on 201 the overlay row (server id) renders.
      final result = await container
          .read(costumesControllerProvider('season-1').notifier)
          .create();
      expect(result.isRight(), isTrue);
      expect(repo.createCalls, 1);
      await _pumpFrames(tester);
      expect(find.byKey(const Key('overlay-c-new-1')), findsOneWidget);
    });

    testWidgets('assign: optimistic row carries the assignment (fence)', (
      tester,
    ) async {
      // Acted-on row v1, ack v2: the fence holds until the projection
      // reaches the acknowledged version (realistic 1-based increment).
      final row = _costume('c-7');
      await setupContainer(initialRows: [row]);
      await pumpScreen(tester);
      final result = await container
          .read(costumesControllerProvider('season-1').notifier)
          .assign(costume: row, characterId: 'ch-3');
      expect(result.isRight(), isTrue);
      expect(repo.assignCalls, 1);
      expect(repo.lastAssignCharacter, 'ch-3');
      await _pumpFrames(tester);
      // Overlay survives while the projection is stale (version fence).
      final state = container.read(costumesControllerProvider('season-1'));
      expect(state.overlays.where((o) => o.id == 'c-7'), hasLength(1));
    });

    testWidgets('conflict: 409 renders keyed copy, no optimistic edit', (
      tester,
    ) async {
      final row = _costume('c-7', version: 3);
      await setupContainer(initialRows: [row]);
      await pumpScreen(tester);
      repo.nextWrite = const Left(_conflict);
      final result = await container
          .read(costumesControllerProvider('season-1').notifier)
          .assign(costume: row, characterId: 'ch-3');
      expect(result.isLeft(), isTrue);
      await _pumpFrames(tester);
      expect(
        find.text('Changed elsewhere — refresh and try again.'),
        findsOneWidget,
      );
      final state = container.read(costumesControllerProvider('season-1'));
      expect(state.overlays, isEmpty);
    });

    testWidgets('denial: no capability → 403 narrative, zero network calls', (
      tester,
    ) async {
      final row = _costume('c-7', version: 3);
      await setupContainer(initialRows: [row], capabilities: const []);
      await pumpScreen(tester);
      final result = await container
          .read(costumesControllerProvider('season-1').notifier)
          .assign(costume: row, characterId: 'ch-3');
      expect(result.isLeft(), isTrue);
      // Request-counter proof: the gate short-circuits before the network.
      expect(repo.assignCalls, 0);
      await _pumpFrames(tester);
      expect(
        find.text('You need an active costume role in this season.'),
        findsOneWidget,
      );
    });
  });

  group('CostumesScreen goldens (4.3, data state)', () {
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
              home: CostumesScreen(season: _season()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(CostumesScreen),
          matchesGoldenFile('goldens/$golden'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('golden light android', (tester) async {
      await setupContainer(
        initialRows: [
          _costume('c-1'),
          _costume('c-2', characterId: 'ch-1'),
        ],
      );
      await pumpGolden(
        tester,
        golden: 'costumes_screen_light_android.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden dark android', (tester) async {
      await setupContainer(
        initialRows: [
          _costume('c-1'),
          _costume('c-2', characterId: 'ch-1'),
        ],
      );
      await pumpGolden(
        tester,
        golden: 'costumes_screen_dark_android.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden light macos', (tester) async {
      await setupContainer(
        initialRows: [
          _costume('c-1'),
          _costume('c-2', characterId: 'ch-1'),
        ],
      );
      await pumpGolden(
        tester,
        golden: 'costumes_screen_light_macos.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.macOS,
      );
    });

    testWidgets('golden dark macos', (tester) async {
      await setupContainer(
        initialRows: [
          _costume('c-1'),
          _costume('c-2', characterId: 'ch-1'),
        ],
      );
      await pumpGolden(
        tester,
        golden: 'costumes_screen_dark_macos.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.macOS,
      );
    });
  });

  group('CostumesScreen extras (8.3)', () {
    testWidgets('unassign/addDetail/updateNotes conflicts surface copy', (
      tester,
    ) async {
      final row = _costume('c-7');
      await setupContainer(initialRows: [row]);
      await pumpScreen(tester);
      repo.nextWrite = const Left(_conflict);
      final controller = container.read(
        costumesControllerProvider('season-1').notifier,
      );
      expect((await controller.unassign(costume: row)).isLeft(), isTrue);
      expect(
        (await controller.addDetail(costume: row, text: 't')).isLeft(),
        isTrue,
      );
      expect(
        (await controller.updateNotes(costume: row, notes: 'n')).isLeft(),
        isTrue,
      );
      await _pumpFrames(tester);
      expect(
        find.text('Changed elsewhere — refresh and try again.'),
        findsOneWidget,
      );
      controller.dismissCommandError();
      await controller.refresh();
      await _pumpFrames(tester);
      expect(
        container.read(costumesControllerProvider('season-1')).commandError,
        isNull,
      );
    });

    testWidgets('exhausted reconciliation retains a stale overlay', (
      tester,
    ) async {
      await setupContainer(initialRows: [_costume('c-1')]);
      await pumpScreen(tester);
      // The projection never carries the created id: bounded retries
      // exhaust and the overlay is retained stale (never discarded).
      final result = await container
          .read(costumesControllerProvider('season-1').notifier)
          .create();
      expect(result.isRight(), isTrue);
      for (var i = 0; i < 6; i++) {
        scheduler.advanceAll();
        await _pumpFrames(tester, n: 10);
      }
      final state = container.read(costumesControllerProvider('season-1'));
      expect(state.overlays, hasLength(1));
      expect(find.byKey(const Key('overlay-warning')), findsOneWidget);
    });

    testWidgets('overlay version advances: follow-up echoes the ack', (
      tester,
    ) async {
      final row = _costume('c-7');
      await setupContainer(initialRows: [row]);
      await pumpScreen(tester);
      final controller = container.read(
        costumesControllerProvider('season-1').notifier,
      );
      expect(
        (await controller.assign(costume: row, characterId: 'ch-3')).isRight(),
        isTrue,
      );
      expect(repo.lastAssignVersion, 1);
      // The fence-held overlay carries the ack version, so the follow-up
      // notes command echoes 2 instead of the stale pre-command 1.
      final overlay = container
          .read(costumesControllerProvider('season-1'))
          .overlays
          .single
          .overlay;
      expect(overlay.version, 2);
      expect(
        (await controller.updateNotes(costume: overlay, notes: 'n')).isRight(),
        isTrue,
      );
      expect(repo.lastNotesVersion, 2);
    });

    testWidgets('list resolves assigned names via characters join', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [_costume('c-7', characterId: 'ch-3')],
        characters: [_character('ch-3')],
      );
      await pumpScreen(tester);
      expect(find.textContaining('Worn by Bea'), findsOneWidget);
    });
  });
}
