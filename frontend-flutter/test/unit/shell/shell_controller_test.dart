// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Tier-1 unit tests for the shell controller (`redesign-app-shell-navigation`
// task 2.1): tab switching, season selection with best-effort persistence,
// and the sign-out reset — driven through a ProviderContainer with an
// in-memory Drift store and a scriptable session controller. Deterministic:
// fixed clock, no wall-clock budgets, no Flutter widget imports.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test/test.dart';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/cache/shell_state_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_view.dart';
import 'package:frontend_flutter/features/shell/active_season_store.dart';
import 'package:frontend_flutter/features/shell/shell_controller.dart';

/// Scriptable [AuthSessionController]: the test mutates the session value
/// in place so a mid-session sign-out rebuilds the controller state
/// (the shell's D7 reset path) without touching secure storage.
class _ScriptableSessionController extends AuthSessionController {
  _ScriptableSessionController(this._session);

  AuthSession? _session;

  void setSession(AuthSession? session) => _session = session;

  @override
  Future<AuthSession?> build() async => _session;
}

/// Flushes the fire-and-forget persistence (write + provider
/// invalidation): a few event-loop turns bound the chain with slack.
/// No wall-clock assertion (deterministic-tests rule).
Future<void> _settlePersistence() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

SeasonView _season(String id, {int number = 1, String? title}) => SeasonView(
  (b) => b
    ..id = id
    ..number = number
    ..seriesId = 'series-1'
    ..title = title
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

/// Container wired to: an in-memory Drift shell-state store, a fixed clock,
/// a scriptable session (default: signed in), and a controllable
/// active-season resolution.
Future<
  ({
    ProviderContainer container,
    _ScriptableSessionController session,
    ShellStateDao dao,
    CacheDatabase db,
    SeasonView Function(String id) season,
  })
>
_buildFixture({AuthSession? session, SeasonView? resolvedSeason}) async {
  final db = CacheDatabase();
  final dao = ShellStateDao(db);
  final sessionController = _ScriptableSessionController(
    session ?? AuthSession(sub: 'sub-1'),
  );
  final container = ProviderContainer(
    overrides: [
      authSessionControllerProvider.overrideWith(() => sessionController),
      shellStateDaoProvider.overrideWithValue(dao),
      clockProvider.overrideWith(
        (ref) => Clock.fixed(DateTime.utc(2026, 2, 1)),
      ),
      activeSeasonResolutionProvider.overrideWith((ref) async {
        final persisted = await ref.watch(activeSeasonPersistedProvider.future);
        if (persisted == null) return resolvedSeason;
        return resolvedSeason?.id == persisted ? resolvedSeason : null;
      }),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(db.close);
  // Settle the session BEFORE any shell provider is touched: production
  // sequencing (the auth gate resolves before the shell mounts) and the
  // deterministic base for the session-scoped persistence key.
  await container.read(authSessionControllerProvider.future);
  return (
    container: container,
    session: sessionController,
    dao: dao,
    db: db,
    season: _season,
  );
}

void main() {
  group('ShellController (task 2.1)', () {
    test('starts on the Season tab without an active season', () async {
      final f = await _buildFixture();
      final state = f.container.read(shellControllerProvider);
      expect(state.selectedIndex, kSeasonTabIndex);
      expect(state.activeSeason, isNull);
    });

    test('selectTab switches the selected index', () async {
      final f = await _buildFixture();
      final c = f.container.read(shellControllerProvider.notifier);
      c.selectTab(kPlanenTabIndex);
      expect(
        f.container.read(shellControllerProvider).selectedIndex,
        kPlanenTabIndex,
      );
      c.selectTab(kKleidungTabIndex);
      expect(
        f.container.read(shellControllerProvider).selectedIndex,
        kKleidungTabIndex,
      );
    });

    test('selectTab keeps the active season', () async {
      final s = _season('season-1');
      final f = await _buildFixture(resolvedSeason: s);
      final container = f.container;
      final notifier = container.read(shellControllerProvider.notifier);
      notifier.setActiveSeason(s);
      notifier.selectTab(kPlanenTabIndex);
      final state = container.read(shellControllerProvider);
      expect(state.selectedIndex, kPlanenTabIndex);
      expect(state.activeSeason?.id, 'season-1');
    });

    test('out-of-range indices are ignored (no throw)', () async {
      final f = await _buildFixture();
      final c = f.container.read(shellControllerProvider.notifier);
      c.selectTab(-1);
      c.selectTab(99);
      expect(
        f.container.read(shellControllerProvider).selectedIndex,
        kSeasonTabIndex,
      );
    });

    test(
      'setActiveSeason sets the season and persists the reference',
      () async {
        final f = await _buildFixture();
        final container = f.container;
        final notifier = container.read(shellControllerProvider.notifier);
        notifier.setActiveSeason(_season('season-42'));
        expect(
          container.read(shellControllerProvider).activeSeason?.id,
          'season-42',
        );
        await _settlePersistence();
        final persisted = (await f.dao.read(activeSeasonKeyFor('sub-1')))
            .getRight()
            .toNullable();
        expect(persisted!.value, 'season-42');
      },
    );

    test(
      'clearActiveSeason clears in memory AND the persisted reference',
      () async {
        final f = await _buildFixture();
        final container = f.container;
        final notifier = container.read(shellControllerProvider.notifier);
        notifier.setActiveSeason(_season('season-1'));
        await _settlePersistence();
        expect(
          (await f.dao.read(activeSeasonKeyFor('sub-1')))
              .getRight()
              .toNullable(),
          isNotNull,
        );

        notifier.clearActiveSeason();
        await _settlePersistence();
        final state = container.read(shellControllerProvider);
        expect(state.activeSeason, isNull);
        expect(
          (await f.dao.read(activeSeasonKeyFor('sub-1')))
              .getRight()
              .toNullable(),
          isNull,
        );
      },
    );

    test('persisted season hydrates the controller state (D5)', () async {
      // CodeRabbit review fix: the fixture's resolution override bypasses
      // the persisted reference, so this test must seed the DAO + the live
      // projection and exercise the REAL resolution path.
      final s = _season('season-7', number: 7);
      final db = CacheDatabase();
      addTearDown(db.close);
      final dao = ShellStateDao(db);
      await dao.upsert(
        key: activeSeasonKeyFor('sub-1'),
        value: 'season-7',
        cachedAt: DateTime.utc(2026, 2, 1),
      );
      final container = ProviderContainer(
        overrides: [
          authSessionControllerProvider.overrideWith(
            () => _ScriptableSessionController(AuthSession(sub: 'sub-1')),
          ),
          shellStateDaoProvider.overrideWithValue(dao),
          clockProvider.overrideWith(
            (ref) => Clock.fixed(DateTime.utc(2026, 2, 1)),
          ),
          seasonsView.overrideWithValue(SeasonsView(rows: [s], isStale: false)),
        ],
      );
      addTearDown(container.dispose);
      // Settle the session FIRST (production sequencing — see _buildFixture).
      await container.read(authSessionControllerProvider.future);
      // The resolution is async: let it settle, then read the controller
      // (it rebuilds when the resolution provider completes).
      await container.read(activeSeasonResolutionProvider.future);
      final state = container.read(shellControllerProvider);
      expect(state.activeSeason?.id, 'season-7');
      expect(state.activeSeason?.number, 7);
    });

    test('direct u1 → u2 session switch never resolves the previous '
        "session's season (session-scoped persistence)", () async {
      final db = CacheDatabase();
      addTearDown(db.close);
      final dao = ShellStateDao(db);
      await dao.upsert(
        key: activeSeasonKeyFor('user-1'),
        value: 'season-1',
        cachedAt: DateTime.utc(2026, 2, 1),
      );
      final sessionController = _ScriptableSessionController(
        AuthSession(sub: 'user-1'),
      );
      final container = ProviderContainer(
        overrides: [
          authSessionControllerProvider.overrideWith(() => sessionController),
          shellStateDaoProvider.overrideWithValue(dao),
          clockProvider.overrideWith(
            (ref) => Clock.fixed(DateTime.utc(2026, 2, 1)),
          ),
          // The live projection still carries u1's season — but the
          // persisted key is u2-scoped, so u2 resolves nothing.
          seasonsView.overrideWithValue(
            SeasonsView(rows: [_season('season-1')], isStale: false),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authSessionControllerProvider.future);
      await container.read(activeSeasonResolutionProvider.future);
      // Mount the shell controller while u1 is active (production state:
      // the shell exists whenever a season can be set).
      final mounted = container.read(shellControllerProvider);
      expect(mounted.activeSeason?.id, 'season-1');
      // u1 resolves its own persisted season…
      expect(
        await container.read(activeSeasonResolutionProvider.future),
        isNotNull,
      );

      // …then the session switches DIRECTLY to u2 (no signed-out
      // intermediate): the controller evicts u1's key and re-resolves
      // against u2's (nonexistent) scope.
      sessionController.setSession(AuthSession(sub: 'user-2'));
      container.invalidate(authSessionControllerProvider);
      await container.read(authSessionControllerProvider.future);
      container.invalidate(shellControllerProvider);
      await container.read(activeSeasonResolutionProvider.future);
      final state = container.read(shellControllerProvider);
      expect(state.activeSeason, isNull);
      expect(
        container.read(shellControllerProvider).selectedIndex,
        kSeasonTabIndex,
      );
      // Flush the fire-and-forget eviction write.
      await _settlePersistence();
      // u1's persisted entry is evicted; u2 has none.
      expect(
        (await dao.read(activeSeasonKeyFor('user-1'))).getRight().toNullable(),
        isNull,
      );
      expect(
        (await dao.read(activeSeasonKeyFor('user-2'))).getRight().toNullable(),
        isNull,
      );
    });

    test('reset on sign-out: tab index AND active season reset (D7)', () async {
      final s = _season('season-1');
      final f = await _buildFixture(resolvedSeason: s);
      final container = f.container;
      final notifier = container.read(shellControllerProvider.notifier);
      notifier.selectTab(kMehrTabIndex);
      notifier.setActiveSeason(s);
      await _settlePersistence();

      // Mid-session sign-out rebuilds the controller (the session
      // dependency it watches flips to signed-out).
      f.session.setSession(null);
      container.invalidate(authSessionControllerProvider);
      await container.read(authSessionControllerProvider.future);
      final state = container.read(shellControllerProvider);
      expect(state.selectedIndex, kSeasonTabIndex);
      expect(state.activeSeason, isNull);
    });
  });

  group('activeSeasonResolution (task 2.2 TTL discipline)', () {
    test('resolves the injected season without a persisted id', () async {
      final f = await _buildFixture(resolvedSeason: _season('season-1'));
      final res = await f.container.read(activeSeasonResolutionProvider.future);
      expect(res?.id, 'season-1');
    });

    test('persisted id matching no projected row resolves to null '
        '(TTL-compliant: never a stale DTO)', () async {
      final db = CacheDatabase();
      addTearDown(db.close);
      final dao = ShellStateDao(db);
      await dao.upsert(
        key: activeSeasonKeyFor(null),
        value: 'season-gone',
        cachedAt: DateTime.utc(2026, 2, 1),
      );
      final container = ProviderContainer(
        overrides: [
          shellStateDaoProvider.overrideWithValue(dao),
          clockProvider.overrideWith(
            (ref) => Clock.fixed(DateTime.utc(2026, 2, 1)),
          ),
          activeSeasonPersistedProvider.overrideWith(
            (ref) async => 'season-gone',
          ),
          // The live projection carries a DIFFERENT season (the persisted
          // one disappeared / expired).
          seasonsView.overrideWithValue(
            SeasonsView(rows: [_season('season-9')], isStale: false),
          ),
        ],
      );
      addTearDown(container.dispose);
      final res = await container.read(activeSeasonResolutionProvider.future);
      expect(res, isNull);
    });

    test(
      'persisted id matching a projected row resolves to that season',
      () async {
        final db = CacheDatabase();
        addTearDown(db.close);
        final dao = ShellStateDao(db);
        await dao.upsert(
          key: activeSeasonKeyFor('anon'),
          value: 'season-9',
          cachedAt: DateTime.utc(2026, 2, 1),
        );
        final sessionController = _ScriptableSessionController(
          AuthSession(sub: 'anon'),
        );
        final container = ProviderContainer(
          overrides: [
            authSessionControllerProvider.overrideWith(() => sessionController),
            shellStateDaoProvider.overrideWithValue(dao),
            clockProvider.overrideWith(
              (ref) => Clock.fixed(DateTime.utc(2026, 2, 1)),
            ),
            seasonsView.overrideWithValue(
              SeasonsView(
                rows: [_season('season-9', number: 9)],
                isStale: false,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(authSessionControllerProvider.future);
        final res = await container.read(activeSeasonResolutionProvider.future);
        expect(res?.id, 'season-9');
        expect(res?.number, 9);
      },
    );
  });
}
