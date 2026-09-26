// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

// Tier-1 data tests for the scene provenance cache column (issue #538, EU
// AI Act Art. 50 substratum): the `SceneCacheRows.sourceJson` wire round-
// trip (absent / `Manual` / `AiExtracted{…}` stored verbatim so future
// variants survive) and the v8 → v9 ADD COLUMN migration against a
// populated real-v8 scene table (guarded with `_tableExists` like the v7
// rebuild so probe/partial installs tolerate the upgrade).

import 'dart:io';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_of/one_of.dart';

import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/domain/ai_provenance.dart';

import 'cache/probe_scene_rows_v8.dart';

SceneView _scene(
  String id, {
  SceneSource? source,
  String episodeId = 'episode-1',
}) => SceneView(
  (b) => b
    ..id = id
    ..episodeId = episodeId
    ..assignedCharacters.replace(const [])
    ..isScheduleSet = false
    ..shootingDayIds.replace(const [])
    // built_value optional field: the builder setter takes the nested
    // builder, exactly like the DAO's read path.
    ..source_ = source?.toBuilder()
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

void main() {
  group('SceneCacheDao provenance round-trip (issue #538)', () {
    late CacheDatabase db;
    late SceneCacheDao dao;

    setUp(() {
      db = CacheDatabase(NativeDatabase.memory());
      dao = SceneCacheDao(db);
    });
    tearDown(() => db.close());

    test(
      'absent / Manual / AiExtracted survive source_json verbatim',
      () async {
        final manual = SceneSource(
          (s) => s..oneOf = OneOf.fromValue1<String>(value: 'Manual'),
        );
        final ai = SceneSource(
          (s) => s
            ..oneOf = OneOf.fromValue2<String, SceneSourceOneOf>(
              value: SceneSourceOneOf(
                (d) => d
                  ..aiExtracted = SceneSourceOneOfAiExtracted(
                    (d2) => d2
                      ..documentId = 'job-1'
                      ..externalRef = 'draft-1'
                      // Honest null: the pipeline measures no per-row
                      // confidence (issue #517) — carried through verbatim,
                      // never fabricated into a placeholder.
                      ..confidence = null,
                  ).toBuilder(),
              ),
            ),
        );
        await dao.applySnapshotForEpisode('episode-1', [
          _scene('s-absent'),
          _scene('s-manual', source: manual),
          _scene('s-ai', source: ai),
        ], DateTime.utc(2026, 1, 1));

        final rows = await dao.readByEpisode('episode-1');
        expect(
          sceneProvenance(rows.firstWhere((v) => v.id == 's-absent').source_),
          AiProvenanceVariant.absent,
        );
        expect(
          sceneProvenance(rows.firstWhere((v) => v.id == 's-manual').source_),
          AiProvenanceVariant.manual,
        );
        final aiBack = rows.firstWhere((v) => v.id == 's-ai');
        expect(
          sceneProvenance(aiBack.source_),
          AiProvenanceVariant.aiExtracted,
        );
        final detail = extractionDetailOf(aiBack.source_!.oneOf);
        expect(detail!.documentId, 'job-1');
        expect(detail.externalRef, 'draft-1');
        expect(detail.confidence, isNull);
      },
    );
  });

  test('v8 → v9: source_json is added without touching the v8 data', () async {
    final dir = await Directory.systemTemp.createTemp('scene-migration-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/cache.db');

    // A real v8 install: the probe GeneratedDatabase persists the file at
    // `user_version = 8` with the scene table in the v8 shape (current
    // columns minus source_json) and one populated witness row.
    final v8 = ProbeDatabaseV8(NativeDatabase(file));
    await v8
        .into(v8.probeSceneRowsV8)
        .insert(
          ProbeSceneRowsV8Companion.insert(
            id: 's-1',
            episodeId: 'episode-1',
            assignedCharacters: '[]',
            isScheduleSet: false,
            shootingDayIds: '[]',
            updatedAt: DateTime.utc(2026, 1, 1),
            version: 1,
            cachedAt: DateTime.utc(2026, 1, 1),
          ),
        );
    await v8.close();

    // Opening through the app database runs ONLY the from == 8 landing of
    // the `from < 9` branch: the guarded ADD COLUMN, the v8 row survives
    // and reads as ABSENT provenance — never as `Manual` (no invented
    // attribution on legacy installs).
    // `db` is closed explicitly before the reopen assertion below, so it is
    // not registered for tear-down (a double close is not the contract we
    // want to exercise).
    final db = CacheDatabase(NativeDatabase(file));
    final rows = await SceneCacheDao(db).readByEpisode('episode-1');
    expect(rows.single.id, 's-1');
    expect(sceneProvenance(rows.single.source_), AiProvenanceVariant.absent);

    // A fresh snapshot applies cleanly on the migrated schema.
    final dao = SceneCacheDao(db);
    final ai = SceneSource(
      (s) => s
        ..oneOf = OneOf.fromValue2<String, SceneSourceOneOf>(
          value: SceneSourceOneOf(
            (d) => d
              ..aiExtracted = SceneSourceOneOfAiExtracted(
                (d2) => d2..documentId = 'job-mig',
              ).toBuilder(),
          ),
        ),
    );
    await dao.applySnapshotForEpisode('episode-1', [
      _scene('s-2', source: ai),
    ], DateTime.utc(2026, 1, 2));

    // Reopen through a FRESH connection before the final provenance
    // assertion: the claim is persistence across a restart, not an
    // in-connection read (the previous version asserted through the still
    // open `db`, which proves nothing about the stored column).
    await db.close();
    final reopened = CacheDatabase(NativeDatabase(file));
    addTearDown(reopened.close);
    final after = await SceneCacheDao(reopened).readByEpisode('episode-1');
    expect(after.single.id, 's-2');
    expect(
      sceneProvenance(after.single.source_),
      AiProvenanceVariant.aiExtracted,
      reason:
          'the AI provenance survived the close/reopen through '
          'source_json',
    );
  });
}
