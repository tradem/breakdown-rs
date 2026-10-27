// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Read-only DAO tests for the OmniSearch season composition (issue #616,
// tasks §2.3): the season scope cannot leak through the hierarchy join,
// cold/unfetched is distinguishable from warm-empty, TTL staleness is
// computed from the client-only cachedAt with the injectable clock (no
// wall-clock), and AI-import draft data can NEVER appear in the search
// universe (task §5.1 regression). No Flutter imports.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:drift/native.dart';
import 'package:one_of/one_of.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/piece_domains_cache_dao.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/omni_search_cache_dao.dart';
import 'package:frontend_flutter/features/omni_search/omni_search_model.dart';

void main() {
  late CacheDatabase db;
  late OmniSearchDao dao;

  setUp(() {
    db = CacheDatabase(NativeDatabase.memory());
    dao = OmniSearchDao(db);
  });

  tearDown(() async => db.close());

  // Deterministic freshness: rows are written at 2026-01-01, the clock
  // advances to 2026-01-02 (inside the 24h TTL) unless the test wants the
  // rows expired.
  final writtenAt = DateTime.utc(2026, 1, 1, 10);
  final nowAt = DateTime.utc(2026, 1, 2);
  const expiredTtl = Duration(hours: 1);
  final freshClock = Clock.fixed(nowAt); // 24h <> 1h → fresh

  test('season scoping: scenes and days of other seasons never leak', () async {
    // Season 1: block b1 → episode e1 → scene s1 (Wohnung) + day d1.
    // Season 2: block b2 → episode e2 → scene s2 (Wohnung) + day d2 —
    // identical naming on purpose: a query leak would surface it.
    await seedHierarchy(db, season: 'season-1', block: 'b1', episode: 'e1');
    await seedHierarchy(db, season: 'season-2', block: 'b2', episode: 'e2');
    await seedScene(
      db,
      episode: 'e1',
      id: 's1',
      sceneNumber: 1,
      summary: 'Wohnung',
    );
    await seedScene(
      db,
      episode: 'e2',
      id: 's2',
      sceneNumber: 1,
      summary: 'Wohnung',
    );
    await seedDay(db, episode: 'e1', id: 'd1', label: 'Wohnungstag');
    await seedDay(db, episode: 'e2', id: 'd2', label: 'Wohnungstag');

    final result = await dao.readSeasonInputs(
      'season-1',
      ttl: const Duration(hours: 24),
      clock: freshClock,
    );

    final inputs = result.fold((e) => throw StateError('$e'), (v) => v);
    expect(inputs.scenes.map((h) => h.scene.id), ['s1']);
    expect(inputs.shootingDays.map((h) => h.day.id), ['d1']);
    // The parent DTOs ride along (deep-link context contract).
    expect(inputs.scenes.single.episode.id, 'e1');
    expect(inputs.scenes.single.block.id, 'b1');
    expect(inputs.shootingDays.single.block.id, 'b1');
  });

  test(
    'scene order: scene_number ASC, unnumbered LAST, episode tie-break',
    () async {
      await seedHierarchy(db, season: 'season-1', block: 'b1', episode: 'e1');
      // ONE snapshot per episode (the DAO is snapshot-replace scoped) — the
      // scenes seed in one call so all of them coexist.
      await seedScenes(db, 'e1', [
        ('s-x', null, 'X'),
        ('s-2', 2, 'Zwei'),
        ('s-1', 1, 'Eins'),
        // Equal numbers in the SAME episode: the scene id is the final
        // stable key (CodeRabbit review — the join has no ORDER BY).
        ('s-b', 1, 'Eins b'),
        ('s-a', 1, 'Eins a'),
      ]);

      final inputs = await readInputs(dao, freshClock);
      expect(inputs.scenes.map((h) => h.scene.id).toList(), [
        's-1',
        's-a',
        's-b',
        's-2',
        's-x',
      ]);
    },
  );

  test(
    'characters and costumes are season-scoped by their own tables',
    () async {
      await seedHierarchy(db, season: 'season-1', block: 'b1', episode: 'e1');
      await seedCharacter(db, id: 'c1', seasonId: 'season-1', name: 'Zoe');
      await seedCharacter(db, id: 'c2', seasonId: 'season-2', name: 'Zoe');
      await seedCostume(
        db,
        season: 'season-1',
        id: 'k1',
        notes: 'Zoe Marineblau',
      );
      await seedCostume(
        db,
        season: 'season-2',
        id: 'k2',
        notes: 'Zoe Marineblau',
      );

      final inputs = await readInputs(dao, freshClock);
      expect(inputs.characters.map((h) => h.character.id), ['c1']);
      expect(inputs.costumes.map((h) => h.costume.id), ['k1']);
    },
  );

  test(
    'cold vs. warm-empty: empty scope with no blocks is "no rows"',
    () async {
      // No data seeded for season-1 at all: the search surface must see the
      // not-yet-fetched signals (zero rows everywhere) — not a zero-match.
      final inputs = await readInputs(dao, freshClock);
      expect(inputs.isEmpty, isTrue);
      expect(inputs.hasHierarchyRows, isFalse);
      expect(inputs.hasCharacterRows, isFalse);
      expect(inputs.hasCostumeRows, isFalse);
    },
  );

  test(
    'warm-empty: existING blocks but no scenes are valid, not cold',
    () async {
      await seedHierarchy(db, season: 'season-1', block: 'b1', episode: 'e1');
      final inputs = await readInputs(dao, freshClock);
      expect(inputs.hasHierarchyRows, isTrue);
      expect(inputs.scenes.isEmpty, isTrue);
    },
  );

  test(
    'staleness: TTL-relative per facet (injectable clock, no wall-clock)',
    () async {
      await seedHierarchy(db, season: 'season-1', block: 'b1', episode: 'e1');
      await seedScene(
        db,
        episode: 'e1',
        id: 's1',
        sceneNumber: 1,
        summary: 'Wohnung',
      );
      await seedCharacter(db, id: 'c1', seasonId: 'season-1', name: 'Zoe');

      // Fresh: all facet verdicts false.
      final fresh = await readInputs(dao, freshClock);
      expect(fresh.facetState(OmniSearchFacet.scene).stale, isFalse);
      expect(fresh.facetState(OmniSearchFacet.character).stale, isFalse);

      // Expired: rows are 2h old, TTL 1h → every involved facet is stale.
      final staleClock = Clock.fixed(writtenAt.add(const Duration(hours: 2)));
      final stale = await dao.readSeasonInputs(
        'season-1',
        ttl: expiredTtl,
        clock: staleClock,
      );
      expect(
        stale
            .fold((e) => throw StateError('$e'), (v) => v)
            .facetState(OmniSearchFacet.scene)
            .stale,
        isTrue,
      );
    },
  );

  test(
    'AI-import drafts can never surface in the search universe (task 5.1)',
    () async {
      await seedHierarchy(db, season: 'season-1', block: 'b1', episode: 'e1');
      // A REAL domain scene the user sees; and an AI-import draft row whose
      // identifiers all contain the exact query would find it if the facet
      // queries ever swept the ai_import tables.
      await seedScene(
        db,
        episode: 'e1',
        id: 's1',
        sceneNumber: 1,
        summary: 'Wohnung',
      );
      await db
          .into(db.aiImportJobCacheRows)
          .insert(
            AiImportJobCacheRowsCompanion.insert(
              id: 'job-draft',
              userId: 'user-1',
              status: 'succeeded',
              documentKind: 'script',
              sourceFormat: 'plain_text',
              dedupKey: 'wohnung-draft-synopsis-marker',
              documentDigest: 'wohnung-draft-synopsis-marker',
              sourceHandle: 'wohnung-draft-synopsis-marker',
              retries: 0,
              maxRetries: 3,
              createdAt: writtenAt,
              updatedAt: writtenAt,
              cachedAt: writtenAt,
            ),
          );

      final inputs = await readInputs(dao, freshClock);
      expect(inputs.scenes.map((h) => h.scene.id), ['s1']);
      // Nothing anywhere in the universe carries the draft marker.
      expect(inputs.isEmpty, isFalse);
      expect(
        inputs.scenes.any(
          (h) =>
              (h.scene.summary ?? '').contains('draft-synopsis-marker') ||
              h.scene.id.contains('draft'),
        ),
        isFalse,
      );
    },
  );

  test('corrupt cache rows decode as Result Left(cache.read_failed) — never a throw', () async {
    // A corrupted stored JSON value throws FormatException at row mapping
    // — the DAO catches and decodes to the season-metrics convention's
    // stable problem code (the same convention the costume repo's
    // readCached path documents for corrupt rows).
    await seedHierarchy(db, season: 'season-1', block: 'b1', episode: 'e1');
    await seedScene(
      db,
      episode: 'e1',
      id: 's1',
      sceneNumber: 1,
      summary: 'Wohnung',
    );
    // Corrupt the scene's stored JSON columns with raw text values.
    await db.customStatement(
      'UPDATE scene_cache_rows SET assigned_characters = ?, shooting_day_ids = ? WHERE id = ?',
      ['not-json', 'not-json', 's1'],
    );
    final result = await dao.readSeasonInputs('season-1', clock: freshClock);
    expect(result.fold((e) => e.code, (_) => null), 'cache.read_failed');
  });
}

// --- helpers -----------------------------------------------------------------

Future<void> seedHierarchy(
  CacheDatabase db, {
  required String season,
  required String block,
  required String episode,
}) async {
  await BlockCacheDao(db).applySnapshotForSeason(season, [
    BlockView(
      (b) => b
        ..id = block
        ..number = 1
        ..seasonId = season
        ..projectId = 'project-1'
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    ),
  ], DateTime.utc(2026, 1, 1, 10));
  await EpisodeCacheDao(db).applySnapshotForBlock(block, [
    EpisodeView(
      (b) => b
        ..id = episode
        ..blockId = block
        ..number = 1
        ..projectId = 'project-1'
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    ),
  ], DateTime.utc(2026, 1, 1, 10));
}

Future<void> seedScene(
  CacheDatabase db, {
  required String episode,
  required String id,
  required int? sceneNumber,
  required String? summary,
}) async {
  await seedScenes(db, episode, [(id, sceneNumber, summary)]);
}

/// One snapshot call per episode: the snapshot-replace replaces the whole
/// episode scene set, so multi-scene tests seed through ONE call.
Future<void> seedScenes(
  CacheDatabase db,
  String episode,
  List<(String id, int? sceneNumber, String? summary)> scenes,
) async {
  await SceneCacheDao(db).applySnapshotForEpisode(episode, [
    for (final (id, sceneNumber, summary) in scenes)
      SceneView(
        (b) => b
          ..id = id
          ..episodeId = episode
          ..sceneNumber = sceneNumber
          ..summary = summary
          ..assignedCharacters.replace(BuiltList<String>())
          ..shootingDayIds.replace(BuiltList<String>())
          ..isScheduleSet = false
          ..updatedAt = DateTime.utc(2026, 1, 1)
          ..version = 1,
      ),
  ], DateTime.utc(2026, 1, 1, 10));
}

Future<void> seedDay(
  CacheDatabase db, {
  required String episode,
  required String id,
  required String? label,
}) async {
  await ShootingDayCacheDao(db).applySnapshotForEpisode(episode, [
    ShootingDayView(
      (b) => b
        ..id = id
        ..episodeId = episode
        ..orderKey = '!0'
        ..source_.replace(
          ShootingDaySource(
            (s) => s..oneOf = OneOf.fromValue1(value: 'Manual'),
          ),
        )
        ..label = label
        ..archived = false
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    ),
  ], DateTime.utc(2026, 1, 1, 10));
}

Future<void> seedCharacter(
  CacheDatabase db, {
  required String id,
  required String seasonId,
  required String name,
}) async {
  await CharacterCacheDao(db).applySnapshotForSeason(seasonId, [
    _character(id: id, seasonId: seasonId, name: name),
  ], DateTime.utc(2026, 1, 1, 10));
}

CharacterView _character({
  required String id,
  required String seasonId,
  required String name,
}) => CharacterView(
  (b) => b
    ..id = id
    ..seasonId = seasonId
    ..name = name
    ..category = serializers.deserializeWith(
      CharacterCategory.serializer,
      'main_cast',
    )!
    ..measurements.replace(CharacterMeasurements((m) => m..height = '180'))
    ..contact.replace(ContactInfo((c) => c..email = 'a@b.c'))
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

Future<void> seedCostume(
  CacheDatabase db, {
  required String season,
  required String id,
  required String notes,
}) async {
  await PieceCacheDao(db).applySnapshotForSeason(season, [
    PieceView(
      (b) => b
        ..name = 'Fundus-Piece'
        ..id = id
        ..notes = notes
        ..details.replace(BuiltList<PieceDetailView>())
        ..photos.replace(BuiltList<PiecePhotoView>())
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    ),
  ], DateTime.utc(2026, 1, 1, 10));
}

Future<OmniSearchInputs> readInputs(OmniSearchDao dao, Clock clock) async {
  final result = await dao.readSeasonInputs(
    'season-1',
    ttl: freshTtl,
    clock: clock,
  );
  return result.fold((e) => throw StateError('$e'), (v) => v);
}

const freshTtl = Duration(hours: 24);
