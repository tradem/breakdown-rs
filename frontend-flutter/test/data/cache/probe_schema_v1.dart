// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:drift/drift.dart';

part 'probe_schema_v1.g.dart';

// v1 mirror of a projection table — WITHOUT the additive `archived` column.
class ProbeRowsV1 extends Table {
  @override
  String get tableName => 'probe_rows';
  TextColumn get id => text()();
  TextColumn get name => text()();
}

@DriftDatabase(tables: [ProbeRowsV1])
class ProbeDatabaseV1 extends _$ProbeDatabaseV1 {
  ProbeDatabaseV1(super.executor);
  @override
  int get schemaVersion => 1;
}
