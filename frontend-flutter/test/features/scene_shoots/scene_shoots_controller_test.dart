// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark (pi)

// Controller tests (`flutter-shoot-day-execution` 2.1, closing the 1.1
// local-denial proof): execution commands dispatch with version echoes +
// optimistic overlays, 409 sets the keyed error without an overlay, and the
// continuity AUTHZ-GATE (link/list/unlink) denies locally with ZERO repo
// calls for a viewer while allowing for the continuity capability.

import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
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
import 'package:frontend_flutter/data/cache/scene_shoot_cache_dao.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/costume_repository.dart';
import 'package:frontend_flutter/data/photo_repository.dart';
import 'package:frontend_flutter/data/scene_shoot_repository.dart';
import 'package:frontend_flutter/features/costumes/costumes_controller.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
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
}) => SceneShootView(
  (b) => b
    ..id = id
    ..shootingDayId = 'day-1'
    ..sceneId = 'scene-1'
    ..plannedOrder = 'a0'
    ..status = status
    ..notes.replace(BuiltList<SerializedNote>())
    ..continuityPhotoIds.replace(BuiltList<String>())
    ..updatedAt = DateTime.utc(2026, 5, 1)
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
  int listCalls = 0;
  int unlinkCalls = 0;
  int? lastVersion;
  int? lastWrapVersion;
  int addNoteCalls = 0;
  int updateNoteCalls = 0;
  int removeNoteCalls = 0;
  String? lastNoteBody;
  String? lastNoteId;
  int? lastNoteVersion;

  @override
  Future<Result<int>> start(
    String dayId,
    String sceneId,
    String shootId,
    StartSceneShootRequest request,
  ) {
    startCalls++;
    lastVersion = request.version;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right<ProblemError, int>(2));
  }

  @override
  Future<Result<int>> finish(
    String dayId,
    String sceneId,
    String shootId,
    FinishSceneShootRequest request,
  ) {
    finishCalls++;
    lastVersion = request.version;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right<ProblemError, int>(2));
  }

  @override
  Future<Result<int>> skip(
    String dayId,
    String sceneId,
    String shootId,
    SkipSceneShootRequest request,
  ) {
    skipCalls++;
    lastVersion = request.version;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right<ProblemError, int>(2));
  }

  @override
  Future<Result<int>> wrap(String dayId, WrapShootingDayRequest request) {
    wrapCalls++;
    lastWrapVersion = request.version;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right<ProblemError, int>(6));
  }

  @override
  Future<Result<int>> linkContinuityPhoto(
    String dayId,
    String sceneId,
    String shootId,
    LinkContinuityPhotoRequest request,
  ) {
    linkCalls++;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right<ProblemError, int>(4));
  }

  @override
  Future<Result<List<String>>> listContinuityPhotos(
    String dayId,
    String sceneId,
    String shootId,
  ) {
    listCalls++;
    return Future.value(const Right<ProblemError, List<String>>(['ph-1']));
  }

  @override
  Future<Result<int>> addNote(
    String dayId,
    String sceneId,
    String shootId,
    AddNoteRequest request,
  ) {
    addNoteCalls++;
    lastNoteBody = request.body;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right<ProblemError, int>(3));
  }

  @override
  Future<Result<int>> updateNote(
    String dayId,
    String sceneId,
    String shootId,
    String noteId,
    UpdateNoteRequest request,
  ) {
    updateNoteCalls++;
    lastNoteId = noteId;
    lastNoteBody = request.body;
    lastNoteVersion = request.version;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right<ProblemError, int>(4));
  }

  @override
  Future<Result<int>> removeNote(
    String dayId,
    String sceneId,
    String shootId,
    String noteId,
    VersionRequest request,
  ) {
    removeNoteCalls++;
    lastNoteId = noteId;
    lastNoteVersion = request.version;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right<ProblemError, int>(5));
  }

  @override
  Future<Result<int>> unlinkContinuityPhoto(
    String dayId,
    String sceneId,
    String shootId,
    String photoId,
    int version,
  ) {
    unlinkCalls++;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right<ProblemError, int>(5));
  }
}

class _FakePhotoRepository extends PhotoRepository {
  _FakePhotoRepository(super.api);

  int uploadCalls = 0;
  String? lastCostumeId;
  String? lastContentType;

  @override
  Future<Result<PhotoView>> upload(
    String costumeId,
    Uint8List bytes,
    String contentType, {
    ProgressCallback? onSendProgress,
  }) {
    uploadCalls++;
    lastCostumeId = costumeId;
    lastContentType = contentType;
    return Future.value(
      Right<ProblemError, PhotoView>(
        PhotoView(
          (b) => b
            ..id = 'ph-new'
            ..binding.replace(
              PhotoBinding(
                (pb) => pb
                  ..oneOf = OneOf.fromValue1(
                    value: PhotoBindingOneOf(
                      (o) => o
                        ..costume.replace(
                          PhotoBindingOneOfCostume(
                            (c) => c..costumeId = costumeId,
                          ),
                        ),
                    ),
                  ),
              ),
            )
            ..contentType = contentType
            ..sizeBytes = bytes.length
            ..variants.replace(BuiltList<PhotoVariantView>())
            ..version = 1,
        ),
      ),
    );
  }
}

void main() {
  late CacheDatabase db;
  late _FakeSceneShootRepository repo;
  late ValueNotifier<Result<List<SceneShootView>>> holder;
  late ValueNotifier<Result<SeasonMembershipDto>> membershipHolder;
  late ManualReconciliationScheduler scheduler;
  late _FakePhotoRepository photoRepo;
  late ProviderContainer container;

  Future<void> setupContainer({
    List<SceneShootView> initialRows = const [],
    List<String> capabilities = const ['upload_continuity_photos'],
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _FakeSceneShootRepository(BreakdownApi(), SceneShootCacheDao(db));
    photoRepo = _FakePhotoRepository(BreakdownApi());
    holder = ValueNotifier<Result<List<SceneShootView>>>(Right(initialRows));
    membershipHolder = ValueNotifier<Result<SeasonMembershipDto>>(
      Right(_membership(capabilities)),
    );
    scheduler = ManualReconciliationScheduler();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        sceneShootRepositoryProvider.overrideWithValue(repo),
        costumePhotoRepositoryProvider.overrideWithValue(photoRepo),
        // The board derives finality from the live day projection;
        // widget tests run with an empty day projection (entry DTO wins).
        shootingDaysViewProvider(
          'episode-1',
        ).overrideWithValue(const ShootingDaysView(rows: [], isStale: false)),
        costumeRepositoryProvider.overrideWithValue(
          CostumeRepository(BreakdownApi(), CostumeCacheDao(db)),
        ),
        // The continuity strip joins against the season costumes; the
        // board smoke tests run with an empty costume projection (strip
        // renders linked ids as orphans, capture stays disabled).
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

  SceneShootsController controller() =>
      container.read(sceneShootsControllerProvider(_scope).notifier);

  /// Drains the command-triggered reconciliation pass deterministically
  /// (no wall-clock): publishes [ackedRows] as the fresh projection, then
  /// repeatedly advances the manual scheduler and flushes the event loop
  /// until the version fence clears every overlay (bounded loop — never
  /// joins a parked pass future, so no hang). Afterwards no DB access is
  /// in flight, so teardown cannot race the closed database.
  Future<void> settleReconcile(List<SceneShootView> ackedRows) async {
    holder.value = Right(ackedRows);
    for (var i = 0; i < 10; i++) {
      scheduler.advanceAll();
      for (var j = 0; j < 50; j++) {
        await Future<void>.delayed(Duration.zero);
      }
      if (container.read(sceneShootsOverlaysProvider(_scope)).isEmpty) break;
    }
  }

  group('SceneShootsController execution', () {
    test('start echoes the version + optimistic overlay (fence)', () async {
      await setupContainer(initialRows: [_shoot('ssh-1')]);
      final res = await controller().start(shoot: _shoot('ssh-1'));
      expect(res.isRight(), isTrue);
      expect(repo.startCalls, 1);
      expect(repo.lastVersion, 1);
      final overlays = container.read(sceneShootsOverlaysProvider(_scope));
      expect(overlays.map((o) => o.id), ['ssh-1']);
      expect(overlays.single.overlay.status, SceneShootStatus.inProgress);
      expect(overlays.single.acknowledgedVersion, 2);
      // The ack'd projection clears the overlay through the version fence.
      await settleReconcile([
        _shoot('ssh-1', status: SceneShootStatus.inProgress, version: 2),
      ]);
      expect(container.read(sceneShootsOverlaysProvider(_scope)), isEmpty);
    });

    test(
      'finish/skip dispatch with echoes; wrap echoes the day version',
      () async {
        await setupContainer(
          initialRows: [
            _shoot('ssh-1', status: SceneShootStatus.inProgress),
            _shoot('ssh-2'),
          ],
        );
        expect(
          (await controller().finish(
            shoot: _shoot('ssh-1', status: SceneShootStatus.inProgress),
          )).isRight(),
          isTrue,
        );
        expect(
          (await controller().skip(shoot: _shoot('ssh-2'))).isRight(),
          isTrue,
        );
        expect(repo.finishCalls, 1);
        expect(repo.skipCalls, 1);
        expect((await controller().wrap(dayVersion: 5)).isRight(), isTrue);
        expect(repo.wrapCalls, 1);
        expect(repo.lastWrapVersion, 5);
        // Both execution overlays clear once the ack'd rows project.
        await settleReconcile([
          _shoot('ssh-1', status: SceneShootStatus.shot, version: 2),
          _shoot('ssh-2', status: SceneShootStatus.skipped, version: 2),
        ]);
        expect(container.read(sceneShootsOverlaysProvider(_scope)), isEmpty);
      },
    );

    test('409 sets the keyed error and adds no overlay', () async {
      await setupContainer(initialRows: [_shoot('ssh-1')]);
      repo.nextWrite = const Left(
        ProblemError(code: 'scene_shoot.version_conflict'),
      );
      final res = await controller().finish(shoot: _shoot('ssh-1'));
      expect(res.isLeft(), isTrue);
      expect(
        container.read(sceneShootsCommandErrorProvider(_scope))?.code,
        'scene_shoot.version_conflict',
      );
      expect(container.read(sceneShootsOverlaysProvider(_scope)), isEmpty);
      expect(
        sceneShootErrorCopy(const ProblemError(code: 'concurrency.conflict')),
        contains('Changed elsewhere'),
      );
    });
  });

  group('SceneShootsController notes (2.2)', () {
    SceneShootView notedShoot() => SceneShootView(
      (b) => b
        ..id = 'ssh-1'
        ..shootingDayId = 'day-1'
        ..sceneId = 'scene-1'
        ..plannedOrder = 'a0'
        ..status = SceneShootStatus.planned
        ..notes.replace(
          BuiltList<SerializedNote>([
            SerializedNote(
              (n) => n
                ..id = 'n-1'
                ..body = 'first',
            ),
          ]),
        )
        ..continuityPhotoIds.replace(BuiltList<String>())
        ..updatedAt = DateTime.utc(2026, 5, 1)
        ..version = 3,
    );

    test(
      'add dispatches the body; optimistic placeholder rides a pending id',
      () async {
        await setupContainer(initialRows: [notedShoot()]);
        final res = await controller().addNote(
          shoot: notedShoot(),
          body: 'second',
        );
        expect(res.isRight(), isTrue);
        expect(repo.addNoteCalls, 1);
        expect(repo.lastNoteBody, 'second');
        final overlays = container.read(sceneShootsOverlaysProvider(_scope));
        expect(overlays.single.overlay.notes.map((n) => n.body), [
          'first',
          'second',
        ]);
        await settleReconcile([
          SceneShootView(
            (b) => b
              ..id = 'ssh-1'
              ..shootingDayId = 'day-1'
              ..sceneId = 'scene-1'
              ..plannedOrder = 'a0'
              ..status = SceneShootStatus.planned
              ..notes.replace(
                BuiltList<SerializedNote>([
                  SerializedNote(
                    (n) => n
                      ..id = 'n-1'
                      ..body = 'first',
                  ),
                  SerializedNote(
                    (n) => n
                      ..id = 'n-2'
                      ..body = 'second',
                  ),
                ]),
              )
              ..continuityPhotoIds.replace(BuiltList<String>())
              ..updatedAt = DateTime.utc(2026, 5, 1)
              ..version = 4,
          ),
        ]);
        expect(container.read(sceneShootsOverlaysProvider(_scope)), isEmpty);
      },
    );

    test('update echoes note id + version; remove echoes both', () async {
      await setupContainer(initialRows: [notedShoot()]);
      expect(
        (await controller().updateNote(
          shoot: notedShoot(),
          noteId: 'n-1',
          body: 'edited',
        )).isRight(),
        isTrue,
      );
      expect(repo.updateNoteCalls, 1);
      expect(repo.lastNoteId, 'n-1');
      expect(repo.lastNoteBody, 'edited');
      expect(repo.lastNoteVersion, 3);
      expect(
        container
            .read(sceneShootsOverlaysProvider(_scope))
            .single
            .overlay
            .notes
            .single
            .body,
        'edited',
      );
      expect(
        (await controller().removeNote(
          shoot: notedShoot(),
          noteId: 'n-1',
        )).isRight(),
        isTrue,
      );
      expect(repo.removeNoteCalls, 1);
      expect(repo.lastNoteId, 'n-1');
      expect(repo.lastNoteVersion, 3);
      await settleReconcile([notedShoot()]);
    });

    test('note 409 sets the keyed error and adds no overlay', () async {
      await setupContainer(initialRows: [notedShoot()]);
      repo.nextWrite = const Left(
        ProblemError(code: 'scene_shoot.version_conflict'),
      );
      final res = await controller().addNote(
        shoot: notedShoot(),
        body: 'second',
      );
      expect(res.isLeft(), isTrue);
      expect(repo.addNoteCalls, 1);
      expect(container.read(sceneShootsOverlaysProvider(_scope)), isEmpty);
      expect(
        container.read(sceneShootsCommandErrorProvider(_scope))?.code,
        'scene_shoot.version_conflict',
      );
    });
  });

  group('SceneShootsController continuity upload (2.3)', () {
    test('viewer denial: 403 narrative, zero upload calls', () async {
      await setupContainer(
        initialRows: [_shoot('ssh-1')],
        capabilities: const [],
      );
      final res = await controller().uploadContinuityBytes(
        costumeId: 'c-1',
        bytes: Uint8List.fromList([1, 2, 3]),
        contentType: 'image/jpeg',
      );
      expect(res.isLeft(), isTrue);
      res.fold((l) {
        expect(l.code, 'photo.forbidden');
        expect(l.status, 403);
      }, (_) => fail('expected Left(photo.forbidden)'));
      expect(photoRepo.uploadCalls, 0);
    });

    test('holder upload reaches the costume endpoint, then links', () async {
      await setupContainer(initialRows: [_shoot('ssh-1')]);
      final upload = await controller().uploadContinuityBytes(
        costumeId: 'c-1',
        bytes: Uint8List.fromList([1, 2, 3]),
        contentType: 'image/jpeg',
      );
      expect(upload.isRight(), isTrue);
      expect(photoRepo.uploadCalls, 1);
      expect(photoRepo.lastCostumeId, 'c-1');
      expect(photoRepo.lastContentType, 'image/jpeg');
      final photoId = upload.fold((_) => '', (view) => view.id);
      expect(photoId, 'ph-new');
      expect(
        (await controller().linkContinuityPhoto(
          shoot: _shoot('ssh-1'),
          photoId: photoId,
        )).isRight(),
        isTrue,
      );
      expect(repo.linkCalls, 1);
      await controller().refresh();
    });
  });

  group('Continuity AUTHZ-GATE (1.1 zero-call proof)', () {
    test('viewer denial: 403 narrative, zero link/list/unlink calls', () async {
      await setupContainer(
        initialRows: [_shoot('ssh-1')],
        capabilities: const [],
      );
      final c = controller();
      final link = await c.linkContinuityPhoto(
        shoot: _shoot('ssh-1'),
        photoId: 'ph-1',
      );
      final list = await c.listContinuityPhotos(shoot: _shoot('ssh-1'));
      final unlink = await c.unlinkContinuityPhoto(
        shoot: _shoot('ssh-1'),
        photoId: 'ph-1',
      );
      for (final r in [link, list, unlink]) {
        expect(r.isLeft(), isTrue);
        r.fold((l) {
          expect(l.code, 'photo.forbidden');
          expect(l.status, 403);
        }, (_) => fail('expected Left(photo.forbidden)'));
      }
      // No network request leaves the device for any of the three calls.
      expect(repo.linkCalls, 0);
      expect(repo.listCalls, 0);
      expect(repo.unlinkCalls, 0);
      expect(
        container.read(sceneShootsCommandErrorProvider(_scope))?.code,
        'photo.forbidden',
      );
    });

    test('capability holder: link/list/unlink reach the repo', () async {
      await setupContainer(initialRows: [_shoot('ssh-1')]);
      final c = controller();
      expect(
        (await c.linkContinuityPhoto(
          shoot: _shoot('ssh-1'),
          photoId: 'ph-1',
        )).isRight(),
        isTrue,
      );
      expect(
        (await c.listContinuityPhotos(shoot: _shoot('ssh-1'))).isRight(),
        isTrue,
      );
      expect(
        (await c.unlinkContinuityPhoto(
          shoot: _shoot('ssh-1'),
          photoId: 'ph-1',
        )).isRight(),
        isTrue,
      );
      expect(repo.linkCalls, 1);
      expect(repo.listCalls, 1);
      expect(repo.unlinkCalls, 1);
      // Join the refresh-triggered pass so no refetch outlives teardown.
      await controller().refresh();
    });
  });

  group('SceneShootsScreen smoke (2.1 board renders)', () {
    Future<void> pumpScreen(
      WidgetTester tester, {
      required ShootingDayView day,
    }) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: SceneShootsScreen(
              day: day,
              scene: _scene(),
              seasonId: 'season-1',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('open day: cards render with Ist strip + actions', (
      tester,
    ) async {
      await setupContainer(
        initialRows: [
          _shoot('ssh-1'),
          _shoot('ssh-2', status: SceneShootStatus.inProgress),
        ],
      );
      await pumpScreen(tester, day: _day());
      expect(find.byKey(const Key('scene-shoots-list')), findsOneWidget);
      expect(find.byKey(const Key('scene-shoot-card-ssh-1')), findsOneWidget);
      expect(find.byKey(const Key('scene-shoot-card-ssh-2')), findsOneWidget);
      expect(find.text('Planned'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      // Planned offers start+skip; in-progress offers finish+skip.
      expect(find.byKey(const Key('scene-shoot-start-ssh-1')), findsOneWidget);
      expect(find.byKey(const Key('scene-shoot-finish-ssh-2')), findsOneWidget);
      expect(find.byKey(const Key('scene-shoots-wrap')), findsOneWidget);
      // Continuity strip renders against the (empty) costume projection:
      // no linked ids, capture disabled until a costume is picked.
      expect(find.byKey(const Key('continuity-strip-ssh-1')), findsOneWidget);
      expect(
        find.byKey(const Key('continuity-costume-hint-ssh-1')),
        findsOneWidget,
      );
    });

    testWidgets('wrapped day: read-only, finality banner, no actions', (
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
      expect(find.byKey(const Key('scene-shoot-card-ssh-1')), findsOneWidget);
      expect(find.byKey(const Key('scene-shoot-start-ssh-1')), findsNothing);
      expect(find.byKey(const Key('scene-shoot-finish-ssh-1')), findsNothing);
      expect(find.byKey(const Key('scene-shoot-skip-ssh-1')), findsNothing);
      expect(find.byKey(const Key('scene-shoots-wrap')), findsNothing);
    });

    testWidgets('notes: expand shows notes and add affordance', (tester) async {
      await setupContainer(initialRows: [_shoot('ssh-1')]);
      await pumpScreen(tester, day: _day());
      await tester.tap(find.byKey(const Key('scene-shoot-notes-ssh-1')));
      // Fixed pumps only: 5x100ms covers the 200ms expansion with margin.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final addButton = find.byKey(const Key('scene-shoot-note-add-ssh-1'));
      expect(addButton, findsOneWidget);
      // The button exists in the tree even while collapsed (zero height)
      // — it laid out only once the tile expanded.
      expect(tester.getSize(addButton).height, greaterThan(0));
      // The dialog + save dispatch path is covered at controller level
      // (notes 2.2 group); full dialog flows land with the 2.4 widget set.
    });
  });
}
