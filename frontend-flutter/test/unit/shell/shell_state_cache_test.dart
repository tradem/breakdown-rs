// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Tier-1 unit tests for the shell-state store (`redesign-app-shell-navigation`
// task 2.2): a REAL DAO over an in-memory Drift database verifies the
// round-trip; a fault-injecting QueryExecutor wrapper triggers the
// documented `Err` branches deterministically — the fault surfaces INSIDE
// the real DAO's defensive catch, which is exactly the surface that must
// resolve to `Left(shell.state_*_failed)` (same reasoning as
// `costume_domain_cache_faults_test`: a closed in-memory database does not
// reliably produce DAO faults). Headless, deterministic, no Flutter imports.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/shell_state_cache_dao.dart';

final class _InjectedFault implements Exception {
  const _InjectedFault(this.phase);

  final String phase;

  @override
  String toString() => 'InjectedFault($phase)';
}

/// Scriptable [QueryExecutor] wrapper: delegates everything to the real
/// in-memory executor and throws on demand in the selected phase, so the
/// REAL DAO's defensive catch resolves to its documented `Left` code.
class _FaultQueryExecutor implements QueryExecutor {
  _FaultQueryExecutor(this._inner);

  final QueryExecutor _inner;
  bool failSelect = false;
  bool failWrite = false;

  void reset() {
    failSelect = false;
    failWrite = false;
  }

  @override
  SqlDialect get dialect => _inner.dialect;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) => _inner.ensureOpen(user);

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) async {
    if (failSelect) throw const _InjectedFault('select');
    return _inner.runSelect(statement, args);
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    if (failWrite) throw const _InjectedFault('insert');
    return _inner.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async {
    if (failWrite) throw const _InjectedFault('update');
    return _inner.runUpdate(statement, args);
  }

  @override
  Future<int> runDelete(String statement, List<Object?> args) async {
    if (failWrite) throw const _InjectedFault('delete');
    return _inner.runDelete(statement, args);
  }

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _inner.runCustom(statement, args);

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _inner.runBatched(statements);

  @override
  TransactionExecutor beginTransaction() => _inner.beginTransaction();

  @override
  QueryExecutor beginExclusive() => _inner.beginExclusive();

  @override
  Future<void> close() => _inner.close();
}

void main() {
  late CacheDatabase db;
  late ShellStateDao dao;
  const key = 'active_season_id';
  final cachedAt = DateTime.utc(2026, 2, 1, 12);

  setUp(() {
    db = CacheDatabase();
    dao = ShellStateDao(db);
  });

  tearDown(() async => db.close());

  group('ShellStateDao round-trip (real in-memory Drift)', () {
    test('reads null when nothing is stored', () async {
      final res = await dao.read(key);
      expect(res.getRight().toNullable(), isNull);
    });

    test('upsert then read round-trips the value', () async {
      final write = await dao.upsert(
        key: key,
        value: 'season-42',
        cachedAt: cachedAt,
      );
      expect(write.isRight(), isTrue);

      final entry = (await dao.read(key)).getRight().toNullable();
      expect(entry, isNotNull);
      expect(entry!.key, key);
      expect(entry.value, 'season-42');
      // Drift's default int storage round-trips the instant (zone-offset
      // agnostic) — compare moments, not representations.
      expect(
        entry.cachedAt.millisecondsSinceEpoch,
        cachedAt.millisecondsSinceEpoch,
      );
    });

    test('upsert overwrites (insert-on-conflict-update)', () async {
      await dao.upsert(key: key, value: 'season-1', cachedAt: cachedAt);
      await dao.upsert(key: key, value: 'season-2', cachedAt: cachedAt);
      final entry = (await dao.read(key)).getRight().toNullable();
      expect(entry!.value, 'season-2');
    });

    test('other keys are untouched (key scoping)', () async {
      await dao.upsert(key: key, value: 'season-1', cachedAt: cachedAt);
      final other = await dao.read('other_key');
      expect(other.getRight().toNullable(), isNull);
    });

    test('delete removes the entry; deleting absent is a no-op', () async {
      await dao.upsert(key: key, value: 'season-1', cachedAt: cachedAt);
      expect((await dao.delete(key)).isRight(), isTrue);
      expect((await dao.read(key)).getRight().toNullable(), isNull);
      // Idempotent delete.
      expect((await dao.delete(key)).isRight(), isTrue);
    });
  });

  group('ShellStateDao Err branches (executor fault injection)', () {
    late _FaultQueryExecutor executor;
    late ShellStateDao faultDao;

    setUp(() {
      executor = _FaultQueryExecutor(NativeDatabase.memory());
      faultDao = ShellStateDao(CacheDatabase(executor));
    });

    tearDown(() async {
      await executor.close();
    });

    test('read failure → Left(shell.state_read_failed)', () async {
      executor.failSelect = true;
      final res = await faultDao.read(key);
      expect(res.getLeft().toNullable()!.code, 'shell.state_read_failed');
    });

    test('upsert failure → Left(shell.state_write_failed)', () async {
      executor.failWrite = true;
      final res = await faultDao.upsert(
        key: key,
        value: 'season-1',
        cachedAt: cachedAt,
      );
      expect(res.getLeft().toNullable()!.code, 'shell.state_write_failed');
    });

    test('delete failure → Left(shell.state_delete_failed)', () async {
      executor.failWrite = true;
      final res = await faultDao.delete(key);
      expect(res.getLeft().toNullable()!.code, 'shell.state_delete_failed');
    });

    test('failure leaves the store untouched (no partial write)', () async {
      await faultDao.upsert(key: key, value: 'season-1', cachedAt: cachedAt);
      executor.failWrite = true;
      await faultDao.upsert(key: key, value: 'season-2', cachedAt: cachedAt);
      executor.reset();
      final entry = (await faultDao.read(key)).getRight().toNullable();
      expect(entry!.value, 'season-1');
    });
  });
}
