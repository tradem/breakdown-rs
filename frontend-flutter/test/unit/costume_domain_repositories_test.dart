// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)

// Tier-1 unit tests, part 2 (Task 1.6): every repository method Ok AND Err.
// Fake Dio interceptors resolve with wire-serialized DTOs (the generated
// client deserializes `response.data`, so fakes speak the wire form) or
// reject with RFC 9457 problem+json DioExceptions. Cache-untouched-on-
// failure is asserted per collection fetch. No Flutter imports.

import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:one_of/one_of.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';
import 'package:frontend_flutter/data/character_repository.dart';
import 'package:frontend_flutter/data/costume_repository.dart';
import 'package:frontend_flutter/data/photo_repository.dart';
import 'package:frontend_flutter/data/shooting_day_repository.dart';

// --- Fixtures ---------------------------------------------------------------

CostumeView _costume(String id, {int version = 1}) => CostumeView(
  (b) => b
    ..id = id
    ..notes = 'notes'
    ..details.replace(BuiltList<CostumeDetailView>())
    ..photos.replace(BuiltList<CostumePhotoView>())
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version,
);

CharacterView _character(String id) => CharacterView(
  (b) => b
    ..id = id
    ..seasonId = 'season-1'
    ..name = 'Name'
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

ShootingDayView _day(String id) => ShootingDayView(
  (b) => b
    ..id = id
    ..episodeId = 'ep-1'
    ..orderKey = '!'
    ..source_.replace(
      ShootingDaySource((s) => s..oneOf = OneOf.fromValue1(value: 'Manual')),
    )
    ..archived = false
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

/// Serializes a list of views to the wire form the generated client
/// deserializes (`response.data`).
Object _wireList<T>(List<T> views, Serializer<T> serializer) =>
    serializers.serialize(
      BuiltList<T>(views),
      specifiedType: FullType(BuiltList, [FullType(T)]),
    )!;

Object _wire<T>(T view, Serializer<T> serializer) =>
    serializers.serializeWith(serializer, view)!;

// --- Fake transport ---------------------------------------------------------

/// Scriptable interceptor: resolves every request with [respond], or rejects
/// with [problem] (RFC 9457 problem+json, stable `code`).
class _ScriptInterceptor extends Interceptor {
  _ScriptInterceptor({this.respond, this.problem, this.statusCode = 200});

  final Object? Function(RequestOptions options)? respond;
  final String? problem;
  final int statusCode;
  int calls = 0;
  RequestOptions? lastOptions;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    calls++;
    lastOptions = options;
    if (problem != null) {
      handler.reject(
        DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: statusCode,
            data: {'code': problem, 'title': 'err', 'status': statusCode},
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      return;
    }
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: respond?.call(options),
      ),
    );
  }
}

BreakdownApi _api(_ScriptInterceptor i) =>
    BreakdownApi(dio: Dio(), interceptors: [i]);

void _expectLeftCode(Result<Object?> result, String code) {
  expect(result.isLeft(), isTrue, reason: 'expected Left($code)');
  result.fold((l) => expect(l.code, code), (_) => fail('expected Left($code)'));
}

void main() {
  group('CostumeRepository Ok/Err', () {
    test(
      'listBySeason Ok writes the snapshot; Err leaves cache untouched',
      () async {
        final db = CacheDatabase();
        addTearDown(db.close);
        final dao = CostumeCacheDao(db);
        final ok = _ScriptInterceptor(
          respond: (_) => _wireList([_costume('c-1')], CostumeView.serializer),
        );
        final repo = CostumeRepository(_api(ok), dao);
        final res = await repo.listBySeason('s-1');
        expect(res.isRight(), isTrue);
        expect((await dao.readBySeason('s-1')).map((c) => c.id), ['c-1']);

        final err = _ScriptInterceptor(
          problem: 'costume.forbidden',
          statusCode: 403,
        );
        final failing = CostumeRepository(_api(err), dao);
        final left = await failing.listBySeason('s-1');
        _expectLeftCode(left, 'costume.forbidden');
        // Cache untouched on failure (D1): the earlier row survives.
        expect((await dao.readBySeason('s-1')).map((c) => c.id), ['c-1']);
        await db.close();
      },
    );

    test('getAndCache Ok upserts; Err touches nothing', () async {
      final db = CacheDatabase();
      addTearDown(db.close);
      final dao = CostumeCacheDao(db);
      final ok = _ScriptInterceptor(
        respond: (_) => _wire(_costume('c-9'), CostumeView.serializer),
      );
      final repo = CostumeRepository(_api(ok), dao);
      expect((await repo.getAndCache('s-1', 'c-9')).isRight(), isTrue);
      expect(await dao.readById('s-1', 'c-9'), isNotNull);

      final err = _ScriptInterceptor(
        problem: 'costume.not-found',
        statusCode: 404,
      );
      final failing = CostumeRepository(_api(err), dao);
      _expectLeftCode(
        await failing.getAndCache('s-1', 'c-missing'),
        'costume.not-found',
      );
      expect(await dao.readById('s-1', 'c-missing'), isNull);
      await db.close();
    });

    test('create/assign/unassign/addDetail/updateNotes Ok and Err', () async {
      final db = CacheDatabase();
      addTearDown(db.close);
      final dao = CostumeCacheDao(db);
      Object okFor(String path) {
        if (path == '/v1/costumes') {
          return _wire(
            IdVersionResponse(
              (b) => b
                ..id = 'c-new'
                ..version = 1,
            ),
            IdVersionResponse.serializer,
          );
        }
        return 2; // AggregateVersion ack for commands.
      }

      final ok = _ScriptInterceptor(respond: (o) => okFor(o.path));
      final repo = CostumeRepository(_api(ok), dao);
      expect((await repo.createEmpty()).isRight(), isTrue);
      expect(
        (await repo.assign(
          'c-1',
          AssignCostumeRequest(
            (b) => b
              ..characterId = 'ch-1'
              ..version = 1,
          ),
        )).isRight(),
        isTrue,
      );
      expect(
        (await repo.unassign(
          'c-1',
          VersionRequest((b) => b..version = 2),
        )).isRight(),
        isTrue,
      );
      expect(
        (await repo.addDetail(
          'c-1',
          AddCostumeDetailRequest(
            (b) => b
              ..detail.id = 'd-1'
              ..detail.text = 't'
              ..version = 2,
          ),
        )).isRight(),
        isTrue,
      );
      expect(
        (await repo.updateNotes(
          'c-1',
          UpdateCostumeNotesRequest(
            (b) => b
              ..notes = 'n'
              ..version = 2,
          ),
        )).isRight(),
        isTrue,
      );

      final conflict = _ScriptInterceptor(
        problem: 'concurrency.conflict',
        statusCode: 409,
      );
      final failing = CostumeRepository(_api(conflict), dao);
      _expectLeftCode(await failing.createEmpty(), 'concurrency.conflict');
      _expectLeftCode(
        await failing.assign(
          'c-1',
          AssignCostumeRequest(
            (b) => b
              ..characterId = 'ch-1'
              ..version = 1,
          ),
        ),
        'concurrency.conflict',
      );
      _expectLeftCode(
        await failing.unassign('c-1', VersionRequest((b) => b..version = 1)),
        'concurrency.conflict',
      );
      await db.close();
    });
  });

  group('CharacterRepository Ok/Err', () {
    test('listBySeason/create/updateContact/updateMeasurements', () async {
      final db = CacheDatabase();
      addTearDown(db.close);
      final dao = CharacterCacheDao(db);
      final ok = _ScriptInterceptor(
        respond: (o) {
          if (o.path == '/v1/characters' && o.method == 'GET') {
            return _wireList([_character('ch-1')], CharacterView.serializer);
          }
          if (o.path == '/v1/characters' && o.method == 'POST') {
            return _wire(
              IdVersionResponse(
                (b) => b
                  ..id = 'ch-new'
                  ..version = 1,
              ),
              IdVersionResponse.serializer,
            );
          }
          return 2;
        },
      );
      final repo = CharacterRepository(_api(ok), dao);
      expect((await repo.listBySeason('season-1')).isRight(), isTrue);
      expect((await dao.readBySeason('season-1')).map((c) => c.id), ['ch-1']);
      expect(
        (await repo.create(
          CreateCharacterRequest(
            (b) => b
              ..seasonId = 'season-1'
              ..name = 'N'
              ..category = serializers.deserializeWith(
                CharacterCategory.serializer,
                'guest',
              )!,
          ),
        )).isRight(),
        isTrue,
      );
      expect(
        (await repo.updateContact(
          'ch-1',
          buildContactRequest(email: 'x@y.z', phone: null, version: 1),
        )).isRight(),
        isTrue,
      );
      expect(
        (await repo.updateMeasurements(
          'ch-1',
          buildMeasurementsRequest(
            measurements: _character('ch-1').measurements,
            version: 1,
          ),
        )).isRight(),
        isTrue,
      );

      final err = _ScriptInterceptor(
        problem: 'character.not-found',
        statusCode: 404,
      );
      final failing = CharacterRepository(_api(err), dao);
      _expectLeftCode(
        await failing.listBySeason('season-1'),
        'character.not-found',
      );
      // Untouched: the earlier snapshot survives the failed refetch.
      expect((await dao.readBySeason('season-1')).map((c) => c.id), ['ch-1']);
      _expectLeftCode(
        await failing.updateContact(
          'ch-1',
          buildContactRequest(email: null, phone: null, version: 1),
        ),
        'character.not-found',
      );
      await db.close();
    });
  });

  group('ShootingDayRepository Ok/Err', () {
    test('listByEpisode/create/update/archive', () async {
      final db = CacheDatabase();
      addTearDown(db.close);
      final dao = ShootingDayCacheDao(db);
      final ok = _ScriptInterceptor(
        respond: (o) {
          if (o.method == 'GET') {
            return _wireList([_day('d-1')], ShootingDayView.serializer);
          }
          if (o.path.endsWith('/shooting-days') && o.method == 'POST') {
            return _wire(
              IdVersionResponse(
                (b) => b
                  ..id = 'd-new'
                  ..version = 1,
              ),
              IdVersionResponse.serializer,
            );
          }
          return 2;
        },
      );
      final repo = ShootingDayRepository(_api(ok), dao);
      expect((await repo.listByEpisode('ep-1')).isRight(), isTrue);
      expect((await dao.readByEpisodeOrdered('ep-1')).map((d) => d.id), [
        'd-1',
      ]);
      expect(
        (await repo.create(
          'ep-1',
          CreateShootingDayRequest(
            (b) => b
              ..episodeId = 'ep-1'
              ..orderKey = '!'
              ..source_.replace(
                ShootingDaySource(
                  (s) => s..oneOf = OneOf.fromValue1(value: 'Manual'),
                ),
              ),
          ),
        )).isRight(),
        isTrue,
      );
      expect(
        (await repo.update(
          'd-1',
          buildRenameRequest(label: 'Tag', version: 1),
        )).isRight(),
        isTrue,
      );
      expect(
        (await repo.archive(
          'd-1',
          VersionRequest((b) => b..version = 1),
        )).isRight(),
        isTrue,
      );

      final err = _ScriptInterceptor(
        problem: 'concurrency.conflict',
        statusCode: 409,
      );
      final failing = ShootingDayRepository(_api(err), dao);
      _expectLeftCode(
        await failing.listByEpisode('ep-1'),
        'concurrency.conflict',
      );
      expect((await dao.readByEpisodeOrdered('ep-1')).map((d) => d.id), [
        'd-1',
      ]);
      _expectLeftCode(
        await failing.update(
          'd-1',
          buildReorderRequest(orderKey: 'a', version: 1),
        ),
        'concurrency.conflict',
      );
      await db.close();
    });
  });

  group('PhotoRepository Ok/Err', () {
    test('delete Ok; Err maps the problem code', () async {
      final ok = _ScriptInterceptor(respond: (_) => null);
      final repo = PhotoRepository(_api(ok));
      expect((await repo.delete('c-1', 'p-1')).isRight(), isTrue);

      final err = _ScriptInterceptor(
        problem: 'photo.forbidden',
        statusCode: 403,
      );
      _expectLeftCode(
        await PhotoRepository(_api(err)).delete('c-1', 'p-1'),
        'photo.forbidden',
      );
    });

    test('upload rejects unknown content types before the network', () async {
      final ok = _ScriptInterceptor(respond: (_) => null);
      final repo = PhotoRepository(_api(ok));
      final res = await repo.upload(
        'c-1',
        // ignore: avoid_redundant_argument_values (tiny body, never sent)
        Uint8List.fromList([1, 2, 3]),
        'image/bmp',
      );
      _expectLeftCode(res, 'photo.unsupported_media_type');
      expect(ok.calls, 0);
    });
  });
}
