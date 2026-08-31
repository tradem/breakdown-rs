// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:drift/drift.dart';

part 'probe_schema_v2.g.dart';

// v2 mirror of the SAME projection table — the `archived` column is an additive
// field added by a DTO-shape change. It must migrate in the same PR (Task 5.1 /
// AGENTS.md §8 — the cache never silently drops a field). The runtime table
// name stays `probe_rows` so the v1→v2 upgrade runs in place.
class ProbeRowsV2 extends Table {
  @override
  String get tableName => 'probe_rows';
  TextColumn get id => text()();
  TextColumn get name => text()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

@DriftDatabase(tables: [ProbeRowsV2])
class ProbeDatabaseV2 extends _$ProbeDatabaseV2 {
  ProbeDatabaseV2(super.executor);
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          // Additive migration only — the cache never drops a field.
          if (from < 2) {
            await m.addColumn(probeRowsV2, probeRowsV2.archived);
            // Drift's `addColumn` emits `ALTER TABLE ... ADD COLUMN archived`
            // WITHOUT a DEFAULT, so pre-existing rows are NULL. Backfill them
            // (this mirrors a real additive-column migration, and is why the
            // column is non-nullable with a client-side default).
            await m.database
                .update(probeRowsV2)
                .write(const ProbeRowsV2Companion(archived: Value(false)));
          }
        },
      );
}
