// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

// Tier-4 integration smoke (Task 8.1, on device/emulator, dev-auth):
// season → costume create + detail → assign to a character → capture
// (picker faked) → upload → thumbnail appears after variant `Ready`.
//
// Runs against scriptable fakes (no backend needed): the device exercises
// the real navigation, AUTHZ-GATE, prepare pipeline (real `Isolate.run`
// downscale of a tiny fixture), upload, watch reconciliation and gallery
// rendering. Run via `dart run integration_test run-tests` against a
// device/emulator; not part of the headless `flutter test` pass.
//
// Issue #370: the `prepareImage` isolate boundary never completes headless
// under `flutter_test`, so the 3-line wrapper has no headless coverage.
// This file is the on-device cover: the smoke below deliberately does NOT
// override `preparePhotoProvider` (production `Isolate.run` path), and the
// dedicated isolate test asserts `defaultPreparePhoto` resolves to
// `PrepareReady` on device.

import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:one_of/one_of.dart';
import 'package:integration_test/integration_test.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:dio/dio.dart';
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
import 'package:frontend_flutter/features/costumes/costumes_controller.dart';
import 'package:frontend_flutter/features/costumes/costumes_screen.dart';
import 'package:frontend_flutter/features/photos/capture.dart';
import 'package:frontend_flutter/features/photos/prepare.dart';

SeasonView _season() => SeasonView(
  (b) => b
    ..id = 'season-1'
    ..number = 1
    ..seriesId = 'series-e2e'
    ..title = 'E2E Season'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

CostumeView _costume(
  String id, {
  String? characterId,
  int version = 1,
  List<CostumePhotoView> photos = const [],
}) => CostumeView(
  (b) => b
    ..id = id
    ..characterId = characterId
    ..notes = 'E2E costume'
    ..details.replace(BuiltList<CostumeDetailView>())
    ..photos.replace(BuiltList<CostumePhotoView>(photos))
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version,
);

CharacterView _character(String id) => CharacterView(
  (b) => b
    ..id = id
    ..seasonId = 'season-1'
    ..name = 'E2E Ada'
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

CostumePhotoView _readyPhoto(String id) => CostumePhotoView(
  (b) => b
    ..id = id
    ..contentType = 'image/jpeg'
    ..sizeBytes = 100
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
            ..sizeBytes = 20,
        ),
      ]),
    ),
);

SeasonMembershipDto _membership() => SeasonMembershipDto(
  (b) => b
    ..seasonId = 'season-1'
    ..hasActiveCostumeRoleInSeason = true
    ..capabilities.replace(['assign_costumes', 'upload_continuity_photos']),
);

/// Tiny valid JPEG fixture (2×2) so the real prepare pipeline converges
/// on device without camera hardware.
Uint8List _tinyJpeg() {
  final image = img.Image(width: 2, height: 2);
  image.setPixelRgb(0, 0, 200, 30, 30);
  return Uint8List.fromList(img.encodeJpg(image));
}

/// Scriptable costume backend: create shells, assign bumps the version,
/// upload records bytes; the projection holder is the source of truth the
/// watch reconciles against.
class _E2eCostumeRepository extends CostumeRepository {
  _E2eCostumeRepository(super.api, super.cache, {required this.rows});

  List<CostumeView> rows;
  int assignCalls = 0;

  @override
  Future<Result<IdVersionResponse>> createEmpty() async {
    final id = 'e2e-costume';
    rows = [...rows, _costume(id)];
    return Right(
      IdVersionResponse(
        (b) => b
          ..id = id
          ..version = 1,
      ),
    );
  }

  @override
  Future<Result<int>> assign(String id, AssignCostumeRequest request) async {
    assignCalls++;
    rows = [
      for (final c in rows)
        if (c.id == id)
          c.rebuild(
            (b) => b
              ..characterId = request.characterId
              ..version = c.version + 1,
          )
        else
          c,
    ];
    return Right(rows.firstWhere((c) => c.id == id).version);
  }
}

class _E2ePhotoRepository extends PhotoRepository {
  _E2ePhotoRepository(super.api, {required this.onUpload});

  final void Function(String costumeId) onUpload;
  int uploadCalls = 0;

  @override
  Future<Result<PhotoView>> upload(
    String costumeId,
    Uint8List bytes,
    String contentType, {
    ProgressCallback? onSendProgress,
  }) async {
    uploadCalls++;
    onUpload(costumeId);
    return Right(
      PhotoView(
        (b) => b
          ..id = 'e2e-photo'
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
                    'Pending',
                  )!
                  ..sizeBytes = bytes.length,
              ),
            ]),
          ),
      ),
    );
  }

  @override
  Future<Result<Uint8List>> getBytes(
    String costumeId,
    String photoId,
    String variant,
  ) async => Right(_tinyJpeg());
}

class _ScriptedPicker extends ImagePicker {
  _ScriptedPicker(this.file);

  final XFile file;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => file;
}

/// Immediate scheduler so no backoff is ever awaited on-device.
class _E2eScheduler extends ReconciliationScheduler {
  const _E2eScheduler();

  @override
  Future<void> tick(int attempt) => Future<void>.value();
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

  testWidgets(
    'Costume domains smoke: create → assign → capture → upload → thumb',
    (tester) async {
      final db = CacheDatabase();
      addTearDown(db.close);
      final costumeRows = <CostumeView>[];
      final repo = _E2eCostumeRepository(
        BreakdownApi(),
        CostumeCacheDao(db),
        rows: costumeRows,
      );
      // Upload flips the projection's photo to `Ready` so the watch
      // terminates and the gallery renders the thumbnail.
      final photos = _E2ePhotoRepository(
        BreakdownApi(),
        onUpload: (costumeId) {
          repo.rows = [
            for (final c in repo.rows)
              if (c.id == costumeId)
                c.rebuild(
                  (b) => b
                    ..photos.replace(
                      BuiltList<CostumePhotoView>([_readyPhoto('e2e-photo')]),
                    )
                    ..version = c.version + 1,
                )
              else
                c,
          ];
        },
      );
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devConfig),
          cacheDatabaseProvider.overrideWithValue(db),
          costumeRepositoryProvider.overrideWithValue(repo),
          costumePhotoRepositoryProvider.overrideWithValue(photos),
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
            (ref) => const _E2eScheduler(),
          ),
          membershipFetchProvider('season-1')
              .overrideWith((ref) async => Right(_membership())),
          imagePickerProvider.overrideWithValue(
            _ScriptedPicker(XFile.fromData(_tinyJpeg(), name: 'capture.jpg')),
          ),
          costumesListFetchProvider('season-1').overrideWith((ref) async {
            final dao = CostumeCacheDao(ref.watch(cacheDatabaseProvider));
            await dao.applySnapshotForSeason(
              'season-1',
              repo.rows,
              DateTime.now().toUtc(),
            );
            return Right(repo.rows);
          }),
          charactersListFetchProvider('season-1')
              .overrideWith((ref) async => Right([_character('ch-1')])),
          costumeCategoriesListFetchProvider('season-1')
              .overrideWith((ref) async => const Right([])),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authSessionControllerProvider.notifier).signIn();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: CostumesScreen(season: _season())),
        ),
      );
      await tester.pumpAndSettle();

      // Create shell → detail chains automatically (D1, no dead-end row).
      await tester.tap(find.byKey(const Key('costume-add-fab')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('costume-detail-e2e-costume')),
        findsOneWidget,
      );

      // Assign to the character (optimistic → projection refresh).
      await tester.tap(
        find.byKey(const Key('assign-costume-e2e-costume-none')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assign-character-ch-1')));
      await tester.pumpAndSettle();
      expect(repo.assignCalls, 1);

      // Capture (picker faked) → prepare (real isolate: no
      // `preparePhotoProvider` override above — production `Isolate.run`)
      // → upload → Ready thumb. `uploadCalls == 1` proves the isolate
      // prepare resolved to `PrepareReady` (upload only runs on that
      // branch); the dedicated isolate test below asserts the boundary
      // directly. Deterministic: `pumpAndSettle` bounds the wait, no
      // wall-clock-gated correctness.
      await tester.tap(
        find.byKey(const Key('photo-capture-camera-e2e-costume')),
      );
      await tester.pumpAndSettle();
      expect(photos.uploadCalls, 1);
      expect(find.byKey(const Key('photo-tile-e2e-photo')), findsOneWidget);
    },
  );

  testWidgets('Prepare isolate boundary resolves on device (issue #370)', (
    tester,
  ) async {
    // Direct `Isolate.run` boundary assertion: plain `await` (the harness
    // bounds the wait — never a wall-clock-gated correctness check, never
    // `Future.delayed`). Headless this future never completes, which is
    // why the wrapper stays uncovered in `flutter test` coverage.
    final prepared = await defaultPreparePhoto(
      PrepareInput(bytes: _tinyJpeg(), contentType: 'image/jpeg'),
    );
    expect(prepared, isA<PrepareReady>());
    final ready = prepared as PrepareReady;
    expect(ready.contentType, 'image/jpeg');
    expect(ready.bytes.lengthInBytes, greaterThan(0));
  });
}
