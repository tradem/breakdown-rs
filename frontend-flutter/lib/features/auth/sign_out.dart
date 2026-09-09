// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../auth/active_block.dart';
import '../../auth/active_block_store.dart';
import '../../auth/auth_providers.dart';
import '../../auth/membership/membership_providers.dart';
import '../../core/problem_error.dart';
import '../../core/result.dart';
import '../../data/ai_import_providers.dart';
import '../../features/ai_import/ai_config/ai_config_controller.dart'
    show aiImportHandoffProvider;
import '../../features/ai_import/import_jobs/job_status_controller.dart';
import '../../data/cache/ai_import_jobs_cache_dao.dart';
import '../../data/cache/cache_generation.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../../data/settings/api_base_override_store.dart';
import '../../data/settings/api_base_validation.dart';
import '../../auth/season_membership_provider.dart';
import '../blocks/blocks_controller.dart';
import '../characters/characters_controller.dart';
import '../costume_categories/costume_categories_controller.dart';
import '../costumes/costumes_controller.dart';
import '../episodes/episodes_controller.dart';
import '../scenes/scenes_controller.dart';
import '../seasons/seasons_controller.dart';
import '../photos/capture.dart';
import '../photos/widgets/photo_gallery.dart';
import '../shooting_days/shooting_days_controller.dart';
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
    // Decoded photo bytes are sensitive (CWE-524): drop the in-memory LRU
    // before the next session starts (Drift never persisted them).
    ref.read(photoBytesLruProvider).clear();
    // Active-block scopes are identity-scoped (issue #382): wipe the
    // persisted per-season map so the next session never inherits it. A
    // clear failure fails the session closed, like the cache-clear failure
    // above — stale identity state must never survive sign-out.
    final scopesCleared = await ref.read(activeBlockStoreProvider).clear();
    final scopesError = scopesCleared.getLeft().toNullable();
    if (scopesError != null) {
      await ref
          .read(authSessionControllerProvider.notifier)
          .failSession(scopesError);
    }
    // AI-import state is identity-scoped (`flutter-ai-import` design §3):
    // the secure-storage hand-off (config id + remembered job ids, keyed
    // by the authenticated `sub`) and the Drift job rows are wiped so the
    // next session never reads the previous user's ids. Failures fail the
    // session closed (same discipline as the scope clear above).
    final handoffCleared = await ref.read(aiImportHandoffStoreProvider).clear();
    final handoffError = handoffCleared.getLeft().toNullable();
    if (handoffError != null) {
      await ref
          .read(authSessionControllerProvider.notifier)
          .failSession(handoffError);
    }
    // The Drift job rows clear goes through the DAO directly (no API
    // client needed — a network dependency in the sign-out path would
    // couple identity teardown to transport availability).
    String? jobsError;
    try {
      await AiImportJobsCacheDao(ref.read(cacheDatabaseProvider)).clear();
    } on Object catch (e) {
      jobsError = '$e';
    }
    if (jobsError != null) {
      await ref
          .read(authSessionControllerProvider.notifier)
          .failSession(
            ProblemError(code: 'cache.clear_failed', detail: jobsError),
          );
    }
    ref.invalidate(aiJobStatusControllerProvider);
    ref.invalidate(aiImportHandoffProvider);
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
    // Issue #378 (review): clear the active-block scope BEFORE switching
    // the base — the Dio rebuild triggered by `set(base)` would otherwise
    // issue requests to the new backend with the old backend's block id.
    // The second invalidation in `_invalidateReadScope` below is kept:
    // it clears a scope set mid-switch (fail-closed).
    ref.invalidate(activeBlockProvider);
    // Block ids are backend-scoped (issue #382): wipe the persisted
    // per-season map BEFORE switching the base — otherwise the gate would
    // restore the old backend's block id against the new backend (403).
    // A clear failure fails the session closed AND returns `Err`, like the
    // cache failure below.
    final scopesCleared = await ref.read(activeBlockStoreProvider).clear();
    final scopesError = scopesCleared.getLeft().toNullable();
    if (scopesError != null) {
      await ref
          .read(authSessionControllerProvider.notifier)
          .failSession(scopesError);
      return Left(scopesError);
    }
    ref.invalidate(activeBlockPersistedProvider);
    // AI-import ids are backend-scoped (`flutter-ai-import` design §3):
    // the hand-off store and the Drift job rows are wiped BEFORE the
    // switch (a remembered id from the old backend must never be sent to
    // the new one). A failure fails the session closed AND returns Err.
    final handoffCleared = await ref.read(aiImportHandoffStoreProvider).clear();
    final handoffError = handoffCleared.getLeft().toNullable();
    if (handoffError != null) {
      await ref
          .read(authSessionControllerProvider.notifier)
          .failSession(handoffError);
      return Left(handoffError);
    }
    String? jobsError;
    try {
      await AiImportJobsCacheDao(ref.read(cacheDatabaseProvider)).clear();
    } on Object catch (e) {
      jobsError = '$e';
    }
    if (jobsError != null) {
      final problem = ProblemError(
        code: 'cache.clear_failed',
        detail: jobsError,
      );
      await ref
          .read(authSessionControllerProvider.notifier)
          .failSession(problem);
      return Left(problem);
    }
    ref.invalidate(aiImportHandoffProvider);
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
  /// no cross-identity rows, overlays, or membership reads survive. The
  /// costume-domain families (`flutter-costume-domains`: costumes,
  /// characters, shooting days) reset for the same reason — their keepAlive
  /// `*PrevRows` would otherwise serve the previous session's rows after a
  /// failed refetch (the empty-cache branch preserves nonempty state).
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
      ..invalidate(costumeCategoriesShowArchivedProvider)
      ..invalidate(costumesControllerProvider)
      ..invalidate(costumesViewControllerProvider)
      ..invalidate(costumesListFetchProvider)
      ..invalidate(costumesPrevRowsProvider)
      ..invalidate(costumesOverlaysProvider)
      ..invalidate(costumesCommandErrorProvider)
      ..invalidate(charactersControllerProvider)
      ..invalidate(charactersViewControllerProvider)
      ..invalidate(charactersListFetchProvider)
      ..invalidate(charactersPrevRowsProvider)
      ..invalidate(charactersOverlaysProvider)
      ..invalidate(charactersCommandErrorProvider)
      ..invalidate(shootingDaysControllerProvider)
      ..invalidate(shootingDaysViewControllerProvider)
      ..invalidate(shootingDaysListFetchProvider)
      ..invalidate(shootingDaysPrevRowsProvider)
      ..invalidate(shootingDaysOverlaysProvider)
      ..invalidate(shootingDaysCommandErrorProvider)
      // Session-scoped photo rationale: the next user must see the
      // pre-permission rationale instead of inheriting `seen`.
      ..invalidate(photoRationaleSeenProvider)
      // Active-block scope (issue #378): identity-scoped — the next
      // session must never inherit the previous user's block, so reset
      // to the unset (`null`) scope rather than merely clearing rows.
      // The persisted per-season map (issue #382) was already wiped by
      // the caller; this drops the provider's cached read alongside it.
      ..invalidate(activeBlockProvider)
      ..invalidate(activeBlockPersistedProvider);
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
      ..invalidate(currentMembershipProvider)
      // Block ids are backend-scoped (issue #378): clears a scope set
      // mid-switch; the pre-switch scope was already cleared in
      // `_applyNewBase` before `set(base)` so no request ever pairs the
      // new base with the old backend's block id. The persisted map
      // (issue #382) was wiped there too; this drops its cached read.
      ..invalidate(activeBlockProvider)
      ..invalidate(activeBlockPersistedProvider);
  }
}

final sessionResetProvider = NotifierProvider<SessionReset, void>(
  SessionReset.new,
);
