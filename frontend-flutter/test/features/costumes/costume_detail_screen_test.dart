// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash (opencode-go)

// Tier-2 widget tests for `CostumeDetailScreen` (Task 4.3): detail elements
// (+ denormalized category names), notes editor, assign/unassign (version
// echo, optimistic overlay keys, 409 copy, role-denial with zero network
// calls), add-detail form (category picker), photo empty state + delete
// confirm flow + photo denial narrative.

import 'dart:async';

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
import 'package:frontend_flutter/l10n/generated/app_localizations_en.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/character_repository.dart';
import 'package:frontend_flutter/data/costume_category_repository.dart';
import 'package:frontend_flutter/data/costume_repository.dart';
import 'package:frontend_flutter/data/photo_repository.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/season_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/characters/characters_controller.dart';
import 'package:frontend_flutter/features/costume_categories/costume_categories_controller.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/features/costumes/costume_detail_screen.dart';
import 'package:frontend_flutter/features/costumes/costumes_controller.dart';
import 'package:frontend_flutter/features/costumes/costumes_state.dart';
import 'package:frontend_flutter/features/photos/capture.dart';
import 'package:frontend_flutter/features/photos/prepare.dart';
import 'package:frontend_flutter/features/photos/widgets/photo_gallery.dart';

import '../seasons/seasons_test_fakes.dart';

CostumeView _costume(
  String id, {
  String? characterId,
  String? categoryId,
  String? categoryName,
  int version = 1,
  String notes = 'Linen suit',
  List<CostumeDetailView> details = const [],
  // Issue #534: the season repertoire (m:n) on the row.
  List<String> seasonIds = const [],
}) => CostumeView(
  (b) => b
    ..id = id
    ..characterId = characterId
    // Issue #543: costume-level category on the row for picker/no-op tests.
    ..categoryId = categoryId
    ..categoryName = categoryName
    ..notes = notes
    ..details.replace(BuiltList<CostumeDetailView>(details))
    ..photos.replace(BuiltList<CostumePhotoView>())
    ..seasonIds.replace(BuiltList<String>(seasonIds))
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version,
);

/// A photo whose thumb variant is READY, so the gallery renders the tile itself
/// instead of a pending spinner. READY needs no byte fetch to lay out, which
/// keeps the test free of any network seam.
CostumePhotoView _readyPhoto(String id) => CostumePhotoView(
  (b) => b
    ..id = id
    ..contentType = 'image/jpeg'
    ..sizeBytes = 10
    ..variants.replace([
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
);

/// A genuine optimistic-concurrency defeat (server equality guard):
/// `concurrency.version-mismatch` 409 — distinct from the generic
/// conflict/validation codes.
const _versionMismatch = ProblemError(
  code: 'concurrency.version-mismatch',
  status: 409,
);

CostumeDetailView _detail(String id) => CostumeDetailView(
  (b) => b
    ..id = id
    ..subject = 'Jacket'
    ..text = 'Red leather jacket',
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

CostumeCategoryView _category(
  String id, {
  String name = 'Outerwear',
  bool archived = false,
}) => CostumeCategoryView(
  (b) => b
    ..id = id
    ..seasonId = 'season-1'
    ..name = name
    ..orderKey = '!'
    ..archived = archived
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

SeasonView _season() => SeasonView(
  (b) => b
    ..archived = false
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

  /// While set, the add-detail ack stays unresolved until the test
  /// completes the gate — simulates the in-flight window the double-tap
  /// guard (CodeRabbit #563) protects.
  Completer<void>? detailGate;

  @override
  Future<Result<int>> addDetail(String id, AddCostumeDetailRequest request) {
    detailCalls++;
    lastDetailVersion = request.version;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    final gate = detailGate;
    if (gate != null) {
      return gate.future.then<Right<ProblemError, int>>((_) => const Right(2));
    }
    return Future.value(const Right(2));
  }

  /// Issue #545: the inline editor dispatches these via the #544 controller
  /// seam; counters + captured echoes make edit and delete provable.
  int updateDetailCalls = 0;
  int removeDetailCalls = 0;
  String? lastUpdateDetailId;
  String? lastRemoveDetailId;
  UpdateCostumeDetailRequest? lastUpdateDetailRequest;
  VersionRequest? lastRemoveDetailRequest;

  @override
  Future<Result<int>> updateDetail(
    String id,
    String detailId,
    UpdateCostumeDetailRequest request,
  ) {
    updateDetailCalls++;
    lastUpdateDetailId = detailId;
    lastUpdateDetailRequest = request;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right(2));
  }

  @override
  Future<Result<int>> removeDetail(
    String id,
    String detailId,
    VersionRequest request,
  ) {
    removeDetailCalls++;
    lastRemoveDetailId = detailId;
    lastRemoveDetailRequest = request;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right(2));
  }

  /// Issue #543: the costume-level category command capture.
  int setCategoryCalls = 0;
  String? lastSetCategoryId;
  int? lastSetCategoryVersion;

  @override
  Future<Result<int>> setCategory(
    String id,
    SetCostumeCategoryRequest request,
  ) {
    setCategoryCalls++;
    lastSetCategoryId = request.categoryId;
    lastSetCategoryVersion = request.version;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right(2));
  }

  /// Issue #534: the repertoire command capture (calls + echoes).
  int addToSeasonCalls = 0;
  int removeFromSeasonCalls = 0;
  String? lastAddToSeasonId;
  int? lastAddToSeasonVersion;
  String? lastRemoveFromSeasonId;
  int? lastRemoveFromSeasonVersion;

  @override
  Future<Result<int>> addToSeason(
    String id,
    AddCostumeToSeasonRequest request,
  ) {
    addToSeasonCalls++;
    lastAddToSeasonId = request.seasonId;
    lastAddToSeasonVersion = request.version;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right(2));
  }

  @override
  Future<Result<int>> removeFromSeason(
    String id,
    String seasonId,
    VersionRequest request,
  ) {
    removeFromSeasonCalls++;
    lastRemoveFromSeasonId = seasonId;
    lastRemoveFromSeasonVersion = request.version;
    final scripted = nextWrite;
    if (scripted != null) return Future.value(scripted);
    return Future.value(const Right(2));
  }

  /// Scripted row for `GET /v1/costumes/{id}` (`getAndCache`), plus a call
  /// counter. The screen fetches the enriched single row on open and after
  /// gallery-affecting commands, because the rendered row may be the
  /// OPTIMISTIC overlay whose photos the last snapshot does not know about
  /// (the list route itself is batch-enriched since the #543/#544 tranche).
  /// Defaulting to the unscripted-error shape keeps every pre-existing test on
  /// its old rendering;
  /// without the override at all the fake would fall through to the real Dio
  /// client and leave an unsettled request behind.
  Result<CostumeView>? enrichedDetail;

  /// Successive results for `getAndCache`, consumed in order. The reload-after-
  /// command tests need this: the row the screen re-reads after a photo command
  /// DIFFERS from the one it read on open, which one scripted value cannot say.
  final List<Result<CostumeView>> detailQueue = [];
  int detailFetchCalls = 0;

  @override
  Future<Result<CostumeView>> getAndCache(
    String seasonId,
    String id, {
    Clock clock = Clock.system,
  }) {
    detailFetchCalls++;
    if (detailQueue.isNotEmpty) return Future.value(detailQueue.removeAt(0));
    return Future.value(
      // UNSCRIPTED = the read failed: the screen then keeps rendering the list
      // row it was handed, exactly what the old (real-Dio, never-settling) path
      // produced. Defaulting to a photo-less enriched row would instead REPLACE
      // a list row that has photos and silently empty the gallery.
      enrichedDetail ??
          const Left(
            ProblemError(code: 'costume.detail-not-scripted', status: 500),
          ),
    );
  }
}

class _FakePhotoRepository extends PhotoRepository {
  _FakePhotoRepository(super.api);

  int deleteCalls = 0;
  int uploadCalls = 0;

  /// Scripted server failure for the next call (issue #532: the server owns
  /// the costume-scope decision, so its rejection must be asserted through the
  /// honest code-keyed copy). `null` = serve a success.
  ProblemError? uploadError;
  ProblemError? deleteError;

  @override
  Future<Result<void>> delete(String costumeId, String photoId) {
    deleteCalls++;
    final error = deleteError;
    if (error != null) return Future.value(Left(error));
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
    final error = uploadError;
    if (error != null) return Future.value(Left(error));
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
    // Issue #534: the seasons projection the repertoire section joins
    // against (names + picker eligibility).
    List<SeasonView> seasons = const [],
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
        // Issue #534: the repertoire section reads the seasons projection
        // (names + picker eligibility). The season repository override
        // keeps SeasonsViewController/s TTL staleness fixated on the test
        // database — the fetch seam supplies the authoritative rows.
        seasonRepositoryProvider.overrideWithValue(
          SeasonRepository(BreakdownApi(), SeasonCacheDao(db)),
        ),
        seasonsListFetchProvider.overrideWith((ref) async => Right(seasons)),
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
          details: [_detail('d-1')],
        ),
        characters: [_character('ch-1')],
      );
      await pumpDetail(tester, 'c-1');
      expect(find.text('Red leather jacket'), findsOneWidget);
      // Issue #543: no per-detail category line any more — the category
      // lives on the costume (identity section of the editor, later PR).
      expect(find.text('Outerwear'), findsNothing);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.byKey(const Key('costume-notes-c-1')), findsOneWidget);
      expect(find.byKey(const Key('photo-gallery-empty-c-1')), findsOneWidget);
    });

    // The photo gallery renders the ENRICHED single-costume row fetched on
    // open, not the possibly-optimistic rendered row (see `_detail` and the
    // fake's `enrichedDetail` doc).
    testWidgets('opening fetches the enriched detail ONCE and the gallery '
        'renders its photos', (tester) async {
      await setupContainer(costume: _costume('c-1'));
      repo.enrichedDetail = Right<ProblemError, CostumeView>(
        _costume('c-1').rebuild((b) => b..photos.replace([_readyPhoto('p-1')])),
      );
      await pumpDetail(tester, 'c-1');

      expect(
        repo.detailFetchCalls,
        1,
        reason: 'one fetch per open — never a retry loop',
      );
      expect(find.byKey(const Key('photo-tile-p-1')), findsOneWidget);
      expect(
        find.byKey(const Key('photo-gallery-empty-c-1')),
        findsNothing,
        reason:
            'an empty affordance would be a lie: the fetched row has a photo',
      );
    });

    // The gallery renders the re-read row, so a photo command must trigger a
    // fresh detail read: otherwise a deleted photo stays on screen and a newly
    // uploaded one never appears, because the list rows `refresh()` updates
    // carry no photos at all.
    testWidgets('a deleted photo disappears from the gallery: the detail is '
        're-read after the command succeeds', (tester) async {
      final withPhoto = _costume(
        'c-1',
        characterId: 'ch-1',
      ).rebuild((b) => b..photos.replace([_readyPhoto('p-1')]));
      await setupContainer(costume: withPhoto);
      // Open: the enriched row still has the photo. After the delete: it is gone.
      repo.detailQueue.addAll([
        Right<ProblemError, CostumeView>(withPhoto),
        Right<ProblemError, CostumeView>(_costume('c-1', characterId: 'ch-1')),
      ]);
      await pumpDetail(tester, 'c-1');
      expect(find.byKey(const Key('photo-tile-p-1')), findsOneWidget);
      expect(repo.detailFetchCalls, 1);

      await tester.tap(find.byKey(const Key('photo-delete-p-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('photo-delete-confirm-p-1')));
      await _pumpFrames(tester);

      expect(photos.deleteCalls, 1);
      expect(
        repo.detailFetchCalls,
        2,
        reason: 'the successful delete must re-read the enriched row',
      );
      expect(find.byKey(const Key('photo-tile-p-1')), findsNothing);
    });

    testWidgets('a FAILED photo command does NOT re-read or rewrite the '
        'gallery — the shown row stays honest', (tester) async {
      final withPhoto = _costume(
        'c-1',
        characterId: 'ch-1',
      ).rebuild((b) => b..photos.replace([_readyPhoto('p-1')]));
      await setupContainer(costume: withPhoto);
      repo.detailQueue.add(Right<ProblemError, CostumeView>(withPhoto));
      await pumpDetail(tester, 'c-1');
      expect(repo.detailFetchCalls, 1);

      photos.deleteError = const ProblemError(
        code: 'photo.forbidden',
        status: 403,
      );
      await tester.tap(find.byKey(const Key('photo-delete-p-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('photo-delete-confirm-p-1')));
      await _pumpFrames(tester);

      expect(
        repo.detailFetchCalls,
        1,
        reason: 'a rejected command must not trigger a re-read',
      );
      expect(
        find.byKey(const Key('photo-tile-p-1')),
        findsOneWidget,
        reason: 'the photo still exists server-side, so it stays visible',
      );
    });

    testWidgets(
      'a FAILED detail fetch keeps the list row rendering — no crash, '
      'and no invented gallery',
      (tester) async {
        await setupContainer(costume: _costume('c-1'));
        repo.enrichedDetail = const Left(
          ProblemError(code: 'costume.detail-unavailable', status: 503),
        );
        await pumpDetail(tester, 'c-1');

        expect(repo.detailFetchCalls, 1);
        // The rest of the screen is untouched by the failed read.
        expect(find.byKey(const Key('costume-detail-c-1')), findsOneWidget);
        expect(
          find.byKey(const Key('photo-gallery-empty-c-1')),
          findsOneWidget,
          reason:
              'with no enriched row the honest state is still "no photos seen"',
        );
      },
    );

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
      // command must carry v2, not the initial snapshot's 1. The inline
      // editor (issue #545) opens via the `＋` row and submits in place.
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
      // Open the create editor inline: editor mounts, no dialog route.
      await tester.tap(find.byKey(const Key('costume-detail-add-c-1')));
      await _pumpFrames(tester);
      expect(find.byKey(const Key('add-detail-editor')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('add-detail-text')),
        'Silk lining',
      );
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('add-detail-submit')));
      await _pumpFrames(tester, n: 12);
      expect(repo.detailCalls, 1);
      expect(repo.lastDetailVersion, 2);
      expect(
        find.byKey(const Key('costume-saved-confirmation')),
        findsOneWidget,
      );
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

    testWidgets(
      'add-detail: pure-description INLINE editor (no category field, #543)',
      (tester) async {
        await setupContainer(
          costume: _costume('c-1'),
          categories: [_category('cat-1')],
        );
        await pumpDetail(tester, 'c-1');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.byKey(const Key('costume-detail-add-c-1')));
        await _pumpFrames(tester);
        await tester.enterText(
          find.byKey(const Key('add-detail-text')),
          'Silk lining',
        );
        await _pumpFrames(tester);
        // The category dropdown is GONE from the editor; the category is set
        // on the costume via the identity section (issue #543).
        expect(find.byKey(const Key('add-detail-category')), findsNothing);
        await tester.tap(find.byKey(const Key('add-detail-submit')));
        await _pumpFrames(tester, n: 12);
        expect(repo.detailCalls, 1);
      },
    );

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
          // Issue #513 assignment gate: the delete affordance only renders
          // for an ASSIGNED costume (the backend resolves the photo season
          // through the character).
          ..characterId = 'ch-1'
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

  group('CostumeDetailScreen inline detail editor (issue #545)', () {
    CostumeDetailView detailView(
      String id, {
      String? subject,
      String text = '',
    }) => CostumeDetailView(
      (b) => b
        ..id = id
        ..subject = subject
        ..text = text,
    );

    testWidgets('edit opens the SAME editor widget inline, prefilled '
        '(no dialog route)', (tester) async {
      await setupContainer(
        costume: _costume(
          'c-1',
          details: [
            detailView('d-1', subject: 'Jacke', text: 'rote Lederjacke'),
          ],
        ),
      );
      await pumpDetail(tester, 'c-1');
      await tester.tap(find.byKey(const Key('costume-detail-edit-d-1')));
      await _pumpFrames(tester);
      // The editor expands IN the row — the same widget as create mode.
      expect(
        find.byKey(const Key('detail-editor-d-1')),
        findsOneWidget,
        reason: 'one shared editor widget, edit mode seeded from the row',
      );
      // The prefilled fields hold the row's content (the row tile renders
      // the same strings, so find.text matches the editor AND the tile).
      expect(find.text('Jacke'), findsNWidgets(2));
      expect(find.text('rote Lederjacke'), findsNWidgets(2));
    });

    testWidgets('create opens the editor inline via the + row (empty)', (
      tester,
    ) async {
      await setupContainer(costume: _costume('c-1'));
      await pumpDetail(tester, 'c-1');
      await tester.tap(find.byKey(const Key('costume-detail-add-c-1')));
      await _pumpFrames(tester);
      expect(find.byKey(const Key('add-detail-editor')), findsOneWidget);
      expect(find.byKey(const Key('add-detail-text')), findsOneWidget);
      // One widget, both modes: no edit-mode editor mounted while drafting.
      expect(find.byKey(const Key('detail-editor-d-1')), findsNothing);
    });

    testWidgets('save stays DISABLED while the required text is empty', (
      tester,
    ) async {
      await setupContainer(costume: _costume('c-1'));
      await pumpDetail(tester, 'c-1');
      await tester.tap(find.byKey(const Key('costume-detail-add-c-1')));
      await _pumpFrames(tester);
      final disabled = tester.widget<FilledButton>(
        find.byKey(const Key('add-detail-submit')),
      );
      expect(disabled.onPressed, isNull);
      // Whitespace-only must not count as content either.
      await tester.enterText(find.byKey(const Key('add-detail-text')), '   ');
      await _pumpFrames(tester);
      final stillDisabled = tester.widget<FilledButton>(
        find.byKey(const Key('add-detail-submit')),
      );
      expect(stillDisabled.onPressed, isNull);
      expect(repo.detailCalls, 0);
    });

    testWidgets('valid text ENABLES save and dispatches (subject optional)', (
      tester,
    ) async {
      await setupContainer(costume: _costume('c-1'));
      await pumpDetail(tester, 'c-1');
      await tester.tap(find.byKey(const Key('costume-detail-add-c-1')));
      await _pumpFrames(tester);
      await tester.enterText(
        find.byKey(const Key('add-detail-text')),
        'echtes Leder, vintage',
      );
      await _pumpFrames(tester);
      final enabled = tester.widget<FilledButton>(
        find.byKey(const Key('add-detail-submit')),
      );
      expect(enabled.onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('add-detail-submit')));
      await _pumpFrames(tester, n: 12);
      expect(repo.detailCalls, 1);
    });

    testWidgets('a same-frame double tap dispatches only once while '
        'the first command is in flight', (tester) async {
      // CodeRabbit #563: version fencing rejects a STALE second request,
      // but two in-flight adds would carry two different UUIDv7s — the
      // affordance itself must serialize them (the _submitting guard runs
      // synchronously before the first await).
      await setupContainer(costume: _costume('c-1'));
      await pumpDetail(tester, 'c-1');
      repo.detailGate = Completer<void>();
      await tester.tap(find.byKey(const Key('costume-detail-add-c-1')));
      await _pumpFrames(tester);
      await tester.enterText(
        find.byKey(const Key('add-detail-text')),
        'echtes Leder',
      );
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('add-detail-submit')));
      // Second tap in the SAME frame — no pump between the two dispatches.
      await tester.tap(find.byKey(const Key('add-detail-submit')));
      repo.detailGate!.complete();
      await _pumpFrames(tester, n: 12);
      expect(
        repo.detailCalls,
        1,
        reason: 'the in-flight guard swallowed the duplicate dispatch',
      );
    });

    testWidgets('edit seed dispatches updateDetail with the existing id', (
      tester,
    ) async {
      await setupContainer(
        costume: _costume(
          'c-1',
          details: [detailView('d-1', subject: 'Jacke', text: 'leder')],
        ),
      );
      await pumpDetail(tester, 'c-1');
      await tester.tap(find.byKey(const Key('costume-detail-edit-d-1')));
      await _pumpFrames(tester);
      await tester.enterText(
        find.byKey(const Key('add-detail-text')),
        'echtes Leder, vintage',
      );
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('add-detail-submit')));
      await _pumpFrames(tester, n: 12);
      expect(repo.updateDetailCalls, 1);
      // The existing detail id — unlike addDetail, no placeholder (issue #472).
      expect(repo.lastUpdateDetailId, 'd-1');
      expect(repo.lastUpdateDetailRequest!.detail.id, 'd-1');
      expect(
        repo.lastUpdateDetailRequest!.detail.text,
        'echtes Leder, vintage',
      );
    });

    testWidgets('delete asks for confirmation FIRST, then dispatches', (
      tester,
    ) async {
      await setupContainer(
        costume: _costume('c-1', details: [detailView('d-1', text: 'x')]),
      );
      await pumpDetail(tester, 'c-1');
      await tester.tap(find.byKey(const Key('costume-detail-delete-d-1')));
      await _pumpFrames(tester);
      expect(repo.removeDetailCalls, 0);
      await tester.tap(
        find.byKey(const Key('costume-detail-delete-confirm-d-1')),
      );
      await _pumpFrames(tester, n: 12);
      expect(
        repo.removeDetailCalls,
        1,
        reason: 'destructive action routes through the confirm dialog',
      );
      expect(repo.lastRemoveDetailId, 'd-1');
    });

    testWidgets('cancel closes the editor and dispatches nothing', (
      tester,
    ) async {
      await setupContainer(
        costume: _costume('c-1', details: [detailView('d-1', text: 'x')]),
      );
      await pumpDetail(tester, 'c-1');
      await tester.tap(find.byKey(const Key('costume-detail-edit-d-1')));
      await _pumpFrames(tester);
      await tester.enterText(
        find.byKey(const Key('add-detail-text')),
        'changed',
      );
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('add-detail-cancel')));
      await _pumpFrames(tester);
      expect(find.byKey(const Key('detail-editor-d-1')), findsNothing);
      expect(repo.updateDetailCalls, 0);
      expect(repo.detailCalls, 0);
    });

    testWidgets(
      'Err branch: failed command surfaces the command-error banner',
      (tester) async {
        await setupContainer(
          costume: _costume('c-1', details: [detailView('d-1', text: 'x')]),
        );
        await pumpDetail(tester, 'c-1');
        repo.nextWrite = const Left(
          ProblemError(code: 'transport.generic', status: 502),
        );
        await tester.tap(find.byKey(const Key('costume-detail-delete-d-1')));
        await _pumpFrames(tester);
        await tester.tap(
          find.byKey(const Key('costume-detail-delete-confirm-d-1')),
        );
        await _pumpFrames(tester, n: 10);
        expect(
          find.byKey(const Key('costume-detail-error')),
          findsOneWidget,
          reason:
              'the Result Err branch is visible, never swallowed (AGENTS.md '
              '§4 no-discard)',
        );
      },
    );

    testWidgets('golden: the open inline editor state', (tester) async {
      await setupContainer(
        costume: _costume(
          'c-1',
          details: [
            detailView('d-1', subject: 'Jacke', text: 'rote Lederjacke'),
          ],
        ),
      );
      await pumpDetail(tester, 'c-1');
      await tester.tap(find.byKey(const Key('costume-detail-edit-d-1')));
      await _pumpFrames(tester);
      await expectLater(
        find.byType(CostumeDetailScreen),
        matchesGoldenFile('goldens/costume_detail_editor_open.png'),
      );
    });

    testWidgets('category stays GONE from the editor (issue #543 contract)', (
      tester,
    ) async {
      await setupContainer(
        costume: _costume('c-1'),
        categories: [_category('cat-1')],
      );
      await pumpDetail(tester, 'c-1');
      await tester.tap(find.byKey(const Key('costume-detail-add-c-1')));
      await _pumpFrames(tester);
      expect(find.byKey(const Key('add-detail-category')), findsNothing);
    });
  });

  group('CostumeDetailScreen repertoire (issue #534)', () {
    final s1 = _season();
    SeasonView s2() => SeasonView(
      (b) => b
        ..archived = false
        ..id = 'season-2'
        ..number = 2
        ..seriesId = 'series-1'
        ..title = 'Season Two'
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

    testWidgets('repertoire rows render resolved season names', (tester) async {
      await setupContainer(
        costume: _costume('c-1', seasonIds: ['season-2']),
        seasons: [s1, s2()],
      );
      await pumpDetail(tester, 'c-1');
      expect(
        find.byKey(const Key('costume-repertoire-row-c-1-season-2')),
        findsOneWidget,
      );
      expect(find.text('Season Two'), findsOneWidget);
      // Only the repertoire row — the picker button is present but no
      // remove affordance for a season outside the repertoire.
      expect(
        find.byKey(const Key('costume-repertoire-remove-c-1-season-2')),
        findsOneWidget,
      );
    });

    testWidgets(
      'add: picker submit dispatches id + version echo, overlay row',
      (tester) async {
        await setupContainer(costume: _costume('c-1'), seasons: [s2()]);
        await pumpDetail(tester, 'c-1');
        await tester.tap(find.byKey(const Key('costume-repertoire-add-c-1')));
        // Let the modal route's entrance animation settle before picking.
        await _pumpFrames(tester, n: 24);
        // The sheet renders at the bottom edge; the tile can sit just below
        // the viewport bottom in the 1200px test surface — scroll it into
        // view before tapping (same affordance a tall list needs on-device).
        await tester.ensureVisible(
          find.byKey(const Key('repertoire-pick-season-2')),
        );
        await _pumpFrames(tester);
        await tester.tap(find.byKey(const Key('repertoire-pick-season-2')));
        await _pumpFrames(tester, n: 24);
        expect(repo.addToSeasonCalls, 1);
        expect(repo.lastAddToSeasonId, 'season-2');
        // Optimistic-concurrency: the request echoes the pre-command version.
        expect(repo.lastAddToSeasonVersion, 1);
        // The optimistic overlay renders the added season immediately.
        expect(
          find.byKey(const Key('costume-repertoire-row-c-1-season-2')),
          findsOneWidget,
        );
      },
    );

    testWidgets('remove: confirm dialog dispatches id + version echo', (
      tester,
    ) async {
      await setupContainer(
        costume: _costume('c-1', seasonIds: ['season-1', 'season-2']),
        seasons: [s1, s2()],
      );
      await pumpDetail(tester, 'c-1');
      await tester.tap(
        find.byKey(const Key('costume-repertoire-remove-c-1-season-2')),
      );
      await _pumpFrames(tester);
      await tester.tap(
        find.byKey(const Key('costume-repertoire-confirm-remove')),
      );
      await _pumpFrames(tester, n: 12);
      expect(repo.removeFromSeasonCalls, 1);
      expect(repo.lastRemoveFromSeasonId, 'season-2');
      expect(repo.lastRemoveFromSeasonVersion, 1);
    });

    testWidgets('denial: capability missing → zero network calls (gate '
        'short-circuit)', (tester) async {
      await setupContainer(
        costume: _costume('c-1'),
        seasons: [s2()],
        capabilities: const [],
      );
      await pumpDetail(tester, 'c-1');
      await tester.tap(find.byKey(const Key('costume-repertoire-add-c-1')));
      await _pumpFrames(tester, n: 24);
      await tester.ensureVisible(
        find.byKey(const Key('repertoire-pick-season-2')),
      );
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('repertoire-pick-season-2')));
      await _pumpFrames(tester, n: 24);
      expect(repo.addToSeasonCalls, 0);
      // The client-side AUTHZ-GATE denial carries the localized 403 copy.
      expect(find.byKey(const Key('costume-detail-error')), findsOneWidget);
    });

    test('controller no-op: a season already in the repertoire dispatches '
        'nothing and echoes the unchanged version', () async {
      await setupContainer(
        costume: _costume('c-1', seasonIds: ['season-2']),
        seasons: [s1, s2()],
      );
      final costume = _costume('c-1', seasonIds: ['season-2']);
      final controller = container.read(
        costumesControllerProvider('season-1').notifier,
      );
      final res = await controller.addToSeason(
        costume: costume,
        seasonId: 'season-2',
      );
      expect(res, const Right(1));
      expect(repo.addToSeasonCalls, 0);
      final res2 = await controller.removeFromSeason(
        costume: costume,
        seasonId: 'season-3',
      );
      expect(res2, const Right(1));
      expect(repo.removeFromSeasonCalls, 0);
      // ProviderContainer.dispose() returns void — never awaited.
      container.dispose();
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
        costume: _costume('c-1', characterId: 'ch-1'),
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
          // Issue #534: keep the repertoire section's seasons projection off
          // the production seam (same tolerance as setupContainer).
          seasonRepositoryProvider.overrideWithValue(
            SeasonRepository(BreakdownApi(), SeasonCacheDao(db)),
          ),
          seasonsListFetchProvider.overrideWith((ref) async => const Right([])),
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

  group('CostumeDetailScreen photo scope gate (issue #532)', () {
    testWidgets(
      'unassigned costume: affordances stay enabled, upload is dispatched '
      '(server owns the season scope)',
      (tester) async {
        // Issue #532: the server resolves a costume's season scopes as
        // `character season ∪ repertoire seasons` (issue #453), so an
        // unassigned costume in the season's repertoire — how the client
        // creates every costume — CAN manage photos. The client-side
        // character pre-deny of issue #513 is resolved: no gate narrative,
        // no hidden affordances, and the request actually leaves the device.
        await setupContainer(costume: _costume('c-1')); // characterId: null
        await pumpDetail(tester, 'c-1');
        // The #513 gate narrative is gone: there is nothing to pre-explain.
        expect(
          find.byKey(const Key('photo-assignment-gate-narrative')),
          findsNothing,
        );
        // Capture affordances render on an unassigned costume.
        expect(find.byKey(const Key('photo-capture-c-1')), findsOneWidget);
        expect(
          find.byKey(const Key('photo-capture-camera-c-1')),
          findsOneWidget,
        );
        // The command is dispatched — the server decides (fake repo counter
        // proves the request left the device).
        ProblemError? failure;
        final result = await container
            .read(costumesControllerProvider('season-1').notifier)
            .uploadPhoto(
              costumeId: 'c-1',
              bytes: Uint8ListBytes(Uint8List.fromList(const [1, 2, 3])),
              contentType: 'image/jpeg',
            );
        result.match((e) => failure = e, (_) {});
        expect(failure, isNull);
        expect(photos.uploadCalls, 1);
        // No client-side gate denial surfaces on the happy path.
        await _pumpFrames(tester);
        expect(find.byKey(const Key('costume-detail-error')), findsNothing);
      },
    );

    testWidgets(
      'delete dispatches on an unassigned costume that holds photos',
      (tester) async {
        // Same scope resolution as upload: the server authorizes against the
        // costume's repertoire season, so the delete affordance is not hidden.
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
        expect(find.byKey(const Key('photo-delete-p-1')), findsOneWidget);
        expect(
          find.byKey(const Key('photo-assignment-gate-narrative')),
          findsNothing,
        );
        ProblemError? failure;
        final result = await container
            .read(costumesControllerProvider('season-1').notifier)
            .deletePhoto(costumeId: 'c-1', photoId: 'p-1');
        result.match((e) => failure = e, (_) {});
        expect(failure, isNull);
        expect(photos.deleteCalls, 1);
      },
    );

    testWidgets(
      'server-side no-scope rejection renders the honest photo copy (Err branch)',
      (tester) async {
        // Err-branch assertion for the resolved #532 client gate: a costume
        // with NO season scope at all (not assigned, not in any repertoire) is
        // rejected by the server with `domain.validation`. The request IS
        // issued (the server owns the decision) and the failure surfaces
        // through the photo copy, never the "costume could not be saved"
        // fallback (origin-routed copy, issue #513).
        await setupContainer(costume: _costume('c-1')); // characterId: null
        photos.uploadError = const ProblemError(
          code: 'domain.validation',
          status: 422,
        );
        await pumpDetail(tester, 'c-1');
        ProblemError? failure;
        final result = await container
            .read(costumesControllerProvider('season-1').notifier)
            .uploadPhoto(
              costumeId: 'c-1',
              bytes: Uint8ListBytes(Uint8List.fromList(const [1, 2, 3])),
              contentType: 'image/jpeg',
            );
        result.match((e) => failure = e, (_) {});
        expect(failure?.code, 'domain.validation');
        expect(photos.uploadCalls, 1);
        await _pumpFrames(tester);
        expect(
          find.descendant(
            of: find.byKey(const Key('costume-detail-error')),
            matching: find.text(
              'The photo could not be saved (domain.validation).',
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'unknown costume binding lets the server decide (no pre-deny)',
      (tester) async {
        // CodeRabbit #4101353477: a costume row ABSENT from the local
        // projection is UNKNOWN, not confirmed-unassigned — the client must
        // not pre-deny; it falls through and lets the authoritative server
        // decide. (The fake repo serves the upload, proving the request is
        // issued rather than refused on an unknown binding.)
        await setupContainer(costume: _costume('c-1')); // projection: c-1 only
        final result = await container
            .read(costumesControllerProvider('season-1').notifier)
            .uploadPhoto(
              costumeId: 'c-unknown', // absent from overlays + projection
              bytes: Uint8ListBytes(Uint8List.fromList(const [1, 2, 3])),
              contentType: 'image/jpeg',
            );
        // Proceeds → the fake repo serves a success (server decides).
        expect(result.isRight(), isTrue);
        expect(photos.uploadCalls, 1);
        await _pumpFrames(tester);
        // No client-side gate denial surfaces.
        expect(find.byKey(const Key('costume-detail-error')), findsNothing);
      },
    );
  });

  group('CostumeDetailScreen category section (issue #543)', () {
    testWidgets('the identity section shows the costume category with icon', (
      tester,
    ) async {
      await setupContainer(
        costume: _costume('c-1'),
        categories: [_category('cat-1')],
      );
      await pumpDetail(tester, 'c-1');
      // The section is present with an un-categorised default.
      expect(find.byKey(const Key('costume-category-section')), findsOneWidget);
      expect(
        find.byKey(const Key('costume-category-current-c-1')),
        findsOneWidget,
      );
      expect(find.text('Uncategorized'), findsOneWidget);
      // The picker opens with the projected vocabulary (icon + text).
      await tester.tap(find.byKey(const Key('costume-category-pick-c-1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('costume-category-picker-title')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('costume-category-option-cat-1')),
        findsOneWidget,
      );
      expect(find.text('Outerwear'), findsOneWidget);
      // Picking dispatches the category command (version echo from the
      // acted-on row).
      await tester.tap(find.byKey(const Key('costume-category-option-cat-1')));
      await _pumpFrames(tester);
      expect(repo.setCategoryCalls, 1);
      expect(repo.lastSetCategoryVersion, 1);
      // The optimistic overlay key while the fence holds.
      expect(
        find.byKey(const Key('overlay-category-c-1-cat-1')),
        findsOneWidget,
      );
    });

    testWidgets('picker hides archived categories, clear row always present', (
      tester,
    ) async {
      await setupContainer(
        costume: _costume('c-1'),
        categories: [
          _category('cat-1'),
          _category('cat-archived', name: 'Archived row', archived: true),
        ],
      );
      await pumpDetail(tester, 'c-1');
      await tester.tap(find.byKey(const Key('costume-category-pick-c-1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('costume-category-option-cat-1')),
        findsOneWidget,
      );
      // Archived vocabulary is never an option (no new categorisation).
      expect(
        find.byKey(const Key('costume-category-option-cat-archived')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('costume-category-option-none')),
        findsOneWidget,
      );
    });

    testWidgets('category denial: 403 narrative, zero calls', (tester) async {
      await setupContainer(
        costume: _costume('c-1'),
        categories: [_category('cat-1')],
        capabilities: const [],
      );
      await pumpDetail(tester, 'c-1');
      await tester.tap(find.byKey(const Key('costume-category-pick-c-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('costume-category-option-cat-1')));
      await _pumpFrames(tester);
      // Request-counter proof: the gate short-circuits before the network.
      expect(repo.setCategoryCalls, 0);
      await _pumpFrames(tester);
      expect(
        find.text('You need an active costume role in this season.'),
        findsOneWidget,
      );
    });

    testWidgets('category command echoes the acked version and reconciles', (
      tester,
    ) async {
      // Version-freshness cross-command variant (issue #473): save notes
      // first (v1 → ack v2), then set the category — the echoed version is
      // v2, never the stale v1 that would 422 as `domain.validation`.
      await setupContainer(costume: _costume('c-1'));
      await pumpDetail(tester, 'c-1');
      await tester.enterText(
        find.byKey(const Key('costume-notes-c-1')),
        'Wool coat',
      );
      await tester.tap(find.byKey(const Key('costume-notes-save-c-1')));
      await _pumpFrames(tester);
      expect(repo.notesCalls, 1);
      final result = await container
          .read(costumesControllerProvider('season-1').notifier)
          .setCategory(
            costume: _costume('c-1'),
            categoryId: 'cat-1',
            categoryName: 'Outerwear',
          );
      expect(result.isRight(), isTrue);
      expect(repo.setCategoryCalls, 1);
      expect(repo.lastSetCategoryVersion, 2);
      expect(repo.lastSetCategoryId, 'cat-1');
      // CodeRabbit #4126529973: the ack must UPDATE the overlay, not just
      // echo a version — script the ack to v3 and assert the reconciling
      // overlay row carries the requested category at the ack version.
      final state = container.read(costumesControllerProvider('season-1'));
      final overlay = state.overlays.firstWhere((o) => o.id == 'c-1');
      expect(overlay.acknowledgedVersion, 2);
      expect(overlay.status, OverlayStatus.acknowledged);
      expect(overlay.overlay.categoryId, 'cat-1');
      expect(overlay.overlay.categoryName, 'Outerwear');
      // The notes value the user just saved is NOT clobbered by the
      // category overlay merge onto the freshest row.
      expect(overlay.overlay.notes, 'Wool coat');
    });

    testWidgets(
      'category ack advances the overlay via a scripted v3 acknowledgement',
      (tester) async {
        // CodeRabbit #4126529973: the fake's default ack (v2) equals the
        // echoed version, so it cannot prove the overlay advanced. Script
        // v3 and assert the overlay carries the requested category at v3.
        await setupContainer(
          costume: _costume('c-1'),
          categories: [_category('cat-1')],
        );
        await pumpDetail(tester, 'c-1');
        repo.nextWrite = const Right(3);
        final result = await container
            .read(costumesControllerProvider('season-1').notifier)
            .setCategory(
              costume: _costume('c-1'),
              categoryId: 'cat-1',
              categoryName: 'Outerwear',
            );
        expect(result.isRight(), isTrue);
        expect(repo.setCategoryCalls, 1);
        final state = container.read(costumesControllerProvider('season-1'));
        final overlay = state.overlays.firstWhere((o) => o.id == 'c-1');
        expect(overlay.acknowledgedVersion, 3);
        expect(overlay.overlay.version, 3);
        expect(overlay.overlay.categoryId, 'cat-1');
        expect(overlay.overlay.categoryName, 'Outerwear');
        // The fence holds (projection still at v1 below the ack): the
        // editor renders the optimistic category key.
        await _pumpFrames(tester);
        expect(
          find.byKey(const Key('overlay-category-c-1-cat-1')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '409 costume-category.season-mismatch renders its distinct narrative',
      (tester) async {
        await setupContainer(
          costume: _costume('c-1'),
          categories: [_category('cat-1')],
        );
        await pumpDetail(tester, 'c-1');
        repo.nextWrite = const Left(
          ProblemError(code: 'costume-category.season-mismatch', status: 409),
        );
        final result = await container
            .read(costumesControllerProvider('season-1').notifier)
            .setCategory(
              costume: _costume('c-1'),
              categoryId: 'cat-foreign',
              categoryName: 'Foreign',
            );
        expect(result.isLeft(), isTrue);
        await _pumpFrames(tester);
        expect(
          find.text(
            'That category belongs to a different season — pick a category '
            'from this season.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('clearing an un-categorised costume is a no-op (zero calls)', (
      tester,
    ) async {
      await setupContainer(costume: _costume('c-1'));
      await pumpDetail(tester, 'c-1');
      final result = await container
          .read(costumesControllerProvider('season-1').notifier)
          .setCategory(costume: _costume('c-1'), categoryId: null);
      expect(result.isRight(), isTrue);
      // Idempotent no-op: no network call, no command errors.
      expect(repo.setCategoryCalls, 0);
    });

    testWidgets('clearing a categorized costume via the picker', (
      tester,
    ) async {
      // CodeRabbit #4126529985: the no-op test above only covers clear-
      // when-empty. Here the costume STARTS categorized; the "Ohne
      // Kategorie" row must dispatch a REAL clear request (null id,
      // acted-on version) and the cleared overlay holds until the fence.
      await setupContainer(
        costume: _costume(
          'c-1',
          categoryId: 'cat-1',
          categoryName: 'Outerwear',
        ),
        categories: [_category('cat-1')],
      );
      await pumpDetail(tester, 'c-1');
      expect(
        find.byKey(const Key('costume-category-c-1-cat-1')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('costume-category-pick-c-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('costume-category-option-none')));
      await _pumpFrames(tester);
      expect(repo.setCategoryCalls, 1);
      expect(repo.lastSetCategoryId, null);
      expect(repo.lastSetCategoryVersion, 1);
      final overlay = container
          .read(costumesControllerProvider('season-1'))
          .overlays
          .firstWhere((o) => o.id == 'c-1');
      expect(overlay.overlay.categoryId, isNull);
      expect(overlay.overlay.version, 2);
      await _pumpFrames(tester);
      // Optimistic key while the fence holds (projection still at v1).
      expect(
        find.byKey(const Key('overlay-category-c-1-none')),
        findsOneWidget,
      );
    });
  });

  group('command-error copy routing (issue #513)', () {
    test('photo-command failures route to the photo copy, never "costume"', () {
      expect(
        costumeCommandErrorCopy(
          AppLocalizationsEn(),
          const CostumeCommandFailure(
            CostumeCommandSurface.photo,
            ProblemError(code: 'photo.requires_character'),
          ),
        ),
        'Assign the costume to a character before managing photos.',
      );
      expect(
        costumeCommandErrorCopy(
          AppLocalizationsEn(),
          const CostumeCommandFailure(
            CostumeCommandSurface.photo,
            ProblemError(code: 'photo.not-found'),
          ),
        ),
        'The photo could not be saved (photo.not-found).',
      );
      expect(
        costumeCommandErrorCopy(
          AppLocalizationsEn(),
          const CostumeCommandFailure(
            CostumeCommandSurface.photo,
            ProblemError(code: 'photo.forbidden'),
          ),
        ),
        'You need an active costume role in this season to manage photos.',
      );
    });

    test('generic domain.validation from a PHOTO command uses photo copy', () {
      // CodeRabbit #4101353471: the ORIGIN, not the `photo.*` prefix,
      // decides. A concurrent unassign makes the local gate stale; the
      // backend then 422s `domain.validation` for the photo command, which
      // must STILL render the photo copy — never "The costume could not be
      // saved".
      expect(
        costumeCommandErrorCopy(
          AppLocalizationsEn(),
          const CostumeCommandFailure(
            CostumeCommandSurface.photo,
            ProblemError(code: 'domain.validation'),
          ),
        ),
        'The photo could not be saved (domain.validation).',
      );
    });

    test('costume-command codes keep the costume copy', () {
      expect(
        costumeCommandErrorCopy(
          AppLocalizationsEn(),
          const CostumeCommandFailure(
            CostumeCommandSurface.costume,
            ProblemError(code: 'concurrency.version-mismatch'),
          ),
        ),
        'Changed elsewhere — pull to refresh and try again.',
      );
      expect(
        costumeCommandErrorCopy(
          AppLocalizationsEn(),
          const CostumeCommandFailure(
            CostumeCommandSurface.costume,
            ProblemError(code: 'domain.validation'),
          ),
        ),
        'The costume could not be saved (domain.validation).',
      );
    });
  });
}
