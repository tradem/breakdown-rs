// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:async';
import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/membership/membership_providers.dart';
import '../../core/problem_error.dart';
import '../../core/result.dart';
import '../../data/cache/cache_generation.dart';
import '../../data/cache/piece_domains_cache_dao.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../../data/outfit_repository.dart';
import '../../data/photo_repository.dart';
import '../../domain/reconciliation/reconciliation_scheduler.dart';
import '../../l10n/generated/app_localizations.dart';
import '../photos/widgets/photo_gallery.dart';
import 'outfits_state.dart';

part 'outfits_controller.g.dart';

/// Outfit repository: the character's composed looks (own network + Drift
/// slice). The scene-beat picker and the outfit screens both read here.
@riverpod
OutfitRepository outfitRepository(Ref ref) => OutfitRepository(
  ref.watch(apiClientProvider),
  OutfitCacheDao(ref.watch(cacheDatabaseProvider)),
);

/// The outfits of one character (fetch + snapshot-replace). The scene-beat
/// picker watches this; a fetch failure surfaces as a `Result` error.
@riverpod
Future<Result<List<OutfitView>>> characterOutfits(
  Ref ref,
  String characterId,
) async {
  final repo = ref.watch(outfitRepositoryProvider);
  final clock = ref.watch(clockProvider);
  final generation = ref.watch(cacheGenerationProvider);
  return repo.listByCharacter(
    characterId,
    clock: clock,
    fence: CacheWriteFence(
      generation: generation,
      isCurrentGeneration: (g) =>
          ref.mounted && ref.read(cacheGenerationProvider) == g,
    ),
  );
}

/// Photo repository for fitting photos (upload / bytes / delete / watch).
@riverpod
PhotoRepository outfitPhotoRepository(Ref ref) =>
    PhotoRepository(ref.watch(apiClientProvider));

/// One character's looks, fetched through the repository (network + Drift
/// snapshot-replace, character-scoped).
///
/// The injected seam: tests override this provider with a fake so neither the
/// network nor Drift is touched.
@riverpod
Future<Result<List<OutfitView>>> outfitsListFetch(
  Ref ref,
  String characterId,
) async {
  final repo = ref.watch(outfitRepositoryProvider);
  final clock = ref.watch(clockProvider);
  final generation = ref.watch(cacheGenerationProvider);
  return repo.listByCharacter(
    characterId,
    clock: clock,
    fence: CacheWriteFence(
      generation: generation,
      isCurrentGeneration: (g) =>
          ref.mounted && ref.read(cacheGenerationProvider) == g,
    ),
  );
}

/// Retained last-good snapshot per character (stale-on-error).
@Riverpod(keepAlive: true)
class OutfitsPrevRows extends _$OutfitsPrevRows {
  @override
  List<OutfitView> build(String characterId) => const [];

  void set(List<OutfitView> rows) => state = rows;
}

/// Read-projection controller (mirror of the pieces/seasons pattern).
@Riverpod(keepAlive: false)
class OutfitsViewController extends _$OutfitsViewController {
  @override
  AsyncValue<OutfitsView> build(String characterId) {
    final repo = ref.watch(outfitRepositoryProvider);

    unawaited(() async {
      final cached = (await repo.readCachedFresh(characterId))
          .match((err) => null, (value) => value.rows);
      if (!ref.mounted || cached == null) return;
      if (cached.isNotEmpty ||
          ref.read(outfitsPrevRowsProvider(characterId)).isEmpty) {
        ref.read(outfitsPrevRowsProvider(characterId).notifier).set(cached);
      }
    }());

    final fetch = ref.watch(outfitsListFetchProvider(characterId));
    return switch (fetch) {
      AsyncData(:final value) => value.match(
        (err) => AsyncValue<OutfitsView>.error(err, StackTrace.current),
        (rows) {
          unawaited(
            Future.microtask(() {
              if (!ref.mounted) return;
              ref.read(outfitsPrevRowsProvider(characterId).notifier).set(rows);
            }),
          );
          return AsyncValue<OutfitsView>.data(
            OutfitsView(rows: rows, isStale: false),
          );
        },
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<OutfitsView>.error(error, stackTrace),
      AsyncLoading() => const AsyncValue<OutfitsView>.loading(),
    };
  }
}

/// TTL-based cache staleness for one character's looks.
@riverpod
Future<bool> outfitsCacheStale(Ref ref, String characterId) async {
  final repo = ref.watch(outfitRepositoryProvider);
  final clock = ref.watch(clockProvider);
  final cached = await repo.readCachedFresh(characterId, clock: clock);
  return cached.match((_) => false, (value) => value.stale);
}

/// The projection a screen reads (selector pattern).
@riverpod
OutfitsView outfitsView(Ref ref, String characterId) {
  final async = ref.watch(outfitsViewControllerProvider(characterId));
  final prev = ref.watch(outfitsPrevRowsProvider(characterId));
  final ttlStale =
      ref.watch(outfitsCacheStaleProvider(characterId)).value ?? false;
  return switch (async) {
    AsyncData(:final value) => value,
    AsyncError(:final error) => OutfitsView(
      rows: prev,
      isStale: prev.isNotEmpty,
      error: error is ProblemError
          ? error
          : const ProblemError(code: 'unknown'),
    ),
    AsyncLoading() => OutfitsView(
      rows: prev,
      isStale: prev.isNotEmpty && ttlStale,
    ),
  };
}

/// Ephemeral row-level overlays per character (controller state, NOT Drift).
@Riverpod(keepAlive: true)
class OutfitsOverlays extends _$OutfitsOverlays {
  @override
  List<OutfitRowOverlay> build(String characterId) => const [];

  void add(OutfitRowOverlay overlay) =>
      state = [...state.where((o) => o.id != overlay.id), overlay];

  void markAllReconciling() => state = [
    for (final o in state) o.copyWithStatus(status: OverlayStatus.reconciling),
  ];

  void markAllStale(String warning) => state = [
    for (final o in state)
      o.copyWithStatus(status: OverlayStatus.stale, warning: warning),
  ];

  /// Drops the overlays whose version fence the fresh [projection] passes.
  void pruneWithProjection(List<OutfitView> projection) {
    final byId = {for (final o in projection) o.id: o};
    state = state.where((overlay) {
      final row = byId[overlay.id];
      if (row == null) return true;
      return !shouldClearOutfitOverlay(
        projection: row,
        acknowledgedVersion: overlay.acknowledgedVersion,
      );
    }).toList();
  }
}

/// Last command failure per character (surfaced keyed on the problem `code`).
@Riverpod(keepAlive: true)
class OutfitsCommandError extends _$OutfitsCommandError {
  @override
  OutfitCommandFailure? build(String characterId) => null;

  void set(OutfitCommandFailure failure) => state = failure;

  void clear() => state = null;
}

/// Localized copy for look command failures, keyed on the stable problem
/// `code` (never the server's localized `detail`).
String outfitErrorCopy(AppLocalizations l10n, ProblemError error) =>
    switch (error.code) {
      'concurrency.version-mismatch' => l10n.pieceErrorChanged,
      'outfit.forbidden' ||
      'piece.forbidden' ||
      'authz.denied' => l10n.outfitErrorForbidden,
      'domain.forbidden' => l10n.outfitErrorForbidden,
      'membership.pending' => l10n.outfitErrorMembership,
      'auth.session_required' => l10n.blocksCreateErrorSignIn,
      'outfit.not-found' || 'outfit.validation' => l10n.outfitDetailGone,
      'season.archived' => l10n.pieceErrorSeasonArchived,
      'season.not-found' => l10n.pieceErrorSeasonNotFound,
      'character.not-found' => l10n.characterDetailGone,
      // A garment added to the look that vanished from the wardrobe.
      'piece.not-found' => l10n.pieceErrorDetailNotFound,
      _ when error.code.startsWith('transport.') =>
        l10n.costumeCategoryErrorNetwork,
      _ => l10n.outfitErrorGeneric(error.code),
    };

/// Copy routed by the command ORIGIN (photo commands reuse the photo copy).
String outfitCommandErrorCopy(
  AppLocalizations l10n,
  OutfitCommandFailure failure,
) => failure.surface == OutfitCommandSurface.photo
    ? photoErrorCopy(l10n, failure.error)
    : outfitErrorCopy(l10n, failure.error);

/// `OutfitsController(characterId)`: one character's look commands with
/// optimistic-after-2xx + bounded-retry reconciliation (version fence).
@Riverpod(keepAlive: true)
class OutfitsController extends _$OutfitsController {
  @override
  OutfitsScreenState build(String characterId) {
    final view = ref.watch(outfitsViewProvider(characterId));
    final async = ref.watch(outfitsViewControllerProvider(characterId));
    return OutfitsScreenState(
      projected: switch (async) {
        AsyncData() when view.error == null => AsyncValue.data(view.rows),
        AsyncData() => AsyncValue.error(view.error!, StackTrace.current),
        AsyncError(:final error, :final stackTrace) =>
          AsyncValue<List<OutfitView>>.error(error, stackTrace),
        _ => const AsyncValue<List<OutfitView>>.loading(),
      },
      cachedRows: view.rows,
      isStale: view.isStale,
      overlays: ref.watch(outfitsOverlaysProvider(characterId)),
      commandError: ref.watch(outfitsCommandErrorProvider(characterId)),
    );
  }

  OutfitRepository get _repo => ref.read(outfitRepositoryProvider);

  // AUTHZ-GATE: every `/v1/outfits*` mutation runs a handler-internal
  // season-scoped costume-department check (the outfit's scope is its
  // character's season). Mirror it: await the backend-computed predicate and
  // deny only on a RESOLVED `false` — a pending fetch disables the affordance
  // in the UI, it never denies.
  //
  // Tri-state: `null` means the command may proceed. A fetch [Left] (network /
  // transport / DTO failure) is a PENDING state ('membership.pending'), never
  // a denial, and the failed provider state is dropped so the NEXT attempt
  // re-executes the fetch instead of replaying the retained failure (mirror of
  // the pieces `_photoGate` and seasons `archive` gates). A resolved `false`
  // is `domain.forbidden` — the code the server renders on every outfit route
  // (`authorize_outfit_scoped` → `ApiError::Forbidden` → 403
  // `domain.forbidden`); `outfit.forbidden`/`photo.forbidden` do not exist
  // server-side. An empty scope (the projection's `season_id` is nullable)
  // can never be verified, so it stays pending rather than skipping the
  // client-side mirror silently.
  Future<ProblemError?> _allowed(String seasonId) async {
    if (seasonId.isEmpty) {
      return const ProblemError(code: 'membership.pending', status: 403);
    }
    final ProblemError? denial;
    try {
      final membership = await ref.read(
        membershipFetchProvider(seasonId).future,
      );
      denial = membership.match(
        // Retry-ability: drop the failed result so a subsequent command
        // re-executes the fetch (the retained Left would otherwise be
        // replayed as a permanent pending).
        (_) => _pending(seasonId),
        (dto) => dto.hasActiveCostumeRoleInSeason
            ? null
            : const ProblemError(code: 'domain.forbidden', status: 403),
      );
    } on Object {
      // A throw (transport fault, provider torn down mid-await) is pending as
      // well — same retry-ability, same non-denial verdict.
      ref.invalidate(membershipFetchProvider(seasonId));
      return const ProblemError(code: 'membership.pending', status: 403);
    }
    return denial;
  }

  /// Drops the retained fetch failure so the NEXT command attempt re-executes
  /// the membership lookup instead of replaying it as a permanent pending.
  ProblemError _pending(String seasonId) {
    ref.invalidate(membershipFetchProvider(seasonId));
    return const ProblemError(code: 'membership.pending', status: 403);
  }

  void _fail(OutfitCommandSurface surface, ProblemError error) {
    ref
        .read(outfitsCommandErrorProvider(characterId).notifier)
        .set(OutfitCommandFailure(surface, error));
  }

  /// Clears the last command failure (banner dismiss / retry).
  void clearError() =>
      ref.read(outfitsCommandErrorProvider(characterId).notifier).clear();

  /// Refetches the character slice (pull-to-refresh, manual resync).
  Future<void> refresh() async {
    ref.invalidate(outfitsListFetchProvider(characterId));
    ref
        .read(outfitsOverlaysProvider(characterId).notifier)
        .markAllReconciling();
    await _resync();
  }

  /// Single-look read (the detail route); the projection row is authoritative.
  Future<Result<OutfitView>> loadDetail(String outfitId) => _repo.get(outfitId);

  /// Creates a look for this character and returns the new outfit id.
  Future<Result<String>> create({
    required String seasonId,
    required String name,
    List<String> pieceIds = const [],
  }) async {
    final denial = await _allowed(seasonId);
    if (denial != null) return Left(denial);
    final created = await _repo.create(
      characterId: characterId,
      name: name,
      pieceIds: pieceIds,
    );
    return created.match(
      (err) {
        _fail(OutfitCommandSurface.outfit, err);
        return Left<ProblemError, String>(err);
      },
      (ack) {
        ref.read(outfitsCommandErrorProvider(characterId).notifier).clear();
        _installCreateOverlay(
          id: ack.id,
          seasonId: seasonId,
          name: name,
          pieceIds: pieceIds,
          version: ack.version,
        );
        unawaited(_resync());
        return Right<ProblemError, String>(ack.id);
      },
    );
  }

  /// Forks [source] into an independent look (copy-on-write variant).
  Future<Result<String>> createVariant(
    OutfitView source, {
    String? name,
    String? seasonId,
  }) async {
    final scope = seasonId ?? source.seasonId ?? '';
    final denial = await _allowed(scope);
    if (denial != null) return Left(denial);
    final created = await _repo.createVariant(source.id, name: name);
    return created.match(
      (err) {
        _fail(OutfitCommandSurface.outfit, err);
        return Left<ProblemError, String>(err);
      },
      (ack) {
        ref.read(outfitsCommandErrorProvider(characterId).notifier).clear();
        _installCreateOverlay(
          id: ack.id,
          seasonId: source.seasonId ?? '',
          name: name ?? source.name,
          pieceIds: source.pieceIds.toList(),
          version: ack.version,
          notes: source.notes,
          variantOf: source.id,
        );
        unawaited(_resync());
        return Right<ProblemError, String>(ack.id);
      },
    );
  }

  Future<Result<int>> rename(
    OutfitView outfit,
    String name, {
    String? seasonId,
  }) async {
    final scope = seasonId ?? outfit.seasonId ?? '';
    final denial = await _allowed(scope);
    if (denial != null) return Left(denial);
    final result = await _repo.rename(
      outfit.id,
      RenameOutfitRequest(
        (b) => b
          ..name = name
          ..version = outfit.version,
      ),
    );
    return result.match(
      (err) {
        _fail(OutfitCommandSurface.outfit, err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(outfitsCommandErrorProvider(characterId).notifier).clear();
        _installOverlay(
          applyOutfitRenameOptimistic(outfit, name),
          acknowledgedVersion: version,
        );
        unawaited(_resync());
        return Right<ProblemError, int>(version);
      },
    );
  }

  Future<Result<int>> saveNotes(
    OutfitView outfit,
    String notes, {
    String? seasonId,
  }) async {
    final scope = seasonId ?? outfit.seasonId ?? '';
    final denial = await _allowed(scope);
    if (denial != null) return Left(denial);
    final result = await _repo.updateNotes(
      outfit.id,
      UpdateOutfitNotesRequest(
        (b) => b
          ..notes = notes
          ..version = outfit.version,
      ),
    );
    return result.match(
      (err) {
        _fail(OutfitCommandSurface.outfit, err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(outfitsCommandErrorProvider(characterId).notifier).clear();
        _installOverlay(
          applyOutfitNotesOptimistic(outfit, notes),
          acknowledgedVersion: version,
        );
        unawaited(_resync());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Joins a garment to the look (idempotent on the server; the overlay does
  /// not duplicate the row).
  Future<Result<int>> addPiece(
    OutfitView outfit,
    PieceView piece, {
    String? seasonId,
  }) async {
    final scope = seasonId ?? outfit.seasonId ?? '';
    final denial = await _allowed(scope);
    if (denial != null) return Left(denial);
    final result = await _repo.addPiece(
      outfit.id,
      AddOutfitPieceRequest(
        (b) => b
          ..pieceId = piece.id
          ..version = outfit.version,
      ),
    );
    return result.match(
      (err) {
        _fail(OutfitCommandSurface.outfit, err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(outfitsCommandErrorProvider(characterId).notifier).clear();
        _installOverlay(
          applyOutfitAddPieceOptimistic(
            outfit,
            OutfitPieceView(
              (b) => b
                ..pieceId = piece.id
                ..position = outfit.pieces.length
                ..name = piece.name
                ..categoryId = piece.categoryId
                ..categoryName = piece.categoryName,
            ),
          ),
          acknowledgedVersion: version,
        );
        unawaited(_resync());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Removes a garment from the look (version echo guards the concurrency).
  Future<Result<int>> removePiece(
    OutfitView outfit,
    String pieceId, {
    String? seasonId,
  }) async {
    final scope = seasonId ?? outfit.seasonId ?? '';
    final denial = await _allowed(scope);
    if (denial != null) return Left(denial);
    final result = await _repo.removePiece(outfit.id, pieceId, outfit.version);
    return result.match(
      (err) {
        _fail(OutfitCommandSurface.outfit, err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(outfitsCommandErrorProvider(characterId).notifier).clear();
        _installOverlay(
          applyOutfitRemovePieceOptimistic(outfit, pieceId),
          acknowledgedVersion: version,
        );
        unawaited(_resync());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Raw-bytes fitting-photo upload (`POST /v1/outfits/{id}/photos`).
  Future<Result<PhotoView>> uploadPhoto({
    required OutfitView outfit,
    required Uint8List bytes,
    required String contentType,
    String? seasonId,
  }) async {
    final scope = seasonId ?? outfit.seasonId ?? '';
    final denial = await _allowed(scope);
    if (denial != null) return Left(denial);
    final result = await ref
        .read(outfitPhotoRepositoryProvider)
        .uploadOutfit(outfit.id, bytes, contentType);
    result.match((err) => _fail(OutfitCommandSurface.photo, err), (_) {
      ref.read(outfitsCommandErrorProvider(characterId).notifier).clear();
      unawaited(_resync());
    });
    return result;
  }

  /// Fitting-photo delete (`DELETE /v1/outfits/{id}/photos/{photo_id}`).
  Future<Result<void>> deletePhoto({
    required OutfitView outfit,
    required String photoId,
    String? seasonId,
  }) async {
    final scope = seasonId ?? outfit.seasonId ?? '';
    final denial = await _allowed(scope);
    if (denial != null) return Left(denial);
    final result = await ref
        .read(outfitPhotoRepositoryProvider)
        .deleteOutfitPhoto(outfit.id, photoId);
    result.match((err) => _fail(OutfitCommandSurface.photo, err), (_) {
      ref.read(outfitsCommandErrorProvider(characterId).notifier).clear();
      unawaited(_resync());
    });
    return result;
  }

  void _installOverlay(OutfitView overlay, {required int acknowledgedVersion}) {
    ref
        .read(outfitsOverlaysProvider(characterId).notifier)
        .add(
          OutfitRowOverlay(
            id: overlay.id,
            overlay: overlay,
            acknowledgedVersion: acknowledgedVersion,
            status: OverlayStatus.acknowledged,
          ),
        );
  }

  void _installCreateOverlay({
    required String id,
    required String seasonId,
    required String name,
    required List<String> pieceIds,
    required int version,
    String notes = '',
    String? variantOf,
  }) {
    final createdAt = ref.read(clockProvider).now();
    final overlay = OutfitView(
      (b) => b
        ..id = id
        ..characterId = characterId
        ..name = name
        ..notes = notes
        ..variantOf = variantOf
        ..seasonId = seasonId.isEmpty ? null : seasonId
        ..version = version
        ..updatedAt = createdAt
        ..pieceIds.replace(BuiltList<String>(pieceIds))
        ..pieces.replace(BuiltList<OutfitPieceView>())
        ..photos.replace(BuiltList<OutfitPhotoView>()),
    );
    _installOverlay(overlay, acknowledgedVersion: version);
  }

  /// Bounded-retry resync of the character slice; overlays are pruned by the
  /// version fence, and a stale overlay is retained with the warning code
  /// (never silently dropped) when the budget is exhausted.
  Future<void> _resync() async {
    final scheduler = ref.read(reconciliationSchedulerProvider);
    // The TTL staleness verdict is re-read alongside the refetch, so a
    // reconciled row does not keep rendering the stale banner (mirror of the
    // pieces `_refetchProjection`).
    ref.invalidate(outfitsCacheStaleProvider(characterId));
    for (var attempt = 0; attempt < kMaxReconcileAttempts; attempt++) {
      if (attempt > 0) await scheduler.tick(attempt - 1);
      if (!ref.mounted) return;
      ref.invalidate(outfitsListFetchProvider(characterId));
      final fetched = await ref.read(
        outfitsListFetchProvider(characterId).future,
      );
      if (!ref.mounted) return;
      final rows = fetched.match((_) => null, (value) => value);
      if (rows == null) continue;
      ref.read(outfitsPrevRowsProvider(characterId).notifier).set(rows);
      ref
          .read(outfitsOverlaysProvider(characterId).notifier)
          .pruneWithProjection(rows);
      if (ref.read(outfitsOverlaysProvider(characterId)).isEmpty) return;
    }
    // Budget exhausted: retain the optimistic rows and tell the user to
    // refresh — never restore the pre-command row silently.
    ref
        .read(outfitsOverlaysProvider(characterId).notifier)
        .markAllStale(kReconcileStaleWarningCode);
  }
}
