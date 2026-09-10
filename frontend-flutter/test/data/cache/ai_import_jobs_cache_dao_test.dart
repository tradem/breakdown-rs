// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Tier-1 unit tests for the AI-import job cache DAO (`flutter-ai-import`
// task 1.4): merge-with-context upserts, newest-first reads, the bounded
// recent window, the client-local apply-context columns, and clear.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';

AiImportJob _job(
  String id, {
  JobStatus status = JobStatus.pending,
  DateTime? updatedAt,
  String userId = 'user-a',
}) => AiImportJob(
  (b) => b
    ..id = id
    ..userId = userId
    ..status = status
    ..documentKind = DocumentKind.schedule
    ..sourceFormat = SourceFormat.csv
    ..dedupKey = 'dedup-$id'
    ..documentDigest = 'digest-$id'
    ..sourceHandle = 'handle-$id'
    ..retries = 0
    ..maxRetries = 3
    ..createdAt = DateTime.utc(2026, 1, 1)
    ..updatedAt = updatedAt ?? DateTime.utc(2026, 1, 1),
);

void main() {
  late CacheDatabase db;
  late AiImportJobsCacheDao dao;

  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
    dao = AiImportJobsCacheDao(db);
  });

  tearDown(() => db.close());

  test("reads are IDENTITY-SCOPED: a previous user's rows are invisible "
      'to the next sub (review: userId filtering at the query)', () async {
    await dao.upsertAll([
      _job('j1'),
      _job('j2', userId: 'user-b'),
    ], DateTime.utc(2026, 1, 1));
    // Same table, two identities: each read sees only its own rows — a
    // failed/missed sign-out clear can never leak dedupKey/digest rows.
    expect((await dao.readAll('user-a')).map((r) => r.id), ['j1']);
    expect((await dao.readAll('user-b')).map((r) => r.id), ['j2']);
    expect(await dao.readById('j2', 'user-a'), isNull);
    expect((await dao.readById('j2', 'user-b'))!.id, 'j2');
    // The context merge never bridges identities: stamping j2 under
    // user-a is a no-op (the row belongs to user-b).
    await dao.setEpisodeContext(
      'j2',
      userId: 'user-a',
      episodeId: 'ep-x',
      seriesId: 'series-x',
    );
    expect((await dao.readById('j2', 'user-b'))!.episodeId, isNull);
  });

  test('upsertAll inserts rows; a later page MERGES (never deletes)', () async {
    await dao.upsertAll([
      _job('j1'),
      _job('j2'),
      _job('j3'),
    ], DateTime.utc(2026, 1, 1));
    // The newest-first page window only carries j2/j3; a snapshot-delete
    // would evict the remembered j1 — the merge keeps it (task 1.4).
    await dao.upsertAll([
      _job('j2', updatedAt: DateTime.utc(2026, 1, 2)),
      _job('j3'),
    ], DateTime.utc(2026, 1, 2));
    final rows = await dao.readAll('user-a');
    expect(rows.map((r) => r.id), containsAll(['j1', 'j2', 'j3']));
    expect(rows, hasLength(3));
  });

  test('readAll orders newest-first by server updatedAt', () async {
    await dao.upsertAll([
      _job('old', updatedAt: DateTime.utc(2026, 1, 1)),
      _job('new', updatedAt: DateTime.utc(2026, 1, 3)),
      _job('mid', updatedAt: DateTime.utc(2026, 1, 2)),
    ], DateTime.utc(2026, 1, 3));
    final ids = (await dao.readAll('user-a')).map((r) => r.id).toList();
    expect(ids, ['new', 'mid', 'old']);
  });

  test('readRecent bounds the window', () async {
    final jobs = [
      for (var i = 0; i < 10; i++)
        _job(
          'j$i',
          updatedAt: DateTime.utc(2026, 1, 1).add(Duration(hours: i)),
        ),
    ];
    await dao.upsertAll(jobs, DateTime.utc(2026, 1, 2));
    final recent = await dao.readRecent('user-a', limit: 3);
    expect(recent.map((r) => r.id), ['j9', 'j8', 'j7']);
  });

  test(
    'upsertWithEpisodeContext persists the client-local apply context',
    () async {
      await dao.upsertWithEpisodeContext(
        _job('j1'),
        DateTime.utc(2026, 1, 1),
        episodeId: 'ep-1',
        seriesId: 'series-1',
      );
      final row = (await dao.readById('j1', 'user-a'))!;
      expect(row.episodeId, 'ep-1');
      expect(row.seriesId, 'series-1');
      // Round-trips the mirrored DTO fields.
      expect(row.status, JobStatus.pending.name);
      expect(row.documentKind, DocumentKind.schedule.name);
      expect(row.sourceFormat, SourceFormat.csv.name);
    },
  );

  test('upsertAll preserves an existing episode context the list route '
      'does not carry', () async {
    await dao.upsertWithEpisodeContext(
      _job('j1'),
      DateTime.utc(2026, 1, 1),
      episodeId: 'ep-1',
      seriesId: 'series-1',
    );
    // A list refetch (no context on the wire) must NOT wipe the context.
    await dao.upsertAll([
      _job('j1', status: JobStatus.succeeded),
    ], DateTime.utc(2026, 1, 2));
    final row = (await dao.readById('j1', 'user-a'))!;
    expect(row.episodeId, 'ep-1');
    expect(row.seriesId, 'series-1');
    expect(row.status, JobStatus.succeeded.name);
  });

  test('setEpisodeContext backfills a remembered row; a missing row is a '
      'no-op', () async {
    await dao.upsertAll([_job('j1')], DateTime.utc(2026, 1, 1));
    await dao.setEpisodeContext(
      'j1',
      userId: 'user-a',
      episodeId: 'ep-9',
      seriesId: 'series-9',
    );
    expect((await dao.readById('j1', 'user-a'))!.episodeId, 'ep-9');

    // Missing row: no insert, no throw.
    await dao.setEpisodeContext(
      'ghost',
      userId: 'user-a',
      episodeId: 'ep-9',
      seriesId: 'series-9',
    );
    expect(await dao.readById('ghost', 'user-a'), isNull);
  });

  test('strict wire parsers reject unknown future enum values', () {
    expect(jobStatusFromWire('succeeded'), JobStatus.succeeded);
    expect(jobStatusFromWire('superceded_v9'), isNull);
    expect(documentKindFromWire('schedule'), DocumentKind.schedule);
    expect(documentKindFromWire('ledger'), isNull);
    expect(sourceFormatFromWire('plain_text'), SourceFormat.plainText);
    expect(sourceFormatFromWire('rtf'), isNull);
  });

  test('clear wipes every row (sign-out / backend-switch reset)', () async {
    await dao.upsertAll([_job('j1'), _job('j2')], DateTime.utc(2026, 1, 1));
    await dao.clear();
    expect(await dao.readAll('user-a'), isEmpty);
  });
}
