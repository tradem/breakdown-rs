// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/auth_providers.dart';
import '../../auth/membership/membership_providers.dart';
import '../../auth/membership_gate.dart';
import '../../core/problem_error.dart';
import '../../core/result.dart';
import '../../data/cache/cache_generation.dart';
import '../../data/cache/costume_domains_cache_dao.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../../data/character_repository.dart';
import '../../domain/reconciliation/overlay_store.dart';
import '../../domain/reconciliation/reconcile_coordinator.dart';
import '../../domain/reconciliation/reconciliation_scheduler.dart';
import 'characters_state.dart';

part 'characters_controller.g.dart';

/// Character repository: owns network + Drift cache writes.
@riverpod
CharacterRepository characterRepository(Ref ref) => CharacterRepository(
  ref.watch(apiClientProvider),
  CharacterCacheDao(ref.watch(cacheDatabaseProvider)),
);

/// The injected season-scoped list-fetch seam
/// (`GET /v1/characters?season_id=…`). Tests override this provider with a
/// fake.
@riverpod
Future<Result<List<CharacterView>>> charactersListFetch(
  Ref ref,
  String seasonId,
) async {
  final repo = ref.watch(characterRepositoryProvider);
  final clock = ref.watch(clockProvider);
  final generation = ref.watch(cacheGenerationProvider);
  return repo.listBySeason(
    seasonId,
    clock: clock,
    fence: CacheWriteFence(
      generation: generation,
      isCurrentGeneration: (g) =>
          ref.mounted && ref.read(cacheGenerationProvider) == g,
    ),
  );
}

/// Retained last-good snapshot per season.
@Riverpod(keepAlive: true)
class CharactersPrevRows extends _$CharactersPrevRows {
  @override
  List<CharacterView> build(String seasonId) => const [];

  void set(List<CharacterView> rows) => state = rows;
}

/// The projection a screen reads from (seasons reference pattern).
class CharactersView {
  const CharactersView({required this.rows, required this.isStale, this.error});

  final List<CharacterView> rows;
  final bool isStale;
  final ProblemError? error;
}

/// Read-projection controller (seeder watches repository + fetch only).
@Riverpod(keepAlive: false)
class CharactersViewController extends _$CharactersViewController {
  @override
  AsyncValue<CharactersView> build(String seasonId) {
    final repo = ref.watch(characterRepositoryProvider);

    unawaited(() async {
      final cached = (await repo.readCached(seasonId))
          .getOrElse((_) => const <CharacterView>[]);
      if (!ref.mounted) return;
      if (cached.isNotEmpty ||
          ref.read(charactersPrevRowsProvider(seasonId)).isEmpty) {
        ref.read(charactersPrevRowsProvider(seasonId).notifier).set(cached);
      }
    }());

    final fetch = ref.watch(charactersListFetchProvider(seasonId));
    return switch (fetch) {
      AsyncData(:final value) => value.match(
        (err) => AsyncValue<CharactersView>.error(err, StackTrace.current),
        (rows) {
          unawaited(
            Future.microtask(() {
              if (!ref.mounted) return;
              ref.read(charactersPrevRowsProvider(seasonId).notifier).set(rows);
            }),
          );
          return AsyncValue<CharactersView>.data(
            CharactersView(rows: rows, isStale: false),
          );
        },
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<CharactersView>.error(error, stackTrace),
      AsyncLoading() => const AsyncValue<CharactersView>.loading(),
    };
  }
}

/// TTL-based cache staleness for one season's characters (issue #366).
@riverpod
Future<bool> charactersCacheStale(Ref ref, String seasonId) async {
  final repo = ref.watch(characterRepositoryProvider);
  final clock = ref.watch(clockProvider);
  try {
    return await repo.isCacheStale(seasonId, clock: clock);
  } on Object {
    return false;
  }
}

/// The projection a screen reads (selector).
@riverpod
CharactersView charactersView(Ref ref, String seasonId) {
  final async = ref.watch(charactersViewControllerProvider(seasonId));
  final prev = ref.watch(charactersPrevRowsProvider(seasonId));
  final ttlStale =
      ref.watch(charactersCacheStaleProvider(seasonId)).value ?? false;
  return switch (async) {
    AsyncData(:final value) => value,
    AsyncError(:final error) => CharactersView(
      rows: prev,
      isStale: prev.isNotEmpty,
      error: error is ProblemError
          ? error
          : const ProblemError(code: 'unknown'),
    ),
    AsyncLoading() => CharactersView(
      rows: prev,
      isStale: prev.isNotEmpty && ttlStale,
    ),
  };
}

/// Ephemeral optimistic overlay store per season (controller state, NOT
/// Drift — no global overlay store).
@Riverpod(keepAlive: true)
class CharactersOverlays extends _$CharactersOverlays {
  @override
  List<CharacterOverlay> build(String seasonId) => const [];

  void add(CharacterOverlay overlay) => state = overlayAdd(state, overlay);

  void markAllReconciling() => state = overlayMarkAllReconciling(state);

  void dropProjectedIds(Set<String> projectedIds) =>
      state = overlayDropProjectedIds(state, projectedIds);

  void markAllStale(String warning) =>
      state = overlayMarkAllStale(state, warning);
}

/// Last command failure per season, surfaced to the screen keyed on `code`.
@Riverpod(keepAlive: true)
class CharactersCommandError extends _$CharactersCommandError {
  @override
  ProblemError? build(String seasonId) => null;

  void set(ProblemError error) => state = error;

  void clear() => state = null;
}

/// Localized client-side copy for character command failures, keyed on the
/// stable problem `code` (never the server's localized `detail`).
String characterErrorCopy(ProblemError error) => switch (error.code) {
  'concurrency.conflict' ||
  'character.version_conflict' => 'Changed elsewhere — refresh and try again.',
  'authz.denied' || 'auth.session_required' => 'Please sign in to continue.',
  _ when error.code.startsWith('transport.') =>
    'Network problem — the change was not saved. Try again.',
  _ => 'The character could not be saved (${error.code}).',
};

/// `CharactersController(seasonId)` on the shared reconciliation runner:
/// create follows the optimistic-overlay pattern; contact/measurements are
/// full-replacement PATCH editors (prefilled, version echo, 409 → keyed
/// copy, never auto-bump).
@Riverpod(keepAlive: true)
class CharactersController extends _$CharactersController {
  ReconciliationCoordinator? _coordinator;

  ReconciliationCoordinator get _reconcile =>
      _coordinator ??= ReconciliationCoordinator(
        refetchProjectedIds: () async {
          final rows = await _refetchProjection();
          return rows?.map((c) => c.id).toList();
        },
        hasOverlays: () =>
            ref.read(charactersOverlaysProvider(seasonId)).isNotEmpty,
        markAllReconciling: () => ref
            .read(charactersOverlaysProvider(seasonId).notifier)
            .markAllReconciling(),
        dropProjectedIds: (ids) => ref
            .read(charactersOverlaysProvider(seasonId).notifier)
            .dropProjectedIds(ids),
        markAllStale: (warning) => ref
            .read(charactersOverlaysProvider(seasonId).notifier)
            .markAllStale(warning),
        scheduler: () => ref.read(reconciliationSchedulerProvider),
        isAlive: () => ref.mounted,
      );

  @override
  CharactersScreenState build(String seasonId) {
    final async = ref.watch(charactersViewControllerProvider(seasonId));
    final view = ref.watch(charactersViewProvider(seasonId));
    final projected = switch (async) {
      AsyncData(:final value) => AsyncValue<List<CharacterView>>.data(
        value.rows,
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<List<CharacterView>>.error(error, stackTrace),
      _ => const AsyncValue<List<CharacterView>>.loading(),
    };
    return CharactersScreenState(
      projected: projected,
      cachedRows: view.rows,
      isStale: view.isStale,
      overlays: ref.watch(charactersOverlaysProvider(seasonId)),
      commandError: ref.watch(charactersCommandErrorProvider(seasonId)),
    );
  }

  /// Creates a character (`POST /v1/characters` with `season_id` from the
  /// season read DTO — never from a second projection lookup).
  Future<Result<IdVersionResponse>> create({
    required String name,
    required String categoryWire,
  }) async {
    // AUTHZ-GATE: authenticated session required before any network call.
    if (await _resolveSession() == null) {
      const error = ProblemError(code: 'auth.session_required', status: 403);
      ref.read(charactersCommandErrorProvider(seasonId).notifier).set(error);
      return const Left(error);
    }
    final parsedCategory = tryParseCharacterCategory(categoryWire);
    if (parsedCategory == null) {
      // Unknown category variants strictly reject (no guessed meaning).
      const error = ProblemError(code: 'character.unknown_category');
      ref.read(charactersCommandErrorProvider(seasonId).notifier).set(error);
      return const Left(error);
    }
    final repo = ref.read(characterRepositoryProvider);
    final ack = await repo.create(
      CreateCharacterRequest(
        (b) => b
          ..seasonId = seasonId
          ..name = name
          ..category = parsedCategory,
      ),
    );
    return ack.match(
      (err) {
        ref.read(charactersCommandErrorProvider(seasonId).notifier).set(err);
        return Left<ProblemError, IdVersionResponse>(err);
      },
      (res) {
        ref.read(charactersCommandErrorProvider(seasonId).notifier).clear();
        ref
            .read(charactersOverlaysProvider(seasonId).notifier)
            .add(
              CharacterOverlay(
                id: res.id,
                name: name,
                category: categoryWire,
                status: OverlayStatus.acknowledged,
              ),
            );
        _reconcile.ackReceived();
        unawaited(reconcile());
        return Right<ProblemError, IdVersionResponse>(res);
      },
    );
  }

  /// Full-replacement contact editor (prefilled from the read DTO).
  Future<Result<int>> updateContact({
    required CharacterView character,
    required String? email,
    required String? phone,
  }) async {
    if (await _resolveSession() == null) {
      const error = ProblemError(code: 'auth.session_required', status: 403);
      ref.read(charactersCommandErrorProvider(seasonId).notifier).set(error);
      return const Left(error);
    }
    final repo = ref.read(characterRepositoryProvider);
    final res = await repo.updateContact(
      character.id,
      buildContactRequest(
        email: email,
        phone: phone,
        version: character.version,
      ),
    );
    return res.match(
      (err) {
        ref.read(charactersCommandErrorProvider(seasonId).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(charactersCommandErrorProvider(seasonId).notifier).clear();
        unawaited(refresh());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Full-replacement measurements editor (all seven fields; empty strings
  /// remain valid submissions — no client-side numeric validation).
  Future<Result<int>> updateMeasurements({
    required CharacterView character,
    required CharacterMeasurements measurements,
  }) async {
    if (await _resolveSession() == null) {
      const error = ProblemError(code: 'auth.session_required', status: 403);
      ref.read(charactersCommandErrorProvider(seasonId).notifier).set(error);
      return const Left(error);
    }
    final repo = ref.read(characterRepositoryProvider);
    final res = await repo.updateMeasurements(
      character.id,
      buildMeasurementsRequest(
        measurements: measurements,
        version: character.version,
      ),
    );
    return res.match(
      (err) {
        ref.read(charactersCommandErrorProvider(seasonId).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(charactersCommandErrorProvider(seasonId).notifier).clear();
        unawaited(refresh());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Scene-character binding: assign (picker over the season's characters;
  /// the scene `version` comes from the acted-on `SceneView`).
  ///
  /// // AUTHZ-GATE: `assign_costumes` capability checked before the call.
  Future<Result<int>> assignToScene({
    required String sceneId,
    required int sceneVersion,
    required String characterId,
  }) async {
    // AUTHZ-GATE: capability check before any network call.
    if (await _assignGateDeny() case final deny?) {
      return Left(ProblemError(code: deny.code, status: 403));
    }
    final repo = ref.read(characterRepositoryProvider);
    final res = await repo.assignToScene(
      sceneId,
      AssignCharacterRequest(
        (b) => b
          ..characterId = characterId
          ..version = sceneVersion,
      ),
    );
    return res.match(
      (err) {
        ref.read(charactersCommandErrorProvider(seasonId).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(charactersCommandErrorProvider(seasonId).notifier).clear();
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Scene-character binding: unassign (DELETE with `?version=`).
  ///
  /// // AUTHZ-GATE: `assign_costumes` capability checked before the call.
  Future<Result<int>> unassignFromScene({
    required String sceneId,
    required int sceneVersion,
    required String characterId,
  }) async {
    // AUTHZ-GATE: capability check before any network call.
    if (await _assignGateDeny() case final deny?) {
      return Left(ProblemError(code: deny.code, status: 403));
    }
    final repo = ref.read(characterRepositoryProvider);
    final res = await repo.unassignFromScene(
      sceneId,
      characterId,
      sceneVersion,
    );
    return res.match(
      (err) {
        ref.read(charactersCommandErrorProvider(seasonId).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(charactersCommandErrorProvider(seasonId).notifier).clear();
        return Right<ProblemError, int>(version);
      },
    );
  }

  Future<GateDeny?> _assignGateDeny() async {
    if (await _resolveSession() == null) {
      const error = ProblemError(code: 'auth.session_required', status: 403);
      ref.read(charactersCommandErrorProvider(seasonId).notifier).set(error);
      return const GateDeny('auth.session_required');
    }
    try {
      final res = await ref.read(membershipFetchProvider(seasonId).future);
      final gate = res.match(
        (_) => const GateDeny('membership.pending'),
        (dto) => checkAssignCapability(dto),
      );
      if (gate is GateDeny) {
        ref
            .read(charactersCommandErrorProvider(seasonId).notifier)
            .set(ProblemError(code: gate.code, status: 403));
        return gate;
      }
      return null;
    } on Object {
      return const GateDeny('membership.pending');
    }
  }

  Future<AuthSession?> _resolveSession() async {
    try {
      return await ref.read(authSessionControllerProvider.future);
    } on Object {
      return null;
    }
  }

  Future<void> reconcile() => _reconcile.reconcile();

  Future<void> refresh() async {
    ref.read(charactersCommandErrorProvider(seasonId).notifier).clear();
    await reconcile();
  }

  void dismissCommandError() =>
      ref.read(charactersCommandErrorProvider(seasonId).notifier).clear();

  Future<List<CharacterView>?> _refetchProjection() async {
    ref.invalidate(charactersListFetchProvider(seasonId));
    ref.invalidate(charactersCacheStaleProvider(seasonId));
    final res = await ref.read(charactersListFetchProvider(seasonId).future);
    return res.match((_) => null, (rows) => rows);
  }
}
