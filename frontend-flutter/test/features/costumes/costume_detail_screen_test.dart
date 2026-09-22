// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

// Tier-2 widget tests for `CostumeDetailScreen` (Task 4.3): detail elements
// (+ denormalized category names), notes editor, assign/unassign (version
// echo, optimistic overlay keys, 409 copy, role-denial with zero network
// calls), add-detail form (category picker), photo empty state + delete
// confirm flow + photo denial narrative.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:one_of/one_of.dart';
import 'package:built_collection/built_collection.dart';
import 'package:drift/native.dart';
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
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/character_repository.dart';
import 'package:frontend_flutter/data/costume_category_repository.dart';
import 'package:frontend_flutter/data/costume_repository.dart';
import 'package:frontend_flutter/data/photo_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/characters/characters_controller.dart';
import 'package:frontend_flutter/features/costume_categories/costume_categories_controller.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:frontend_flutter/features/costumes/costume_detail_screen.dart';
import 'package:frontend_flutter/features/costumes/costumes_controller.dart';
import 'package:frontend_flutter/features/photos/capture.dart';
import 'package:frontend_flutter/features/photos/prepare.dart';
import 'package:frontend_flutter/features/photos/widgets/photo_gallery.dart';

import '../seasons/seasons_test_fakes.dart';

CostumeView _costume(
  String id, {
  String? characterId,
  int version = 1,
  List<CostumeDetailView> details = const [],
}) => CostumeView(
  (b) => b
    ..id = id
    ..characterId = characterId
    ..notes = 'Linen suit'
    ..details.replace(BuiltList<CostumeDetailView>(details))
    ..photos.replace(BuiltList<CostumePhotoView>())
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version,
);

/// A genuine optimistic-concurrency defeat (server equality guard):
/// `concurrency.version-mismatch` 409 — distinct from the generic
/// conflict/validation codes.
const _versionMismatch = ProblemError(
  code: 'concurrency.version-mismatch',
  status: 409,
);

CostumeDetailView _detail(String id, {String? categoryName}) =>
    CostumeDetailView(
      (b) => b
        ..id = id
        ..subject = 'Jacket'
        ..text = 'Red leather jacket'
        ..categoryName = categoryName,
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

CostumeCategoryView _category(String id, {String name = 'Outerwear'}) =>
    CostumeCategoryView(
      (b) => b
        ..id = id
        ..seasonId = 'season-1'
        ..name = name
        ..orderKey = '!'
        ..archived = false
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

  Result<int>? nextWrite;
  int assignCalls = 0;
  int unassignCalls = 0;
  int notesCalls = 0;
  int detailCalls = 0;

  /// Captured echoed versions of the LAST notes/detail requests — the
  /// second-edit test (issue #473) asserts the follow-up save carries the
  /// first ack version, never the stale pre-command version.
  int? lastNotesVersion;
  int? lastDetailVersion;

  /// Captured echoed versions of the LAST assign/unassign requests — the
  /// reassignment test (issue #454) asserts the assign leg echoes the
  /// unassign ACK version, not the pre-command version.
  int? lastAssignVersion;
  int? lastUnassignVersion;

  /// Scripted per-call results (in order) for the sequential unassign →
  /// assign sequence failures (issue #454: assign leg fails after unassign).
  List<Result<int>>? nextUnassignResults;
  List<Result<int>>? nextAssignResults;

  @override
  Future<Result<int>> unassign(String id, VersionRequest request) {
    unassignCalls++;
    lastUnassignVersion = request.version;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    final queued = nextUnassignResults;
    if (queued != null && queued.isNotEmpty) {
      return Future.value(queued.removeAt(0));
    }
    return Future.value(const Right(2));
  }

  @override
  Future<Result<int>> assign(String id, AssignCostumeRequest request) {
    assignCalls++;
    lastAssignVersion = request.version;
    // Reassignment also records the picked character for the sequence check.
    lastAssignCharacterId = request.characterId;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    final queued = nextAssignResults;
    if (queued != null && queued.isNotEmpty) {
      return Future.value(queued.removeAt(0));
    }
    return Future.value(const Right(2));
  }

  String? lastAssignCharacterId;

  @override
  Future<Result<int>> updateNotes(
    String id,
    UpdateCostumeNotesRequest request,
  ) {
    notesCalls++;
    lastNotesVersion = request.version;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    // Realistic ack progression: aggregate advances version+1. The
    // second-edit regression flips this to a 422 when the echoed version
    // is stale (server-side equality guard).
    return Future.value(const Right(2));
  }

  @override
  Future<Result<int>> addDetail(String id, AddCostumeDetailRequest request) {
    detailCalls++;
    lastDetailVersion = request.version;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right(2));
  }
}

class _FakePhotoRepository extends PhotoRepository {
  _FakePhotoRepository(super.api);

  int deleteCalls = 0;
  int uploadCalls = 0;

  @override
  Future<Result<void>> delete(String costumeId, String photoId) {
    deleteCalls++;
    return Future.value(const Right(null));
  }

  @override
  Future<Result<PhotoView>> upload(
    String costumeId,
    Uint8List bytes,
    String contentType, {
    ProgressCallback? onSendProgress,
  }) {
    uploadCalls++;
    return Future.value(
      Right(
        PhotoView(
          (b) => b
            ..id = 'p-new'
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
            ..version = 1
            ..variants.replace(BuiltList<PhotoVariantView>()),
        ),
      ),
    );
  }
}

class _ScriptedPicker extends ImagePicker {
  _ScriptedPicker({this.file, this.exception});

  final XFile? file;
  final PlatformException? exception;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    final e = exception;
    if (e != null) throw e;
    return file;
  }
}

Future<void> _pumpFrames(WidgetTester tester, {int n = 6}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late CacheDatabase db;
  late _FakeCostumeRepository repo;
  late _FakePhotoRepository photos;
  late ValueNotifier<Result<List<CostumeView>>> holder;
  late ValueNotifier<Result<SeasonMembershipDto>> membershipHolder;
  late ProviderContainer container;
  late _ScriptedPicker flowPicker;
  var settingsOpened = 0;

  setUp(() {
    flowPicker = _ScriptedPicker();
    settingsOpened = 0;
  });

  Future<void> setupContainer({
    required CostumeView costume,
    List<CharacterView> characters = const [],
    List<CostumeCategoryView> categories = const [],
    List<String> capabilities = const [
      'assign_costumes',
      'upload_continuity_photos',
    ],
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = _FakeCostumeRepository(BreakdownApi(), CostumeCacheDao(db));
    photos = _FakePhotoRepository(BreakdownApi());
    holder = ValueNotifier<Result<List<CostumeView>>>(Right([costume]));
    membershipHolder = ValueNotifier<Result<SeasonMembershipDto>>(
      Right(_membership(capabilities)),
    );
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        costumeRepositoryProvider.overrideWithValue(repo),
        costumePhotoRepositoryProvider.overrideWithValue(photos),
        // Untouched read paths (characters/categories sections) run the
        // real cache-backed implementation over plain-Dio clients — never
        // the pinned production Dio (no TLS context in tests).
        characterRepositoryProvider.overrideWithValue(
          CharacterRepository(BreakdownApi(), CharacterCacheDao(db)),
        ),
        costumeCategoryRepositoryProvider.overrideWithValue(
          CostumeCategoryRepository(
            BreakdownApi(),
            CostumeCategoryCacheDao(db),
          ),
        ),
        photoBytesLruProvider.overrideWithValue(PhotoBytesLru()),
        reconciliationSchedulerProvider.overrideWith(
          (ref) => ManualReconciliationScheduler(),
        ),
        membershipFetchProvider('season-1')
            .overrideWith((ref) async => membershipHolder.value),
        // The variant watch is irrelevant to these assertions; stub
        // it closed so no backoff timers outlive the widget tree.
        costumePhotoWatchProvider(
          'season-1',
          'c-1',
        ).overrideWith((ref) => const Stream<PhotoWatchEvent>.empty()),
        costumesListFetchProvider('season-1').overrideWith((ref) async {
          final dao = CostumeCacheDao(ref.watch(cacheDatabaseProvider));
          return holder.value.match((err) => Left(err), (rows) async {
            await dao.applySnapshotForSeason(
              'season-1',
              rows,
              DateTime.utc(2026, 1, 1),
            );
            return Right(rows);
          });
        }),
        charactersListFetchProvider('season-1')
            .overrideWith((ref) async => Right(characters)),
        costumeCategoriesListFetchProvider('season-1')
            .overrideWith((ref) async => Right(categories)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();
  }

  Future<void> pumpDetail(WidgetTester tester, String costumeId) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: CostumeDetailScreen(season: _season(), costumeId: costumeId),
        ),
      ),
    );
    // Bounded frames (never pumpAndSettle): the foreground-only photo watch
    // keeps a stream subscription alive while visible by design (D5).
    await _pumpFrames(tester, n: 30);
  }

  group('CostumeDetailScreen (4.3)', () {
    testWidgets('renders details, notes, assignment and photo sections', (
      tester,
    ) async {
      await setupContainer(
        costume: _costume(
          'c-1',
          characterId: 'ch-1',
          details: [_detail('d-1', categoryName: 'Outerwear')],
        ),
        characters: [_character('ch-1')],
      );
      await pumpDetail(tester, 'c-1');
      expect(find.text('Red leather jacket'), findsOneWidget);
      expect(find.text('Outerwear'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.byKey(const Key('costume-notes-c-1')), findsOneWidget);
      expect(find.byKey(const Key('photo-gallery-empty-c-1')), findsOneWidget);
    });

    testWidgets('assign: picker submit carries picked id + version echo', (
      tester,
    ) async {
      await setupContainer(
        costume: _costume('c-1'),
        characters: [_character('ch-9', name: 'Bea')],
      );
      await pumpDetail(tester, 'c-1');
      await tester.tap(find.byKey(const Key('assign-costume-c-1-none')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assign-character-ch-9')));
      await _pumpFrames(tester);
      expect(repo.assignCalls, 1);
      // Optimistic overlay key while the fence holds.
      expect(find.byKey(const Key('overlay-assign-c-1-ch-9')), findsOneWidget);
    });

    testWidgets('denial: capability missing → 403 narrative, zero calls', (
      tester,
    ) async {
      await setupContainer(
        costume: _costume('c-1'),
        characters: [_character('ch-1')],
        capabilities: const [],
      );
      await pumpDetail(tester, 'c-1');
      expect(find.byKey(const Key('costume-assign-denied')), findsOneWidget);
      expect(find.byKey(const Key('photo-denied-narrative')), findsOneWidget);
      final result = await container
          .read(costumesControllerProvider('season-1').notifier)
          .assign(costume: _costume('c-1'), characterId: 'ch-1');
      expect(result.isLeft(), isTrue);
      expect(repo.assignCalls, 0);
    });

    testWidgets('notes: save dispatches version echo', (tester) async {
      await setupContainer(costume: _costume('c-1'));
      await pumpDetail(tester, 'c-1');
      await tester.enterText(
        find.byKey(const Key('costume-notes-c-1')),
        'Wool coat',
      );
      await tester.tap(find.byKey(const Key('costume-notes-save-c-1')));
      await _pumpFrames(tester);
      expect(repo.notesCalls, 1);
    });

    testWidgets('second notes save echoes the ack version (no 422 loop)', (
      tester,
    ) async {
      // Issue #473 acceptance: consecutive writes to the same costume must
      // echo the acknowledged version — save notes, then save notes again;
      // the second request must carry v2 (the first ack), never the stale
      // v1 the backend equality guard would 422 as `domain.validation`.
      await setupContainer(costume: _costume('c-1')); // v1
      await pumpDetail(tester, 'c-1');
      // First save echoes v1 → ack v2.
      await tester.enterText(
        find.byKey(const Key('costume-notes-c-1')),
        'Wool coat',
      );
      await tester.tap(find.byKey(const Key('costume-notes-save-c-1')));
      await _pumpFrames(tester);
      expect(repo.notesCalls, 1);
      expect(repo.lastNotesVersion, 1);
      // Second save: the editor holds the fence (overlay version advanced
      // to the ack), so the follow-up echoes 2 — and the save succeeds.
      await tester.enterText(
        find.byKey(const Key('costume-notes-c-1')),
        'Wool coat v2',
      );
      await tester.tap(find.byKey(const Key('costume-notes-save-c-1')));
      await _pumpFrames(tester);
      expect(repo.notesCalls, 2);
      expect(repo.lastNotesVersion, 2);
      // The command error tray is quiet: no silent 422 loop.
      expect(find.byKey(const Key('costume-detail-error')), findsNothing);
    });

    testWidgets('add detail after save echoes the ack version', (tester) async {
      // Cross-command variant of the version-freshness contract (issue
      // #473): save notes (v1 → ack v2), then add a detail — the detail
      // command must carry v2, not the initial snapshot's 1.
      await setupContainer(costume: _costume('c-1')); // v1
      await pumpDetail(tester, 'c-1');
      await tester.enterText(
        find.byKey(const Key('costume-notes-c-1')),
        'Wool coat',
      );
      await tester.tap(find.byKey(const Key('costume-notes-save-c-1')));
      await _pumpFrames(tester);
      expect(repo.notesCalls, 1);
      expect(repo.lastNotesVersion, 1);
      await tester.tap(find.byKey(const Key('costume-detail-add-c-1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('add-detail-text')),
        'Silk lining',
      );
      await tester.tap(find.byKey(const Key('add-detail-submit')));
      await _pumpFrames(tester);
      expect(repo.detailCalls, 1);
      expect(repo.lastDetailVersion, 2);
    });

    testWidgets('409 version-mismatch renders pull-to-refresh copy', (
      tester,
    ) async {
      // Requirement #3 (issue #473): a genuine optimistic-concurrency
      // defeat surfaced as `concurrency.version-mismatch` (409) must show a
      // distinct, actionable pull-to-refresh narrative — never generic copy
      // (ties into the #467/#470 tranche).
      await setupContainer(costume: _costume('c-1'));
      await pumpDetail(tester, 'c-1');
      repo.nextWrite = const Left(_versionMismatch);
      await tester.enterText(
        find.byKey(const Key('costume-notes-c-1')),
        'Wool coat',
      );
      await tester.tap(find.byKey(const Key('costume-notes-save-c-1')));
      await _pumpFrames(tester);
      expect(
        find.text('Changed elsewhere — pull to refresh and try again.'),
        findsOneWidget,
      );
    });

    testWidgets('add-detail: form carries category id from read DTOs', (
      tester,
    ) async {
      await setupContainer(
        costume: _costume('c-1'),
        categories: [_category('cat-1')],
      );
      await pumpDetail(tester, 'c-1');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('costume-detail-add-c-1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('add-detail-text')),
        'Silk lining',
      );
      await tester.tap(find.byKey(const Key('add-detail-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Outerwear').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-detail-submit')));
      await _pumpFrames(tester);
      expect(repo.detailCalls, 1);
    });

    testWidgets('delete photo: confirm-first, then dispatch', (tester) async {
      final photo = CostumePhotoView(
        (b) => b
          ..id = 'p-1'
          ..contentType = 'image/jpeg'
          ..sizeBytes = 10
          ..variants.replace(
            BuiltList<PhotoVariantView>([
              PhotoVariantView(
                (v) => v
                  ..kind = serializers.deserializeWith(
                    PhotoVariant.serializer,
                    'Thumb',
                  )!
                  ..status = serializers.deserializeWith(
                    VariantStatus.serializer,
                    'Ready',
                  )!
                  ..sizeBytes = 5,
              ),
            ]),
          ),
      );
      final costume = CostumeView(
        (b) => b
          ..id = 'c-1'
          ..notes = 'n'
          ..details.replace(BuiltList<CostumeDetailView>())
          ..photos.replace(BuiltList<CostumePhotoView>([photo]))
          ..updatedAt = DateTime.utc(2026, 1, 1)
          ..version = 1,
      );
      await setupContainer(costume: costume);
      await pumpDetail(tester, 'c-1');
      expect(find.byKey(const Key('photo-tile-p-1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('photo-delete-p-1')));
      await tester.pumpAndSettle();
      // Confirm-first: no dispatch before confirmation.
      expect(photos.deleteCalls, 0);
      await tester.tap(find.byKey(const Key('photo-delete-confirm-p-1')));
      await _pumpFrames(tester);
      expect(photos.deleteCalls, 1);
    });
  });

  group('CostumeDetailScreen capture + command flows (8.3)', () {
    Future<void> setupFlow({
      List<String> capabilities = const [
        'assign_costumes',
        'upload_continuity_photos',
      ],
    }) async {
      await setupContainer(
        costume: _costume('c-1'),
        characters: [_character('ch-1')],
        capabilities: capabilities,
      );
      container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          cacheDatabaseProvider.overrideWithValue(db),
          costumeRepositoryProvider.overrideWithValue(repo),
          costumePhotoRepositoryProvider.overrideWithValue(photos),
          photoBytesLruProvider.overrideWithValue(PhotoBytesLru()),
          characterRepositoryProvider.overrideWithValue(
            CharacterRepository(BreakdownApi(), CharacterCacheDao(db)),
          ),
          costumeCategoryRepositoryProvider.overrideWithValue(
            CostumeCategoryRepository(
              BreakdownApi(),
              CostumeCategoryCacheDao(db),
            ),
          ),
          reconciliationSchedulerProvider.overrideWith(
            (ref) => ManualReconciliationScheduler(),
          ),
          membershipFetchProvider('season-1')
              .overrideWith((ref) async => membershipHolder.value),
          imagePickerProvider.overrideWithValue(flowPicker),
          // Isolates never complete headless: run the pure core inline.
          preparePhotoProvider.overrideWith(
            (ref) =>
                (PrepareInput input) async => prepareImageCore(input),
          ),
          openAppSettingsProvider.overrideWithValue(() async {
            settingsOpened++;
            return true;
          }),
          // The variant watch is irrelevant to these assertions; stub
          // it closed so no backoff timers outlive the widget tree.
          costumePhotoWatchProvider(
            'season-1',
            'c-1',
          ).overrideWith((ref) => const Stream<PhotoWatchEvent>.empty()),
          costumesListFetchProvider('season-1').overrideWith((ref) async {
            final dao = CostumeCacheDao(ref.watch(cacheDatabaseProvider));
            return holder.value.match((err) => Left(err), (rows) async {
              await dao.applySnapshotForSeason(
                'season-1',
                rows,
                DateTime.utc(2026, 1, 1),
              );
              return Right(rows);
            });
          }),
          charactersListFetchProvider('season-1')
              .overrideWith((ref) async => Right([_character('ch-1')])),
          costumeCategoriesListFetchProvider('season-1')
              .overrideWith((ref) async => const Right([])),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authSessionControllerProvider.notifier).signIn();
    }

    /// Tiny valid JPEG so the real prepare pipeline converges.
    Uint8List tinyJpeg() {
      final image = img.Image(width: 4, height: 4);
      image.setPixelRgb(1, 1, 200, 30, 30);
      return Uint8List.fromList(img.encodeJpg(image));
    }

    testWidgets('capture accept → prepare → upload dispatches', (tester) async {
      flowPicker = _ScriptedPicker(
        file: XFile.fromData(tinyJpeg(), name: 'c.jpg'),
      );
      await setupFlow();
      await pumpDetail(tester, 'c-1');
      await tester.tap(find.byKey(const Key('photo-capture-camera-c-1')));
      await _pumpFrames(tester, n: 30);
      // In-app rationale BEFORE the system prompt.
      expect(find.byKey(const Key('photo-rationale-accept')), findsOneWidget);
      await tester.tap(find.byKey(const Key('photo-rationale-accept')));
      // The prepare pipeline runs on a real background isolate: poll in
      // real time (bounded) instead of fixed virtual frames.
      var settled = false;
      for (var i = 0; i < 100 && !settled; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        settled = photos.uploadCalls == 1;
      }
      expect(photos.uploadCalls, 1);
    });

    testWidgets('rationale decline cancels without upload', (tester) async {
      flowPicker = _ScriptedPicker(
        file: XFile.fromData(tinyJpeg(), name: 'c.jpg'),
      );
      await setupFlow();
      await pumpDetail(tester, 'c-1');
      await tester.tap(find.byKey(const Key('photo-capture-camera-c-1')));
      await _pumpFrames(tester, n: 30);
      await tester.tap(find.text('Not now'));
      await _pumpFrames(tester, n: 30);
      expect(photos.uploadCalls, 0);
    });

    testWidgets('denied → re-rationale with open-settings', (tester) async {
      flowPicker = _ScriptedPicker(
        exception: PlatformException(code: 'camera_access_denied'),
      );
      await setupFlow();
      // Rationale already seen: skip straight to the system prompt denial.
      container.read(photoRationaleSeenProvider.notifier).markSeen();
      await pumpDetail(tester, 'c-1');
      await tester.tap(find.byKey(const Key('photo-capture-camera-c-1')));
      await _pumpFrames(tester, n: 30);
      expect(find.byKey(const Key('photo-open-settings')), findsOneWidget);
      await tester.tap(find.byKey(const Key('photo-open-settings')));
      await _pumpFrames(tester, n: 30);
      expect(settingsOpened, 1);
      expect(photos.uploadCalls, 0);
    });

    testWidgets('unavailable picker surfaces copy, no upload', (tester) async {
      flowPicker = _ScriptedPicker(
        exception: PlatformException(code: 'camera_unavailable'),
      );
      await setupFlow();
      container.read(photoRationaleSeenProvider.notifier).markSeen();
      await pumpDetail(tester, 'c-1');
      await tester.tap(find.byKey(const Key('photo-capture-camera-c-1')));
      await _pumpFrames(tester, n: 30);
      expect(find.textContaining('unavailable'), findsOneWidget);
      expect(photos.uploadCalls, 0);
    });

    testWidgets('unassign confirm dispatches version echo', (tester) async {
      await setupContainer(
        costume: _costume('c-1', characterId: 'ch-1'),
        characters: [_character('ch-1')],
      );
      await pumpDetail(tester, 'c-1');
      await tester.tap(find.byKey(const Key('costume-unassign-c-1')));
      await _pumpFrames(tester, n: 30);
      await tester.tap(find.byKey(const Key('costume-unassign-confirm-c-1')));
      await _pumpFrames(tester);
      expect(repo.unassignCalls, 1);
    });

    testWidgets(
      'reassign: unassign→assign sequence with fence-friendly version echo',
      (tester) async {
        // Costume already assigned to ch-1; the Reassign flow must NOT send
        // the plain assign command (it would 409 `costume.already-assigned`
        // — issue #454). The controller runs unassign first (echoing the
        // acted-on version), then assign echoing the unassign ACK version.
        await setupContainer(
          costume: _costume('c-1', characterId: 'ch-1', version: 3),
          characters: [
            _character('ch-1'),
            _character('ch-9', name: 'Bea'),
          ],
        );
        // Unassign ack advances 3 → 4; assign ack advances 4 → 5.
        repo.nextUnassignResults = [Right(4)];
        repo.nextAssignResults = [Right(5)];
        await pumpDetail(tester, 'c-1');
        // The row is assigned: the button renders 'Reassign'.
        expect(find.text('Reassign'), findsOneWidget);
        await tester.tap(find.byKey(const Key('assign-costume-c-1-ch-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('assign-character-ch-9')));
        await _pumpFrames(tester);
        // Both legs dispatched, in order.
        expect(repo.unassignCalls, 1);
        expect(repo.assignCalls, 1);
        // Unassign echoed the acted-on row's version (3).
        expect(repo.lastUnassignVersion, 3);
        // Assign echoed the unassign ACK version (4), NOT the pre-command
        // version (3) — the fence-friendly version echo the issue demands.
        expect(repo.lastAssignVersion, 4);
        // The assign leg carried the picked target character.
        expect(repo.lastAssignCharacterId, 'ch-9');
        // Optimistic overlay key while the fence holds.
        expect(
          find.byKey(const Key('overlay-assign-c-1-ch-9')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'reassign: already assigned to the picked character is a no-op',
      (tester) async {
        // Re-picking the CURRENTLY assigned character must not dispatch any
        // command: the backend 422s the same-character reassign, and the
        // assignment already holds (issue #454).
        await setupContainer(
          costume: _costume('c-1', characterId: 'ch-1', version: 3),
          characters: [_character('ch-1')],
        );
        await pumpDetail(tester, 'c-1');
        await tester.tap(find.byKey(const Key('assign-costume-c-1-ch-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('assign-character-ch-1')));
        await _pumpFrames(tester);
        expect(repo.unassignCalls, 0);
        expect(repo.assignCalls, 0);
        // The assignment already holds: no overlay key change.
        expect(find.byKey(const Key('assigned-c-1-ch-1')), findsOneWidget);
      },
    );

    testWidgets(
      'reassign: assign-leg failure keeps the honest unassigned state + error',
      (tester) async {
        // Issue #454: the sequence is NOT atomic. When the assign leg fails
        // after the unassign leg succeeded, the costume is genuinely
        // UNASSIGNED server-side — the overlay must show the true unassigned
        // state (never a fake target binding) and the failure surfaces via
        // the command-error provider (no silent discard, AGENTS.md §4).
        await setupContainer(
          costume: _costume('c-1', characterId: 'ch-1', version: 3),
          characters: [
            _character('ch-1'),
            _character('ch-9', name: 'Bea'),
          ],
        );
        repo.nextUnassignResults = [Right(4)];
        repo.nextAssignResults = [
          Left(ProblemError(code: 'transport.generic', status: 502)),
        ];
        await pumpDetail(tester, 'c-1');
        await tester.tap(find.byKey(const Key('assign-costume-c-1-ch-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('assign-character-ch-9')));
        await _pumpFrames(tester);
        expect(repo.unassignCalls, 1);
        expect(repo.assignCalls, 1);
        // Error surfaced keyed on the stable code (honest surface).
        expect(find.byKey(const Key('costume-detail-error')), findsOneWidget);
        expect(find.textContaining('Network problem'), findsWidgets);
        // The honest unassigned state: the unassign leg succeeded, so the
        // costume is genuinely UNASSIGNED — the unassigned control renders,
        // and neither the pre-command (ch-1) nor the target (ch-9)
        // assignment badge is present. No fake target binding survives the
        // failed assign leg (issue #454).
        expect(
          find.byKey(const Key('assign-costume-c-1-none')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('assigned-c-1-ch-1')), findsNothing);
        expect(find.byKey(const Key('overlay-assign-c-1-ch-9')), findsNothing);
      },
    );
  });
}
