// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:async';
import 'dart:io';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/membership/capability.dart';
import '../../auth/membership/membership_providers.dart';
import '../../core/problem_error.dart';
import '../../core/result.dart';
import '../../data/report_cache.dart';
import '../../data/report_models.dart';
import '../scene_shoots/scene_shoots_controller.dart'
    show sceneShootRepositoryProvider;
import 'report_share.dart';
import 'reports_state.dart';

part 'reports_controller.g.dart';

/// Staged temp directory for report PDFs (production: the platform
/// cache/temporary directory — never the persistent documents directory,
/// never Drift). Tests override with `Directory.systemTemp`.
@riverpod
Future<Directory> reportsTempDir(Ref ref) => getTemporaryDirectory();

/// Share seam (production: platform sheet via `share_plus`).
@riverpod
ReportShareService reportShareService(Ref ref) => SharePlusReportShare();

/// Container-scoped PDF transport state for one [ReportDayScope]: the active
/// [CancelToken]s and staged temp files.
///
/// On [dispose] every in-flight transfer is cancelled and every staged file
/// is deleted — so a container teardown never leaves a pending transfer or a
/// leaked partial file behind.
class ReportsPdfTransport {
  final Map<ReportPdfKind, CancelToken> _tokens = {};
  final Map<ReportPdfKind, File> _staged = {};

  void registerToken(ReportPdfKind kind, CancelToken token) =>
      _tokens[kind] = token;

  void stage(ReportPdfKind kind, File file) => _staged[kind] = file;

  void unstage(ReportPdfKind kind) => _staged.remove(kind);

  /// Cancels in-flight transfers and deletes staged temp files. Best-effort
  /// by contract (`deleteReportTemp` never throws).
  Future<void> dispose() async {
    for (final token in _tokens.values) {
      token.cancel();
    }
    _tokens.clear();
    final staged = Map.of(_staged);
    _staged.clear();
    for (final file in staged.values) {
      await deleteReportTemp(file);
    }
  }
}

/// The transport registry provider. KeepAlive and — deliberately — watches
/// NOTHING: Riverpod fires `ref.onDispose` on dependency-driven rebuilds
/// too, so a cleanup hooked into a watching provider (or into the
/// controller's `build()`, which watches the membership) would cancel
/// in-flight user fetches on every rebuild. Watching nothing confines the
/// dispose to actual provider-container destruction.
@Riverpod(keepAlive: true)
ReportsPdfTransport reportsPdfTransport(Ref ref, ReportDayScope scope) {
  final transport = ReportsPdfTransport();
  ref.onDispose(() {
    unawaited(transport.dispose());
  });
  return transport;
}

/// Local AUTHZ-GATE decision for [scope]: the resolved membership DTO when
/// the gate may pass, or the local denial code when the action must be
/// refused with zero report requests.
///
/// The check is local and non-fetching: `AsyncLoading`, `AsyncError`, and
/// unknown capability strings all deny locally — the action never triggers
/// a membership fetch, and a denied action issues zero report requests.
ProblemError? _reportGate(AsyncValue<SeasonMembershipDto> membership) {
  switch (membership) {
    case AsyncLoading():
      return const ProblemError(code: 'membership.pending');
    case AsyncError():
      return const ProblemError(code: 'membership.unavailable');
    case AsyncData(:final value):
      // Unknown capability strings never enable this gate: `canViewReports`
      // follows the backend-computed `hasActiveCostumeRoleInSeason` flag
      // only (server remains authoritative on every handler).
      return value.canViewReports
          ? null
          : const ProblemError(code: 'report.forbidden');
  }
}

/// The injected Soll-Ist fetch seam
/// (`GET /v1/shooting-days/{id}/report/soll-ist`). Tests override this
/// provider with a fake.
@riverpod
Future<Result<SollIstReport>> reportsSollIstFetch(
  Ref ref,
  ReportDayScope scope,
) async {
  // AUTHZ-GATE: local non-fetching pre-check BEFORE any network call —
  // a denied membership issues zero report requests.
  final sollIstGate = _reportGate(
    ref.watch(currentMembershipProvider(scope.seasonId)),
  );
  if (sollIstGate != null) {
    return Left(sollIstGate);
  }
  return ref
      .watch(sceneShootRepositoryProvider)
      .fetchSollIstReport(scope.dayId);
}

/// The injected dispo fetch seam (planned-count input only).
@riverpod
Future<Result<List<DispoRow>>> reportsDispoFetch(
  Ref ref,
  ReportDayScope scope,
) async {
  // AUTHZ-GATE: same local pre-check as [reportsSollIstFetch].
  final dispoGate = _reportGate(
    ref.watch(currentMembershipProvider(scope.seasonId)),
  );
  if (dispoGate != null) {
    return Left(dispoGate);
  }
  return ref.watch(sceneShootRepositoryProvider).fetchDispoReport(scope.dayId);
}

/// The injected shoot-day fetch seam (actual-count input only).
@riverpod
Future<Result<List<ShootDayRow>>> reportsShootDayFetch(
  Ref ref,
  ReportDayScope scope,
) async {
  // AUTHZ-GATE: same local pre-check as [reportsSollIstFetch].
  final shootDayGate = _reportGate(
    ref.watch(currentMembershipProvider(scope.seasonId)),
  );
  if (shootDayGate != null) {
    return Left(shootDayGate);
  }
  return ref
      .watch(sceneShootRepositoryProvider)
      .fetchShootDayReport(scope.dayId);
}

/// Per-kind PDF card state (controller-owned, NOT Drift — ephemeral fetch
/// state with temp-file staging).
@Riverpod(keepAlive: true)
class ReportsPdfCards extends _$ReportsPdfCards {
  @override
  Map<ReportPdfKind, PdfCardState> build(ReportDayScope scope) => const {
    ReportPdfKind.dispo: PdfIdle(),
    ReportPdfKind.shootDay: PdfIdle(),
    ReportPdfKind.plannedVsActual: PdfIdle(),
  };

  void set(ReportPdfKind kind, PdfCardState cardState) =>
      state = {...state, kind: cardState};
}

/// Last report command failure, surfaced keyed on `code`.
@Riverpod(keepAlive: true)
class ReportsCommandError extends _$ReportsCommandError {
  @override
  ProblemError? build(ReportDayScope scope) => null;

  void set(ProblemError error) => state = error;

  void clear() => state = null;
}

/// Reports controller (seasons reference pattern): read-model fetches for
/// the on-screen Soll-Ist report plus user-initiated PDF fetch/preview/
/// share per day. PDF bytes never touch Drift; staged temp files are
/// deleted on every non-save exit.
@Riverpod(keepAlive: true)
class ReportsController extends _$ReportsController {
  final Map<ReportPdfKind, CancelToken> _pdfTokens = {};

  /// The container-scoped transport registry for this scope (cancel tokens +
  /// staged temp files). Registered through the watch-free
  /// [reportsPdfTransportProvider] so its `ref.onDispose` fires ONLY on
  /// actual provider-container destruction — a `build()`-scoped onDispose
  /// would fire on every membership-driven rebuild and cancel in-flight
  /// user fetches.
  ReportsPdfTransport get _transport =>
      ref.read(reportsPdfTransportProvider(scope));

  @override
  ReportsScreenState build(ReportDayScope scope) {
    final membership = ref.watch(currentMembershipProvider(scope.seasonId));
    final accessDenial = _reportGate(membership);

    AsyncValue<SollIstReport> projectSollIst(
      AsyncValue<Result<SollIstReport>> fetch,
    ) => switch (fetch) {
      AsyncData(:final value) => value.match(
        (err) => AsyncValue<SollIstReport>.error(err, StackTrace.current),
        AsyncValue<SollIstReport>.data,
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<SollIstReport>.error(error, stackTrace),
      _ => const AsyncValue<SollIstReport>.loading(),
    };

    AsyncValue<int> projectCount(AsyncValue<Result<List>> fetch) =>
        switch (fetch) {
          AsyncData(:final value) => value.match(
            (err) => AsyncValue<int>.error(err, StackTrace.current),
            (rows) => AsyncValue<int>.data(rows.length),
          ),
          AsyncError(:final error, :final stackTrace) => AsyncValue<int>.error(
            error,
            stackTrace,
          ),
          _ => const AsyncValue<int>.loading(),
        };

    return ReportsScreenState(
      sollIst: projectSollIst(ref.watch(reportsSollIstFetchProvider(scope))),
      plannedCount: projectCount(ref.watch(reportsDispoFetchProvider(scope))),
      actualCount: projectCount(ref.watch(reportsShootDayFetchProvider(scope))),
      pdfs: ref.watch(reportsPdfCardsProvider(scope)),
      commandError: ref.watch(reportsCommandErrorProvider(scope)),
      accessDenial: accessDenial,
    );
  }

  void _cards(ReportPdfKind kind, PdfCardState cardState) =>
      ref.read(reportsPdfCardsProvider(scope).notifier).set(kind, cardState);

  /// The current card state for [kind] (screen seam for preview entry).

  PdfCardState? pdfCard(ReportPdfKind kind) =>
      ref.read(reportsPdfCardsProvider(scope))[kind];

  /// Fetches a PDF card (user-initiated only — no prefetching).
  ///
  /// // AUTHZ-GATE: `canViewReports` via `currentMembershipProvider`
  /// // BEFORE any network call; `AsyncLoading`, `AsyncError`, and unknown
  /// // capability strings all deny locally with zero report requests.
  Future<void> fetchPdf(ReportPdfKind kind) async {
    final membership = ref.read(currentMembershipProvider(scope.seasonId));
    if (_reportGate(membership) != null) return;
    _pdfTokens[kind]?.cancel();
    final token = CancelToken();
    _pdfTokens[kind] = token;
    _transport.registerToken(kind, token);
    _cards(kind, const PdfFetching());
    ref.read(reportsCommandErrorProvider(scope).notifier).clear();

    Directory tempDir;
    try {
      tempDir = await ref.read(reportsTempDirProvider.future);
    } on Object {
      _cards(kind, const PdfError(ProblemError(code: 'transport.network')));
      return;
    }

    final repo = ref.read(sceneShootRepositoryProvider);
    void onProgress(int received, int total) {
      if (!ref.mounted || (token.isCancelled)) return;
      _cards(kind, PdfFetching(progress: total > 0 ? received / total : null));
    }

    final Result<File> res = await switch (kind) {
      ReportPdfKind.dispo => repo.dispoReportPdf(
        scope.dayId,
        tempDir: tempDir,
        cancelToken: token,
        onReceiveProgress: onProgress,
      ),
      ReportPdfKind.shootDay => repo.shootDayReportPdf(
        scope.dayId,
        tempDir: tempDir,
        cancelToken: token,
        onReceiveProgress: onProgress,
      ),
      ReportPdfKind.plannedVsActual => repo.plannedVsActualReportPdf(
        scope.dayId,
        tempDir: tempDir,
        cancelToken: token,
        onReceiveProgress: onProgress,
      ),
    };
    if (!ref.mounted) {
      final File? staged = res.fold((_) => null, (f) => f);
      if (staged != null) await deleteReportTemp(staged);
      return;
    }
    // Superseded (a newer fetch took over the card): clean up silently —
    // never touch the newer fetch's card state. A user cancel (token still
    // the current one) lands back on idle (partial temp already deleted by
    // the cache layer) — never on an error card.
    final superseded = !identical(_pdfTokens[kind], token);
    if (superseded || token.isCancelled) {
      final File? staged = res.fold((_) => null, (f) => f);
      if (staged != null) await deleteReportTemp(staged);
      if (!superseded) _cards(kind, const PdfIdle());
      return;
    }
    res.match((err) => _cards(kind, PdfError(err)), (file) {
      _transport.stage(kind, file);
      _cards(kind, PdfReady(file));
    });
  }

  /// Cancels an in-flight PDF fetch; the card returns to idle and no
  /// partial file survives.
  void cancelPdf(ReportPdfKind kind) {
    _pdfTokens[kind]?.cancel();
    _cards(kind, const PdfIdle());
  }

  /// Shares a staged PDF via the platform sheet, then deletes the staged
  /// temp copy on every exit (share done, cancelled, or failed) and returns
  /// the card to idle.
  ///
  /// // AUTHZ-GATE: staged files only ever exist after a gated fetch; the
  /// // share itself issues no report request.
  Future<void> sharePdf(ReportPdfKind kind) async {
    final card = ref.read(reportsPdfCardsProvider(scope))[kind];
    if (card is! PdfReady) return;
    final share = ref.read(reportShareServiceProvider);
    final res = await share.sharePdf(
      card.file,
      fileName: reportShareFileName(dayLabel: scope.dayId, kind: kind),
    );
    await deleteReportTemp(card.file);
    _transport.unstage(kind);
    if (!ref.mounted) return;
    _cards(kind, const PdfIdle());
    res.match(
      (err) => ref.read(reportsCommandErrorProvider(scope).notifier).set(err),
      (_) => ref.read(reportsCommandErrorProvider(scope).notifier).clear(),
    );
  }

  /// Dismisses a staged PDF (preview closed without sharing): deletes the
  /// temp copy and returns the card to idle.
  Future<void> dismissPdf(ReportPdfKind kind) async {
    final card = ref.read(reportsPdfCardsProvider(scope))[kind];
    if (card is PdfReady) {
      await deleteReportTemp(card.file);
      _transport.unstage(kind);
    }
    if (!ref.mounted) return;
    _cards(kind, const PdfIdle());
  }

  /// Pull-to-refresh: refetches the three JSON read models. Awaits the
  /// rebuilt futures so the `RefreshIndicator` spinner tracks the actual
  /// requests (ref.invalidate alone returns before recomputation settles).
  Future<void> refresh() async {
    ref.read(reportsCommandErrorProvider(scope).notifier).clear();
    ref.invalidate(reportsSollIstFetchProvider(scope));
    ref.invalidate(reportsDispoFetchProvider(scope));
    ref.invalidate(reportsShootDayFetchProvider(scope));
    await Future.wait([
      ref.read(reportsSollIstFetchProvider(scope).future),
      ref.read(reportsDispoFetchProvider(scope).future),
      ref.read(reportsShootDayFetchProvider(scope).future),
    ]);
  }

  /// Retry affordance for the `membership.unavailable` denial.
  Future<void> retryAccess() async {
    await ref.read(currentMembershipProvider(scope.seasonId).notifier).retry();
    ref.invalidate(reportsSollIstFetchProvider(scope));
    ref.invalidate(reportsDispoFetchProvider(scope));
    ref.invalidate(reportsShootDayFetchProvider(scope));
  }

  void dismissCommandError() =>
      ref.read(reportsCommandErrorProvider(scope).notifier).clear();
}
