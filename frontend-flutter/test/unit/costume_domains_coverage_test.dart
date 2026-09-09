// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)

// Tier-1 coverage tests (Task 8.3): branches the happy-path suites leave
// cold — prepare reduction/tooLarge via the injectable budget seam,
// capture intent extras (generic failure, settings opener, rationale
// provider), DAO TTL/clear/miss paths, photo upload Ok (dispatch-level
// adapter), screen-state row merging, error-copy branches, overlay-store
// bookkeeping. Runs under `flutter test --coverage --branch-coverage`
// (some fixtures need Flutter packages such as flutter_riverpod and
// image_picker); deterministic (fake clocks, no wall-clock).

import 'dart:convert';
import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:one_of/one_of.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/auth/membership_gate.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';
import 'package:frontend_flutter/data/character_repository.dart';
import 'package:frontend_flutter/data/photo_repository.dart';
import 'package:frontend_flutter/data/shooting_day_repository.dart';
import 'package:frontend_flutter/domain/reconciliation/overlay_store.dart';
import 'package:frontend_flutter/features/characters/characters_controller.dart';
import 'package:frontend_flutter/features/characters/characters_state.dart';
import 'package:frontend_flutter/features/costumes/costumes_controller.dart';
import 'package:frontend_flutter/features/costumes/costumes_state.dart';
import 'package:frontend_flutter/features/photos/capture.dart';
import 'package:frontend_flutter/features/photos/prepare.dart';
import 'package:frontend_flutter/features/photos/widgets/photo_gallery.dart';
import 'package:frontend_flutter/features/shooting_days/order_keys.dart';
import 'package:frontend_flutter/features/shooting_days/shooting_days_controller.dart';
import 'package:frontend_flutter/features/shooting_days/shooting_days_state.dart';

CostumeView _costume(String id, {int version = 1}) => CostumeView(
  (b) => b
    ..id = id
    ..notes = 'n'
    ..details.replace(BuiltList<CostumeDetailView>())
    ..photos.replace(BuiltList<CostumePhotoView>())
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version,
);

CharacterView _character(String id) => CharacterView(
  (b) => b
    ..id = id
    ..seasonId = 's-1'
    ..name = 'N'
    ..category = serializers.deserializeWith(
      CharacterCategory.serializer,
      'guest',
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

ShootingDayView _day(String id, {String orderKey = '!'}) => ShootingDayView(
  (b) => b
    ..id = id
    ..episodeId = 'ep-1'
    ..orderKey = orderKey
    ..source_.replace(
      ShootingDaySource((s) => s..oneOf = OneOf.fromValue1(value: 'Manual')),
    )
    ..archived = false
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

Uint8List _png(int size) {
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      image.setPixelRgb(x, y, (x * y) % 256, x % 256, y % 256);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

class _ThrowingPicker extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => throw StateError('boom');
}

class _Overlay implements ReconciliationOverlay {
  const _Overlay(this.id, this.status);

  @override
  final String id;
  @override
  final OverlayStatus status;
  @override
  String? get warning => null;
  @override
  ReconciliationOverlay copyWithStatus({
    OverlayStatus? status,
    String? warning,
    bool clearWarning = false,
  }) => _Overlay(id, status ?? this.status);
}

/// Dio adapter stub capturing dispatch-level headers (interceptors run
/// before Dio computes the content length, so only the adapter observes
/// the final `Content-Length` Dio derives from a Uint8List body).
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.payload);

  final Object? payload;

  String? sentContentType;
  String? sentContentLength;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sentContentType = options.contentType;
    sentContentLength = options.headers[Headers.contentLengthHeader]
        ?.toString();
    return ResponseBody.fromString(
      jsonEncode(payload),
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('prepare budget seam', () {
    test('reduction loop converges under a tight budget', () {
      final image = img.Image(width: 600, height: 600);
      for (var y = 0; y < 600; y++) {
        for (var x = 0; x < 600; x++) {
          image.setPixelRgb(x, y, (x * y) % 256, x % 256, y % 256);
        }
      }
      final bytes = Uint8List.fromList(img.encodeJpg(image));
      final full = prepareImageCore(
        PrepareInput(bytes: bytes, contentType: 'image/jpeg'),
      );
      expect(full, isA<PrepareReady>());
      final fullSize = (full as PrepareReady).bytes.lengthInBytes;
      // A budget below the full size forces at least one reduction
      // iteration (JPEG scales with dimensions); the loop converges.
      final tight = prepareImageCore(
        PrepareInput(
          bytes: bytes,
          contentType: 'image/jpeg',
          maxBytes: (fullSize * 3) ~/ 4,
        ),
      );
      expect(tight, isA<PrepareReady>());
      expect(
        (tight as PrepareReady).bytes.lengthInBytes,
        lessThanOrEqualTo((fullSize * 3) ~/ 4),
      );
    });

    test('impossible budget fails locally with photo_too_large', () {
      final result = prepareImageCore(
        PrepareInput(bytes: _png(8), contentType: 'image/png', maxBytes: 0),
      );
      expect(result, PrepareFailure.tooLarge);
    });

    test('content-type mapping covers all extensions', () {
      expect(contentTypeForExtension('JPG'), 'image/jpeg');
      expect(contentTypeForExtension('jpeg'), 'image/jpeg');
      expect(contentTypeForExtension('.PNG'), 'image/png');
      expect(contentTypeForExtension('webp'), 'image/webp');
      expect(contentTypeForExtension('gif'), isNull);
      expect(contentTypeForExtension(''), isNull);
    });
  });

  group('capture extras', () {
    test('generic picker failure → unavailable', () async {
      final outcome = await runCaptureIntent(
        source: ImageSource.camera,
        picker: _ThrowingPicker(),
        rationaleSeen: true,
        markRationaleSeen: () {},
        showRationale: () async => true,
      );
      expect(outcome, isA<CaptureUnavailable>());
    });

    test('picked/cancelled carry empty copy', () {
      expect(
        captureOutcomeCopy(CapturePicked(XFile.fromData(Uint8List(0)))),
        '',
      );
      expect(captureOutcomeCopy(const CaptureCancelled()), '');
    });

    test('default settings opener fails closed headless', () async {
      expect(await defaultOpenAppSettings(), isFalse);
    });

    test('rationale provider marks seen', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(photoRationaleSeenProvider), isFalse);
      container.read(photoRationaleSeenProvider.notifier).markSeen();
      expect(container.read(photoRationaleSeenProvider), isTrue);
    });
  });

  group('costume snapshot order (ordinal)', () {
    test('readBySeason reproduces snapshot order incl. ties', () async {
      final db = CacheDatabase();
      addTearDown(db.close);
      final dao = CostumeCacheDao(db);
      CostumeView costume(String id) => CostumeView(
        (b) => b
          ..id = id
          ..notes = 'n'
          ..details.replace(BuiltList<CostumeDetailView>())
          ..photos.replace(BuiltList<CostumePhotoView>())
          // Identical timestamps: only the ordinal separates them.
          ..updatedAt = DateTime.utc(2026, 1, 1)
          ..version = 1,
      );
      // Snapshot arrives in server order (updated_at DESC); SQLite must
      // not resurface insertion order instead.
      await dao.applySnapshotForSeason('s-1', [
        costume('c-b'),
        costume('c-a'),
        costume('c-c'),
      ], DateTime.utc(2026, 1, 2));
      expect((await dao.readBySeason('s-1')).map((c) => c.id), [
        'c-b',
        'c-a',
        'c-c',
      ]);
    });

    test('single-row upsert preserves the existing ordinal', () async {
      final db = CacheDatabase();
      addTearDown(db.close);
      final dao = CostumeCacheDao(db);
      CostumeView costume(String id) => CostumeView(
        (b) => b
          ..id = id
          ..notes = 'n'
          ..details.replace(BuiltList<CostumeDetailView>())
          ..photos.replace(BuiltList<CostumePhotoView>())
          ..updatedAt = DateTime.utc(2026, 1, 1)
          ..version = 1,
      );
      await dao.applySnapshotForSeason('s-1', [
        costume('c-1'),
        costume('c-2'),
      ], DateTime.utc(2026, 1, 1));
      // Refetch of one row keeps its list position …
      await dao.upsert('s-1', costume('c-2'), DateTime.utc(2026, 1, 2));
      expect((await dao.readBySeason('s-1')).map((c) => c.id), ['c-1', 'c-2']);
      // … while a brand-new row appends after the season maximum.
      await dao.upsert('s-1', costume('c-9'), DateTime.utc(2026, 1, 2));
      expect((await dao.readBySeason('s-1')).map((c) => c.id), [
        'c-1',
        'c-2',
        'c-9',
      ]);
    });
  });

  group('DAO TTL/clear/miss', () {
    test('costume TTL: empty fresh, expired old, cleared gone', () async {
      final db = CacheDatabase();
      addTearDown(db.close);
      final dao = CostumeCacheDao(db);
      expect(
        await dao.isSeasonExpired(
          's-1',
          const Duration(hours: 24),
          clock: Clock.fixed(DateTime.utc(2026, 2, 1)),
        ),
        isFalse,
      );
      await dao.applySnapshotForSeason('s-1', [
        _costume('c-1'),
      ], DateTime.utc(2026, 1, 1));
      expect(
        await dao.isSeasonExpired(
          's-1',
          const Duration(hours: 24),
          clock: Clock.fixed(DateTime.utc(2026, 1, 3)),
        ),
        isTrue,
      );
      expect(
        await dao.isSeasonExpired(
          's-1',
          const Duration(hours: 24),
          clock: Clock.fixed(DateTime.utc(2026, 1, 1, 12)),
        ),
        isFalse,
      );
      expect(await dao.readById('s-1', 'missing'), isNull);
      await dao.clearSeason('s-1');
      expect(await dao.readBySeason('s-1'), isEmpty);
    });

    test('character/ day DAOs: miss, expiry, clear', () async {
      final db = CacheDatabase();
      addTearDown(db.close);
      final characters = CharacterCacheDao(db);
      final days = ShootingDayCacheDao(db);
      expect(await characters.readById('missing'), isNull);
      expect(await days.readById('missing'), isNull);
      await characters.applySnapshotForSeason('s-1', [
        _character('ch-1'),
      ], DateTime.utc(2026, 1, 1));
      await days.applySnapshotForEpisode('ep-1', [
        _day('d-1'),
      ], DateTime.utc(2026, 1, 1));
      expect(
        await characters.isSeasonExpired(
          's-1',
          const Duration(hours: 24),
          clock: Clock.fixed(DateTime.utc(2026, 3, 1)),
        ),
        isTrue,
      );
      expect(
        await days.isEpisodeExpired(
          'ep-1',
          const Duration(hours: 24),
          clock: Clock.fixed(DateTime.utc(2026, 3, 1)),
        ),
        isTrue,
      );
      await characters.clearSeason('s-1');
      await days.clearEpisode('ep-1');
      expect(await characters.readBySeason('s-1'), isEmpty);
      expect(await days.readByEpisodeOrdered('ep-1'), isEmpty);
    });
  });

  group('photo upload Ok', () {
    test('raw-bytes upload deserializes the PhotoView ack', () async {
      final view = PhotoView(
        (b) => b
          ..id = 'p-1'
          ..binding.replace(
            PhotoBinding(
              (pb) => pb
                ..oneOf = OneOf.fromValue1(
                  value: PhotoBindingOneOf(
                    (o) => o
                      ..costume.replace(
                        PhotoBindingOneOfCostume((c) => c..costumeId = 'c-1'),
                      ),
                  ),
                ),
            ),
          )
          ..contentType = 'image/jpeg'
          ..sizeBytes = 3
          ..version = 1
          ..variants.replace(BuiltList<PhotoVariantView>()),
      );
      final dio = Dio();
      final adapter = _RecordingAdapter(
        serializers.serializeWith(PhotoView.serializer, view),
      );
      dio.httpClientAdapter = adapter;
      final repo = PhotoRepository(BreakdownApi(dio: dio));
      final result = await repo.upload(
        'c-1',
        Uint8List.fromList([1, 2, 3]),
        'image/jpeg',
      );
      expect(result.isRight(), isTrue);
      expect(result.match((_) => '', (v) => v.id), 'p-1');
      // Dispatch-level headers: Dio derives the content length from a
      // Uint8List body automatically (a Stream body would leave it unset
      // and onSendProgress totals broken) with the matching content type.
      expect(adapter.sentContentType, 'image/jpeg');
      expect(adapter.sentContentLength, '3');
    });
  });

  group('screen-state row merging (pure)', () {
    test(
      'costumes: fence-held renders optimistic, passed renders projected',
      () {
        final base = _costume('c-1', version: 1);
        final overlay = CostumeRowOverlay(
          id: 'c-1',
          overlay: applyAssignOptimistic(base, 'ch-9'),
          acknowledgedVersion: 2,
          status: OverlayStatus.reconciling,
        );
        final held = CostumesScreenState(
          projected: const AsyncLoading(),
          cachedRows: [base],
          overlays: [overlay],
          characterNames: const {'ch-9': 'Bea'},
        );
        final rows = held.rows;
        expect(rows.single, isA<OptimisticCostumeRow>());
        expect((rows.single as OptimisticCostumeRow).characterName, 'Bea');
        // Fence passes at version 2 → authoritative row.
        final fresh = _costume('c-1', version: 2);
        final passed = CostumesScreenState(
          projected: const AsyncLoading(),
          cachedRows: [fresh],
          overlays: [overlay],
          characterNames: const {'ch-9': 'Bea'},
        );
        expect(passed.rows.single, isA<ProjectedCostumeRow>());
        // Create-path overlay (id absent) appends.
        final created = CostumesScreenState(
          projected: const AsyncLoading(),
          cachedRows: const [],
          overlays: [
            overlay.copyWithStatus(status: OverlayStatus.acknowledged),
          ],
        );
        expect(created.rows.single, isA<OptimisticCostumeRow>());
        expect(held.notFound, isNull);
      },
    );

    test('characters/shooting states merge + notFound', () {
      const err = ProblemError(code: 'season.not-found', status: 404);
      final characters = CharactersScreenState(
        projected: const AsyncError(err, StackTrace.empty),
        cachedRows: [_character('ch-1')],
        overlays: const [
          CharacterOverlay(id: 'ch-9', status: OverlayStatus.acknowledged),
        ],
      );
      expect(characters.rows, hasLength(2));
      expect(characters.notFound?.code, 'season.not-found');
      expect(characters.namesById['ch-1'], 'N');
      final days = ShootingDaysScreenState(
        projected: const AsyncError(err, StackTrace.empty),
        cachedRows: [_day('d-1')],
        overlays: const [
          ShootingDayOverlay(id: 'd-9', status: OverlayStatus.reconciling),
        ],
      );
      expect(days.rows, hasLength(2));
      expect(days.notFound?.code, 'season.not-found');
    });

    test('overlay store bookkeeping', () {
      expect(
        overlayAdd([
          _Overlay('a', OverlayStatus.acknowledged),
        ], _Overlay('a', OverlayStatus.reconciling)),
        hasLength(1),
      );
      expect(
        overlayMarkAllReconciling([_Overlay('a', OverlayStatus.acknowledged)])
            .single
            .status,
        OverlayStatus.reconciling,
      );
      expect(
        overlayDropProjectedIds(
          [_Overlay('a', OverlayStatus.acknowledged)],
          {'a'},
        ),
        isEmpty,
      );
      expect(
        overlayDropProjectedIds([
          _Overlay('a', OverlayStatus.acknowledged),
        ], {}),
        hasLength(1),
      );
      expect(
        overlayMarkAllStale([
          _Overlay('a', OverlayStatus.acknowledged),
        ], 'w').single.status,
        OverlayStatus.stale,
      );
    });
  });

  group('error-copy branches', () {
    test('costume/character/day/photo copies cover codes', () {
      expect(
        costumeErrorCopy(const ProblemError(code: 'membership.pending')),
        contains('permissions'),
      );
      expect(
        costumeErrorCopy(const ProblemError(code: 'auth.session_required')),
        contains('sign in'),
      );
      expect(
        costumeErrorCopy(const ProblemError(code: 'transport.x')),
        contains('Network'),
      );
      expect(
        costumeErrorCopy(const ProblemError(code: 'costume.unknown_xyz')),
        contains('costume.unknown_xyz'),
      );
      expect(
        characterErrorCopy(
          const ProblemError(code: 'character.unknown_category'),
        ),
        contains('character.unknown_category'),
      );
      expect(
        shootingDayErrorCopy(const ProblemError(code: 'authz.denied')),
        contains('sign in'),
      );
      expect(
        shootingDayErrorCopy(const ProblemError(code: 'transport.x')),
        contains('Network'),
      );
      expect(
        photoErrorCopy(const ProblemError(code: 'transport.x')),
        contains('Network'),
      );
      expect(
        photoErrorCopy(const ProblemError(code: 'photo.mystery')),
        contains('photo.mystery'),
      );
    });

    test('category labels + gate denies', () {
      expect(characterCategoryLabel(_character('x')), 'Guest');
      expect(checkAssignCapability(null), isA<GateDeny>());
      expect(
        (checkPhotoCapability(null) as GateDeny).code,
        'membership.pending',
      );
    });
  });

  group('midpointKey (pure)', () {
    void expectBetween(String lo, String hi, String? mid) {
      final result = midpointKey(lo, hi);
      expect(result, mid);
      if (mid != null) {
        expect(lo.compareTo(mid) < 0, isTrue, reason: '$lo < $mid');
        expect(mid.compareTo(hi) < 0, isTrue, reason: '$mid < $hi');
      }
    }

    test('roomy pairs split in both directions', () {
      expectBetween('a', 'c', 'b');
      expectBetween('a', 'b', 'a!');
      expectBetween('m5', 'm6', 'm5!');
      expectBetween('V', 'Vn', 'VG');
    });

    test('prepend below the first key', () {
      expectBetween('', 'a', 'A');
      expectBetween('', '!', null);
    });

    test('invalid order returns null', () {
      expect(midpointKey('b', 'a'), isNull);
      expect(midpointKey('a', 'a'), isNull);
    });

    test('impossible dense floor returns null', () {
      // Nothing over the alphabet fits strictly inside ('a', 'a!').
      expect(midpointKey('a', 'a!'), isNull);
    });
  });

  group('request builders', () {
    test('reschedule carries version echo', () {
      expect(
        buildRescheduleRequest(date: Date(2026, 5, 1), version: 3).version,
        3,
      );
      expect(
        buildMeasurementsRequest(
          measurements: _character('x').measurements,
          version: 3,
        ).version,
        3,
      );
    });
  });
}
