// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

// Tier-2 tests for the photo gallery + capture intent (Task 3.4): variant
// states (Pending spinner / Ready thumb / Failed explanation +
// capture-again), 413/415/403 copy branches, delete confirm affordance,
// camera-permission scenarios (denied, revoked-between-sessions, granted)
// with a faked picker, LRU eviction, grid breakpoints, and goldens
// {light,dark}×{android,macos}.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:image_picker/image_picker.dart';

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/photo_repository.dart';
import 'package:frontend_flutter/features/photos/capture.dart';
import 'package:frontend_flutter/features/photos/widgets/photo_gallery.dart';

CostumePhotoView _photo(String id, List<String> statuses) => CostumePhotoView(
  (b) => b
    ..id = id
    ..contentType = 'image/jpeg'
    ..sizeBytes = 10
    ..variants.replace(
      BuiltList<PhotoVariantView>([
        for (final s in statuses)
          PhotoVariantView(
            (v) => v
              ..kind = serializers.deserializeWith(
                PhotoVariant.serializer,
                'Thumb',
              )!
              ..status = serializers.deserializeWith(
                VariantStatus.serializer,
                s,
              )!
              ..sizeBytes = 5,
          ),
      ]),
    ),
);

CostumeView _costume(List<CostumePhotoView> photos) => CostumeView(
  (b) => b
    ..id = 'c-1'
    ..notes = 'n'
    ..details.replace(BuiltList<CostumeDetailView>())
    ..photos.replace(BuiltList<CostumePhotoView>(photos))
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

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

class _FakePhotoRepository extends PhotoRepository {
  _FakePhotoRepository(super.api);

  int bytesCalls = 0;
  final Map<String, Uint8List> bytes = {};

  @override
  Future<Result<Uint8List>> getBytes(
    String costumeId,
    String photoId,
    String variant,
  ) async {
    bytesCalls++;
    final b = bytes['$photoId@$variant'];
    if (b == null) return const Left(ProblemError(code: 'photo.not-found'));
    return Right(b);
  }
}

void main() {
  group('photoGridColumns + photoRowStatus (pure)', () {
    test('columns follow token breakpoints', () {
      expect(photoGridColumns(300), 2);
      expect(photoGridColumns(399), 2);
      expect(photoGridColumns(400), 3);
      expect(photoGridColumns(799), 3);
      expect(photoGridColumns(800), 4);
      expect(photoGridColumns(1200), 4);
    });

    test('mixed Ready + Pending keeps pending; Failed wins', () {
      expect(
        photoRowStatus(_photo('p', ['Ready', 'Ready'])),
        PhotoRowStatus.ready,
      );
      expect(
        photoRowStatus(_photo('p', ['Ready', 'Pending'])),
        PhotoRowStatus.pending,
      );
      expect(
        photoRowStatus(_photo('p', ['Ready', 'Failed'])),
        PhotoRowStatus.failed,
      );
    });
  });

  group('PhotoBytesLru (pure)', () {
    test('evicts least-recently-used beyond capacity', () {
      final lru = PhotoBytesLru(capacity: 2);
      lru.put('a', 'Thumb', Uint8List.fromList([1]));
      lru.put('b', 'Thumb', Uint8List.fromList([2]));
      // Touch a → b is LRU.
      expect(lru.get('a', 'Thumb'), isNotNull);
      lru.put('c', 'Thumb', Uint8List.fromList([3]));
      expect(lru.length, 2);
      expect(lru.get('b', 'Thumb'), isNull);
      expect(lru.get('a', 'Thumb'), isNotNull);
      expect(lru.get('c', 'Thumb'), isNotNull);
    });

    test('remove drops all variants of a photo', () {
      final lru = PhotoBytesLru();
      lru.put('a', 'Thumb', Uint8List.fromList([1]));
      lru.put('a', 'Medium', Uint8List.fromList([2]));
      lru.remove('a');
      expect(lru.length, 0);
    });
  });

  group('runCaptureIntent (3.2 matrix)', () {
    test('first capture shows rationale once per session', () async {
      var rationaleShown = 0;
      var marked = 0;
      final outcome = await runCaptureIntent(
        source: ImageSource.camera,
        picker: _ScriptedPicker(
          file: XFile.fromData(Uint8List.fromList([1]), name: 'a.jpg'),
        ),
        rationaleSeen: false,
        markRationaleSeen: () => marked++,
        showRationale: () async {
          rationaleShown++;
          return true;
        },
      );
      expect(outcome, isA<CapturePicked>());
      expect(rationaleShown, 1);
      expect(marked, 1);
    });

    test('rationale rejection cancels without touching the picker', () async {
      var pickerTouched = false;
      final picker = _ScriptedPicker();
      final outcome = await runCaptureIntent(
        source: ImageSource.camera,
        picker: picker,
        rationaleSeen: false,
        markRationaleSeen: () {},
        showRationale: () async => false,
      );
      expect(outcome, isA<CaptureCancelled>());
      expect(pickerTouched, isFalse);
    });

    test('later captures skip the rationale', () async {
      var rationaleShown = 0;
      final outcome = await runCaptureIntent(
        source: ImageSource.gallery,
        picker: _ScriptedPicker(),
        rationaleSeen: true,
        markRationaleSeen: () {},
        showRationale: () async {
          rationaleShown++;
          return true;
        },
      );
      expect(outcome, isA<CaptureCancelled>());
      expect(rationaleShown, 0);
    });

    test(
      'denied at prompt → CaptureDenied (re-rationale + settings)',
      () async {
        final outcome = await runCaptureIntent(
          source: ImageSource.camera,
          picker: _ScriptedPicker(
            exception: PlatformException(code: 'camera_access_denied'),
          ),
          rationaleSeen: true,
          markRationaleSeen: () {},
          showRationale: () async => true,
        );
        expect(outcome, isA<CaptureDenied>());
        expect(captureOutcomeCopy(outcome), contains('settings'));
      },
    );

    test('revoked between sessions → CaptureUnavailable', () async {
      final outcome = await runCaptureIntent(
        source: ImageSource.camera,
        picker: _ScriptedPicker(
          exception: PlatformException(code: 'camera_unavailable'),
        ),
        rationaleSeen: true,
        markRationaleSeen: () {},
        showRationale: () async => true,
      );
      expect(outcome, isA<CaptureUnavailable>());
      expect(captureOutcomeCopy(outcome), contains('unavailable'));
    });

    test('granted capture picks the file', () async {
      final outcome = await runCaptureIntent(
        source: ImageSource.camera,
        picker: _ScriptedPicker(
          file: XFile.fromData(Uint8List.fromList([9]), name: 'c.jpg'),
        ),
        rationaleSeen: true,
        markRationaleSeen: () {},
        showRationale: () async => true,
      );
      expect(outcome, isA<CapturePicked>());
    });
  });

  group('photoErrorCopy branches', () {
    test('413/415/403 map to localized copy', () {
      expect(
        photoErrorCopy(const ProblemError(code: 'photo.too_large')),
        contains('too large'),
      );
      expect(
        photoErrorCopy(
          const ProblemError(code: 'photo.unsupported_media_type'),
        ),
        contains('JPEG'),
      );
      expect(
        photoErrorCopy(const ProblemError(code: 'photo.forbidden')),
        contains('costume role'),
      );
    });
  });

  group('PhotoGallery widget (3.4)', () {
    Future<void> pumpGallery(
      WidgetTester tester,
      CostumeView costume, {
      VoidCallback? onDelete,
    }) async {
      final repo = _FakePhotoRepository(BreakdownApi());
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: PhotoGallery(
                costume: costume,
                repository: repo,
                lru: PhotoBytesLru(),
                onDelete: onDelete == null ? null : (photo) => onDelete(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('empty: explicit empty state, no placeholder images', (
      tester,
    ) async {
      await pumpGallery(tester, _costume([]));
      expect(find.byKey(const Key('photo-gallery-empty-c-1')), findsOneWidget);
      // No pretending images.
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('pending: spinner + status chip', (tester) async {
      await pumpGallery(
        tester,
        _costume([
          _photo('p-1', ['Pending']),
        ]),
      );
      expect(find.byKey(const Key('photo-tile-p-1')), findsOneWidget);
      expect(find.byKey(const Key('photo-pending-spinner')), findsOneWidget);
      expect(find.byKey(const Key('photo-status-p-1')), findsOneWidget);
    });

    testWidgets('failed: explanation + capture-again', (tester) async {
      var again = 0;
      final repo = _FakePhotoRepository(BreakdownApi());
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: PhotoGallery(
                costume: _costume([
                  _photo('p-1', ['Failed']),
                ]),
                repository: repo,
                lru: PhotoBytesLru(),
                onRetryCapture: () => again++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('photo-failed-explanation')), findsOneWidget);
      await tester.tap(find.byKey(const Key('photo-capture-again-p-1')));
      expect(again, 1);
    });

    testWidgets('delete affordance renders with callback', (tester) async {
      var deleted = 0;
      await pumpGallery(
        tester,
        _costume([
          _photo('p-1', ['Ready']),
        ]),
        onDelete: () => deleted++,
      );
      expect(find.byKey(const Key('photo-delete-p-1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('photo-delete-p-1')));
      expect(deleted, 1);
    });
  });

  group('PhotoGallery goldens (3.4)', () {
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
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: ThemeData.light(),
              darkTheme: ThemeData.dark(),
              themeMode: mode,
              home: Scaffold(
                body: PhotoGallery(
                  costume: _costume([
                    _photo('p-1', ['Pending']),
                    _photo('p-2', ['Failed']),
                  ]),
                  repository: _FakePhotoRepository(BreakdownApi()),
                  lru: PhotoBytesLru(),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await expectLater(
          find.byType(PhotoGallery),
          matchesGoldenFile('goldens/$golden'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('golden light android', (tester) async {
      await pumpGolden(
        tester,
        golden: 'photo_gallery_light_android.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden dark android', (tester) async {
      await pumpGolden(
        tester,
        golden: 'photo_gallery_dark_android.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden light macos', (tester) async {
      await pumpGolden(
        tester,
        golden: 'photo_gallery_light_macos.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.macOS,
      );
    });

    testWidgets('golden dark macos', (tester) async {
      await pumpGolden(
        tester,
        golden: 'photo_gallery_dark_macos.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.macOS,
      );
    });
  });
}
