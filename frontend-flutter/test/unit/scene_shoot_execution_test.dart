// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark (pi)

// Tier-1 unit tests (`flutter-shoot-day-execution` 1.3): every
// `SceneShootRepository` execution command Ok AND Err, the pure
// command-request builders (path-ids-only plan, version echoes), the
// optimistic-edit reducers + version-fence merge, and the Ist-state renderer
// purity (flags/finality come from the read model only — the client never
// derives them). Fake Dio interceptors resolve with wire-serialized DTOs or
// reject with RFC 9457 problem+json DioExceptions. No Flutter imports.

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:one_of/one_of.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/scene_shoot_cache_dao.dart';
import 'package:frontend_flutter/data/scene_shoot_repository.dart';

// --- Fixtures ---------------------------------------------------------------

SceneShootView _shoot(
  String id, {
  String dayId = 'day-1',
  String sceneId = 'scene-1',
  String plannedOrder = 'a0',
  String? actualOrder,
  SceneShootStatus status = SceneShootStatus.planned,
  int version = 1,
}) => SceneShootView(
  (b) => b
    ..id = id
    ..shootingDayId = dayId
    ..sceneId = sceneId
    ..plannedOrder = plannedOrder
    ..actualOrder = actualOrder
    ..status = status
    ..notes.replace(
      BuiltList<SerializedNote>([
        SerializedNote(
          (n) => n
            ..id = 'n-$id'
            ..body = 'body-$id',
        ),
      ]),
    )
    ..continuityPhotoIds.replace(BuiltList<String>(['ph-$id']))
    ..updatedAt = DateTime.utc(2026, 5, 1)
    ..version = version,
);

ShootingDayView _day(String id, {DateTime? wrappedAt}) => ShootingDayView(
  (b) => b
    ..id = id
    ..episodeId = 'ep-1'
    ..orderKey = 'a0'
    ..source_.replace(
      ShootingDaySource((s) => s..oneOf = OneOf.fromValue1(value: 'Manual')),
    )
    ..archived = false
    ..wrappedAt = wrappedAt
    ..updatedAt = DateTime.utc(2026, 5, 1)
    ..version = 1,
);

Object _wire<T>(T view, Serializer<T> serializer) =>
    serializers.serializeWith(serializer, view)!;

Object _wireList<T>(List<T> views, Serializer<T> serializer) =>
    serializers.serialize(
      BuiltList<T>(views),
      specifiedType: FullType(BuiltList, [FullType(T)]),
    )!;

Object _wireStrings(List<String> ids) => serializers.serialize(
  BuiltList<String>(ids),
  specifiedType: const FullType(BuiltList, [FullType(String)]),
)!;

// --- Fake transport ---------------------------------------------------------

/// Scriptable interceptor: resolves every request with [respond], or rejects
/// with [problem] (RFC 9457 problem+json, stable `code`).
class _ScriptInterceptor extends Interceptor {
  _ScriptInterceptor({this.respond, this.problem, this.statusCode = 200});

  final Object? Function(RequestOptions options)? respond;
  final String? problem;
  final int statusCode;
  int calls = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    calls++;
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

BreakdownApi _apiFrom(Interceptor i) =>
    BreakdownApi(dio: Dio(), interceptors: [i]);

/// Scriptable interceptor with an optional per-call parking gate: when
/// [gate] returns a future, the response waits for it (old request parks
/// until the newer one wrote). Used only by the superseded-snapshot test.
class _GatedInterceptor extends Interceptor {
  _GatedInterceptor({required this.gate, required this.respond});

  final Future<void>? Function() gate;
  final Object? Function(bool first) respond;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final first = !_seen;
    _seen = true;
    final wait = gate();
    if (wait == null) {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: respond(first),
        ),
      );
      return;
    }
    wait.then(
      (_) => handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: respond(first),
        ),
      ),
    );
  }

  bool _seen = false;
}

void _expectLeftCode(Result<Object?> result, String code) {
  expect(result.isLeft(), isTrue, reason: 'expected Left($code)');
  result.fold((l) => expect(l.code, code), (_) => fail('expected Left($code)'));
}

/// Every execution command acknowledges with an `AggregateVersion` int,
/// except plan (`IdVersionResponse`) and the two list/get reads.
Object? _okFor(String path, String method) {
  if (method == 'GET' && path.endsWith('/scene-shoots')) {
    return _wireList([_shoot('ssh-1')], SceneShootView.serializer);
  }
  if (method == 'GET' && path.contains('/continuity-photos')) {
    return _wireStrings(['ph-1']);
  }
  if (method == 'GET') {
    return _wire(_shoot('ssh-1'), SceneShootView.serializer);
  }
  if (method == 'POST' && path.endsWith('/scene-shoots')) {
    return _wire(
      IdVersionResponse(
        (b) => b
          ..id = 'ssh-new'
          ..version = 1,
      ),
      IdVersionResponse.serializer,
    );
  }
  return 2; // AggregateVersion ack for commands.
}

Future<void> _exerciseAllCommands(SceneShootRepository repo) async {
  expect(
    (await repo.plan(
      'day-1',
      'scene-1',
      buildPlanSceneShootRequest(plannedOrder: 'a0'),
    )).isRight(),
    isTrue,
  );
  expect(
    (await repo.replan(
      'day-1',
      'scene-1',
      'ssh-1',
      buildReplanSceneShootRequest(plannedOrder: 'a1', version: 1),
    )).isRight(),
    isTrue,
  );
  expect(
    (await repo.start(
      'day-1',
      'scene-1',
      'ssh-1',
      buildStartSceneShootRequest(version: 1),
    )).isRight(),
    isTrue,
  );
  expect(
    (await repo.setActualOrder(
      'day-1',
      'scene-1',
      'ssh-1',
      buildSetActualOrderRequest(actualOrder: 'a0!', version: 2),
    )).isRight(),
    isTrue,
  );
  expect(
    (await repo.finish(
      'day-1',
      'scene-1',
      'ssh-1',
      buildFinishSceneShootRequest(version: 2),
    )).isRight(),
    isTrue,
  );
  expect(
    (await repo.skip(
      'day-1',
      'scene-1',
      'ssh-1',
      buildSkipSceneShootRequest(version: 1),
    )).isRight(),
    isTrue,
  );
  expect(
    (await repo.addNote(
      'day-1',
      'scene-1',
      'ssh-1',
      buildAddSceneShootNoteRequest(body: 'b'),
    )).isRight(),
    isTrue,
  );
  expect(
    (await repo.updateNote(
      'day-1',
      'scene-1',
      'ssh-1',
      'n-ssh-1',
      buildUpdateSceneShootNoteRequest(body: 'b2', version: 3),
    )).isRight(),
    isTrue,
  );
  expect(
    (await repo.removeNote(
      'day-1',
      'scene-1',
      'ssh-1',
      'n-ssh-1',
      buildSceneShootNoteRemoveRequest(version: 3),
    )).isRight(),
    isTrue,
  );
  expect(
    (await repo.linkContinuityPhoto(
      'day-1',
      'scene-1',
      'ssh-1',
      buildLinkContinuityPhotoRequest(photoId: 'ph-1', version: 3),
    )).isRight(),
    isTrue,
  );
  expect(
    (await repo.listContinuityPhotos('day-1', 'scene-1', 'ssh-1')).isRight(),
    isTrue,
  );
  expect(
    (await repo.unlinkContinuityPhoto(
      'day-1',
      'scene-1',
      'ssh-1',
      'ph-1',
      4,
    )).isRight(),
    isTrue,
  );
  expect(
    (await repo.wrap(
      'day-1',
      buildWrapShootingDayRequest(version: 5),
    )).isRight(),
    isTrue,
  );
  // Legacy schedule pair (int acks).
  expect(
    (await repo.schedule(
      'scene-1',
      ScheduleSceneRequest(
        (b) => b
          ..shootingDayId = 'day-1'
          ..version = 1,
      ),
    )).isRight(),
    isTrue,
  );
  expect((await repo.unschedule('scene-1', 'day-1', 1)).isRight(), isTrue);
}

void main() {
  group('SceneShootRepository execution commands Ok/Err', () {
    test('every command Ok on 2xx; 409 surfaces the stable code', () async {
      final db = CacheDatabase();
      addTearDown(db.close);
      final repo = SceneShootRepository(
        _api(_ScriptInterceptor(respond: (o) => _okFor(o.path, o.method))),
        SceneShootCacheDao(db),
      );
      await _exerciseAllCommands(repo);

      final conflict = _ScriptInterceptor(
        problem: 'scene_shoot.version_conflict',
        statusCode: 409,
      );
      final failing = SceneShootRepository(
        _api(conflict),
        SceneShootCacheDao(db),
      );
      // A 409 renders "changed elsewhere — refresh" copy keyed on `code`
      // without auto-retry: the stable code (never `detail`) must survive.
      _expectLeftCode(
        await failing.finish(
          'day-1',
          'scene-1',
          'ssh-1',
          buildFinishSceneShootRequest(version: 2),
        ),
        'scene_shoot.version_conflict',
      );
      _expectLeftCode(
        await failing.setActualOrder(
          'day-1',
          'scene-1',
          'ssh-1',
          buildSetActualOrderRequest(actualOrder: 'a0!', version: 2),
        ),
        'scene_shoot.version_conflict',
      );
      _expectLeftCode(
        await failing.linkContinuityPhoto(
          'day-1',
          'scene-1',
          'ssh-1',
          buildLinkContinuityPhotoRequest(photoId: 'ph-1', version: 3),
        ),
        'scene_shoot.version_conflict',
      );
      _expectLeftCode(
        await failing.wrap('day-1', buildWrapShootingDayRequest(version: 5)),
        'scene_shoot.version_conflict',
      );
      await db.close();
    });

    test(
      '403 denial surfaces the code; report PDFs propagate errors',
      () async {
        final db = CacheDatabase();
        addTearDown(db.close);
        final denied = _ScriptInterceptor(
          problem: 'scene_shoot.forbidden',
          statusCode: 403,
        );
        final repo = SceneShootRepository(_api(denied), SceneShootCacheDao(db));
        _expectLeftCode(
          await repo.start(
            'day-1',
            'scene-1',
            'ssh-1',
            buildStartSceneShootRequest(version: 1),
          ),
          'scene_shoot.forbidden',
        );
        _expectLeftCode(
          await repo.listContinuityPhotos('day-1', 'scene-1', 'ssh-1'),
          'scene_shoot.forbidden',
        );
        // Legacy report/archive endpoints share the same error surface.
        _expectLeftCode(
          await repo.dispoReportPdf('day-1'),
          'scene_shoot.forbidden',
        );
        await db.close();
      },
    );

    test(
      'listByDay Ok writes the snapshot; Err leaves cache untouched',
      () async {
        final db = CacheDatabase();
        addTearDown(db.close);
        final dao = SceneShootCacheDao(db);
        final repo = SceneShootRepository(
          _api(_ScriptInterceptor(respond: (o) => _okFor(o.path, o.method))),
          dao,
        );
        final res = await repo.listByDay('day-1', 'scene-1');
        expect(res.isRight(), isTrue);
        expect((await dao.readByDayOrdered('day-1')).map((v) => v.id), [
          'ssh-1',
        ]);

        final err = _ScriptInterceptor(
          problem: 'scene_shoot.not_found',
          statusCode: 404,
        );
        final failing = SceneShootRepository(_api(err), dao);
        _expectLeftCode(
          await failing.listByDay('day-1', 'scene-1'),
          'scene_shoot.not_found',
        );
        // Cache untouched on failure: the earlier row survives.
        expect((await dao.readByDayOrdered('day-1')).map((v) => v.id), [
          'ssh-1',
        ]);
        await db.close();
      },
    );

    test(
      'superseded listByDay returns rows but never writes the snapshot',
      () async {
        // The initial load (outside the coordinator) completes AFTER a
        // command-triggered refetch: the older snapshot must not replace
        // newer rows nor delete rows the newer snapshot added.
        final db = CacheDatabase();
        addTearDown(db.close);
        final dao = SceneShootCacheDao(db);
        final releaseOld = Completer<void>();
        var parked = false;
        final gate = _GatedInterceptor(
          // The first (older) request parks until the newer one wrote;
          // later requests resolve immediately.
          gate: () {
            if (parked) return null;
            parked = true;
            return releaseOld.future;
          },
          respond: (first) => first
              ? _wireList([_shoot('ssh-old')], SceneShootView.serializer)
              : _wireList([
                  _shoot('ssh-old'),
                  _shoot('ssh-new', version: 2),
                ], SceneShootView.serializer),
        );
        final repo = SceneShootRepository(_apiFrom(gate), dao);
        final old = repo.listByDay('day-1', 'scene-1');
        final fresh = await repo.listByDay('day-1', 'scene-1');
        expect(fresh.isRight(), isTrue);
        expect((await dao.readByDayOrdered('day-1')).map((v) => v.id), [
          'ssh-old',
          'ssh-new',
        ]);
        releaseOld.complete();
        final stale = await old;
        // The superseded call still delivers its rows to the caller…
        expect(stale.isRight(), isTrue);
        // …but the cache keeps the newer snapshot (no replace, no
        // delete-missing of ssh-new).
        expect((await dao.readByDayOrdered('day-1')).map((v) => v.id), [
          'ssh-old',
          'ssh-new',
        ]);
        await db.close();
      },
    );

    test(
      'getAndCache Ok upserts; Err touches nothing; cache helpers',
      () async {
        final db = CacheDatabase();
        addTearDown(db.close);
        final dao = SceneShootCacheDao(db);
        final repo = SceneShootRepository(
          _api(_ScriptInterceptor(respond: (o) => _okFor(o.path, o.method))),
          dao,
        );
        expect(
          (await repo.getAndCache('day-1', 'scene-1', 'ssh-1')).isRight(),
          isTrue,
        );
        expect(await dao.readById('day-1', 'ssh-1'), isNotNull);
        expect((await repo.readCached('day-1')).isRight(), isTrue);
        expect(await repo.isCacheStale('day-1'), isFalse);

        final err = _ScriptInterceptor(
          problem: 'scene_shoot.not_found',
          statusCode: 404,
        );
        final failing = SceneShootRepository(_api(err), dao);
        _expectLeftCode(
          await failing.getAndCache('day-1', 'scene-1', 'ssh-missing'),
          'scene_shoot.not_found',
        );
        expect(await dao.readById('day-1', 'ssh-missing'), isNull);

        expect((await repo.clearCache('day-1')).isRight(), isTrue);
        expect(await dao.readByDayOrdered('day-1'), isEmpty);
        await db.close();
      },
    );
  });

  group('Command-request builders', () {
    test('plan carries path ids only (backend issue #346)', () {
      final req = buildPlanSceneShootRequest(plannedOrder: 'a0');
      expect(req.plannedOrder, 'a0');
      // The wire body holds ONLY `planned_order` — day/scene travel in the
      // path, with no redundant body ids and no mismatch policing.
      final wire = serializers.serializeWith(
        PlanSceneShootRequest.serializer,
        req,
      );
      expect(wire, ['planned_order', 'a0']);
    });

    test('every command echoes the acted-on version', () {
      expect(
        buildReplanSceneShootRequest(plannedOrder: 'a1', version: 3).version,
        3,
      );
      expect(buildStartSceneShootRequest(version: 2).version, 2);
      expect(
        buildSetActualOrderRequest(actualOrder: 'a0!', version: 4).actualOrder,
        'a0!',
      );
      expect(buildFinishSceneShootRequest(version: 5).version, 5);
      expect(buildSkipSceneShootRequest(version: 6).version, 6);
      expect(
        buildUpdateSceneShootNoteRequest(body: 'b', version: 7).version,
        7,
      );
      expect(buildSceneShootNoteRemoveRequest(version: 8).version, 8);
      final link = buildLinkContinuityPhotoRequest(photoId: 'ph-1', version: 9);
      expect(link.photoId, 'ph-1');
      expect(link.version, 9);
      expect(buildWrapShootingDayRequest(version: 10).version, 10);
    });

    test('optional payloads default to absent, never invented', () {
      expect(buildStartSceneShootRequest(version: 1).startDt, isNull);
      expect(buildFinishSceneShootRequest(version: 1).endDt, isNull);
      final note = buildAddSceneShootNoteRequest(body: 'b');
      expect(note.body, 'b');
      expect(note.noteId, isNull);
    });
  });

  group('Optimistic reducers + version fence', () {
    test('status transitions preserve the untouched row fields', () {
      final row = _shoot('ssh-1', version: 2);
      final started = applyStartOptimistic(row);
      expect(started.status, SceneShootStatus.inProgress);
      expect(started.notes, row.notes);
      expect(started.continuityPhotoIds, row.continuityPhotoIds);
      expect(started.version, 2);

      final finished = applyFinishOptimistic(row);
      expect(finished.status, SceneShootStatus.shot);
      expect(finished.plannedOrder, 'a0');

      final skipped = applySkipOptimistic(row);
      expect(skipped.status, SceneShootStatus.skipped);

      expect(applyActualOrderOptimistic(row, 'a0!').actualOrder, 'a0!');
      expect(applyReplanOptimistic(row, 'a1').plannedOrder, 'a1');

      final withNote = applyAddNoteOptimistic(
        row,
        optimisticNotePlaceholder(pendingId: 'pending-3', body: 'b'),
      );
      expect(withNote.notes.map((n) => n.body), ['body-ssh-1', 'b']);
    });

    test('note update swaps the body; remove drops by id', () {
      final row = _shoot('ssh-1', version: 2);
      final edited = applyUpdateNoteOptimistic(row, 'n-ssh-1', 'edited');
      expect(edited.notes.single.body, 'edited');
      expect(edited.status, row.status);
      expect(edited.version, 2);
      final removed = applyRemoveNoteOptimistic(edited, 'n-ssh-1');
      expect(removed.notes, isEmpty);
      expect(removed.continuityPhotoIds, row.continuityPhotoIds);
    });

    test('the fence clears only on version >= acknowledgedVersion', () {
      final projection = _shoot('ssh-1', version: 5);
      expect(
        shouldClearSceneShootOverlay(
          projection: projection,
          acknowledgedVersion: 5,
        ),
        isTrue,
      );
      expect(
        shouldClearSceneShootOverlay(
          projection: _shoot('ssh-1', version: 4),
          acknowledgedVersion: 5,
        ),
        isFalse,
      );
    });

    test('merge keeps stale overlays, drops fenced ones, appends creates', () {
      final projected = [_shoot('ssh-1', version: 2), _shoot('ssh-2')];
      final overlay1 = applyFinishOptimistic(_shoot('ssh-1', version: 2));
      final merged = mergeSceneShootOverlays(
        projected: projected,
        overlays: {
          // Stale projection (2 < 3): the overlay wins until reconcile.
          'ssh-1': (overlay: overlay1, acknowledgedVersion: 3),
          // Create-path overlay absent from the projection: appended.
          'ssh-new': (overlay: _shoot('ssh-new'), acknowledgedVersion: 1),
        },
      );
      expect(merged.map((v) => v.id), ['ssh-1', 'ssh-2', 'ssh-new']);
      expect(merged.first.status, SceneShootStatus.shot);

      final fenced = mergeSceneShootOverlays(
        projected: [_shoot('ssh-1', version: 3)],
        overlays: {'ssh-1': (overlay: overlay1, acknowledgedVersion: 3)},
      );
      expect(fenced.single.version, 3);
      expect(fenced.single.status, SceneShootStatus.planned);

      expect(sceneShootProjectedIds(projected), {'ssh-1', 'ssh-2'});
      expect(sceneShootNotesOf(projected.first).single.body, 'body-ssh-1');
    });
  });

  group('Ist-state renderer purity', () {
    test('finality comes from wrapped_at only', () {
      expect(isShootingDayWrapped(_day('d-1')), isFalse);
      expect(
        isShootingDayWrapped(_day('d-1', wrappedAt: DateTime.utc(2026, 5, 2))),
        isTrue,
      );
    });

    test('flags render from the projection, never derived client-side', () {
      // A finished row keeps its server flags through the merge when no
      // overlay exists; the client invents no moved/missing/reshot state.
      final projected = [
        _shoot('ssh-1', status: SceneShootStatus.shot, version: 4),
        _shoot('ssh-2', status: SceneShootStatus.skipped, version: 4),
      ];
      final merged = mergeSceneShootOverlays(
        projected: projected,
        overlays: {},
      );
      expect(merged[0].status, SceneShootStatus.shot);
      expect(merged[1].status, SceneShootStatus.skipped);
      // Wrapping the day changes affordances, never the shoot rows.
      expect(isShootingDayWrapped(_day('d-1')), isFalse);
      expect(merged.map((v) => v.id), ['ssh-1', 'ssh-2']);
    });
  });
}
