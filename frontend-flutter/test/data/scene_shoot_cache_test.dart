// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark (pi)

// Tier-1 unit tests (`flutter-shoot-day-execution` 1.2): the day-board
// projection cache round-trips every `SceneShootView` field, reproduces the
// server `COALESCE(actual_order, planned_order)` sequence via the snapshot
// ordinal, snapshot-replaces per day, and computes TTL from `cachedAt` only.
// No Flutter imports.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/cache_ttl.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/scene_shoot_cache_dao.dart';

SceneShootView _shoot(
  String id, {
  String dayId = 'day-1',
  String sceneId = 'scene-1',
  String plannedOrder = 'a0',
  String? actualOrder,
  SceneShootStatus status = SceneShootStatus.planned,
  int version = 1,
  List<String> continuityPhotoIds = const [],
  String noteBody = 'note',
}) => SceneShootView(
  (b) => b
    ..id = id
    ..shootingDayId = dayId
    ..sceneId = sceneId
    ..plannedOrder = plannedOrder
    ..actualOrder = actualOrder
    ..status = status
    ..startDt =
        status == SceneShootStatus.inProgress || status == SceneShootStatus.shot
        ? DateTime.utc(2026, 5, 1, 8)
        : null
    ..endDt = status == SceneShootStatus.shot
        ? DateTime.utc(2026, 5, 1, 9)
        : null
    ..notes.replace(
      BuiltList<SerializedNote>([
        SerializedNote(
          (n) => n
            ..id = 'n-$id'
            ..body = noteBody,
        ),
      ]),
    )
    ..continuityPhotoIds.replace(BuiltList<String>(continuityPhotoIds))
    ..updatedAt = DateTime.utc(2026, 5, 1)
    ..version = version,
);

void main() {
  group('SceneShootCacheDao', () {
    late CacheDatabase db;
    late SceneShootCacheDao dao;

    setUp(() {
      db = CacheDatabase(NativeDatabase.memory());
      dao = SceneShootCacheDao(db);
    });

    tearDown(() => db.close());

    test('round-trips every field incl. notes and continuity ids', () async {
      final view = _shoot(
        'ssh-1',
        actualOrder: 'a1',
        status: SceneShootStatus.shot,
        version: 4,
        continuityPhotoIds: ['ph-1', 'ph-2'],
      );
      await dao.applySnapshotForDay('day-1', [view], DateTime.utc(2026, 5, 2));

      final rows = await dao.readByDayOrdered('day-1');
      expect(rows, hasLength(1));
      final back = rows.single;
      expect(back.id, 'ssh-1');
      expect(back.shootingDayId, 'day-1');
      expect(back.sceneId, 'scene-1');
      expect(back.plannedOrder, 'a0');
      expect(back.actualOrder, 'a1');
      expect(back.status, SceneShootStatus.shot);
      expect(back.startDt, DateTime.utc(2026, 5, 1, 8));
      expect(back.endDt, DateTime.utc(2026, 5, 1, 9));
      expect(back.notes.map((n) => n.body), ['note']);
      expect(back.continuityPhotoIds.toList(), ['ph-1', 'ph-2']);
      // Server timestamp preserved; client write time drives TTL only.
      expect(back.updatedAt, DateTime.utc(2026, 5, 1));
      expect(back.version, 4);
    });

    test('reproduces the server order via the snapshot ordinal', () async {
      // Server sequence is Ist-aware (COALESCE(actual, planned)); the cache
      // must reproduce the given order verbatim, not re-sort by any column.
      final views = [
        _shoot('ssh-3', plannedOrder: 'a2'),
        _shoot('ssh-1', plannedOrder: 'a0', actualOrder: 'a0!'),
        _shoot('ssh-2', plannedOrder: 'a1', status: SceneShootStatus.skipped),
      ];
      await dao.applySnapshotForDay('day-1', views, DateTime.utc(2026, 5, 2));

      expect((await dao.readByDayOrdered('day-1')).map((v) => v.id), [
        'ssh-3',
        'ssh-1',
        'ssh-2',
      ]);
    });

    test('snapshot-replace deletes missing ids, keeps other days', () async {
      await dao.applySnapshotForDay('day-1', [
        _shoot('ssh-1'),
        _shoot('ssh-2'),
      ], DateTime.utc(2026, 5, 2));
      await dao.applySnapshotForDay('day-2', [
        _shoot('ssh-9', dayId: 'day-2'),
      ], DateTime.utc(2026, 5, 2));

      await dao.applySnapshotForDay('day-1', [
        _shoot('ssh-2', version: 2),
      ], DateTime.utc(2026, 5, 3));

      expect((await dao.readByDayOrdered('day-1')).map((v) => v.id), ['ssh-2']);
      expect((await dao.readByDayOrdered('day-2')).map((v) => v.id), ['ssh-9']);
    });

    test('upsert preserves the board position of a refetched row', () async {
      await dao.applySnapshotForDay('day-1', [
        _shoot('ssh-1'),
        _shoot('ssh-2'),
      ], DateTime.utc(2026, 5, 2));
      await dao.upsert(
        _shoot('ssh-1', status: SceneShootStatus.inProgress, version: 2),
        DateTime.utc(2026, 5, 3),
      );

      final rows = await dao.readByDayOrdered('day-1');
      expect(rows.map((v) => v.id), ['ssh-1', 'ssh-2']);
      expect(rows.first.status, SceneShootStatus.inProgress);
    });

    test('TTL expires from cachedAt only, empty day is not stale', () async {
      expect(await dao.isDayExpired('day-1', kCacheTtl), isFalse);

      final written = DateTime.utc(2026, 5, 1);
      await dao.applySnapshotForDay('day-1', [_shoot('ssh-1')], written);

      expect(
        await dao.isDayExpired(
          'day-1',
          kCacheTtl,
          clock: Clock.fixed(written.add(const Duration(hours: 1))),
        ),
        isFalse,
      );
      expect(
        await dao.isDayExpired(
          'day-1',
          kCacheTtl,
          clock: Clock.fixed(written.add(const Duration(hours: 25))),
        ),
        isTrue,
      );
    });

    test('clearDay empties only the scoped day', () async {
      await dao.applySnapshotForDay('day-1', [
        _shoot('ssh-1'),
      ], DateTime.utc(2026, 5, 2));
      await dao.applySnapshotForDay('day-2', [
        _shoot('ssh-9', dayId: 'day-2'),
      ], DateTime.utc(2026, 5, 2));

      await dao.clearDay('day-1');

      expect(await dao.readByDayOrdered('day-1'), isEmpty);
      expect((await dao.readByDayOrdered('day-2')).map((v) => v.id), ['ssh-9']);
    });
  });
}
