// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'probe_schema_v1.dart';
import 'probe_schema_v2.dart';

void main() {
  // Task 5.1 — a DTO shape change ships with a Drift migration in the same PR,
  // so the cache never silently drops a field (AGENTS.md §8).
  //
  // Drift cannot run a migration when two GeneratedDatabase instances share one
  // already-open executor, so we use a file-backed DB: open at v1, close, then
  // reopen at v2 on the same file. The v2 open triggers the additive migration
  // and the existing row survives with the new column defaulted.
  test('additive column migration preserves existing rows', () async {
    final file = File(
      '${Directory.systemTemp.path}/probe_migration_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    addTearDown(() => file.deleteSync());

    // 1. App installed at v1: create the schema (table `probe_rows` WITHOUT
    // `archived`) and persist a row.
    final v1 = ProbeDatabaseV1(NativeDatabase(file));
    await v1
        .into(v1.probeRowsV1)
        .insert(ProbeRowsV1Companion.insert(id: 's1', name: 'Spring'));
    await v1.close();

    // 2. App upgraded to v2: reopening the same file triggers the additive
    // migration; the existing row is preserved and the new column round-trips.
    final v2 = ProbeDatabaseV2(NativeDatabase(file));
    final rows = await v2.select(v2.probeRowsV2).get();

    expect(rows, hasLength(1));
    expect(rows.first.id, 's1');
    expect(rows.first.name, 'Spring');
    // The new additive column is present with its default (field not dropped).
    expect(rows.first.archived, isFalse);

    await v2.close();
  });
}
