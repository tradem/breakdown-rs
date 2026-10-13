// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

// Project-scoped fundus cache tests (issue #625, tasks §2.5): the project
// scope cannot leak between projects, the repertoire survives the cache
// round-trip, and TTL staleness is computed from the client-only cachedAt
// with the injectable clock (no wall-clock). No Flutter imports.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/costume_domains_cache_dao.dart';

void main() {
  late CacheDatabase db;
  late FundusCostumeCacheDao dao;

  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
    dao = FundusCostumeCacheDao(db);
  });

  tearDown(() async => db.close());

  final writtenAt = DateTime.utc(2026, 1, 1, 10);
  final freshClock = Clock.fixed(DateTime.utc(2026, 1, 2));
  const ttl = Duration(hours: 24);

  CostumeView costume({
    required String id,
    List<String> repertoire = const ['season-1'],
    String notes = '',
  }) => CostumeView(
    (b) => b
      ..id = id
      ..notes = notes
      ..details.replace(BuiltList<CostumeDetailView>())
      ..photos.replace(BuiltList<CostumePhotoView>())
      ..seasonIds.replace(BuiltList<String>(repertoire))
      ..updatedAt = DateTime.utc(2026, 1, 1)
      ..version = 1,
  );

  test('snapshot-replace is scoped to one project', () async {
    await dao.applySnapshotForProject('project-a', [
      costume(id: 'a1'),
      costume(id: 'a2'),
    ], writtenAt);
    await dao.applySnapshotForProject('project-b', [
      costume(id: 'b1'),
    ], writtenAt);

    // Replacing project-a must not touch project-b.
    await dao.applySnapshotForProject('project-a', [
      costume(id: 'a2'),
    ], writtenAt);

    final a = await dao.readByProjectFresh('project-a', clock: freshClock);
    final b = await dao.readByProjectFresh('project-b', clock: freshClock);
    expect(a.rows.map((c) => c.id), ['a2']);
    expect(b.rows.map((c) => c.id), ['b1']);
  });

  test('repertoire survives the cache round-trip', () async {
    await dao.applySnapshotForProject('project-a', [
      costume(id: 'a1', repertoire: ['s1', 's2']),
    ], writtenAt);
    final rows = (await dao.readByProjectFresh(
      'project-a',
      clock: freshClock,
    )).rows;
    expect(rows.single.seasonIds.toList(), ['s1', 's2']);
  });

  test('read preserves snapshot order', () async {
    await dao.applySnapshotForProject('project-a', [
      costume(id: 'a1'),
      costume(id: 'a2'),
      costume(id: 'a3'),
    ], writtenAt);
    final rows = (await dao.readByProjectFresh(
      'project-a',
      clock: freshClock,
    )).rows;
    expect(rows.map((c) => c.id), ['a1', 'a2', 'a3']);
  });

  test('staleness is TTL-relative from cachedAt only', () async {
    await dao.applySnapshotForProject('project-a', [
      costume(id: 'a1'),
    ], writtenAt);
    final fresh = await dao.readByProjectFresh(
      'project-a',
      ttl: ttl,
      clock: freshClock,
    );
    expect(fresh.stale, isFalse);

    final staleClock = Clock.fixed(writtenAt.add(const Duration(hours: 2)));
    final stale = await dao.readByProjectFresh(
      'project-a',
      ttl: const Duration(hours: 1),
      clock: staleClock,
    );
    expect(stale.stale, isTrue);
  });

  test('clearProject empties only the named project', () async {
    await dao.applySnapshotForProject('project-a', [
      costume(id: 'a1'),
    ], writtenAt);
    await dao.applySnapshotForProject('project-b', [
      costume(id: 'b1'),
    ], writtenAt);
    await dao.clearProject('project-a');
    final a = await dao.readByProjectFresh('project-a', clock: freshClock);
    final b = await dao.readByProjectFresh('project-b', clock: freshClock);
    expect(a.rows, isEmpty);
    expect(b.rows.map((c) => c.id), ['b1']);
  });

  test('empty snapshot deletes the project rows', () async {
    await dao.applySnapshotForProject('project-a', [
      costume(id: 'a1'),
    ], writtenAt);
    await dao.applySnapshotForProject('project-a', const [], writtenAt);
    final a = await dao.readByProjectFresh('project-a', clock: freshClock);
    expect(a.rows, isEmpty);
  });

  test('AI-import draft rows can never surface in the fundus', () async {
    // The fundus reads ONLY `fundus_costume_cache_rows`; an AI-import draft
    // row whose identifiers all carry the query marker must never appear.
    await dao.applySnapshotForProject('project-a', [
      costume(id: 'a1', notes: 'Jacke'),
    ], writtenAt);
    await db
        .into(db.aiImportJobCacheRows)
        .insert(
          AiImportJobCacheRowsCompanion.insert(
            id: 'job-draft',
            userId: 'user-1',
            status: 'succeeded',
            documentKind: 'script',
            sourceFormat: 'plain_text',
            dedupKey: 'draft-fundus-marker',
            documentDigest: 'draft-fundus-marker',
            sourceHandle: 'draft-fundus-marker',
            retries: 0,
            maxRetries: 3,
            createdAt: writtenAt,
            updatedAt: writtenAt,
            cachedAt: writtenAt,
          ),
        );
    final rows = (await dao.readByProjectFresh(
      'project-a',
      clock: freshClock,
    )).rows;
    expect(rows.map((c) => c.id), ['a1']);
    expect(rows.any((c) => c.notes.contains('draft')), isFalse);
  });
}
