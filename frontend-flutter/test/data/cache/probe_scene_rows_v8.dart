// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

import 'package:drift/drift.dart';

part 'probe_scene_rows_v8.g.dart';

/// v8 mirror of the scene projection table — WITHOUT the additive
/// `source_json` provenance column (issue #538). Same drift shape as
/// `probe_schema_v1.dart`: a standalone GeneratedDatabase at schemaVersion
/// 8 so opening it on an empty file persists the real `user_version = 8`
/// marker; reopening through the app `CacheDatabase` then runs exactly the
/// `from < 9` upgrade branch against the real v8 column set.
class ProbeSceneRowsV8 extends Table {
  @override
  String get tableName => 'scene_cache_rows';
  TextColumn get id => text()();
  TextColumn get episodeId => text()();
  TextColumn get assignedCharacters => text()();
  BoolColumn get isScheduleSet => boolean()();
  TextColumn get location => text().nullable()();
  TextColumn get mood => text().nullable()();
  IntColumn get sceneNumber => integer().nullable()();
  TextColumn get scriptDay => text().nullable()();
  TextColumn get shootingDayIds => text()();
  TextColumn get summary => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get version => integer()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [ProbeSceneRowsV8])
class ProbeDatabaseV8 extends _$ProbeDatabaseV8 {
  ProbeDatabaseV8(super.executor);
  @override
  int get schemaVersion => 8;
}
