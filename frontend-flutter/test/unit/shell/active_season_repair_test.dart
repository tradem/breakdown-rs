// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-1 unit tests for the dead-anchor repair (issue #817 — C4 of #809).
//
// A persisted active-season reference that a LOADED seasons view does not
// contain is dead state: `activeSeasonResolution` never returned it, but
// nothing evicted it either, so every scope-derived consumer lost its anchor
// until the user cleared app data by hand (a dev data reset is supposed to be
// routine, #810). These tests drive the REAL resolution providers — only the
// list-fetch seam and the two stores are faked:
//
//  - the anchor (`shell_state.active_season_id@<sub>`) is compare-and-removed,
//  - the persisted per-season block scopes of a gone season are removed,
//  - nothing is evicted while the fetch is loading or failed,
//  - a fresh pick that lands after the stale read survives,
//  - session scoping holds (identity B never deletes identity A's document).
//
// Deterministic: in-memory Drift, a fixed clock, and bounded event-loop turns
// (no wall-clock budgets, no sleeps — AGENTS.md §6).

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:fpdart/fpdart.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/auth/active_block_store.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/cache/shell_state_cache_dao.dart';
import 'package:frontend_flutter/features/shell/active_season_store.dart';
import 'package:frontend_flutter/src/network/api_client.dart';

const _offline = ProblemError(code: 'transport.connectionError');

SeasonView _season(String id, {int number = 1, String? title}) => SeasonView(
  (b) => b
    ..archived = false
    ..id = id
    ..number = number
    ..projectId = 'series-1'
    ..title = title
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

/// In-memory [FlutterSecureStoragePlatform] double backing the persisted
/// per-season block scopes (issue #382) in these tests.
class FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};

  /// Fails reads and writes (whole store unavailable).
  bool failAll = false;

  /// Fails only writes — the "document readable, eviction cannot be persisted"
  /// case the repair has to survive without spinning.
  bool failWrites = false;

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => store.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => store.remove(key);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      store.clear();

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => store[key];

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map.of(store);

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (failAll || failWrites) throw PlatformException(code: 'write_failed');
    store[key] = value;
  }
}

/// Scriptable [AuthSessionController] (same pattern as
/// `shell_controller_test`): the session value is set in place, so the
/// session-scoped persistence key is deterministic.
class _ScriptableSessionController extends AuthSessionController {
  _ScriptableSessionController(this._session);

  final AuthSession? _session;

  @override
  Future<AuthSession?> build() async => _session;
}

/// A DAO with the two behaviours the repair's failure/race branches need:
/// a concurrent write landing between the stale read and the conditional
/// delete (the window `deleteIfValue` exists for), and a failing delete.
class _RacingShellStateDao extends ShellStateDao {
  // `ShellStateDao`'s only constructor parameter is a private field, so a
  // super parameter cannot be expressed here (`super._db` is not valid Dart).
  // ignore: use_super_parameters
  _RacingShellStateDao(CacheDatabase db) : super(db);

  /// `(key, value)` written right before the delete is issued.
  (String, String)? raceWrite;

  /// When set, every conditional delete answers `Left` (store failure).
  bool failDelete = false;

  /// How many conditional deletes were attempted — proves the repair does not
  /// retry in a loop when the store fails.
  int deleteAttempts = 0;

  @override
  Future<Result<void>> deleteIfValue({
    required String key,
    required String value,
  }) async {
    deleteAttempts++;
    if (raceWrite case (final raceKey, final raceValue)) {
      await upsert(
        key: raceKey,
        value: raceValue,
        cachedAt: DateTime.utc(2026, 2, 1),
      );
    }
    if (failDelete) {
      return const Left(ProblemError(code: 'shell.state_delete_failed'));
    }
    return super.deleteIfValue(key: key, value: value);
  }
}

/// Counts scope removals so a failing write can be shown to stop after one
/// attempt instead of spinning through invalidate → rebuild → retry.
class _CountingActiveBlockStore extends ActiveBlockStore {
  // ignore: use_super_parameters
  _CountingActiveBlockStore(FlutterSecureStorage storage) : super(storage);

  int removeAttempts = 0;

  @override
  Future<Result<void>> removeScopeIfMatch({
    required String seasonId,
    required String blockId,
  }) {
    removeAttempts++;
    return super.removeScopeIfMatch(seasonId: seasonId, blockId: blockId);
  }
}

FakeSecureStoragePlatform? _platform;

/// Bounded event-loop turns (analytical, not wall-clock): the repair chain is
/// persisted-anchor load → block-scope load → seasons fetch → repair →
/// DAO/secure-storage write → invalidate → repair again. Each arrow is a turn;
/// forty bound the chain with slack (same reasoning as
/// `active_block_gate_test`). No wall-clock assertion is made
/// (deterministic-tests rule).
Future<void> settle(ProviderContainer container, {int turns = 40}) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Waits (bounded) until [condition] holds — used for the positive assertions,
/// where a fixed turn count would be a guess about the drift/secure-storage
/// chain rather than an assertion.
Future<void> waitUntil(
  Future<bool> Function() condition, {
  int maxTurns = 200,
}) async {
  for (var i = 0; i < maxTurns; i++) {
    if (await condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
}

/// Subscribes to the REAL repair provider (watching it is what performs the
/// repair, exactly as the shell does) and keeps the element alive for the
/// whole test.
void watchRepair(ProviderContainer container) {
  final sub = container.listen(activeScopeRepairProvider, (prev, next) {});
  addTearDown(sub.close);
}

/// Settles every input of the repair BEFORE it is first watched, so the
/// assertion "the repair ran exactly once" is about the repair and not about
/// how many turns the projection needed.
Future<void> settleInputs(ProviderContainer container) async {
  // Subscribe to the projection so its (auto-dispose) controller and fetch
  // chain stay alive while the inputs settle — without touching the repair.
  final sub = container.listen(seasonsView, (prev, next) {});
  addTearDown(sub.close);
  await container.read(activeSeasonPersistedProvider.future);
  await container.read(activeBlockPersistedProvider.future);
  await waitUntil(() async => container.read(seasonsView).isLoaded);
  expect(container.read(seasonsView).isLoaded, isTrue);
}

/// A container over the REAL resolution providers with the list fetch faked to
/// [fetch] (a `Future<Result<…>>`, so tests can gate it), an in-memory Drift
/// cache and the real [ActiveBlockStore] over the fake platform.
Future<({ProviderContainer container, CacheDatabase db, ShellStateDao dao})>
_buildFixture(
  Future<Result<List<SeasonView>>> Function() fetch, {
  String sub = 'sub-1',
  ShellStateDao Function(CacheDatabase db)? daoFactory,
  ActiveBlockStore? blockStore,
}) async {
  final db = CacheDatabase();
  final dao = daoFactory?.call(db) ?? ShellStateDao(db);
  final container = ProviderContainer(
    overrides: [
      apiDioProvider.overrideWithValue(Dio()),
      cacheDatabaseProvider.overrideWithValue(db),
      authSessionControllerProvider.overrideWith(
        () => _ScriptableSessionController(AuthSession(sub: sub)),
      ),
      shellStateDaoProvider.overrideWithValue(dao),
      if (blockStore != null)
        activeBlockStoreProvider.overrideWithValue(blockStore),
      clockProvider.overrideWith(
        (ref) => Clock.fixed(DateTime.utc(2026, 2, 1)),
      ),
      seasonsListFetchProvider.overrideWith((ref) => fetch()),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(db.close);
  // Settle the session first: the persistence key is derived from it.
  await container.read(authSessionControllerProvider.future);
  return (container: container, db: db, dao: dao);
}

/// Seeds the persisted active-season anchor for [sub].
Future<void> seedAnchor(
  ShellStateDao dao,
  String value, {
  String sub = 'sub-1',
}) async {
  final res = await dao.upsert(
    key: activeSeasonKeyFor(sub),
    value: value,
    cachedAt: DateTime.utc(2026, 2, 1),
  );
  expect(res.isRight(), isTrue);
}

/// Seeds the persisted per-season block scopes.
Future<void> seedScopes(
  ProviderContainer container,
  Map<String, String> scopes,
) async {
  final store = container.read(activeBlockStoreProvider);
  for (final entry in scopes.entries) {
    final res = await store.saveScope(
      seasonId: entry.key,
      blockId: entry.value,
      blockNumber: 1,
    );
    expect(res.isRight(), isTrue);
  }
}

Future<Map<String, PersistedBlockScope>> readScopes(
  ProviderContainer container,
) async {
  final res = await container.read(activeBlockStoreProvider).readScopes();
  return res.getRight().toNullable() ?? const {};
}

Future<String?> readAnchor(ShellStateDao dao, {String sub = 'sub-1'}) async {
  final res = await dao.read(activeSeasonKeyFor(sub));
  return res.getRight().toNullable()?.value;
}

void main() {
  setUp(() {
    _platform = FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = _platform!;
  });

  group('activeScopeRepair (issue #817)', () {
    test(
      'deletes a persisted season id the loaded view does not contain',
      () async {
        final f = await _buildFixture(() async => Right([_season('season-1')]));
        await seedAnchor(f.dao, 'season-gone');

        watchRepair(f.container);
        await waitUntil(() async => await readAnchor(f.dao) == null);

        expect(await readAnchor(f.dao), isNull);
        // The resolution never served it either (TTL discipline, unchanged).
        expect(f.container.read(activeSeasonResolutionProvider).value, isNull);
      },
    );

    test('keeps a persisted season id the loaded view contains', () async {
      final f = await _buildFixture(() async => Right([_season('season-1')]));
      await seedAnchor(f.dao, 'season-1');

      watchRepair(f.container);
      await settle(f.container);

      expect(await readAnchor(f.dao), 'season-1');
      await waitUntil(
        () async =>
            f.container.read(activeSeasonResolutionProvider).value?.id ==
            'season-1',
      );
      expect(
        f.container.read(activeSeasonResolutionProvider).value?.id,
        'season-1',
      );
    });

    test(
      'removes the block scopes of a gone season, keeps the live ones',
      () async {
        final f = await _buildFixture(() async => Right([_season('season-1')]));
        await seedAnchor(f.dao, 'season-gone');
        await seedScopes(f.container, {
          'season-gone': 'block-gone',
          'season-1': 'block-1',
        });

        watchRepair(f.container);
        await waitUntil(
          () async =>
              !(await readScopes(f.container)).containsKey('season-gone'),
        );

        final scopes = await readScopes(f.container);
        expect(scopes.containsKey('season-gone'), isFalse);
        expect(scopes['season-1']?.blockId, 'block-1');
      },
    );

    test('does not evict while the seasons fetch is still loading', () async {
      final gate = Completer<Result<List<SeasonView>>>();
      final f = await _buildFixture(() => gate.future);
      await seedAnchor(f.dao, 'season-1');

      // The repair runs against the loading view (cached rows only) - the
      // anchor must survive, because "unloaded" is not "gone".
      watchRepair(f.container);
      await settle(f.container);
      expect(await readAnchor(f.dao), 'season-1');

      // ...and the very same anchor IS evicted once a loaded view lacks it,
      // which proves the earlier survival came from the gate, not from an
      // inert repair path.
      gate.complete(Right([_season('season-2')]));
      await waitUntil(() async => await readAnchor(f.dao) == null);
      expect(await readAnchor(f.dao), isNull);
    });

    test('does not evict when the seasons fetch failed', () async {
      final f = await _buildFixture(
        () async => Left<ProblemError, List<SeasonView>>(_offline),
      );
      await seedAnchor(f.dao, 'season-gone');

      watchRepair(f.container);
      await settle(f.container);

      expect(await readAnchor(f.dao), 'season-gone');
    });

    test('a fresh pick that lands after the stale read survives', () async {
      final f = await _buildFixture(
        () async => Right([_season('season-1')]),
        daoFactory: _RacingShellStateDao.new,
      );
      await seedAnchor(f.dao, 'season-gone');
      // A concurrent pick writes the anchor between the read and the delete.
      (f.dao as _RacingShellStateDao).raceWrite = (
        activeSeasonKeyFor('sub-1'),
        'season-1',
      );

      watchRepair(f.container);
      await settle(f.container);

      // Compare-and-remove: the stale value no longer matches, so nothing is
      // deleted and the fresh pick resolves instead.
      expect(await readAnchor(f.dao), 'season-1');
      expect(
        f.container.read(shellStateDaoProvider),
        isA<_RacingShellStateDao>(),
      );
      await waitUntil(
        () async =>
            f.container.read(activeSeasonResolutionProvider).value?.id ==
            'season-1',
      );
      expect(
        f.container.read(activeSeasonResolutionProvider).value?.id,
        'season-1',
      );
    });

    test("identity B never deletes identity A's anchor", () async {
      final f = await _buildFixture(
        () async => Right([_season('season-1')]),
        sub: 'sub-2',
      );
      await seedAnchor(f.dao, 'season-gone', sub: 'sub-1');

      // Session B has nothing persisted, so it has nothing to repair.
      watchRepair(f.container);
      await settle(f.container);

      expect(await readAnchor(f.dao, sub: 'sub-1'), 'season-gone');
      expect(await readAnchor(f.dao, sub: 'sub-2'), isNull);
    });

    test(
      'a failing delete leaves the anchor and is not retried in a loop',
      () async {
        final f = await _buildFixture(
          () async => Right([_season('season-1')]),
          daoFactory: _RacingShellStateDao.new,
        );
        await seedAnchor(f.dao, 'season-gone');
        final dao = f.dao as _RacingShellStateDao;
        dao.failDelete = true;

        await settleInputs(f.container);
        watchRepair(f.container);
        await settle(f.container);

        // Best-effort: nothing is deleted, nothing spins (a rebuild loop would
        // raise the attempt count).
        expect(await readAnchor(f.dao), 'season-gone');
        expect(dao.deleteAttempts, 1);
      },
    );

    test('a failing block-scope write leaves the document and is not retried '
        'in a loop', () async {
      final store = _CountingActiveBlockStore(const FlutterSecureStorage());
      final f = await _buildFixture(
        () async => Right([_season('season-1')]),
        blockStore: store,
      );
      await seedScopes(f.container, {'season-gone': 'block-gone'});
      // Reads keep working, writes fail: the document stays as it was.
      _platform!.failWrites = true;

      await settleInputs(f.container);
      watchRepair(f.container);
      await settle(f.container);

      expect(store.removeAttempts, 1);
      _platform!.failWrites = false;
      expect(
        (await readScopes(f.container))['season-gone']?.blockId,
        'block-gone',
      );
    });

    test('a converged state writes nothing (idempotent repair)', () async {
      final f = await _buildFixture(() async => Right([_season('season-1')]));
      await seedScopes(f.container, {'season-1': 'block-1'});

      watchRepair(f.container);
      await settle(f.container);

      // No anchor and no gone scope: the document is untouched.
      expect(await readAnchor(f.dao), isNull);
      expect((await readScopes(f.container))['season-1']?.blockId, 'block-1');
    });
  });
}
