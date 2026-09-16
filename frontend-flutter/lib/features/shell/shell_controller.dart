// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/auth_providers.dart';
import '../../data/cache/seasons_cache_providers.dart';
import 'active_season_store.dart';

part 'shell_controller.g.dart';

/// Shell controller state (task 2.1, design D2/D5): the selected tab index
/// and the active season as **plain data** — no season-changing token
/// knowledge lives in widgets; the Kleidung tab consumes `activeSeason`
/// directly.
class ShellState {
  const ShellState({this.selectedIndex = 0, this.activeSeason});

  /// Selected destination (0..3: Season | Planen | Kleidung | Mehr).
  final int selectedIndex;

  /// The active season (last-opened, persisted reference resolved against
  /// the live projection). `null` = no season active/known yet.
  final SeasonView? activeSeason;

  ShellState copyWith({int? selectedIndex, SeasonView? activeSeason}) =>
      ShellState(
        selectedIndex: selectedIndex ?? this.selectedIndex,
        activeSeason: activeSeason ?? this.activeSeason,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShellState &&
          other.selectedIndex == selectedIndex &&
          other.activeSeason == activeSeason;

  @override
  int get hashCode => Object.hash(selectedIndex, activeSeason);

  @override
  String toString() =>
      'ShellState(selectedIndex: $selectedIndex, '
      'activeSeason: ${activeSeason?.id})';
}

/// The four shell destinations in display order (spec
/// `flutter-navigation-shell` — Season | Planen | Kleidung | Mehr).
const int kSeasonTabIndex = 0;
const int kPlanenTabIndex = 1;
const int kKleidungTabIndex = 2;
const int kMehrTabIndex = 3;

/// The shell controller (task 2.1, design D2/D7): holds the selected tab
/// index and the active season; resets both on sign-out / a new session.
///
/// `keepAlive: true` so the tab position survives screen pops inside the
/// tabs. Tab switches are user "jump" actions — they mutate only this
/// controller, never a navigation history (no tab-hopping back stack).
@Riverpod(keepAlive: true)
class ShellController extends _$ShellController {
  @override
  ShellState build() {
    // D7: sign-out mid-session (and any new session) resets the tab index
    // and drops the in-memory active season; the Kleidung tab re-resolves
    // from the persisted reference on the next selection.
    final session = ref.watch(authSessionControllerProvider);
    // Session identity: a NEW session (different sub, or signed-out after
    // being signed-in) resets the tab index; a pending restore (null key
    // after null key) does not.
    final key = switch (session) {
      AsyncData(:final value) => value?.sub,
      _ => null,
    };
    if (key != _sessionKey) {
      _sessionKey = key;
      _selectedIndex = kSeasonTabIndex;
    }
    final signedOut = switch (session) {
      AsyncData(:final value) => value == null,
      AsyncError() => true,
      _ => false,
    };
    if (signedOut) {
      _clearPersistedReference();
      return const ShellState();
    }
    // D5: the active season is resolved from the persisted reference
    // against the live (TTL-governed) seasons projection — the controller
    // only carries the resolved value as plain data.
    return ShellState(
      selectedIndex: _selectedIndex,
      activeSeason: ref.watch(activeSeasonResolutionProvider).value,
    );
  }

  int _selectedIndex = kSeasonTabIndex;

  /// Session identity the current tab/season state belongs to. A session
  /// change (sign-out or a new sign-in) resets the tab index — the shell
  /// never carries a previous session's position into a new one (D7).
  /// Restores going through `AsyncLoading` do NOT reset (same session
  /// resuming), matching the restore-pending gate semantics.
  String? _sessionKey;

  /// Switches the selected tab (a user "jump" — no history entry).
  void selectTab(int index) {
    if (index < 0 || index > kMehrTabIndex) return;
    _selectedIndex = index;
    state = ShellState(selectedIndex: index, activeSeason: state.activeSeason);
  }

  /// Sets the active season from the DTO the user acted on (CQRS boundary:
  /// the season context comes from the acted-on read row, never from a
  /// second projection lookup) and persists the reference best-effort.
  void setActiveSeason(SeasonView season) {
    state = ShellState(
      selectedIndex: state.selectedIndex,
      activeSeason: season,
    );
    unawaited(_persist(season.id));
  }

  /// Clears the active season (e.g. the referenced season was deleted and
  /// the resolution dropped it); removes the persisted reference.
  void clearActiveSeason() {
    state = ShellState(selectedIndex: state.selectedIndex, activeSeason: null);
    _clearPersistedReference();
  }

  /// Best-effort persistence of the active-season reference; a store
  /// failure never breaks the in-memory state. Refreshes the persisted-id
  /// provider once settled so the resolution converges.
  Future<void> _persist(String seasonId) async {
    final res = await ref
        .read(shellStateDaoProvider)
        .upsert(
          key: kActiveSeasonKey,
          value: seasonId,
          cachedAt: ref.read(clockProvider).now(),
        );
    res.fold((_) {}, (_) {});
    if (!ref.mounted) return;
    ref.invalidate(activeSeasonPersistedProvider);
  }

  /// Removes the persisted reference (sign-out / cleared season). Failures
  /// are swallowed as the in-memory state is already authoritative-null;
  /// the next boot simply resolves `null`.
  void _clearPersistedReference() {
    unawaited(
      ref.read(shellStateDaoProvider).delete(kActiveSeasonKey).then((r) {
        r.fold((_) {}, (_) {});
        if (!ref.mounted) return;
        ref.invalidate(activeSeasonPersistedProvider);
      }),
    );
  }
}
