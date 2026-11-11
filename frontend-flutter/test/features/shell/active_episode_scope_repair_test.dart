// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Widget tests for the dead-episode repair (issue #879 — C5 of #809).
//
// The unit tier (`test/unit/shell/active_episode_scope_repair_test.dart`)
// proves the eviction rules against the real providers. This tier proves the
// part only a mounted widget can: the shell performs the repair, and its
// derived state (the in-memory episode scope every chip and quick-create
// action reads) converges on the repaired store.
//
// Deterministic: both list fetches are seam-faked (and gated by a Completer
// where the loading window matters), the clock is fixed, and the secure
// storage platform is an in-memory double — no wall-clock budgets.

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

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

class _ScriptableSessionController extends AuthSessionController {
  _ScriptableSessionController(this._session);

  final AuthSession? _session;

  @override
  Future<AuthSession?> build() async => _session;
}

/// The shell's own wiring in miniature: watch the repair provider (as
/// `AppShell` does) and render the state every episode consumer reads.
class _ShellProbe extends ConsumerWidget {
  const _ShellProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(activeEpisodeScopeRepairProvider);
    final scope = ref.watch(activeEpisodeProvider);
    return MaterialApp(
      home: Scaffold(
        body: Text(
          scope?.episodeId ?? 'no-episode',
          textDirection: TextDirection.ltr,
        ),
      ),
    );
  }
}

FakeSecureStoragePlatform? _platform;

/// A container over the real providers with both list fetches faked. Built
/// BEFORE the widget is pumped, so the persisted scope can be seeded first —
/// exactly the cold-start order the repair has to survive.
({
  ProviderContainer container,
  CacheDatabase db,
  ShellStateDao dao,
  ActiveEpisodeStore store,
})
_buildContainer({
  required Future<Result<List<SeasonView>>> Function() seasonsFetch,
  required Future<Result<List<EpisodeView>>> Function() episodesFetch,
  String sub = 'sub-1',
}) {
  final db = CacheDatabase();
  final dao = ShellStateDao(db);
  final store = ActiveEpisodeStore.secure();
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
        (ref) => Clock.fixed(DateTime.utc(2026, 2, 1)),
      ),
      seasonsListFetchProvider.overrideWith((ref) => seasonsFetch()),
      episodesListFetchProvider(
        'b-1',
        'season-1',
      ).overrideWith((ref) => episodesFetch()),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(db.close);
  return (container: container, db: db, dao: dao, store: store);
}

Widget _app(ProviderContainer container) =>
    UncontrolledProviderScope(container: container, child: const _ShellProbe());

Future<void> seedAnchor(ShellStateDao dao, String value) async {
  final res = await dao.upsert(
    key: activeSeasonKeyFor('sub-1'),
    value: value,
    cachedAt: DateTime.utc(2026, 2, 1),
  );
  expect(res.isRight(), isTrue);
}

Future<void> seedScope(ActiveEpisodeStore store, String episodeId) async {
  final res = await store.saveScope(
    seasonId: 'season-1',
    blockId: 'b-1',
    episodeId: episodeId,
    episodeNumber: 1,
  );
  expect(res.isRight(), isTrue);
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

  testWidgets('a dead episode is evicted and the shell drops its scope', (
    tester,
  ) async {
    final f = _buildContainer(
      seasonsFetch: () async => Right([_season('season-1')]),
      episodesFetch: () async => Right([_episode('e-other')]),
    );
    await seedAnchor(f.dao, 'season-1');
    await seedScope(f.store, 'e-gone');
    // The dead scope is what the cold-start restore seeded in memory.
    f.container
        .read(activeEpisodeProvider.notifier)
        .set(
          seasonId: 'season-1',
          blockId: 'b-1',
          episodeId: 'e-gone',
          episodeNumber: 1,
          // What `_restoreEpisodeScope` does: a replayed document, not a pick
          // — so it does not renew the projector-lag grace window.
          isRestore: true,
        );

    await tester.pumpWidget(_app(f.container));
    await tester.pumpAndSettle();

    expect((await readScopes(f.store)).containsKey('season-1'), isFalse);
    expect(f.container.read(activeEpisodeProvider), isNull);
    expect(find.text('no-episode'), findsOneWidget);
  });

  testWidgets('a live episode keeps its scope and its stored document', (
    tester,
  ) async {
    final f = _buildContainer(
      seasonsFetch: () async => Right([_season('season-1')]),
      episodesFetch: () async => Right([_episode('e-1')]),
    );
    await seedAnchor(f.dao, 'season-1');
    await seedScope(f.store, 'e-1');
    f.container
        .read(activeEpisodeProvider.notifier)
        .set(
          seasonId: 'season-1',
          blockId: 'b-1',
          episodeId: 'e-1',
          episodeNumber: 1,
          isRestore: true,
        );

    await tester.pumpWidget(_app(f.container));
    await tester.pumpAndSettle();

    expect((await readScopes(f.store))['season-1']?.episodeId, 'e-1');
    expect(find.text('e-1'), findsOneWidget);
  });

  testWidgets('nothing is evicted while the episode fetch is pending', (
    tester,
  ) async {
    final gate = Completer<Result<List<EpisodeView>>>();
    final f = _buildContainer(
      seasonsFetch: () async => Right([_season('season-1')]),
      episodesFetch: () => gate.future,
    );
    await seedAnchor(f.dao, 'season-1');
    await seedScope(f.store, 'e-gone');

    await tester.pumpWidget(_app(f.container));
    await tester.pumpAndSettle();
    // Loading: the view serves cached rows, so nothing is authoritative.
    expect(
      f.container.read(episodesViewProvider('b-1', 'season-1')).isLoaded,
      isFalse,
    );
    expect((await readScopes(f.store))['season-1']?.episodeId, 'e-gone');

    // ...and the very same scope IS evicted once the loaded view lacks it.
    gate.complete(Right([_episode('e-other')]));
    await tester.pumpAndSettle();

    expect((await readScopes(f.store)).containsKey('season-1'), isFalse);
  });

  testWidgets('a failed episode fetch evicts nothing', (tester) async {
    final f = _buildContainer(
      seasonsFetch: () async => Right([_season('season-1')]),
      episodesFetch: () async =>
          Left<ProblemError, List<EpisodeView>>(_offline),
    );
    await seedAnchor(f.dao, 'season-1');
    await seedScope(f.store, 'e-gone');

    await tester.pumpWidget(_app(f.container));
    await tester.pumpAndSettle();

    expect((await readScopes(f.store))['season-1']?.episodeId, 'e-gone');
  });
}
