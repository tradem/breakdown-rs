// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/auth_providers.dart';
import '../../../core/problem_error.dart';
import '../../../core/result.dart';
import '../../../data/ai_import_providers.dart';
import '../../../data/ai_import_repository.dart';
import '../../../data/cache/ai_import_jobs_cache_dao.dart';
import '../../../data/cache/cache_database.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'import_state.dart';

part 'jobs_controller.g.dart';

/// The AI-import **jobs view** (issue #547): a started import job stays
/// reachable after the user leaves the status screen.
///
/// The controller is the seasons/blocks seam shape, read-only:
///
/// * **Cached first** — `AiImportRepository.readCached(sub)` paints
///   immediately (identity-scoped by the authenticated `sub`; the Drift
///   cache holds only state the server also holds, AGENTS.md §8). The
///   remembered-id fast path (`AiImportHandoffState.jobIds`) orders the
///   first paint newest-remembered-first — the documented "what did I
///   import" surface (task 1.3 design).
/// * **Then revalidate** — `AiImportRepository.listJobsAndCache()`, the
///   previously-unused `GET /v1/ai-import/jobs` wiring (server-
///   authoritative, newest-first, paginated).
/// * **NO watch** — the list renders cached status and arms nothing (D5:
///   the single foreground job watch stays owned by `AiJobStatusScreen`;
///   a watch per row would rebuild the request-budget problem D5 exists
///   to prevent). A unit test pins the repository watch-call count at
///   zero.
/// * **`Result`-typed throughout** — a fetch `Err` surfaces as
///   `AsyncError` (never silently swallowed, AGENTS.md §5); the retained
///   snapshot keeps the list on screen with the error keyed on the stable
///   problem `code`, never the server `detail`.
///
/// There is no optimistic overlay: this boundary dispatches no commands
/// (rows are navigation targets; the only write surface remains the
/// submit screen's upload and the apply screen's command).
/// The list fetch is ONE `GET /v1/ai-import/jobs` per (re)build — a
/// revalidation, not polling; pull-to-refresh re-runs exactly it.
@riverpod
Future<Result<List<AiImportJob>>> aiImportJobsFetch(Ref ref) async {
  // AUTHZ-GATE: the jobs list route is handler-gated by the authenticated
  // user (ownership-scoped server-side — a foreign job is unreachable by
  // construction, `ai-import.not-found`/`ai-import.forbidden` are the
  // scoped wire arms). The client resolves the session BEFORE the call:
  // no session, no request. Denial surfaces through `aiJobsListErrorCopy`
  // (the server stays authoritative; the client never fabricates a job
  // not-found/forbidden code of its own).
  final session = await ref.watch(authSessionControllerProvider.future);
  if (session == null) {
    return const Left<ProblemError, List<AiImportJob>>(
      ProblemError(code: 'authz.denied', status: 403),
    );
  }
  return ref.read(aiImportRepositoryProvider).listJobsAndCache();
}

/// Retained last-good snapshot (seasons/blocks pattern): updated after
/// every successful list read and by the cache-first seed, so the
/// selector can serve cached rows while the fetch is loading or failed.
@Riverpod(keepAlive: true)
class AiImportJobsPrevRows extends _$AiImportJobsPrevRows {
  @override
  List<AiImportJobRowView> build() => const [];

  void set(List<AiImportJobRowView> rows) => state = rows;
}

/// Read-projection controller. A sync `Notifier` (not an `AsyncNotifier`)
/// so a fetch `Err` surfaces as `AsyncError` rather than triggering
/// Riverpod's async-notifier retry loop.
///
/// Loop discipline (blocks reference pattern): this seeder watches the
/// repository and the fetch ONLY — never [AiImportJobsPrevRows]. It
/// writes the snapshot store but never reads it back through a watch, so
/// its own writes can never invalidate it.
@Riverpod(keepAlive: false)
class AiImportJobsViewController extends _$AiImportJobsViewController {
  @override
  AsyncValue<AiImportJobsState> build() {
    final repo = ref.watch(aiImportRepositoryProvider);

    // Read the cache FIRST (offline cold start) and seed the retained
    // snapshot store used by `aiImportJobsView`. Fire-and-forget:
    // `build()` is sync (discard_result rule — AGENTS.md §5). The seed
    // never overwrites a populated snapshot with an empty read.
    unawaited(_seed(repo));

    final fetch = ref.watch(aiImportJobsFetchProvider);
    return switch (fetch) {
      AsyncData(:final value) => value.match(
        (err) => AsyncValue<AiImportJobsState>.error(err, StackTrace.current),
        (jobs) {
          // Converge the retained snapshot with every successful read
          // (including empty ones) and reconcile the remembered-id fast
          // path against the authoritative list. Deferred microtask,
          // never a synchronous set during build; this seeder does not
          // watch prevRows, so its own write cannot loop back.
          unawaited(_afterSuccessfulFetch(jobs));
          return AsyncValue<AiImportJobsState>.data(
            AiImportJobsState(
              rows: jobs.map(jobRowViewFromJob).toList(),
              isStale: false,
            ),
          );
        },
      ),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<AiImportJobsState>.error(error, stackTrace),
      AsyncLoading() => const AsyncValue<AiImportJobsState>.loading(),
    };
  }

  /// Cache-first seed: the identity-scoped Drift rows joined with the
  /// remembered-id fast path (newest-remembered-first ordering), painted
  /// while the list fetch is still in flight.
  Future<void> _seed(AiImportRepository repo) async {
    String sub;
    try {
      final session = await ref.read(authSessionControllerProvider.future);
      sub = session?.sub ?? '';
    } on Object {
      return;
    }
    if (sub.isEmpty) return;
    final cached = await repo.readCached(sub);
    final rows = cached.getRight().toNullable();
    if (rows == null) return; // a cache read fault never blocks discovery
    if (!ref.mounted) return;
    List<String> remembered = const <String>[];
    final handoff = await ref.read(aiImportHandoffStoreProvider).read(sub);
    final state = handoff.getRight().toNullable();
    if (state != null) remembered = state.jobIds;
    if (!ref.mounted) return;
    final seeded = seedJobRows(cached: rows, rememberedIds: remembered);
    if (seeded.isNotEmpty || ref.read(aiImportJobsPrevRowsProvider).isEmpty) {
      ref.read(aiImportJobsPrevRowsProvider.notifier).set(seeded);
    }
  }

  /// After a successful list fetch: converge the retained snapshot, then
  /// reconcile the remembered-id fast path — `forgetJob` for every
  /// remembered id the authoritative list no longer returns (the list
  /// route is discovery-authoritative; the method existed for exactly
  /// this and had no caller before #547). Best-effort: a hand-off fault
  /// must never discard a successful read. Every await is followed by a
  /// mounted check — a disposed provider (screen left mid-fetch) never
  /// touches a dead ref.
  Future<void> _afterSuccessfulFetch(List<AiImportJob> jobs) async {
    await Future<void>.microtask(() async {
      if (!ref.mounted) return;
      ref
          .read(aiImportJobsPrevRowsProvider.notifier)
          .set(jobs.map(jobRowViewFromJob).toList());
      if (!ref.mounted) return;
      String sub;
      try {
        final session = await ref.read(authSessionControllerProvider.future);
        sub = session?.sub ?? '';
      } on Object {
        return;
      }
      if (sub.isEmpty || !ref.mounted) return;
      final store = ref.read(aiImportHandoffStoreProvider);
      final handoff = await store.read(sub);
      final state = handoff.getRight().toNullable();
      if (state == null || !ref.mounted) return;
      for (final id in missingRememberedIds(
        state.jobIds,
        jobs.map((j) => j.id).toSet(),
      )) {
        if (!ref.mounted) return;
        // Best-effort prune: a storage fault leaves the id remembered;
        // the next successful fetch retries it.
        (await store.forgetJob(sub, id)).getLeft().toNullable();
      }
    });
  }

  /// Pull-to-refresh: re-runs exactly the list route (the status
  /// authority for rows — no per-row polling, D5). The returned future
  /// only bounds the refresh spinner.
  Future<Result<List<AiImportJob>>> refresh() {
    ref.invalidate(aiImportJobsFetchProvider);
    return ref.read(aiImportJobsFetchProvider.future);
  }
}

/// The projection a screen reads (selector) — `aiImportJobsView` per the
/// issue contract.
///
/// Always exposes a usable value: during loading it serves the seeded
/// cached rows (cache-first paint); on error it serves the retained
/// snapshot with a stale marker and the error; on success it serves the
/// fresh rows.
final aiImportJobsView = Provider<AiImportJobsState>((ref) {
  final async = ref.watch(aiImportJobsViewControllerProvider);
  final prev = ref.watch(aiImportJobsPrevRowsProvider);
  return switch (async) {
    AsyncData(:final value) => value,
    AsyncError(:final error) => AiImportJobsState(
      rows: prev,
      isStale: prev.isNotEmpty,
      error: error is ProblemError
          ? error
          : const ProblemError(code: 'unknown'),
    ),
    AsyncLoading() => AiImportJobsState(rows: prev),
  };
});

/// Controller state shape (issue #547 §Changes 1).
class AiImportJobsState {
  const AiImportJobsState({
    required this.rows,
    this.isStale = false,
    this.error,
  });

  /// The newest-first renderable rows (authoritative after a successful
  /// fetch; retained cached rows while loading / on error).
  final List<AiImportJobRowView> rows;

  /// True when the served rows come from the retained cache after a
  /// failed fetch (the error banner rides on top of them).
  final bool isStale;

  /// Last list-fetch failure keyed by its stable problem `code` (the
  /// screen surfaces localized copy, never the server `detail` text).
  final ProblemError? error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiImportJobsState &&
          other.isStale == isStale &&
          other.error == error &&
          _sameRows(other.rows, rows);

  @override
  int get hashCode => Object.hash(isStale, error, Object.hashAll(rows));

  @override
  String toString() =>
      'AiImportJobsState(rows: ${rows.length}, isStale: $isStale, '
      'error: $error)';
}

bool _sameRows(List<AiImportJobRowView> a, List<AiImportJobRowView> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One renderable jobs-list row (issue #547 §Changes 2).
///
/// A single presentation type over BOTH row sources — the fetched
/// `AiImportJob` DTO and the cached `AiImportJobCacheRow` (whose wire
/// enums arrive as text) — so the screen renders from exactly one honest
/// shape. `status`/`documentKind` are nullable on purpose: an unknown
/// future wire value degrades to an honest unknown-status row (the DAO's
/// strict-parse contract), never a guessed meaning or a dropped row.
class AiImportJobRowView {
  const AiImportJobRowView({
    required this.id,
    required this.statusName,
    this.status,
    this.documentKind,
    required this.createdAt,
    required this.updatedAt,
    required this.retries,
    required this.maxRetries,
    this.lastError,
  });

  /// Server-assigned job id (row key + `AiJobStatusScreen` parameter).
  final String id;

  /// Raw wire status value — the honest fallback copy input when
  /// [status] failed the strict parse (an unknown future status).
  final String statusName;

  /// Parsed status; `null` when the wire value is unknown to this build.
  final JobStatus? status;

  /// Parsed document kind; `null` when the wire value is unknown.
  final DocumentKind? documentKind;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Server-side retry counters — the row shows a STATUS, never a
  /// fabricated progress bar (no percentage exists on the wire).
  final int retries;
  final int maxRetries;

  /// Server error detail. Presence indicator only — the raw text renders
  /// as SECONDARY detail on the status screen, never as row copy.
  final String? lastError;

  /// True when the row carries a server-side error detail (the
  /// `last_error` presence indicator).
  bool get hasLastError => lastError != null && lastError!.isNotEmpty;

  /// True for the two terminal-failure statuses — the states that were
  /// unreachable before #547 (the hole this issue closes).
  bool get isTerminalFailure =>
      status == JobStatus.deadLetter || status == JobStatus.payloadUnavailable;

  /// True while the job is not done (`pending`/`running`/`failed`) — the
  /// Planen-tab summary row's driver.
  bool get isInProgress =>
      status == JobStatus.pending ||
      status == JobStatus.running ||
      status == JobStatus.failed;

  /// True unless the import completed — the summary row shows for every
  /// job that still needs attention, INCLUDING the terminal failures
  /// (a silent dead-letter must keep summoning the row).
  bool get needsAttention => status != JobStatus.succeeded;

  /// Localized status copy: the six-status matrix for known values, the
  /// honest unknown-status copy keyed on the raw wire name otherwise.
  String statusLabel(AppLocalizations l10n) => status != null
      ? jobStatusCopy(l10n, status!)
      : l10n.jobStatusUnknown(statusName);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiImportJobRowView &&
          other.id == id &&
          other.statusName == statusName &&
          other.status == status &&
          other.documentKind == documentKind &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.retries == retries &&
          other.maxRetries == maxRetries &&
          other.lastError == lastError;

  @override
  int get hashCode => Object.hash(
    id,
    statusName,
    status,
    documentKind,
    createdAt,
    updatedAt,
    retries,
    maxRetries,
    lastError,
  );

  @override
  String toString() => 'AiImportJobRowView($id, $statusName)';
}

/// Maps a fetched DTO to the renderable row (pure, Tier-1 testable).
AiImportJobRowView jobRowViewFromJob(AiImportJob job) => AiImportJobRowView(
  id: job.id,
  statusName: job.status.name,
  status: job.status,
  documentKind: job.documentKind,
  createdAt: job.createdAt,
  updatedAt: job.updatedAt,
  retries: job.retries,
  maxRetries: job.maxRetries,
  lastError: job.lastError,
);

/// Maps a cached row to the renderable row (pure, Tier-1 testable).
///
/// Strict wire parses (`jobStatusFromWire`): an unknown future status
/// degrades to `status: null` + the raw `statusName` — the row still
/// renders, with the honest unknown copy. A row is never dropped for
/// being from the future.
AiImportJobRowView jobRowViewFromCacheRow(AiImportJobCacheRow row) =>
    AiImportJobRowView(
      id: row.id,
      statusName: row.status,
      status: jobStatusFromWire(row.status),
      documentKind: documentKindFromWire(row.documentKind),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      retries: row.retries,
      maxRetries: row.maxRetries,
      lastError: row.lastError,
    );

/// Cache-first seed merge (pure, Tier-1 testable): remembered ids paint
/// first in remember-time order (the fast path's documented
/// "what did I import" surface), then the remaining cached rows in the
/// cache's newest-first order. A remembered id without a cached row
/// contributes nothing — a bare id cannot drive an honest row (no
/// status, no kind, no date are ever fabricated).
List<AiImportJobRowView> seedJobRows({
  required List<AiImportJobCacheRow> cached,
  required List<String> rememberedIds,
}) {
  final byId = {for (final row in cached) row.id: row};
  final painted = <String>{};
  final rows = <AiImportJobRowView>[];
  for (final id in rememberedIds) {
    final row = byId[id];
    if (row == null) continue;
    painted.add(id);
    rows.add(jobRowViewFromCacheRow(row));
  }
  for (final row in cached) {
    if (painted.contains(row.id)) continue;
    rows.add(jobRowViewFromCacheRow(row));
  }
  return rows;
}

/// Remembered ids the authoritative list no longer returns (pure,
/// Tier-1 testable) — the `forgetJob` reconciliation input.
List<String> missingRememberedIds(
  List<String> rememberedIds,
  Set<String> fetchedIds,
) => [
  for (final id in rememberedIds)
    if (!fetchedIds.contains(id)) id,
];

/// Localized copy for the jobs-list error state, keyed on the stable
/// problem `code` (never the server `detail`). The forbidden arm matches
/// the scoped server wire code `ai-import.forbidden` AND the client
/// no-session pre-gate code `authz.denied` (different provenance, one
/// narrative — the issue routes a denial through `jobWatchForbidden`).
String aiJobsListErrorCopy(AppLocalizations l10n, ProblemError error) =>
    switch (error.code) {
      'ai-import.forbidden' || 'authz.denied' => l10n.jobWatchForbidden,
      'ai-import.not-found' => l10n.jobWatchNotFound,
      _ when error.code.startsWith('transport.') => l10n.jobWatchNetwork,
      _ => l10n.aiJobsLoadError(error.code),
    };
