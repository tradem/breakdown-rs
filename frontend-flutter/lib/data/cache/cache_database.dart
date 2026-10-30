// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'ai_import_cache.dart';
import 'piece_domains_cache.dart';
import 'hierarchy_cache.dart';
import 'scene_shoot_cache.dart';
import 'season_cache.dart';
import 'shell_state_cache.dart';

part 'cache_database.g.dart';

/// The read-projection cache database (Design Decision D1: cache is the single
/// source for screen state).
///
/// Tables mirror projection DTOs only. In production this is opened against a
/// file via [CacheDatabase.connect]; tests open an in-memory instance with the
/// default constructor.
@DriftDatabase(
  tables: [
    SeasonCacheRows,
    BlockCacheRows,
    EpisodeCacheRows,
    SceneCacheRows,
    CostumeCategoryCacheRows,
    PieceCacheRows,
    FundusPieceCacheRows,
    OutfitCacheRows,
    CharacterCacheRows,
    ShootingDayCacheRows,
    SceneShootCacheRows,
    AiImportJobCacheRows,
    ShellStateRows,
  ],
)
class CacheDatabase extends _$CacheDatabase {
  /// Opens an in-memory database by default (used by tests). Production code
  /// passes a file-backed [QueryExecutor] via [CacheDatabase.connect].
  CacheDatabase([QueryExecutor? executor])
    : super(executor ?? NativeDatabase.memory());

  /// Opens the cache against an explicit [QueryExecutor] (file-backed in the
  /// app, in-memory in tests via [NativeDatabase.memory]).
  CacheDatabase.connect(super.executor);

  @override
  int get schemaVersion => 18;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 16) {
        // `separate-piece-and-outfit-domain` (v16): `PieceView` is retired by
        // a clean cut — a `Piece` is a fundus garment without a character
        // binding, an `Outfit` is the character's composed look. The cached
        // piece snapshots therefore describe a wire shape that no longer
        // exists and can NEVER be read again, so they are dropped. This is the
        // one legitimate departure from the "no destructive cache migrations"
        // rule: that rule protects *fields of a living DTO* (a dropped column
        // would silently lose data the app still shows) — here the whole DTO
        // is gone and there is nothing left to preserve. The replacement
        // tables fill on the next TTL snapshot-replace (design D3: the backend
        // is authoritative for existence), so the worst case is one refetch.
        await m.database.customStatement(
          'DROP TABLE IF EXISTS costume_cache_rows',
        );
        await m.database.customStatement(
          'DROP TABLE IF EXISTS fundus_costume_cache_rows',
        );
        if (!await _tableExists(m.database, 'piece_cache_rows')) {
          await m.createTable(pieceCacheRows);
        }
        if (!await _tableExists(m.database, 'fundus_piece_cache_rows')) {
          await m.createTable(fundusPieceCacheRows);
        }
        if (!await _tableExists(m.database, 'outfit_cache_rows')) {
          await m.createTable(outfitCacheRows);
        }
      }
      // Additive migrations for DTO-shape changes land here, in the same PR
      // as the projection DTO change (AGENTS.md §8 / Task 5.1). Each added
      // column uses `m.addColumn(...)` so the cache never silently drops a
      // field. No destructive (drop/rename) migrations are permitted; the
      // backend is authoritative for existence (D3: snapshot-replace).
      assert(from <= to, 'cache schema downgrade is unsupported');
      if (from < 2) {
        // `flutter-hierarchy-navigation` 2.1: hierarchy projection tables
        // (blocks, episodes, scenes, costume_categories mirroring the read
        // DTOs). Fresh tables for existing installs — no data to migrate.
        await m.createTable(blockCacheRows);
        await m.createTable(episodeCacheRows);
        await m.createTable(sceneCacheRows);
        await m.createTable(costumeCategoryCacheRows);
      }
      if (from < 3) {
        // `flutter-piece-domains` 1.1: piece-domain projection tables
        // (pieces, characters, shooting_days). Fresh tables for existing
        // installs — no data to migrate. Photo bytes are memory-cached
        // only, never persisted (design §3).
        if (!await _tableExists(m.database, 'piece_cache_rows')) {
          await m.createTable(pieceCacheRows);
        }
        await m.createTable(characterCacheRows);
        await m.createTable(shootingDayCacheRows);
      }
      // Guarded by `from == 3` (not `< 4`): older databases enter the
      // `from < 3` branch above, which creates the piece table from the
      // CURRENT definition — already including the column — so a second
      // ADD COLUMN would fail with `duplicate column name`. Only a real
      // v3 database (table exists, column missing) needs the ALTER.
      if (from < 5) {
        // `flutter-shoot-day-execution` 1.2: day-board projection table
        // (scene shoots mirroring `SceneShootView`). Fresh table for
        // existing installs — no data to migrate. Photo bytes stay
        // memory-cached only, never persisted (design §3).
        await m.createTable(sceneShootCacheRows);
      }
      if (from < 6) {
        // `flutter-ai-import` 1.4: AI-import job projection table
        // (mirrors `AiImportJob`; carries the client-local persisted
        // apply context columns `episode_id`/`project_id`, design §2.3).
        // Fresh table for existing installs — no data to migrate.
        // NOTE: the table is defined in `ai_import_cache.dart` (no
        // `cache_database` import — a cycle would break drift_dev table
        // discovery); its DAO lives in `ai_import_jobs_cache_dao.dart`.
        await m.createTable(aiImportJobCacheRows);
      }
      if (from == 3) {
        // CodeRabbit review follow-up: snapshot ordinal on the piece rows
        // so `readBySeason` reproduces the server `ORDER BY updated_at
        // DESC` exactly. Plain `m.addColumn` emits `ADD COLUMN ... NOT
        // NULL` without a default, which SQLite rejects on populated v3
        // tables (and would otherwise leave NULLs the non-nullable Dart
        // mapping cannot read) — so the statement carries `DEFAULT 0`
        // explicitly. The next snapshot replaces all rows anyway.
        //
        // Table-guarded (wardrobe split, v16): the v16 branch above drops the
        // retired piece snapshot table, so a database climbing from v3 in
        // one run no longer has it here. The column is irrelevant for the
        // successor piece table, which carries `snapshot_index` from birth.
        if (await _tableExists(m.database, 'costume_cache_rows')) {
          await m.database.customStatement(
            'ALTER TABLE costume_cache_rows '
            'ADD COLUMN snapshot_index INTEGER NOT NULL DEFAULT 0',
          );
        }
      }
      // Issue #423 (v7): the backend OpenAPI contract relaxed the seven
      // `CharacterMeasurements` properties and the `BlockView` date fields
      // from required/non-nullable to nullable (`type: [string, null]`) —
      // unset values arrive as JSON null. The mirrored cache columns must
      // accept null, which SQLite cannot express with an in-place ALTER
      // (NOT NULL cannot be dropped) — drift rebuilds the table via
      // [TableMigration]. Guarded to (a) tables that actually exist and
      // (b) installs that may hold the old NOT NULL definitions — fresh
      // creations (onCreate / the from < 2 / from < 3 branches above) use
      // the CURRENT definitions, already nullable. The next TTL
      // snapshot-replace rewrites all rows anyway.
      if (from < 7) {
        if (await _tableExists(m.database, 'block_cache_rows')) {
          await m.alterTable(TableMigration(blockCacheRows));
        }
        if (await _tableExists(m.database, 'character_cache_rows')) {
          await m.alterTable(TableMigration(characterCacheRows));
        }
      }
      if (from < 9) {
        // Issue #538 (v9): scene provenance on the cache — `SceneView.source`
        // drifted in with #540 and the read surfaces now render it. Plain
        // ADD COLUMN on a NULLABLE text column: no `NOT NULL`/default
        // wrinkle (contrast to the guarded v3 snapshot-index case);
        // existing rows read `source_json = NULL` and the DAO maps null to
        // absent provenance (no invented attribution). The branch targets
        // what the real v8 install meets (scene table at the v8 shape),
        // so it is guarded by (a) the table existing — an upgrade landing
        // on partial/probe markers that lack the scene table has NOTHING
        // to alter (drift's m.addColumn emits a bare ALTER, which fails on
        // a missing table) and (b) COLUMN presence — every earlier create
        // path that ran against the CURRENT definition (fresh onCreate,
        // migration probes that create the table mid-upgrade) already
        // carries the column — a second ALTER would fail with
        // `duplicate column name`.
        if (await _tableExists(m.database, 'scene_cache_rows') &&
            !(await _columnExists(
              m.database,
              'scene_cache_rows',
              'source_json',
            ))) {
          await m.addColumn(sceneCacheRows, sceneCacheRows.sourceJson);
        }
      }
      if (from < 8) {
        // `redesign-app-shell-navigation` 2.2: shell-state key-value table
        // (persisted active-season reference, design D5). Fresh table for
        // existing installs — no data to migrate. The persisted value is
        // only a reference; its projection row is re-validated against the
        // TTL-stamped seasons cache on every boot (TTL-compliant by
        // construction).
        await m.createTable(shellStateRows);
      }
      if (from < 11) {
        // Issue #533 (v11): the season lifecycle flag mirrors
        // `SeasonView.archived` (terminal archive state). Plain ADD COLUMN
        // on a non-nullable column needs an explicit default (SQLite
        // rejects a bare `NOT NULL` on populated tables) — existing rows
        // read `archived = 0` (never archived), the next TTL
        // snapshot-replace fills the authoritative flag. Guarded by table
        // AND column presence, like the v9/v10 branches.
        if (await _tableExists(m.database, 'season_cache_rows') &&
            !(await _columnExists(
              m.database,
              'season_cache_rows',
              'archived',
            ))) {
          await m.database.customStatement(
            'ALTER TABLE season_cache_rows '
            'ADD COLUMN archived BOOLEAN NOT NULL DEFAULT 0',
          );
        }
      }
      if (from < 13) {
        // Issue #599 (v13): the `SeriesId` → `ProjectId` rename completed its
        // wire/storage layer (ADR-035 D1/S1 layer 3, B5). `SeasonView`,
        // `BlockView`, `EpisodeView` and the AI-import apply context now
        // carry `project_id`, so the mirrored cache columns do too.
        //
        // Deliberately **additive, never a rename**: the cache policy above
        // forbids destructive migrations, and the cache is
        // snapshot-replace by design (D3) — the next TTL refresh rewrites
        // every row anyway. An install upgrading from v12 therefore keeps an
        // orphaned `series_id` column and gains a `project_id` one; nothing
        // reads the old column, and the projection snapshot fills the new one
        // on the next fetch. This mirrors the shape of the v9/v10/v12
        // branches (nullable ADD COLUMN) and of v11 (non-nullable ADD COLUMN
        // with an explicit default — SQLite rejects a bare `NOT NULL` on a
        // populated table). Guarded by table AND column presence, so an
        // upgrade that landed on a fresh create path is a no-op.
        for (final table in const [
          'season_cache_rows',
          'block_cache_rows',
          'episode_cache_rows',
        ]) {
          if (await _tableExists(m.database, table) &&
              !(await _columnExists(m.database, table, 'project_id'))) {
            await m.database.customStatement(
              'ALTER TABLE $table ADD COLUMN project_id TEXT NOT NULL DEFAULT \'\'',
            );
          }
        }
        if (await _tableExists(m.database, 'ai_import_job_cache_rows') &&
            !(await _columnExists(
              m.database,
              'ai_import_job_cache_rows',
              'project_id',
            ))) {
          await m.addColumn(
            aiImportJobCacheRows,
            aiImportJobCacheRows.projectId,
          );
        }
      }
      if (from < 15) {
        // `issue-664-ai-import-sse-progress` (v15): the nullable
        // `progressJson` column on the AI import job cache — the serialized
        // generated `AiImportProgress` object. Guarded by table AND column
        // presence (same tolerance as the v13 branch): a fresh-create path
        // already carries the column (a duplicate ADD COLUMN would abort
        // the batch), and a probe DB that emulates a pre-v6 install
        // legitimately has no AI job table yet (its real counterpart was
        // created on the v6 upgrade).
        if (await _tableExists(m.database, 'ai_import_job_cache_rows') &&
            !(await _columnExists(
              m.database,
              'ai_import_job_cache_rows',
              'progress_json',
            ))) {
          await m.addColumn(
            aiImportJobCacheRows,
            aiImportJobCacheRows.progressJson,
          );
        }
      }
      if (from < 17) {
        // Issue #763: the jobs list names each row by the uploaded document
        // and its imported episode(s), so the cache carries the two new
        // projection fields. Additive and nullable — a pre-change row serves
        // `null` (the row keeps its kind/date title and no target) until the
        // authoritative list read refreshes it, never a fabricated name.
        // Guarded by table AND column presence, exactly like the v15 branch.
        if (await _tableExists(m.database, 'ai_import_job_cache_rows')) {
          if (!(await _columnExists(
            m.database,
            'ai_import_job_cache_rows',
            'source_file_name',
          ))) {
            await m.addColumn(
              aiImportJobCacheRows,
              aiImportJobCacheRows.sourceFileName,
            );
          }
          if (!(await _columnExists(
            m.database,
            'ai_import_job_cache_rows',
            'applied_episodes_json',
          ))) {
            await m.addColumn(
              aiImportJobCacheRows,
              aiImportJobCacheRows.appliedEpisodesJson,
            );
          }
        }
      }
      if (from < 18) {
        // Issue #767 (backend): `AiImportJob.decision_telemetry` names what the
        // Decision Model scoring pass did (resolved provider/model, outcome
        // class, failed row count). A projection DTO shape change ships its
        // Drift migration in the same change (AGENTS.md §8), so the cache never
        // silently drops the field on a cached-first paint. Additive and
        // nullable — a pre-change row serves `null` ("no recorded outcome"),
        // which is also what the server reports for a pre-#767 job, so nothing
        // is invented for rows written before this column existed. Guarded by
        // table AND column presence, exactly like the v15/v17 branches.
        if (await _tableExists(m.database, 'ai_import_job_cache_rows') &&
            !(await _columnExists(
              m.database,
              'ai_import_job_cache_rows',
              'decision_telemetry_json',
            ))) {
          await m.addColumn(
            aiImportJobCacheRows,
            aiImportJobCacheRows.decisionTelemetryJson,
          );
        }
      }
    },
  );

  /// Whether `name` exists as a column of `table` (SQLite catalog probe —
  /// the same tolerance as `_tableExists`, resolved per-column so migration
  /// branches targeting a COLUMN never run against a table shape that
  /// already carries it).
  static Future<bool> _columnExists(
    DatabaseConnectionUser db,
    String table,
    String name,
  ) async {
    final rows = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM pragma_table_info(?) WHERE name = ?",
          variables: [Variable.withString(table), Variable.withString(name)],
        )
        .getSingle();
    return rows.read<int>('c') > 0;
  }

  /// Whether `name` exists as a table in the SQLite master catalog.
  /// Migration branches must tolerate probe databases (and partial
  /// installs) that lack a table an earlier version created.
  static Future<bool> _tableExists(
    DatabaseConnectionUser db,
    String name,
  ) async {
    final row = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM sqlite_master WHERE type = 'table' AND name = ?",
          variables: [Variable.withString(name)],
        )
        .getSingle();
    return row.read<int>('c') > 0;
  }
}
