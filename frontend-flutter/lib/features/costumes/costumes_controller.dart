// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'dart:async';
import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/auth_providers.dart';
import '../../auth/membership/membership_providers.dart';
import '../../auth/membership_gate.dart';
import '../../core/problem_error.dart';
import '../../core/result.dart';
import '../../core/uuid.dart';
import '../../data/cache/cache_generation.dart';
import '../../data/cache/costume_domains_cache_dao.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../../data/costume_repository.dart';
import '../../data/photo_repository.dart';
import '../../domain/reconciliation/reconcile_coordinator.dart';
import '../characters/characters_controller.dart';
import '../../domain/reconciliation/reconciliation_scheduler.dart';
import 'costumes_state.dart';

part 'costumes_controller.g.dart';

/// Costume repository: owns network + Drift cache writes.
@riverpod
CostumeRepository costumeRepository(Ref ref) => CostumeRepository(
  ref.watch(apiClientProvider),
  CostumeCacheDao(ref.watch(cacheDatabaseProvider)),
);

/// Photo repository (upload / bytes / delete / watch).
@riverpod
PhotoRepository costumePhotoRepository(Ref ref) =>
    PhotoRepository(ref.watch(apiClientProvider));

/// The injected season-scoped list-fetch seam
/// (`GET /v1/costumes?season_id=…`). Tests override this provider with a
/// fake.
@riverpod
Future<Result<List<CostumeView>>> costumesListFetch(
  Ref ref,
  String seasonId,
) async {
  final repo = ref.watch(costumeRepositoryProvider);
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
class CostumesPrevRows extends _$CostumesPrevRows {
  @override
  List<CostumeView> build(String seasonId) => const [];

  void set(List<CostumeView> rows) => state = rows;
}

/// The projection a screen reads from (seasons reference pattern).
class CostumesView {
  const CostumesView({required this.rows, required this.isStale, this.error});

  final List<CostumeView> rows;
  final bool isStale;
  final ProblemError? error;
}

/// Read-projection controller (seeder watches repository + fetch only).
@Riverpod(keepAlive: false)
class CostumesViewController extends _$CostumesViewController {
  @override
  AsyncValue<CostumesView> build(String seasonId) {
    final repo = ref.watch(costumeRepositoryProvider);

    unawaited(() async {
      final cached = (await repo.readCached(seasonId))
          .getOrElse((_) => const <CostumeView>[]);
      if (!ref.mounted) return;
      if (cached.isNotEmpty ||
          ref.read(costumesPrevRowsProvider(seasonId)).isEmpty) {
        ref.read(costumesPrevRowsProvider(seasonId).notifier).set(cached);
      }
    }());

    final fetch = ref.watch(costumesListFetchProvider(seasonId));
    return switch (fetch) {
      AsyncData(:final value) => value.match(
        (err) => AsyncValue<CostumesView>.error(err, StackTrace.current),
        (rows) {
          unawaited(
            Future.microtask(() {
              if (!ref.mounted) return;
              ref.read(costumesPrevRowsProvider(seasonId).notifier).set(rows);
            }),
          );
          return AsyncValue<CostumesView>.data(
            CostumesView(rows: rows, isStale: false),
          );
        },
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<CostumesView>.error(error, stackTrace),
      AsyncLoading() => const AsyncValue<CostumesView>.loading(),
    };
  }
}

/// TTL-based cache staleness for one season's costumes (issue #366).
@riverpod
Future<bool> costumesCacheStale(Ref ref, String seasonId) async {
  final repo = ref.watch(costumeRepositoryProvider);
  final clock = ref.watch(clockProvider);
  try {
    return await repo.isCacheStale(seasonId, clock: clock);
  } on Object {
    return false;
  }
}

/// The projection a screen reads (selector).
@riverpod
CostumesView costumesView(Ref ref, String seasonId) {
  final async = ref.watch(costumesViewControllerProvider(seasonId));
  final prev = ref.watch(costumesPrevRowsProvider(seasonId));
  final ttlStale =
      ref.watch(costumesCacheStaleProvider(seasonId)).value ?? false;
  return switch (async) {
    AsyncData(:final value) => value,
    AsyncError(:final error) => CostumesView(
      rows: prev,
      isStale: prev.isNotEmpty,
      error: error is ProblemError
          ? error
          : const ProblemError(code: 'unknown'),
    ),
    AsyncLoading() => CostumesView(
      rows: prev,
      isStale: prev.isNotEmpty && ttlStale,
    ),
  };
}

/// Ephemeral row-level optimistic overlays per season (controller state,
/// NOT Drift). Entries clear by the version fence during the projection
/// refetch — never by projected id (a row-level edit keeps its id).
@Riverpod(keepAlive: true)
class CostumesOverlays extends _$CostumesOverlays {
  @override
  List<CostumeRowOverlay> build(String seasonId) => const [];

  void add(CostumeRowOverlay overlay) =>
      state = [...state.where((o) => o.id != overlay.id), overlay];

  void markAllReconciling() => state = [
    for (final o in state) o.copyWithStatus(status: OverlayStatus.reconciling),
  ];

  /// Drops overlays whose version fence the fresh [projection] passes.
  void pruneWithProjection(List<CostumeView> projection) {
    final byId = {for (final c in projection) c.id: c};
    state = state.where((o) {
      final row = byId[o.id];
      // Create-path overlays (id absent) clear once the id projects.
      if (row == null) return true;
      return !shouldClearCostumeOverlay(
        projection: row,
        acknowledgedVersion: o.acknowledgedVersion,
      );
    }).toList();
  }

  void dropProjectedIds(Set<String> projectedIds) {
    // Id-based drops never apply to row-level edits (same id before and
    // after); the fence in [pruneWithProjection] owns clearing. Create-path
    // overlays are pruned there too once the projection carries the id
    // with a satisfying version.
  }

  void markAllStale(String warning) => state = [
    for (final o in state)
      o.copyWithStatus(status: OverlayStatus.stale, warning: warning),
  ];
}

/// Last command failure per season, surfaced to the screen keyed on `code`.
@Riverpod(keepAlive: true)
class CostumesCommandError extends _$CostumesCommandError {
  @override
  ProblemError? build(String seasonId) => null;

  void set(ProblemError error) => state = error;

  void clear() => state = null;
}

/// Localized client-side copy for costume command failures, keyed on the
/// stable problem `code` (never the server's localized `detail`).
String costumeErrorCopy(ProblemError error) => switch (error.code) {
  'concurrency.conflict' ||
  'costume.version_conflict' => 'Changed elsewhere — refresh and try again.',
  'costume.forbidden' ||
  'authz.denied' => 'You need an active costume role in this season.',
  'membership.pending' =>
    'Could not verify permissions — check the connection and retry.',
  'auth.session_required' => 'Please sign in to continue.',
  _ when error.code.startsWith('transport.') =>
    'Network problem — the change was not saved. Try again.',
  _ => 'The costume could not be saved (${error.code}).',
};

/// `CostumesController(seasonId)` on the shared reconciliation runner.
@Riverpod(keepAlive: true)
class CostumesController extends _$CostumesController {
  ReconciliationCoordinator? _coordinator;

  ReconciliationCoordinator get _reconcile =>
      _coordinator ??= ReconciliationCoordinator(
        refetchProjectedIds: () async {
          final rows = await _refetchProjection();
          return rows?.map((c) => c.id).toList();
        },
        hasOverlays: () =>
            ref.read(costumesOverlaysProvider(seasonId)).isNotEmpty,
        markAllReconciling: () => ref
            .read(costumesOverlaysProvider(seasonId).notifier)
            .markAllReconciling(),
        dropProjectedIds: (ids) => ref
            .read(costumesOverlaysProvider(seasonId).notifier)
            .dropProjectedIds(ids),
        markAllStale: (warning) => ref
            .read(costumesOverlaysProvider(seasonId).notifier)
            .markAllStale(warning),
        scheduler: () => ref.read(reconciliationSchedulerProvider),
        isAlive: () => ref.mounted,
      );

  @override
  CostumesScreenState build(String seasonId) {
    final async = ref.watch(costumesViewControllerProvider(seasonId));
    final view = ref.watch(costumesViewProvider(seasonId));
    final projected = switch (async) {
      AsyncData(:final value) => AsyncValue<List<CostumeView>>.data(value.rows),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<List<CostumeView>>.error(error, stackTrace),
      _ => const AsyncValue<List<CostumeView>>.loading(),
    };
    return CostumesScreenState(
      projected: projected,
      cachedRows: view.rows,
      isStale: view.isStale,
      overlays: ref.watch(costumesOverlaysProvider(seasonId)),
      // Read-DTO join for the assignment display names (never aggregate
      // reconstruction): the characters projection maps ids to names.
      characterNames: {
        for (final c in ref.watch(charactersViewProvider(seasonId)).rows)
          c.id: c.name,
      },
      commandError: ref.watch(costumesCommandErrorProvider(seasonId)),
    );
  }

  /// Client-side AUTHZ-GATE for costume commands (assign/unassign):
  /// the `assign_costumes` capability is checked BEFORE any network call.
  /// A denial short-circuits with the localized 403 narrative and never
  /// issues the request (provable by a fake repo call count of zero).
  Future<GateDecision> _assignGate() async {
    final session = await _resolveSession();
    if (session == null) return const GateDeny('auth.session_required');
    GateDecision gate;
    try {
      final res = await ref.read(membershipFetchProvider(seasonId).future);
      gate = res.match(
        (_) => const GateDeny('membership.pending'),
        (dto) => checkAssignCapability(dto),
      );
    } on Object {
      gate = const GateDeny('membership.pending');
    }
    return gate;
  }

  /// Client-side AUTHZ-GATE for photo commands (upload/delete): the
  /// season-scoped photo policy mirror (`upload_continuity_photos`).
  Future<GateDecision> _photoGate() async {
    final session = await _resolveSession();
    if (session == null) return const GateDeny('auth.session_required');
    GateDecision gate;
    try {
      final res = await ref.read(membershipFetchProvider(seasonId).future);
      gate = res.match(
        (_) => const GateDeny('membership.pending'),
        (dto) => checkPhotoCapability(dto),
      );
    } on Object {
      gate = const GateDeny('membership.pending');
    }
    return gate;
  }

  GateDecision? _deny(GateDecision gate) {
    if (gate is GateDeny) {
      final error = ProblemError(code: gate.code, status: 403);
      ref.read(costumesCommandErrorProvider(seasonId).notifier).set(error);
      return gate;
    }
    return null;
  }

  /// Creates a costume shell (empty-body contract D1) and immediately
  /// chains to the first detail (the create sheet handles the chaining;
  /// the overlay row never dead-ends).
  Future<Result<IdVersionResponse>> create() async {
    // AUTHZ-GATE: authenticated session required before any network call.
    if (await _resolveSession() == null) {
      const error = ProblemError(code: 'auth.session_required', status: 403);
      ref.read(costumesCommandErrorProvider(seasonId).notifier).set(error);
      return const Left(error);
    }
    final repo = ref.read(costumeRepositoryProvider);
    // Issue #453: bind the costume to the current season's repertoire so it
    // is visible in the Kleidung stream while unassigned.
    final ack = await repo.create(seasonId);
    return ack.match(
      (err) {
        ref.read(costumesCommandErrorProvider(seasonId).notifier).set(err);
        return Left<ProblemError, IdVersionResponse>(err);
      },
      (res) {
        ref.read(costumesCommandErrorProvider(seasonId).notifier).clear();
        ref
            .read(costumesOverlaysProvider(seasonId).notifier)
            .add(
              CostumeRowOverlay(
                id: res.id,
                overlay: CostumeView(
                  (b) => b
                    ..id = res.id
                    ..notes = ''
                    ..details.replace(const [])
                    ..photos.replace(const [])
                    ..updatedAt = DateTime.now().toUtc()
                    ..version = res.version,
                ),
                acknowledgedVersion: res.version,
                status: OverlayStatus.acknowledged,
              ),
            );
        _reconcile.ackReceived();
        unawaited(reconcile());
        return Right<ProblemError, IdVersionResponse>(res);
      },
    );
  }

  /// Assigns the costume to a character (version echo from the acted-on
  /// row; 409 → keyed copy, no auto-retry). Optimistic-after-2xx on the
  /// costume row's `character_id`, cleared by the version fence.
  ///
  /// Reassignment (issue #454): an already-assigned costume cannot take the
  /// plain `assign` command — the backend answers 409 `costume.already-
  /// assigned`. When the acted-on row is bound to a DIFFERENT character, a
  /// client-side **unassign→assign sequence** runs instead: unassign echoes
  /// the acted-on row's version, and the follow-up assign echoes the
  /// unassign ACK version (never the pre-command version, which the server
  /// would reject as a version conflict). The sequence is not atomic — an
  /// assign failure after a successful unassign leaves the costume
  /// UNASSIGNED, and that true state is surfaced honestly via the overlay +
  /// command-error provider (AGENTS.md §4: no silent discard). Re-picking the
  /// already-assigned character is a no-op (the backend would 422 it).
  ///
  /// // AUTHZ-GATE: `assign_costumes` capability checked before the call.
  Future<Result<int>> assign({
    required CostumeView costume,
    required String characterId,
  }) async {
    // Already bound to the picked character: the assignment the caller
    // asked for already holds — a no-op success (the backend 422s the
    // same-character reassign command). Run before the AUTHZ-GATE: this path
    // dispatches NO mutating request, so it must not depend on membership
    // resolution (or its fetch failures → `membership.pending`); returning
    // the acted-on row's version immediately is authorization-neutral.
    if (costume.characterId == characterId) {
      return Right<ProblemError, int>(costume.version);
    }
    // AUTHZ-GATE: capability check before any network call.
    final gate = await _assignGate();
    if (_deny(gate) != null) {
      return Left(ProblemError(code: (gate as GateDeny).code, status: 403));
    }
    final repo = ref.read(costumeRepositoryProvider);
    // Reassignment path (issue #454): costume already bound to a DIFFERENT
    // character — unassign first, then assign echoing the unassign ack.
    if (costume.characterId != null) {
      return _reassign(costume: costume, characterId: characterId, repo: repo);
    }
    // First assignment (no current binding): single assign command.
    final res = await repo.assign(
      costume.id,
      AssignCostumeRequest(
        (b) => b
          ..characterId = characterId
          ..version = costume.version,
      ),
    );
    return res.match(
      (err) {
        ref.read(costumesCommandErrorProvider(seasonId).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) => _recordAssignmentOverlay(
        costume: costume,
        characterId: characterId,
        version: version,
      ),
    );
  }

  /// The client-side unassign→assign sequence for reassignment (issue #454).
  ///
  /// 1. `unassign` echoes the acted-on row's version; on ack the overlay is
  ///    updated to the unassigned row (the true intermediate state) with the
  ///    unassign ack version.
  /// 2. `assign` carries that unassign ACK version — never the pre-command
  ///    version, which the server would reject as a version conflict. On ack
  ///    the same overlay is replaced by the final assigned row.
  /// 3. A single reconcile pass runs after the final ack; the intermediate
  ///    overlay is never reconciled on its own.
  ///
  /// If the assign leg fails after the unassign leg succeeded, the costume
  /// stays UNASSIGNED and the error is surfaced via the command-error
  /// provider — the honest state wins over a fake target binding.
  Future<Result<int>> _reassign({
    required CostumeView costume,
    required String characterId,
    required CostumeRepository repo,
  }) async {
    final unResult = await repo.unassign(
      costume.id,
      VersionRequest((b) => b..version = costume.version),
    );
    return unResult.match(
      (err) {
        ref.read(costumesCommandErrorProvider(seasonId).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (unVersion) async {
        // Honest intermediate overlay: the binding is gone, version advanced
        // to the unassign ack — so the follow-up command echoes the ACK, not
        // the pre-command version. The final assign overlay replaces this.
        ref
            .read(costumesOverlaysProvider(seasonId).notifier)
            .add(
              CostumeRowOverlay(
                id: costume.id,
                overlay: applyUnassignOptimistic(costume)
                    .rebuild((b) => b..version = unVersion),
                acknowledgedVersion: unVersion,
                status: OverlayStatus.acknowledged,
              ),
            );
        final assignResult = await repo.assign(
          costume.id,
          AssignCostumeRequest(
            (b) => b
              ..characterId = characterId
              ..version = unVersion,
          ),
        );
        return assignResult.match(
          (err) {
            ref.read(costumesCommandErrorProvider(seasonId).notifier).set(err);
            // The unassign leg already succeeded and recorded an
            // acknowledged unassigned overlay, but the assign leg failed;
            // the costume is genuinely UNASSIGNED server-side. Reconcile now
            // (single bounded pass) so the projection + cache swap to the
            // honest unassigned state instead of lingering on the assigned
            // row — no silent discard (AGENTS.md §4).
            _reconcile.ackReceived();
            unawaited(reconcile());
            return Left<ProblemError, int>(err);
          },
          (version) => _recordAssignmentOverlay(
            costume: costume,
            characterId: characterId,
            version: version,
          ),
        );
      },
    );
  }

  /// Records the final assigned overlay after a successful assign ack
  /// (first-assignment and reassignment both land here) and triggers one
  /// bounded reconcile pass. The overlay version advances to the ack: a
  /// follow-up command echoes it instead of the pre-command version.
  Right<ProblemError, int> _recordAssignmentOverlay({
    required CostumeView costume,
    required String characterId,
    required int version,
  }) {
    ref.read(costumesCommandErrorProvider(seasonId).notifier).clear();
    ref
        .read(costumesOverlaysProvider(seasonId).notifier)
        .add(
          CostumeRowOverlay(
            id: costume.id,
            overlay: applyAssignOptimistic(
              costume,
              characterId,
            ).rebuild((b) => b..version = version),
            acknowledgedVersion: version,
            status: OverlayStatus.acknowledged,
          ),
        );
    _reconcile.ackReceived();
    unawaited(reconcile());
    return Right<ProblemError, int>(version);
  }

  /// Unassigns the costume (`VersionRequest` = `version` only, backend
  /// issue #336). Mirrors [assign].
  ///
  /// // AUTHZ-GATE: `assign_costumes` capability checked before the call.
  Future<Result<int>> unassign({required CostumeView costume}) async {
    // AUTHZ-GATE: capability check before any network call.
    final gate = await _assignGate();
    if (_deny(gate) != null) {
      return Left(ProblemError(code: (gate as GateDeny).code, status: 403));
    }
    final repo = ref.read(costumeRepositoryProvider);
    final res = await repo.unassign(
      costume.id,
      VersionRequest((b) => b..version = costume.version),
    );
    return res.match(
      (err) {
        ref.read(costumesCommandErrorProvider(seasonId).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(costumesCommandErrorProvider(seasonId).notifier).clear();
        ref
            .read(costumesOverlaysProvider(seasonId).notifier)
            .add(
              CostumeRowOverlay(
                id: costume.id,
                overlay: applyUnassignOptimistic(costume)
                    .rebuild((b) => b..version = version),
                acknowledgedVersion: version,
                status: OverlayStatus.acknowledged,
              ),
            );
        _reconcile.ackReceived();
        unawaited(reconcile());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Adds a detail (category id from the season's costume-category read
  /// DTOs). Optimistic-after-2xx on the costume row.
  Future<Result<int>> addDetail({
    required CostumeView costume,
    required String text,
    String? subject,
    String? categoryId,
  }) async {
    if (await _resolveSession() == null) {
      const error = ProblemError(code: 'auth.session_required', status: 403);
      ref.read(costumesCommandErrorProvider(seasonId).notifier).set(error);
      return const Left(error);
    }
    final repo = ref.read(costumeRepositoryProvider);
    final res = await repo.addDetail(
      costume.id,
      AddCostumeDetailRequest(
        (b) => b
          // Wire id MUST be a real UUIDv7 (contract-typed `uuid`); the
          // optimistic overlay keeps its OWN separate transient placeholder
          // (`pending-detail-<version>`) and is reconciled from the
          // projection response — never from this value (issue #472: the
          // old `'pending'` here 422'd as `domain.validation`).
          ..detail.id = generateUuidV7()
          ..detail.text = text
          ..detail.subject = subject
          ..detail.categoryId = categoryId
          ..version = costume.version,
      ),
    );
    return res.match(
      (err) {
        ref.read(costumesCommandErrorProvider(seasonId).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(costumesCommandErrorProvider(seasonId).notifier).clear();
        // Unique placeholder id per command (detail cards key on it);
        // the overlay version advances to the ack (see assign).
        final detail = optimisticDetailPlaceholder(
          pendingId: 'pending-detail-$version',
          subject: subject,
          text: text,
          categoryId: categoryId,
        );
        ref
            .read(costumesOverlaysProvider(seasonId).notifier)
            .add(
              CostumeRowOverlay(
                id: costume.id,
                overlay: applyAddDetailOptimistic(
                  costume,
                  detail,
                ).rebuild((b) => b..version = version),
                acknowledgedVersion: version,
                status: OverlayStatus.acknowledged,
              ),
            );
        _reconcile.ackReceived();
        unawaited(reconcile());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Edits notes (PATCH, version echo). Optimistic-after-2xx on the row.
  Future<Result<int>> updateNotes({
    required CostumeView costume,
    required String notes,
  }) async {
    if (await _resolveSession() == null) {
      const error = ProblemError(code: 'auth.session_required', status: 403);
      ref.read(costumesCommandErrorProvider(seasonId).notifier).set(error);
      return const Left(error);
    }
    final repo = ref.read(costumeRepositoryProvider);
    final res = await repo.updateNotes(
      costume.id,
      UpdateCostumeNotesRequest(
        (b) => b
          ..notes = notes
          ..version = costume.version,
      ),
    );
    return res.match(
      (err) {
        ref.read(costumesCommandErrorProvider(seasonId).notifier).set(err);
        return Left<ProblemError, int>(err);
      },
      (version) {
        ref.read(costumesCommandErrorProvider(seasonId).notifier).clear();
        ref
            .read(costumesOverlaysProvider(seasonId).notifier)
            .add(
              CostumeRowOverlay(
                id: costume.id,
                overlay: applyNotesOptimistic(
                  costume,
                  notes,
                ).rebuild((b) => b..version = version),
                acknowledgedVersion: version,
                status: OverlayStatus.acknowledged,
              ),
            );
        _reconcile.ackReceived();
        unawaited(reconcile());
        return Right<ProblemError, int>(version);
      },
    );
  }

  /// Uploads prepared photo bytes (raw bytes, content-type header).
  /// Returns the Gallery ack; the screen reconciles via the costume refetch
  /// + [PhotoRepository.watch].
  ///
  /// // AUTHZ-GATE: season-scoped photo policy checked before the call.
  Future<Result<PhotoView>> uploadPhoto({
    required String costumeId,
    required Uint8ListBytes bytes,
    required String contentType,
  }) async {
    // AUTHZ-GATE: photo capability checked before any network call.
    final gate = await _photoGate();
    if (_deny(gate) != null) {
      return Left(ProblemError(code: (gate as GateDeny).code, status: 403));
    }
    final repo = ref.read(costumePhotoRepositoryProvider);
    final res = await repo.upload(costumeId, bytes.bytes, contentType);
    return res.match(
      (err) {
        ref.read(costumesCommandErrorProvider(seasonId).notifier).set(err);
        return Left<ProblemError, PhotoView>(err);
      },
      (view) {
        ref.read(costumesCommandErrorProvider(seasonId).notifier).clear();
        unawaited(refresh());
        return Right<ProblemError, PhotoView>(view);
      },
    );
  }

  /// Deletes a costume photo (confirm-first in the UI; 204 → optimistic
  /// removal + reconcile).
  ///
  /// // AUTHZ-GATE: season-scoped photo policy checked before the call.
  Future<Result<void>> deletePhoto({
    required String costumeId,
    required String photoId,
  }) async {
    // AUTHZ-GATE: photo capability checked before any network call.
    final gate = await _photoGate();
    if (_deny(gate) != null) {
      return Left(ProblemError(code: (gate as GateDeny).code, status: 403));
    }
    final repo = ref.read(costumePhotoRepositoryProvider);
    final res = await repo.delete(costumeId, photoId);
    return res.match(
      (err) {
        ref.read(costumesCommandErrorProvider(seasonId).notifier).set(err);
        return Left<ProblemError, void>(err);
      },
      (_) {
        ref.read(costumesCommandErrorProvider(seasonId).notifier).clear();
        unawaited(refresh());
        return const Right<ProblemError, void>(null);
      },
    );
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
    ref.read(costumesCommandErrorProvider(seasonId).notifier).clear();
    await reconcile();
  }

  void dismissCommandError() =>
      ref.read(costumesCommandErrorProvider(seasonId).notifier).clear();

  Future<List<CostumeView>?> _refetchProjection() async {
    ref.invalidate(costumesListFetchProvider(seasonId));
    ref.invalidate(costumesCacheStaleProvider(seasonId));
    final res = await ref.read(costumesListFetchProvider(seasonId).future);
    return res.match((_) => null, (rows) {
      // The version fence owns overlay clearing: prune against the fresh
      // projection here so a stale row never restores pre-command state.
      if (ref.mounted) {
        ref
            .read(costumesOverlaysProvider(seasonId).notifier)
            .pruneWithProjection(rows);
      }
      return rows;
    });
  }
}

/// Typed wrapper so the upload seam stays explicit at call sites.
class Uint8ListBytes {
  const Uint8ListBytes(this.bytes);

  final Uint8List bytes;
}
