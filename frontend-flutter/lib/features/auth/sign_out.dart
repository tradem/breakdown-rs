// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../auth/auth_providers.dart';
import '../../auth/membership/membership_providers.dart';
import '../../core/problem_error.dart';
import '../../core/result.dart';
import '../../data/cache/cache_generation.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../../data/settings/api_base_override_store.dart';
import '../../data/settings/api_base_validation.dart';
import '../../auth/season_membership_provider.dart';
import '../blocks/blocks_controller.dart';
import '../costume_categories/costume_categories_controller.dart';
import '../episodes/episodes_controller.dart';
import '../scenes/scenes_controller.dart';
import '../seasons/seasons_controller.dart';
import 'login_screen.dart';

/// Session-reset coordinator (tasks 4.2/6.3): the single ordered path for
/// sign-out AND runtime backend switches.
///
/// - Sign-out: ordered cleanup in [AuthSessionController.signOut] (clear
///   tokens → gate to `LoginScreen`, fail-closed) → empty the Drift read
///   cache → reset keepAlive UI/session state. The next session can never
///   render the previous user's projections.
/// - Backend switch ([switchBackend]): persist the override → bump the
///   cache-write generation (fences in-flight reads) → rebuild the Dio
///   (provider-driven, same pinned `SecurityContext`) → await the Drift
///   clear → invalidate read providers.
///
/// Reset steps run AFTER the gate swap (sign-out) on purpose: the old
/// subtree is unwatched then, so invalidating resets state without rebuild
/// storms or projection refetches (no post-signout network — asserted in
/// tests). Auto-dispose providers (list fetch, membership fetch, view
/// controller) die with the subtree on their own; session-agnostic keepAlive
/// transports (`dio`, repositories, `oidcClient`) intentionally survive
/// (design.md §7.1).
///
/// Lives here (features-side) rather than in `auth_providers.dart` because
/// that file cannot import `features/` providers without an import cycle.
class SessionReset extends Notifier<void> {
  @override
  void build() {}

  /// Full sign-out gesture (task 4.2). Never throws — failures surface as
  /// gate state (`AsyncError`), so menu callers need no error handling.
  Future<void> signOut() async {
    await ref.read(authSessionControllerProvider.notifier).signOut();
    // Fence first: in-flight reads from the old session discard their
    // writes from here on (the coordinator's own clear below is unfenced).
    ref.read(cacheGenerationProvider.notifier).bump();
    final emptied = await ref.read(seasonRepositoryProvider).clearCache();
    final emptyError = emptied.getLeft().toNullable();
    if (emptyError != null) {
      await ref
          .read(authSessionControllerProvider.notifier)
          .failSession(emptyError);
    }
    _invalidateSessionScope();
  }

  /// Switches the runtime backend base (task 6.3): persist → fence →
  /// rebuild → clear → invalidate. Keeps the session (tokens are IdP-scoped,
  /// not backend-scoped). Returns `Err` for validation, persistence, or
  /// cache-clear failures — the dialog renders it inline; a cache failure
  /// additionally fails the session closed (stale rows must never survive
  /// a base change).
  Future<Result<void>> switchBackend(String base) async {
    final config = ref.read(appConfigProvider);
    final valid = validateApiBase(base, isDev: config.isDev);
    final canonical = valid.getRight().toNullable();
    if (canonical == null) {
      return Left(valid.getLeft().toNullable()!);
    }
    final saved = await ApiBaseOverrideStore.secure().write(canonical);
    final saveError = saved.getLeft().toNullable();
    if (saveError != null) {
      return Left(saveError);
    }
    return _applyNewBase(canonical);
  }

  /// Resets the runtime base to the compile-time default (settings dialog
  /// reset action, task 6.4): clears the persisted override, then applies
  /// the default through the same fenced path as [switchBackend].
  Future<Result<void>> resetBackendToDefault() async {
    final cleared = await ApiBaseOverrideStore.secure().clear();
    final clearError = cleared.getLeft().toNullable();
    if (clearError != null) {
      return Left(clearError);
    }
    return _applyNewBase(null);
  }

  /// Shared tail of [switchBackend] (`base`) and [resetBackendToDefault]
  /// (`null` = compile-time default): fence in-flight reads → rebuild the
  /// Dio (provider-driven from the notifier set, same pinned
  /// `SecurityContext`) → await the Drift clear → invalidate read
  /// providers so the next read refetches against the new reality. A cache
  /// failure fails the session closed AND returns `Err`.
  Future<Result<void>> _applyNewBase(String? base) async {
    // Fence before rebuild: reads in flight against the old base discard
    // their writes; the Dio rebuild follows from the notifier set below.
    ref.read(cacheGenerationProvider.notifier).bump();
    ref.read(runtimeApiBaseProvider.notifier).set(base);
    final emptied = await ref.read(seasonRepositoryProvider).clearCache();
    final emptyError = emptied.getLeft().toNullable();
    if (emptyError != null) {
      await ref
          .read(authSessionControllerProvider.notifier)
          .failSession(emptyError);
      return Left(emptyError);
    }
    // Refetch against the new base (the gate stays — session is kept).
    ref.invalidate(seasonsListFetchProvider);
    _invalidateReadScope();
    return const Right<ProblemError, void>(null);
  }

  /// Resets keepAlive UI/session state after sign-out (identity change:
  /// nothing from the previous session may survive — including the
  /// retained snapshot rows). The hierarchy families
  /// (`flutter-hierarchy-navigation`) reset alongside the seasons scope so
  /// no cross-identity rows, overlays, or membership reads survive.
  void _invalidateSessionScope() {
    ref
      ..invalidate(seasonOverlaysProvider)
      ..invalidate(seasonCommandErrorProvider)
      ..invalidate(seasonsPrevRowsProvider)
      ..invalidate(seasonsControllerProvider)
      ..invalidate(signInErrorProvider)
      ..invalidate(membershipFetchProvider)
      ..invalidate(currentMembershipProvider)
      ..invalidate(seasonMembershipCacheProvider)
      ..invalidate(blocksControllerProvider)
      ..invalidate(blocksViewControllerProvider)
      ..invalidate(blocksListFetchProvider)
      ..invalidate(blocksPrevRowsProvider)
      ..invalidate(blocksOverlaysProvider)
      ..invalidate(blocksCommandErrorProvider)
      ..invalidate(episodesControllerProvider)
      ..invalidate(episodesViewControllerProvider)
      ..invalidate(episodesListFetchProvider)
      ..invalidate(episodesPrevRowsProvider)
      ..invalidate(episodesOverlaysProvider)
      ..invalidate(episodesCommandErrorProvider)
      ..invalidate(scenesControllerProvider)
      ..invalidate(scenesViewControllerProvider)
      ..invalidate(scenesListFetchProvider)
      ..invalidate(scenesPrevRowsProvider)
      ..invalidate(scenesOverlaysProvider)
      ..invalidate(scenesCommandErrorProvider)
      ..invalidate(costumeCategoriesControllerProvider)
      ..invalidate(costumeCategoriesViewControllerProvider)
      ..invalidate(costumeCategoriesListFetchProvider)
      ..invalidate(costumeCategoriesPrevRowsProvider)
      ..invalidate(costumeCategoriesOverlaysProvider)
      ..invalidate(costumeCategoriesCommandErrorProvider)
      ..invalidate(costumeCategoriesShowArchivedProvider);
  }

  /// Resets read state after a backend switch (session kept): like
  /// [_invalidateSessionScope] but RETAINS the snapshot rows — a failed
  /// refetch against the new base then renders the stale banner over the
  /// retained rows instead of an empty screen (task 6.7).
  void _invalidateReadScope() {
    ref
      ..invalidate(seasonOverlaysProvider)
      ..invalidate(seasonCommandErrorProvider)
      ..invalidate(seasonsControllerProvider)
      ..invalidate(membershipFetchProvider)
      ..invalidate(currentMembershipProvider);
  }
}

final sessionResetProvider = NotifierProvider<SessionReset, void>(
  SessionReset.new,
);
