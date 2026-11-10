// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Widget tests for the dead-anchor repair (issue #817 — C4 of #809).
//
// The unit tier (`test/unit/shell/active_season_repair_test.dart`) proves the
// eviction rules against the real providers. This tier proves the part only a
// mounted widget can: the shell performs the repair, and its derived state
// (the active season the views consume) converges on the repaired store. The
// probe below watches exactly what `AppShell` watches.
//
// Deterministic: the list fetch is seam-faked (and gated by a Completer where
// the loading window matters), the clock is fixed, and the secure-storage
// platform is an in-memory double — no wall-clock budgets.

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/cache/shell_state_cache_dao.dart';
import 'package:frontend_flutter/features/shell/active_season_store.dart';
import 'package:frontend_flutter/features/shell/shell_controller.dart';
import 'package:frontend_flutter/src/network/api_client.dart';

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

/// In-memory [FlutterSecureStoragePlatform] double (same pattern as
/// `active_block_gate_test`): the repair's block-scope document lives here.
class FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};

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
  }) async => store[key] = value;
}

class _ScriptableSessionController extends AuthSessionController {
  _ScriptableSessionController(this._session);

  final AuthSession? _session;

  @override
  Future<AuthSession?> build() async => _session;
}

/// The shell's own wiring in miniature: watch the repair provider (as
/// `AppShell` does) plus the shell controller state the views consume.
class _ShellProbe extends ConsumerWidget {
  const _ShellProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(activeScopeRepairProvider);
    final state = ref.watch(shellControllerProvider);
    return MaterialApp(
      home: Scaffold(
        body: Text(
          state.activeSeason?.title ?? 'no-season',
          textDirection: TextDirection.ltr,
        ),
      ),
    );
  }
}

FakeSecureStoragePlatform? _platform;

/// A container over the real providers with the list fetch faked to [fetch].
/// Built BEFORE the widget is pumped, so the persisted anchor can be seeded
/// first — exactly the cold-start order the repair has to survive.
ProviderContainer _buildContainer(
  Future<Result<List<SeasonView>>> Function() fetch, {
  String sub = 'sub-1',
}) {
  final db = CacheDatabase();
  final container = ProviderContainer(
    overrides: [
      apiDioProvider.overrideWithValue(Dio()),
      cacheDatabaseProvider.overrideWithValue(db),
      authSessionControllerProvider.overrideWith(
        () => _ScriptableSessionController(AuthSession(sub: sub)),
      ),
      shellStateDaoProvider.overrideWithValue(ShellStateDao(db)),
      clockProvider.overrideWith(
        (ref) => Clock.fixed(DateTime.utc(2026, 2, 1)),
      ),
      seasonsListFetchProvider.overrideWith((ref) => fetch()),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(db.close);
  return container;
}

Widget _app(ProviderContainer container) =>
    UncontrolledProviderScope(container: container, child: const _ShellProbe());

Future<void> seedAnchor(
  ProviderContainer container,
  String value, {
  String sub = 'sub-1',
}) async {
  final res = await container
      .read(shellStateDaoProvider)
      .upsert(
        key: activeSeasonKeyFor(sub),
        value: value,
        cachedAt: DateTime.utc(2026, 2, 1),
      );
  expect(res.isRight(), isTrue);
}

Future<String?> readAnchor(
  ProviderContainer container, {
  String sub = 'sub-1',
}) async {
  final res = await container
      .read(shellStateDaoProvider)
      .read(activeSeasonKeyFor(sub));
  return res.getRight().toNullable()?.value;
}

void main() {
  setUp(() {
    _platform = FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = _platform!;
  });

  testWidgets(
    'a persisted anchor whose season is gone is evicted and the shell drops it',
    (tester) async {
      final container = _buildContainer(
        () async => Right([_season('season-1', title: 'Staffel 1')]),
      );
      await seedAnchor(container, 'season-gone');

      await tester.pumpWidget(_app(container));
      await tester.pumpAndSettle();

      expect(await readAnchor(container), isNull);
      expect(find.text('no-season'), findsOneWidget);
    },
  );

  testWidgets(
    'a live-but-unloaded season is never dropped while the fetch is pending',
    (tester) async {
      final gate = Completer<Result<List<SeasonView>>>();
      final container = _buildContainer(() => gate.future);
      await seedAnchor(container, 'season-1');

      // Loading: the view holds cached rows only, so nothing is authoritative.
      // Pin the state the repair's first evaluation sees instead of inferring
      // it from a pump count: the anchor is already one of its inputs and the
      // view is not loaded.
      await tester.pumpWidget(_app(container));
      await tester.pumpAndSettle();
      expect(container.read(activeSeasonPersistedProvider).value, 'season-1');
      expect(container.read(seasonsView).isLoaded, isFalse);
      expect(await readAnchor(container), 'season-1');

      // The projection answers with the very season the anchor names: it
      // survives and the shell renders it.
      gate.complete(Right([_season('season-1', title: 'Staffel 1')]));
      await tester.pumpAndSettle();
      expect(await readAnchor(container), 'season-1');
      expect(find.text('Staffel 1'), findsOneWidget);
    },
  );

  testWidgets('a dead anchor is evicted only once the loaded view lacks it', (
    tester,
  ) async {
    final gate = Completer<Result<List<SeasonView>>>();
    final container = _buildContainer(() => gate.future);
    await seedAnchor(container, 'season-gone');

    // Still loading: the anchor is not evidence of absence. Same pinning as
    // above - the repair's first evaluation sees the loaded anchor against an
    // unloaded view.
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();
    expect(container.read(activeSeasonPersistedProvider).value, 'season-gone');
    expect(container.read(seasonsView).isLoaded, isFalse);
    expect(await readAnchor(container), 'season-gone');

    gate.complete(Right([_season('season-1', title: 'Staffel 1')]));
    await tester.pumpAndSettle();

    expect(await readAnchor(container), isNull);
    expect(find.text('no-season'), findsOneWidget);
  });
}
