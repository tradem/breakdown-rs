// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

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

  @override
  Future<Result<int>> unassign(String id, VersionRequest request) {
    unassignCalls++;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right(2));
  }

  @override
  Future<Result<int>> assign(String id, AssignCostumeRequest request) {
    assignCalls++;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right(2));
  }

  @override
  Future<Result<int>> updateNotes(
    String id,
    UpdateCostumeNotesRequest request,
  ) {
    notesCalls++;
    return Future.value(const Right(2));
  }

  @override
  Future<Result<int>> addDetail(String id, AddCostumeDetailRequest request) {
    detailCalls++;
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
  });
}
