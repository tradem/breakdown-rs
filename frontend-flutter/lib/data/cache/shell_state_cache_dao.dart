// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:fpdart/fpdart.dart';

import '../../core/problem_error.dart';
import '../../core/result.dart';
import 'cache_database.dart';
import 'shell_state_cache.dart';

/// One persisted shell-state entry.
class ShellStateEntry {
  const ShellStateEntry({
    required this.key,
    required this.value,
    required this.cachedAt,
  });

  final String key;
  final String value;
  final DateTime cachedAt;
}

/// Data-access object for the [ShellStateRows] key-value table.
///
/// All methods are [Result]-typed; storage failures are values, never
/// throws (AGENTS.md §5) — a corrupt/broken cache must never break shell
/// boot, it degrades to "nothing persisted" via the `Err` branch.
class ShellStateDao {
  const ShellStateDao(this._db);

  final CacheDatabase _db;

  /// Reads the entry for [key], or `null` when none is stored.
  Future<Result<ShellStateEntry?>> read(String key) async {
    try {
      final row = await (_db.select(
        _db.shellStateRows,
      )..where((t) => t.key.equals(key))).getSingleOrNull();
      if (row == null) return const Right(null);
      return Right(
        ShellStateEntry(key: row.key, value: row.value, cachedAt: row.cachedAt),
      );
    } catch (e) {
      return Left(ProblemError(code: 'shell.state_read_failed', detail: '$e'));
    }
  }

  /// Persists [value] under [key] (insert or overwrite), stamped with
  /// [cachedAt].
  Future<Result<void>> upsert({
    required String key,
    required String value,
    required DateTime cachedAt,
  }) async {
    try {
      await _db
          .into(_db.shellStateRows)
          .insertOnConflictUpdate(
            ShellStateRowsCompanion.insert(
              key: key,
              value: value,
              cachedAt: cachedAt,
            ),
          );
      return const Right(null);
    } catch (e) {
      return Left(ProblemError(code: 'shell.state_write_failed', detail: '$e'));
    }
  }

  /// Deletes the entry for [key] (no-op when absent).
  Future<Result<void>> delete(String key) async {
    try {
      await (_db.delete(
        _db.shellStateRows,
      )..where((t) => t.key.equals(key))).go();
      return const Right(null);
    } catch (e) {
      return Left(
        ProblemError(code: 'shell.state_delete_failed', detail: '$e'),
      );
    }
  }
}
