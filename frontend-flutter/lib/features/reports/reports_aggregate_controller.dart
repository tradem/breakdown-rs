// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:io';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/membership/capability.dart';
import '../../auth/membership/membership_providers.dart';
import '../../core/problem_error.dart';
import '../../core/result.dart';
import '../../data/report_cache.dart';
import '../../data/report_models.dart';
import '../scene_shoots/scene_shoots_controller.dart'
    show sceneShootRepositoryProvider;
import 'reports_controller.dart'
    show reportsTempDirProvider, reportShareServiceProvider;
import 'reports_state.dart'
    show PdfCardState, PdfError, PdfFetching, PdfIdle, PdfReady;
import 'reports_aggregate_state.dart';

part 'reports_aggregate_controller.g.dart';

/// Local AUTHZ-GATE decision for the aggregate screen: the SAME client-side
/// check the day-scoped report screen gates on (`currentMembershipProvider`
/// → `canViewReports`), evaluated BEFORE any network call. `AsyncLoading`,
/// `AsyncError`, and unknown capability strings all deny locally — a denied
/// scope issues zero requests. The server remains authoritative on every
/// handler.
ProblemError? _aggregateGate(AsyncValue<SeasonMembershipDto> membership) =>
    switch (membership) {
      AsyncLoading() => const ProblemError(code: 'membership.pending'),
      AsyncError() => const ProblemError(code: 'membership.unavailable'),
      AsyncData(:final value) =>
        value.canViewReports
            ? null
            : const ProblemError(code: 'report.forbidden'),
    };

/// The injected aggregate fetch seam
/// (`GET /v1/seasons/{id}/report/soll-ist` or
/// `GET /v1/episodes/{id}/report/soll-ist`, per the scope kind). Tests
/// override this provider with a fake.
@riverpod
Future<Result<AggregateSollIstReport>> reportsAggregateFetch(
  Ref ref,
  ReportsAggregateScope scope,
) async {
  // AUTHZ-GATE: local non-fetching pre-check BEFORE any network call.
  final gate = _aggregateGate(
    ref.watch(currentMembershipProvider(scope.seasonId)),
  );
  if (gate != null) {
    return Left(gate);
  }
  final repo = ref.watch(sceneShootRepositoryProvider);
  return switch (scope.kind) {
    ReportAggregateScopeKind.season => repo.fetchSeasonSollIstReport(scope.id),
    ReportAggregateScopeKind.episode => repo.fetchEpisodeSollIstReport(
      scope.id,
    ),
  };
}

/// The single PDF card state for the scope's aggregate PDF (idle until the
/// user fetches — no prefetching).
@Riverpod(keepAlive: true)
class AggregatePdfCard extends _$AggregatePdfCard {
  @override
  PdfCardState build(ReportsAggregateScope scope) => const PdfIdle();

  void set(PdfCardState cardState) => state = cardState;
}

/// Last aggregate command failure, surfaced keyed on `code`.
@Riverpod(keepAlive: true)
class ReportsAggregateCommandError extends _$ReportsAggregateCommandError {
  @override
  ProblemError? build(ReportsAggregateScope scope) => null;

  void set(ProblemError error) => state = error;

  void clear() => state = null;
}

/// Aggregated Soll-Ist reports controller: the on-screen JSON aggregation
/// plus user-initiated aggregate-PDF fetch/preview/share. Finality and day
/// counts render verbatim from the DTO — the client never recomputes the
/// aggregate finality rule (issue #571 decision 2).
@Riverpod(keepAlive: true)
class ReportsAggregateController extends _$ReportsAggregateController {
  CancelToken? _pdfToken;

  @override
  ReportsAggregateScreenState build(ReportsAggregateScope scope) {
    // AUTHZ-GATE: local non-fetching pre-check over the membership source.
    // A denial renders the localized narrative with ZERO report requests.
    final accessDenial = _aggregateGate(
      ref.watch(currentMembershipProvider(scope.seasonId)),
    );

    final sollIst = switch (ref.watch(reportsAggregateFetchProvider(scope))) {
      AsyncData(:final value) => value.match(
        (err) =>
            AsyncValue<AggregateSollIstReport>.error(err, StackTrace.current),
        AsyncValue<AggregateSollIstReport>.data,
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<AggregateSollIstReport>.error(error, stackTrace),
      _ => const AsyncValue<AggregateSollIstReport>.loading(),
    };

    return ReportsAggregateScreenState(
      sollIst: sollIst,
      pdf: ref.watch(aggregatePdfCardProvider(scope)),
      commandError: ref.watch(reportsAggregateCommandErrorProvider(scope)),
      accessDenial: accessDenial,
    );
  }

  /// Fetches the scope's aggregate PDF (user-initiated only). Same
  /// cancel-token / staging contract as the day PDF cards: any exit
  /// deletes the staged temp copy.
  ///
  /// // AUTHZ-GATE: `canViewReports` via `currentMembershipProvider`
  /// // BEFORE any network call; denial issues zero report requests.
  Future<void> fetchPdf() async {
    final membership = ref.read(currentMembershipProvider(scope.seasonId));
    if (_aggregateGate(membership) != null) return;
    _pdfToken?.cancel();
    final token = CancelToken();
    _pdfToken = token;
    ref.read(aggregatePdfCardProvider(scope).notifier).set(const PdfFetching());
    ref.read(reportsAggregateCommandErrorProvider(scope).notifier).clear();

    Directory tempDir;
    try {
      tempDir = await ref.read(reportsTempDirProvider.future);
    } on Object {
      ref
          .read(aggregatePdfCardProvider(scope).notifier)
          .set(const PdfError(ProblemError(code: 'transport.network')));
      return;
    }

    final repo = ref.read(sceneShootRepositoryProvider);
    void onProgress(int received, int total) {
      if (!ref.mounted || token.isCancelled) return;
      ref
          .read(aggregatePdfCardProvider(scope).notifier)
          .set(PdfFetching(progress: total > 0 ? received / total : null));
    }

    final Result<File> res = await switch (scope.kind) {
      ReportAggregateScopeKind.season => repo.seasonSollIstReportPdf(
        scope.id,
        tempDir: tempDir,
        scopeLabel: scope.label,
        cancelToken: token,
        onReceiveProgress: onProgress,
      ),
      ReportAggregateScopeKind.episode => repo.episodeSollIstReportPdf(
        scope.id,
        tempDir: tempDir,
        scopeLabel: scope.label,
        cancelToken: token,
        onReceiveProgress: onProgress,
      ),
    };
    if (!ref.mounted) {
      final File? staged = res.fold((_) => null, (f) => f);
      if (staged != null) await deleteReportTemp(staged);
      return;
    }
    final superseded = !identical(_pdfToken, token);
    if (superseded || token.isCancelled) {
      final File? staged = res.fold((_) => null, (f) => f);
      if (staged != null) await deleteReportTemp(staged);
      if (!superseded) {
        ref.read(aggregatePdfCardProvider(scope).notifier).set(const PdfIdle());
      }
      return;
    }
    res.match(
      (err) =>
          ref.read(aggregatePdfCardProvider(scope).notifier).set(PdfError(err)),
      (file) => ref
          .read(aggregatePdfCardProvider(scope).notifier)
          .set(PdfReady(file)),
    );
  }

  /// The current card state for the scope (screen seam for the preview
  /// entry — a read, never a listen).
  PdfCardState? pdfCard() => ref.read(aggregatePdfCardProvider(scope));

  /// Cancels an in-flight PDF fetch; the card returns to idle and no
  /// partial file survives.
  void cancelPdf() {
    _pdfToken?.cancel();
    ref.read(aggregatePdfCardProvider(scope).notifier).set(const PdfIdle());
  }

  /// Shares a staged PDF via the platform sheet, then deletes the staged
  /// temp copy on every exit and returns the card to idle.
  ///
  /// // AUTHZ-GATE: staged files only ever exist after a gated fetch; the
  /// // share itself issues no report request.
  Future<void> sharePdf() async {
    final card = ref.read(aggregatePdfCardProvider(scope));
    if (card is! PdfReady) return;
    final share = ref.read(reportShareServiceProvider);
    final kind = switch (scope.kind) {
      ReportAggregateScopeKind.season => AggregateReportPdfKind.seasonSollIst,
      ReportAggregateScopeKind.episode => AggregateReportPdfKind.episodeSollIst,
    };
    final res = await share.sharePdf(
      card.file,
      fileName: aggregateReportShareFileName(
        scopeLabel: scope.label,
        kind: kind,
      ),
    );
    await deleteReportTemp(card.file);
    if (!ref.mounted) return;
    ref.read(aggregatePdfCardProvider(scope).notifier).set(const PdfIdle());
    res.match(
      (err) => ref
          .read(reportsAggregateCommandErrorProvider(scope).notifier)
          .set(err),
      (_) => ref
          .read(reportsAggregateCommandErrorProvider(scope).notifier)
          .clear(),
    );
  }

  /// Dismisses a staged PDF (preview closed without sharing): deletes the
  /// temp copy and returns the card to idle.
  Future<void> dismissPdf() async {
    final card = ref.read(aggregatePdfCardProvider(scope));
    if (card is PdfReady) {
      await deleteReportTemp(card.file);
    }
    if (!ref.mounted) return;
    ref.read(aggregatePdfCardProvider(scope).notifier).set(const PdfIdle());
  }

  /// Pull-to-refresh: refetches the JSON aggregation (Future.wait shape —
  /// mirrors the day controller's refresh so the spinner tracks the actual
  /// requests instead of a bare invalidated-value promise).
  Future<void> refresh() async {
    ref.read(reportsAggregateCommandErrorProvider(scope).notifier).clear();
    ref.invalidate(reportsAggregateFetchProvider(scope));
    ref.invalidate(aggregatePdfCardProvider(scope));
    await Future.wait([ref.read(reportsAggregateFetchProvider(scope).future)]);
  }

  /// Retry affordance for the `membership.unavailable` denial.
  Future<void> retryAccess() async {
    await ref.read(currentMembershipProvider(scope.seasonId).notifier).retry();
    ref.invalidate(reportsAggregateFetchProvider(scope));
  }

  void dismissCommandError() =>
      ref.read(reportsAggregateCommandErrorProvider(scope).notifier).clear();
}
