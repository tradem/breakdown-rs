// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-1 unit tests for the dead active-episode repair (issue #879 — C5 of
// #809).
//
// The persisted per-season episode scope (`ActiveEpisodeStore`) had the same
// shape of staleness #817 repaired for the season anchor: after a dev data
// reset (#810 / #770) the restore in `AppShell._restoreEpisodeScope` resolved
// to nothing and the entry stayed in secure storage forever. These tests drive
// the REAL repair provider — only the two list-fetch seams and the secure
// storage platform are faked:
//
//  - a scope whose SEASON the loaded seasons projection no longer serves is
//    removed (the dev-data-reset case, no episode read needed),
//  - a scope whose EPISODE the active season's loaded block projection no
//    longer serves is removed, and its in-memory scope is dropped with it,
//  - nothing is evicted while either fetch is loading or failed,
//  - compare-and-remove: a fresh pick that lands after the stale read survives
//    (document AND in-memory scope),
//  - season scoping holds (a sibling season's entry is never touched),
//  - a failing store leaves everything as it was and is not retried in a loop.
//
// Deterministic: in-memory Drift, a fixed clock, and bounded event-loop turns
// (no wall-clock budgets, no sleeps — AGENTS.md §6).

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/auth/active_episode.dart';
import 'package:frontend_flutter/auth/active_episode_store.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/cache/shell_state_cache_dao.dart';
import 'package:frontend_flutter/features/episodes/episodes_controller.dart';
import 'package:frontend_flutter/features/shell/active_episode_scope_repair.dart';
import 'package:frontend_flutter/features/shell/active_season_store.dart';
import 'package:frontend_flutter/src/network/api_client.dart';

import '../../support/fake_secure_storage.dart';

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

EpisodeView _episode(String id, {String blockId = 'b-1', int number = 1}) =>
    EpisodeView(
      (b) => b
        ..id = id
        ..blockId = blockId
        ..name = null
        ..number = number
        ..projectId = 'series-1'
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

/// Scriptable [AuthSessionController] (same pattern as
/// `active_season_repair_test`): the session value is set in place, so the
/// session-scoped season-anchor key is deterministic.
class _ScriptableSessionController extends AuthSessionController {
  _ScriptableSessionController(this._session);

  final AuthSession? _session;

  @override
  Future<AuthSession?> build() async => _session;
}

/// Counts conditional removals, and can write a "fresh pick" through the same
/// store right before the removal — the window `removeScopeIfMatch` exists for.
class _ScriptedActiveEpisodeStore extends ActiveEpisodeStore {
  // ignore: use_super_parameters
  _ScriptedActiveEpisodeStore(FlutterSecureStorage storage) : super(storage);

  /// `(seasonId, episodeId)` persisted right before the conditional removal.
  (String, String)? raceWrite;

  /// A user action (a fresh pick) performed right before the conditional
  /// removal — the in-memory half of the same race.
  void Function()? onRemove;

  int removeAttempts = 0;

  @override
  Future<Result<void>> removeScopeIfMatch({
    required String seasonId,
    required String episodeId,
  }) async {
    removeAttempts++;
    // The race window is a TURN, not the same synchronous frame: a user pick
    // never lands while the repair provider is still building.
    await Future<void>.delayed(Duration.zero);
    onRemove?.call();
    if (raceWrite case (final raceSeason, final raceEpisode)) {
      await saveScope(
        seasonId: raceSeason,
        blockId: 'b-1',
        episodeId: raceEpisode,
        episodeNumber: 2,
      );
    }
    return super.removeScopeIfMatch(seasonId: seasonId, episodeId: episodeId);
  }
}

FakeSecureStoragePlatform? _platform;

/// Bounded event-loop turns (analytical, not wall-clock): the repair chain is
/// persisted-episode load → seasons fetch → resolution → episode fetch →
/// repair → secure-storage write → invalidate → repair again. Forty turns
/// bound the chain with slack (same reasoning as `active_season_repair_test`).
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
/// repair, exactly as the shell does) and keeps the element alive.
void watchRepair(ProviderContainer container) {
  final sub = container.listen(activeEpisodeScopeRepairProvider, (_, _) {});
  addTearDown(sub.close);
}

/// Keeps the (auto-dispose) projection chains alive WITHOUT requiring any
/// particular state, so a test can pin a view in its loading or failed state
/// while the other inputs settle.
void pinProjections(ProviderContainer container) {
  final seasons = container.listen(seasonsView, (_, _) {});
  addTearDown(seasons.close);
  final episodes = container.listen(
    episodesViewProvider('b-1', 'season-1'),
    (_, _) {},
  );
  addTearDown(episodes.close);
}

/// Settles every input of the repair BEFORE it is first watched: the persisted
/// episode document, the season anchor and its resolution, and the seasons
/// view. Pinning them first is what makes "the repair ran exactly once" a
/// statement about the repair instead of about how many turns the projection
/// chain needed.
Future<void> settleInputs(ProviderContainer container) async {
  await container.read(activeEpisodePersistedProvider.future);
  await container.read(activeSeasonPersistedProvider.future);
  await container.read(activeSeasonResolutionProvider.future);
  await waitUntil(() async => container.read(seasonsView).isLoaded);
  expect(container.read(seasonsView).isLoaded, isTrue);
}

/// A container over the REAL repair provider with both list fetches faked, an
/// in-memory Drift cache and the real [ActiveEpisodeStore] over the fake
/// platform.
({
  ProviderContainer container,
  CacheDatabase db,
  ShellStateDao dao,
  ActiveEpisodeStore store,
})
_buildFixture({
  required Future<Result<List<SeasonView>>> Function() seasonsFetch,
  Future<Result<List<EpisodeView>>> Function()? episodesFetch,
  String sub = 'sub-1',
  ActiveEpisodeStore? episodeStore,
  DateTime Function()? now,
}) {
  final db = CacheDatabase();
  final dao = ShellStateDao(db);
  final store = episodeStore ?? ActiveEpisodeStore.secure();
  final container = ProviderContainer(
    overrides: [
      apiDioProvider.overrideWithValue(Dio()),
      cacheDatabaseProvider.overrideWithValue(db),
      authSessionControllerProvider.overrideWith(
        () => _ScriptableSessionController(AuthSession(sub: sub)),
      ),
      shellStateDaoProvider.overrideWithValue(dao),
      activeEpisodeStoreProvider.overrideWithValue(store),
      clockProvider.overrideWith(
        (ref) => now == null
            ? Clock.fixed(DateTime.utc(2026, 2, 1))
            : Clock(() => now()),
      ),
      seasonsListFetchProvider.overrideWith((ref) => seasonsFetch()),
      episodesListFetchProvider('b-1', 'season-1').overrideWith(
        (ref) =>
            episodesFetch?.call() ??
            Future.value(const Right<ProblemError, List<EpisodeView>>([])),
      ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(db.close);
  return (container: container, db: db, dao: dao, store: store);
}

/// Seeds the persisted active-season anchor (the repair's case-2 trigger).
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

/// Seeds the persisted per-season episode scopes.
Future<void> seedScopes(
  ActiveEpisodeStore store,
  Map<String, String> scopes, {
  String blockId = 'b-1',
}) async {
  for (final entry in scopes.entries) {
    final res = await store.saveScope(
      seasonId: entry.key,
      blockId: blockId,
      episodeId: entry.value,
      episodeNumber: 1,
    );
    expect(res.isRight(), isTrue);
  }
}

Future<Map<String, PersistedEpisodeScope>> readScopes(
  ActiveEpisodeStore store,
) async {
  final res = await store.readScopes();
  return res.getRight().toNullable() ?? const {};
}

void main() {
  setUp(() {
    _platform = FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = _platform!;
  });

  group('activeEpisodeScopeRepair (issue #879)', () {
    test(
      'removes the scope of a season the loaded view no longer serves',
      () async {
        final f = _buildFixture(
          seasonsFetch: () async => Right([_season('season-1')]),
        );
        await seedScopes(f.store, {'season-gone': 'e-gone'});

        watchRepair(f.container);
        await waitUntil(
          () async => !(await readScopes(f.store)).containsKey('season-gone'),
        );

        expect((await readScopes(f.store)).containsKey('season-gone'), isFalse);
      },
    );

    test('removes an episode the loaded episode projection lacks', () async {
      final f = _buildFixture(
        seasonsFetch: () async => Right([_season('season-1')]),
        episodesFetch: () async => Right([_episode('e-other')]),
      );
      await seedAnchor(f.dao, 'season-1');
      await seedScopes(f.store, {'season-1': 'e-gone'});

      await settleInputs(f.container);
      watchRepair(f.container);
      await waitUntil(
        () async => !(await readScopes(f.store)).containsKey('season-1'),
      );

      expect((await readScopes(f.store)).containsKey('season-1'), isFalse);
      // The resolution itself stays a pure resolver (unchanged by #879).
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

    test('keeps an episode the loaded projection still contains', () async {
      final f = _buildFixture(
        seasonsFetch: () async => Right([_season('season-1')]),
        episodesFetch: () async =>
            Right([_episode('e-1'), _episode('e-2', number: 2)]),
      );
      await seedAnchor(f.dao, 'season-1');
      await seedScopes(f.store, {'season-1': 'e-1'});

      await settleInputs(f.container);
      watchRepair(f.container);
      await settle(f.container);

      expect((await readScopes(f.store))['season-1']?.episodeId, 'e-1');
    });

    test('does not evict while the episode fetch is loading', () async {
      final gate = Completer<Result<List<EpisodeView>>>();
      final f = _buildFixture(
        seasonsFetch: () async => Right([_season('season-1')]),
        episodesFetch: () => gate.future,
      );
      await seedAnchor(f.dao, 'season-1');
      await seedScopes(f.store, {'season-1': 'e-gone'});

      // Pin the LOADING state before the repair is first watched: its first
      // build evaluates the persisted scope against an unloaded episode view.
      pinProjections(f.container);
      await settleInputs(f.container);
      expect(
        f.container.read(episodesViewProvider('b-1', 'season-1')).isLoaded,
        isFalse,
      );

      watchRepair(f.container);
      await settle(f.container);
      expect((await readScopes(f.store))['season-1']?.episodeId, 'e-gone');

      // ...and the very same scope IS evicted once a loaded view lacks it,
      // which proves the survival above came from the gate.
      gate.complete(Right([_episode('e-other')]));
      await waitUntil(
        () async => !(await readScopes(f.store)).containsKey('season-1'),
      );
      expect((await readScopes(f.store)).containsKey('season-1'), isFalse);
    });

    test('does not evict when the episode fetch failed', () async {
      final f = _buildFixture(
        seasonsFetch: () async => Right([_season('season-1')]),
        episodesFetch: () async =>
            Left<ProblemError, List<EpisodeView>>(_offline),
      );
      await seedAnchor(f.dao, 'season-1');
      await seedScopes(f.store, {'season-1': 'e-gone'});

      pinProjections(f.container);
      await settleInputs(f.container);
      await waitUntil(
        () async =>
            f.container.read(episodesViewProvider('b-1', 'season-1')).error !=
            null,
      );
      expect(
        f.container.read(episodesViewProvider('b-1', 'season-1')).isLoaded,
        isFalse,
      );

      watchRepair(f.container);
      await settle(f.container);

      expect((await readScopes(f.store))['season-1']?.episodeId, 'e-gone');
    });

    test('does not evict while the seasons fetch is still loading', () async {
      final gate = Completer<Result<List<SeasonView>>>();
      final f = _buildFixture(
        seasonsFetch: () => gate.future,
        episodesFetch: () async => Right([_episode('e-other')]),
      );
      await seedAnchor(f.dao, 'season-1');
      await seedScopes(f.store, {'season-gone': 'e-gone'});

      await f.container.read(activeEpisodePersistedProvider.future);
      await f.container.read(activeSeasonPersistedProvider.future);
      expect(f.container.read(seasonsView).isLoaded, isFalse);

      watchRepair(f.container);
      await settle(f.container);
      expect((await readScopes(f.store))['season-gone']?.episodeId, 'e-gone');

      gate.complete(Right([_season('season-1')]));
      await waitUntil(
        () async => !(await readScopes(f.store)).containsKey('season-gone'),
      );
      expect((await readScopes(f.store)).containsKey('season-gone'), isFalse);
    });

    test('a fresh pick that lands after the stale read survives', () async {
      final store = _ScriptedActiveEpisodeStore(const FlutterSecureStorage());
      final f = _buildFixture(
        seasonsFetch: () async => Right([_season('season-1')]),
        // The fresh pick is LIVE in the projection the repair reads.
        episodesFetch: () async => Right([_episode('e-fresh')]),
        episodeStore: store,
      );
      await seedAnchor(f.dao, 'season-1');
      await seedScopes(store, {'season-1': 'e-gone'});
      // A concurrent pick writes a live scope between the read and the write.
      store.raceWrite = ('season-1', 'e-fresh');

      await settleInputs(f.container);
      watchRepair(f.container);
      await settle(f.container);

      // Compare-and-remove: the stale value no longer matches, so the fresh
      // pick survives — and the converged repair keeps it (it is live).
      expect((await readScopes(store))['season-1']?.episodeId, 'e-fresh');
    });

    test(
      'never discards a fresh in-memory pick that landed while deciding',
      () async {
        final store = _ScriptedActiveEpisodeStore(const FlutterSecureStorage());
        final f = _buildFixture(
          seasonsFetch: () async => Right([_season('season-1')]),
          episodesFetch: () async => Right([_episode('e-fresh')]),
          episodeStore: store,
        );
        await seedAnchor(f.dao, 'season-1');
        await seedScopes(store, {'season-1': 'e-gone'});
        // The user picks a LIVE episode of the SAME season while the repair is
        // deciding: the in-memory value no longer matches the eviction target.
        store.onRemove = () => f.container
            .read(activeEpisodeProvider.notifier)
            .set(
              seasonId: 'season-1',
              blockId: 'b-1',
              episodeId: 'e-fresh',
              episodeNumber: 2,
            );

        await settleInputs(f.container);
        watchRepair(f.container);
        await settle(f.container);

        expect(f.container.read(activeEpisodeProvider)?.episodeId, 'e-fresh');
        expect((await readScopes(store))['season-1']?.episodeId, 'e-fresh');
      },
    );

    test(
      'a failing write keeps the scope and is not retried in a loop',
      () async {
        final store = _ScriptedActiveEpisodeStore(const FlutterSecureStorage());
        final f = _buildFixture(
          seasonsFetch: () async => Right([_season('season-1')]),
          episodeStore: store,
        );
        await seedScopes(store, {'season-gone': 'e-gone'});
        // Reads keep working, writes fail: the document stays as it was.
        _platform!.failWrites = true;

        await settleInputs(f.container);
        watchRepair(f.container);
        await settle(f.container);

        expect(store.removeAttempts, 1);
        _platform!.failWrites = false;
        expect((await readScopes(store))['season-gone']?.episodeId, 'e-gone');
      },
    );

    test('a converged state writes nothing (idempotent repair)', () async {
      final store = _ScriptedActiveEpisodeStore(const FlutterSecureStorage());
      final f = _buildFixture(
        seasonsFetch: () async =>
            Right([_season('season-1'), _season('season-2', number: 2)]),
        episodesFetch: () async => Right([_episode('e-1')]),
        episodeStore: store,
      );
      await seedAnchor(f.dao, 'season-1');
      await seedScopes(store, {'season-1': 'e-1', 'season-2': 'e-2'});

      await settleInputs(f.container);
      watchRepair(f.container);
      await settle(f.container);

      // Both seasons are served by the view and the active season's episode is
      // in the projection: no removal is even attempted.
      expect(store.removeAttempts, 0);
      expect((await readScopes(store))['season-2']?.episodeId, 'e-2');
    });

    test(
      'a pick younger than the settle window is not evicted (projector lag)',
      () async {
        var now = DateTime.utc(2026, 2, 1);
        final store = _ScriptedActiveEpisodeStore(const FlutterSecureStorage());
        final f = _buildFixture(
          seasonsFetch: () async => Right([_season('season-1')]),
          // The just-created episode is not in the projection yet.
          episodesFetch: () async => Right([_episode('e-other')]),
          episodeStore: store,
          now: () => now,
        );
        await seedAnchor(f.dao, 'season-1');
        // The AI-import "open imported episode" case: a real PICK, written
        // while the projector still lags.
        f.container
            .read(activeEpisodeProvider.notifier)
            .set(
              seasonId: 'season-1',
              blockId: 'b-1',
              episodeId: 'e-gone',
              episodeNumber: 1,
            );
        await waitUntil(
          () async => (await readScopes(store)).containsKey('season-1'),
        );

        await settleInputs(f.container);
        watchRepair(f.container);
        await settle(f.container);

        // Inside the window the same loaded absence is NOT evidence.
        expect((await readScopes(store))['season-1']?.episodeId, 'e-gone');
        expect(store.removeAttempts, 0);
        expect(f.container.read(activeEpisodeProvider)?.episodeId, 'e-gone');

        // Past the window it is: the episode never appeared.
        now = now.add(kEpisodeScopeSettleWindow);
        f.container.invalidate(activeEpisodeScopeRepairProvider);
        await waitUntil(
          () async => !(await readScopes(store)).containsKey('season-1'),
        );
        expect((await readScopes(store)).containsKey('season-1'), isFalse);
        expect(store.removeAttempts, 1);
      },
    );

    test('season scoping: a sibling live season keeps its scope', () async {
      final f = _buildFixture(
        seasonsFetch: () async =>
            Right([_season('season-1'), _season('season-2', number: 2)]),
        episodesFetch: () async => Right([_episode('e-other')]),
      );
      await seedAnchor(f.dao, 'season-1');
      await seedScopes(f.store, {'season-1': 'e-gone', 'season-2': 'e-2'});

      await settleInputs(f.container);
      watchRepair(f.container);
      await waitUntil(
        () async => !(await readScopes(f.store)).containsKey('season-1'),
      );

      // Only the ACTIVE season is probed; its live sibling keeps its scope
      // (it is repaired when that season becomes active, never fanned out).
      expect((await readScopes(f.store)).containsKey('season-1'), isFalse);
      expect((await readScopes(f.store))['season-2']?.episodeId, 'e-2');
    });
  });
}
