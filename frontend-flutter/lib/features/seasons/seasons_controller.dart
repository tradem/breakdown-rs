// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.8-flash (opencode-go)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import '../../core/result.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../../domain/reconciliation/reconciliation.dart';
import 'seasons_state.dart';

/// Compatibility re-exports: the scheduler, budget, warning and overlay
/// bookkeeping used to live in this file. They moved verbatim-in-behavior
/// to `lib/domain/reconciliation/` (`flutter-hierarchy-navigation` D2);
/// existing imports keep resolving through here.
export '../../domain/reconciliation/reconciliation.dart';

part 'seasons_controller.g.dart';

/// Ephemeral optimistic overlay store (D2: controller state, NOT Drift).
///
/// Kept in its own [Notifier] so the overlay survives projection rebuilds
/// (`SeasonsController.build()` re-runs whenever the projection changes;
/// inlining the list there would wipe it).
class SeasonOverlays extends OverlayStore<SeasonOverlay> {
  @override
  List<SeasonOverlay> build() => const [];
}

final seasonOverlaysProvider =
    NotifierProvider<SeasonOverlays, List<SeasonOverlay>>(SeasonOverlays.new);

/// Last command failure, surfaced to the screen (keyed on the stable
/// problem `code`, never the `detail` text).
class SeasonCommandError extends Notifier<ProblemError?> {
  @override
  ProblemError? build() => null;

  void set(ProblemError error) => state = error;

  void clear() => state = null;
}

final seasonCommandErrorProvider =
    NotifierProvider<SeasonCommandError, ProblemError?>(SeasonCommandError.new);

/// The first screen's controller — the reference pattern for every
/// subsequent screen (AGENTS.md §9).
///
/// State shape per spec `flutter-first-screen` D2; the task text's
/// `AsyncValue<List<SeasonDto>>` is the `projected` field of
/// [SeasonsScreenState] (the spec's `SeasonDto` is the generated
/// `breakdown_api` `SeasonView`).
///
/// It composes the `add-drift-read-cache` projection (Drift is the single
/// authoritative read source, D1 there) with the ephemeral optimistic
/// overlay layer, and owns the bounded-retry reconciliation on
/// `POST /v1/seasons`.
@Riverpod(keepAlive: true)
class SeasonsController extends _$SeasonsController {
  /// Shared single-flight + ack-generation reconcile runner (D2). Created
  /// lazily — the closures capture [ref], which is only available after
  /// the notifier is mounted.
  ReconciliationCoordinator? _coordinator;

  ReconciliationCoordinator get _reconcile =>
      _coordinator ??= ReconciliationCoordinator(
        refetchProjectedIds: () async {
          final rows = await _refetchProjection();
          return rows?.map((s) => s.id).toList();
        },
        hasOverlays: () => ref.read(seasonOverlaysProvider).isNotEmpty,
        markAllReconciling: () =>
            ref.read(seasonOverlaysProvider.notifier).markAllReconciling(),
        dropProjectedIds: (ids) =>
            ref.read(seasonOverlaysProvider.notifier).dropProjectedIds(ids),
        markAllStale: (warning) =>
            ref.read(seasonOverlaysProvider.notifier).markAllStale(warning),
        scheduler: () => ref.read(reconciliationSchedulerProvider),
        isAlive: () => ref.mounted,
      );

  @override
  SeasonsScreenState build() {
    final async = ref.watch(seasonsViewControllerProvider);
    final view = ref.watch(seasonsView);
    // AsyncValue<SeasonsView> → AsyncValue<List<SeasonView>> (the spec's
    // `projected` field): rows ride on success, the error / loading state is
    // preserved on failure. Retained rows stay available via `cachedRows`.
    final projected = switch (async) {
      AsyncData(:final value) => AsyncValue<List<SeasonView>>.data(value.rows),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<List<SeasonView>>.error(error, stackTrace),
      _ => const AsyncValue<List<SeasonView>>.loading(),
    };
    return SeasonsScreenState(
      projected: projected,
      cachedRows: view.rows,
      isStale: view.isStale,
      overlays: ref.watch(seasonOverlaysProvider),
      commandError: ref.watch(seasonCommandErrorProvider),
    );
  }

  /// Submits the Create Season command (task 1.2 — the spec's `create`;
  /// `name` maps to the backend's `title` field).
  ///
  /// Returns the command acknowledgement
  /// (`IdVersionResponse { id, version }` — the real 2xx body of
  /// `POST /v1/seasons`; the full DTO arrives later via the projection
  /// refetch, D1) or propagates the [ProblemError] to the widget.
  ///
  /// The optimistic overlay is inserted **only after** the 2xx (D1) and
  /// reconciled in the background; the call returns as soon as the
  /// command acked so the UI never blocks on projector lag.
  ///
  /// AUTHZ-GATE: the backend `create_season` handler is gated by its
  /// `CurrentUser` extractor (auth-only; no season membership exists yet
  /// for a season that is being created). The client mirrors that gate
  /// here — no network call is issued without an authenticated session.
  Future<Result<IdVersionResponse>> create({
    required String seriesId,
    required int number,
    String? title,
  }) async {
    final AuthSession? session;
    // Awaited (not read): the session restores asynchronously; a pending
    // restore must resolve before the gate decision, never be treated as
    // denial-by-absence. A failed restore is an error state → deny.
    session = await _resolveSession();
    if (session == null) {
      const error = ProblemError(
        code: 'authz.denied',
        title: 'An authenticated session is required to create seasons',
        status: 403,
      );
      ref.read(seasonCommandErrorProvider.notifier).set(error);
      return const Left(error);
    }

    final repo = ref.read(seasonRepositoryProvider);
    final ack = await repo.create(
      CreateSeasonRequest(
        (b) => b
          ..seriesId = seriesId
          ..number = number
          ..title = title,
      ),
    );

    return ack.match(
      (err) {
        // D3: no 2xx → no overlay is ever inserted and Drift is untouched;
        // the error (409 conflict included) propagates keyed on its code.
        ref.read(seasonCommandErrorProvider.notifier).set(err);
        return Left<ProblemError, IdVersionResponse>(err);
      },
      (res) {
        ref.read(seasonCommandErrorProvider.notifier).clear();
        // D1/D2: optimistic overlay keyed by the server-assigned id,
        // controller state only — never a Drift write.
        ref
            .read(seasonOverlaysProvider.notifier)
            .add(
              SeasonOverlay(
                id: res.id,
                name: title,
                number: number,
                status: OverlayStatus.acknowledged,
              ),
            );
        // A late acknowledgement during an in-flight reconcile must trigger
        // a dedicated follow-up pass (see [reconcile]); bump the generation
        // before kicking off reconciliation.
        _reconcile.ackReceived();
        // Fire-and-forget is intentional: the UI must not block on
        // projector lag (Riverpod async state surfaces progress instead).
        unawaited(reconcile());
        return Right<ProblemError, IdVersionResponse>(res);
      },
    );
  }

  /// Resolves the session for the AUTHZ-GATE; a restore failure is treated
  /// as no-session (deny) so the gated request is never issued.
  Future<AuthSession?> _resolveSession() async {
    try {
      return await ref.read(authSessionControllerProvider.future);
    } on Object {
      return null;
    }
  }

  /// Bounded-retry reconciliation pass (D2, shared runner): refetch the
  /// seasons projection up to [kMaxReconcileAttempts] times, dropping
  /// overlays whose id the projection now carries. On exhaustion the
  /// overlays are retained and marked `stale` — Drift still contains no
  /// unprojected row.
  ///
  /// Also used by pull-to-refresh: a stale overlay gets a fresh bounded
  /// pass. Single-flight: concurrent callers join the in-flight pass; a
  /// late acknowledgement mid-pass gets a dedicated follow-up pass (see
  /// [ReconciliationCoordinator]).
  Future<void> reconcile() => _reconcile.reconcile();

  /// Pull-to-refresh (task 4.3): clears a stale command error and runs a
  /// fresh bounded reconciliation pass.
  Future<void> refresh() async {
    ref.read(seasonCommandErrorProvider.notifier).clear();
    await reconcile();
  }

  /// Dismisses the command-error banner (keyed-on-`code` copy).
  void dismissCommandError() =>
      ref.read(seasonCommandErrorProvider.notifier).clear();

  /// Re-runs the injected list-fetch seam (which writes Drift on success,
  /// never on failure) and returns the fresh rows, or `null` on `Err`.
  Future<List<SeasonView>?> _refetchProjection() async {
    ref.invalidate(seasonsListFetchProvider);
    final res = await ref.read(seasonsListFetchProvider.future);
    return res.match((_) => null, (rows) => rows);
  }
}
