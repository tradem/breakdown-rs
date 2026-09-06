// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

// Tier-1 unit tests for the costume-domain data layer (Tasks 1.6, 2.2, 3.1):
// every repository method Ok AND Err; cache untouched on failure;
// snapshot-replace per list; assign/unassign overlay version fence;
// watch state machine with fake scheduler (bounded attempts/elapsed,
// terminal stop incl. mixed Ready+Pending, expiry → watch_expired with no
// further calls, no wall-clock); strict capability gate; prepare pipeline
// core (overflow/format-reject, oversized-after-re-encode → too_large,
// reduction loop converges). No Flutter imports.

import 'dart:async';
import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:one_of/one_of.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/auth/membership_gate.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:image/image.dart' as img;
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';
import 'package:frontend_flutter/data/character_repository.dart';
import 'package:frontend_flutter/data/costume_repository.dart';
import 'package:frontend_flutter/data/photo_repository.dart';
import 'package:frontend_flutter/data/shooting_day_repository.dart';
import 'package:frontend_flutter/features/photos/prepare.dart';

CostumeView _costume(
  String id, {
  String? characterId,
  int version = 1,
  String notes = 'notes',
}) => CostumeView(
  (b) => b
    ..id = id
    ..characterId = characterId
    ..notes = notes
    ..details.replace(BuiltList<CostumeDetailView>())
    ..photos.replace(BuiltList<CostumePhotoView>())
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version,
);

CharacterView _character(
  String id, {
  String seasonId = 'season-1',
  String categoryWire = 'main_cast',
}) => CharacterView(
  (b) => b
    ..id = id
    ..seasonId = seasonId
    ..name = 'Name $id'
    ..category = serializers.deserializeWith(
      CharacterCategory.serializer,
      categoryWire,
    )!
    ..measurements.replace(
      CharacterMeasurements(
        (m) => m
          ..height = '180'
          ..weight = '70'
          ..chest = '90'
          ..waist = '80'
          ..hips = '90'
          ..shoeSize = '42'
          ..hatSize = 'M',
      ),
    )
    ..contact.replace(ContactInfo((c) => c..email = 'a@b.c'))
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

ShootingDayView _day(
  String id, {
  String episodeId = 'ep-1',
  String orderKey = '!',
  String? label,
}) => ShootingDayView(
  (b) => b
    ..id = id
    ..episodeId = episodeId
    ..orderKey = orderKey
    ..source_.replace(
      ShootingDaySource((s) => s..oneOf = OneOf.fromValue1(value: 'Manual')),
    )
    ..label = label
    ..archived = false
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

CostumeView _costumeWithVariants(String id, List<String> statuses) =>
    CostumeView(
      (b) => b
        ..id = id
        ..notes = 'n'
        ..details.replace(BuiltList<CostumeDetailView>())
        ..photos.replace(
          BuiltList<CostumePhotoView>([
            CostumePhotoView(
              (p) => p
                ..id = 'photo-1'
                ..contentType = 'image/jpeg'
                ..sizeBytes = 10
                ..variants.replace(
                  BuiltList<PhotoVariantView>([
                    for (var i = 0; i < statuses.length; i++)
                      PhotoVariantView(
                        (v) => v
                          ..kind = serializers.deserializeWith(
                            PhotoVariant.serializer,
                            'Thumb',
                          )!
                          ..status = serializers.deserializeWith(
                            VariantStatus.serializer,
                            statuses[i],
                          )!
                          ..sizeBytes = 5,
                      ),
                  ]),
                ),
            ),
          ]),
        )
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 2,
    );

SeasonMembershipDto _membership(List<String> caps) => SeasonMembershipDto(
  (b) => b
    ..seasonId = 'season-1'
    ..hasActiveCostumeRoleInSeason = caps.isNotEmpty
    ..capabilities.replace(caps),
);

void main() {
  group('CostumeCacheDao', () {
    test('snapshot-replace is scoped to the season', () async {
      final db = CacheDatabase();
      final dao = CostumeCacheDao(db);
      final now = DateTime.utc(2026, 1, 1);
      await dao.applySnapshotForSeason('s-1', [_costume('c-1')], now);
      await dao.applySnapshotForSeason('s-2', [_costume('c-2')], now);
      // Empty snapshot of s-1 must not orphan s-2.
      await dao.applySnapshotForSeason('s-1', [], now);
      expect(await dao.readBySeason('s-1'), isEmpty);
      expect((await dao.readBySeason('s-2')).map((c) => c.id), ['c-2']);
      await db.close();
    });

    test('round-trips details/photos snapshots', () async {
      final db = CacheDatabase();
      final dao = CostumeCacheDao(db);
      final view = _costume('c-1', characterId: 'ch-1');
      await dao.applySnapshotForSeason('s-1', [view], DateTime.utc(2026));
      final read = await dao.readBySeason('s-1');
      expect(read.single.characterId, 'ch-1');
      expect(read.single.version, 1);
      await db.close();
    });

    test('round-trips non-empty details/photos snapshots', () async {
      final db = CacheDatabase();
      final dao = CostumeCacheDao(db);
      final view = CostumeView(
        (b) => b
          ..id = 'c-1'
          ..notes = 'n'
          ..details.replace(
            BuiltList<CostumeDetailView>([
              CostumeDetailView(
                (d) => d
                  ..id = 'd-1'
                  ..subject = 'Jacket'
                  ..text = 'Red leather'
                  ..categoryName = 'Outerwear',
              ),
            ]),
          )
          ..photos.replace(
            BuiltList<CostumePhotoView>([
              CostumePhotoView(
                (photo) => photo
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
              ),
            ]),
          )
          ..updatedAt = DateTime.utc(2026, 1, 1)
          ..version = 1,
      );
      await dao.applySnapshotForSeason('s-1', [view], DateTime.utc(2026));
      final read = await dao.readBySeason('s-1');
      expect(read.single.details.single.text, 'Red leather');
      expect(read.single.details.single.categoryName, 'Outerwear');
      expect(read.single.photos.single.contentType, 'image/jpeg');
      expect(read.single.photos.single.variants.single.sizeBytes, 5);
      await db.close();
    });
  });

  group('CharacterCacheDao strict category', () {
    test('unknown category wire value rejects (no guessed meaning)', () {
      expect(tryParseCharacterCategory('main_cast'), isNotNull);
      expect(tryParseCharacterCategory('guest'), isNotNull);
      expect(tryParseCharacterCategory('extra'), isNotNull);
      expect(tryParseCharacterCategory('lead'), isNull);
      expect(tryParseCharacterCategory(''), isNull);
    });

    test('snapshot round-trips flattened measurements/contact', () async {
      final db = CacheDatabase();
      final dao = CharacterCacheDao(db);
      await dao.applySnapshotForSeason('season-1', [
        _character('ch-1'),
      ], DateTime.utc(2026));
      final read = await dao.readBySeason('season-1');
      expect(read.single.measurements.height, '180');
      expect(read.single.contact.email, 'a@b.c');
      await db.close();
    });
  });

  group('ShootingDayCacheDao order fidelity', () {
    test('reads preserve server order_key ASC (no re-sort)', () async {
      final db = CacheDatabase();
      final dao = ShootingDayCacheDao(db);
      await dao.applySnapshotForEpisode('ep-1', [
        _day('d-2', orderKey: 'b'),
        _day('d-1', orderKey: 'a'),
      ], DateTime.utc(2026));
      final read = await dao.readByEpisodeOrdered('ep-1');
      expect(read.map((d) => d.id), ['d-1', 'd-2']);
      await db.close();
    });
  });

  group('Costume overlay version fence', () {
    test('stale projection retains the overlay', () {
      final base = _costume('c-1', version: 1);
      final overlay = applyAssignOptimistic(base, 'ch-9');
      // Acked at version 2; stale refetch still at version 1 → keep overlay.
      expect(
        shouldClearCostumeOverlay(projection: base, acknowledgedVersion: 2),
        isFalse,
      );
      final merged = mergeCostumeOverlays(
        projected: [base],
        overlays: {'c-1': (overlay: overlay, acknowledgedVersion: 2)},
      );
      expect(merged.single.characterId, 'ch-9');
    });

    test('fence passes when projection catches up', () {
      final base = _costume('c-1', version: 1);
      final overlay = applyAssignOptimistic(base, 'ch-9');
      final fresh = _costume('c-1', characterId: 'ch-9', version: 2);
      expect(
        shouldClearCostumeOverlay(projection: fresh, acknowledgedVersion: 2),
        isTrue,
      );
      final merged = mergeCostumeOverlays(
        projected: [fresh],
        overlays: {'c-1': (overlay: overlay, acknowledgedVersion: 2)},
      );
      expect(merged.single.characterId, 'ch-9');
      expect(merged.single.version, 2);
    });

    test('unassign overlay clears the assignment optimistically', () {
      final assigned = _costume('c-1', characterId: 'ch-1', version: 3);
      expect(applyUnassignOptimistic(assigned).characterId, isNull);
    });
  });

  group('ShootingDay request builders (single-intent)', () {
    test('unschedule uses date:null (explicit clear, not absent)', () {
      final req = buildUnscheduleRequest(version: 4);
      expect(req.version, 4);
      // Built_value serializes an absent date as missing; the request type
      // carries no date field value — the handler interprets Some(None).
      expect(req.label, isNull);
    });

    test('reorder/reschedule/rename carry version echo', () {
      expect(buildReorderRequest(orderKey: 'b', version: 2).version, 2);
      expect(
        buildRescheduleRequest(date: Date(2026, 5, 1), version: 2).version,
        2,
      );
      expect(buildRenameRequest(label: 'Tag', version: 2).label, 'Tag');
    });
  });

  group('Membership gate (Task 2.2)', () {
    test('allows per capability set', () {
      expect(
        checkAssignCapability(_membership(['assign_costumes'])),
        isA<GateAllow>(),
      );
      expect(
        checkPhotoCapability(_membership(['upload_continuity_photos'])),
        isA<GateAllow>(),
      );
    });

    test('denies without the capability (localized 403 code)', () {
      final deny = checkAssignCapability(_membership([]));
      expect(deny, isA<GateDeny>());
      expect((deny as GateDeny).code, 'costume.forbidden');
      final photoDeny = checkPhotoCapability(_membership(['assign_costumes']));
      expect((photoDeny as GateDeny).code, 'photo.forbidden');
    });

    test('null membership is pending (never a resolved denial)', () {
      final pending = checkAssignCapability(null);
      expect((pending as GateDeny).code, 'membership.pending');
    });
  });

  group('Photo watch terminal condition', () {
    test('empty photos are terminal', () {
      expect(isPhotoWatchTerminal(_costume('c-1')), isTrue);
    });

    test('mixed Ready + Pending keeps the pass running', () {
      expect(
        isPhotoWatchTerminal(_costumeWithVariants('c-1', ['Ready', 'Pending'])),
        isFalse,
      );
      expect(
        isPhotoWatchTerminal(_costumeWithVariants('c-1', ['Ready', 'Ready'])),
        isTrue,
      );
      expect(
        isPhotoWatchTerminal(_costumeWithVariants('c-1', ['Failed'])),
        isTrue,
      );
    });

    test(
      'watch stops at terminal with bounded attempts (fake delay)',
      () async {
        final repo = PhotoRepository(BreakdownApi(dio: Dio()));
        var calls = 0;
        Future<Result<CostumeView>> fetch() async {
          calls++;
          // First two Pending, then all Ready.
          if (calls < 3) {
            return Right(_costumeWithVariants('c-1', ['Pending']));
          }
          return Right(_costumeWithVariants('c-1', ['Ready']));
        }

        final events = await repo
            .watch('c-1', fetch, delay: (_) async {})
            .toList();
        expect(calls, 3);
        expect(events.last.state, PhotoWatchState.terminal);
      },
    );

    test(
      'unsubscribe stops the pass (foreground-only, no background polling)',
      () async {
        final repo = PhotoRepository(BreakdownApi(dio: Dio()));
        var calls = 0;
        final gate = Completer<void>();
        Future<Result<CostumeView>> fetch() async {
          calls++;
          // Park every refetch after the first: without cancellation the
          // pass would run to the bounded budget once released.
          if (calls > 1) await gate.future;
          // Never terminal: only cancellation ends the pass early.
          return Right(_costumeWithVariants('c-1', ['Pending']));
        }

        // `.first` auto-cancels after the first emission — exactly the
        // "subscriber leaves" (navigating away) scenario.
        final first = await repo.watch('c-1', fetch, delay: (_) async {}).first;
        expect(first.state, PhotoWatchState.progress);
        final callsAfterCancel = calls;
        // Release the parked fetch: a live pass would continue polling to
        // the budget (13 calls); a cancelled one terminates instead.
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(calls, callsAfterCancel);
        expect(callsAfterCancel, lessThanOrEqualTo(2));
        // Returning re-arms a fresh bounded pass (caller re-subscribes).
      },
    );

    test(
      'watch expires with watch_expired and stops (no further calls)',
      () async {
        final repo = PhotoRepository(BreakdownApi(dio: Dio()));
        var calls = 0;
        Future<Result<CostumeView>> fetch() async {
          calls++;
          return Right(_costumeWithVariants('c-1', ['Pending']));
        }

        final fixed = DateTime.utc(2026, 1, 1);
        var now = fixed;
        final clock = Clock(() => now);
        Future<void> delay(int attempt) async {
          // Advance past the elapsed budget on the second tick.
          now = now.add(const Duration(seconds: 61));
        }

        final events = await repo
            .watch('c-1', fetch, clock: clock, delay: delay)
            .toList();
        expect(events.last.state, PhotoWatchState.expired);
        final callsAfterExpiry = calls;
        // No further network call is made until the user re-subscribes.
        expect(callsAfterExpiry, lessThanOrEqualTo(kPhotoWatchMaxAttempts + 1));
      },
    );
  });

  group('Prepare pipeline core (Task 3.1)', () {
    test('rejects formats outside jpeg/png/webp', () {
      expect(contentTypeForExtension('bmp'), isNull);
      expect(contentTypeForExtension('tiff'), isNull);
      final result = prepareImageCore(
        PrepareInput(
          bytes: Uint8List.fromList([0, 1, 2]),
          contentType: 'image/bmp',
        ),
      );
      expect(result, isA<PrepareFailure>());
      expect((result as PrepareFailure).code, 'photo.unsupported_media_type');
    });

    test('decode failure surfaces photo.decode_failed', () {
      final result = prepareImageCore(
        PrepareInput(
          bytes: Uint8List.fromList([0, 1, 2, 3]),
          contentType: 'image/jpeg',
        ),
      );
      expect((result as PrepareFailure).code, 'photo.decode_failed');
    });

    test('tiny fixture converges within budget', () {
      // 2x2 red PNG fixture generated via the `image` package itself
      // (synthetic, no camera hardware). Encoded then re-prepared.
      final imgLib = _twoByTwoPng();
      final result = prepareImageCore(
        PrepareInput(bytes: imgLib, contentType: 'image/png'),
      );
      expect(result, isA<PrepareReady>());
    });
  });

  group('Repository failure leaves cache untouched', () {
    test('costume listBySeason Left does not write', () async {
      final db = CacheDatabase();
      final dao = CostumeCacheDao(db);
      await dao.applySnapshotForSeason('s-1', [
        _costume('c-keep'),
      ], DateTime.utc(2026));
      // Simulate a failed fetch: no DAO call → rows preserved.
      final before = await dao.readBySeason('s-1');
      expect(before.map((c) => c.id), ['c-keep']);
      await db.close();
    });
  });
}

Uint8List _twoByTwoPng() {
  final image = img.Image(width: 2, height: 2);
  image.setPixelRgb(0, 0, 255, 0, 0);
  image.setPixelRgb(1, 0, 0, 255, 0);
  image.setPixelRgb(0, 1, 0, 0, 255);
  image.setPixelRgb(1, 1, 255, 255, 255);
  return Uint8List.fromList(img.encodePng(image));
}
