// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

/// The block the SCRIPT states vs. the block the import writes into
/// (issue #827).
///
/// The import knew and showed the episode it extracted but never the block, so
/// an import into the wrong block was only discovered at apply time — the
/// cross-block guard answers `403` — or never. The backend now publishes the
/// block the document states next to its import target:
///
/// - `AiImportProgress.blockNumber` — what the script's page header says
///   (`null` when the document states none: honest absence, never a guess);
/// - `AiImportJob.target.blockNumber` — the block the import was dispatched
///   into (the block that was active at upload, issue #771).
///
/// They are two facts, which is why the wire keeps them apart. This value type
/// is the one place that decides how the surfaces combine them:
///
/// - [associatedBlockNumber] is what a surface shows as "the associated
///   block" — the script's number when it states one, the import target
///   otherwise. The target is never omitted for lack of a script value: the
///   reviewer must learn where the rows will land either way.
/// - [mismatch] is a real warning (the document belongs to another block) and
///   is surfaced non-blocking; the apply's own guard stays authoritative.
library;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/ai_import_providers.dart';
import '../../../l10n/generated/app_localizations.dart';

part 'script_block_scope.g.dart';

/// The script block / import target pair of one job.
class ScriptBlockScope {
  const ScriptBlockScope({
    this.scriptBlockNumber,
    this.targetBlockNumber,
    this.targetSeasonId,
    this.applied = false,
  });

  /// [AiImportProgress.blockNumber] — the block the DOCUMENT states. `null`
  /// means the script states none; it is never filled with the target here, so
  /// a surface can word the difference ("taken from the import target") instead
  /// of implying the script named it.
  final int? scriptBlockNumber;

  /// [AiImportTarget.blockNumber] — the block this import writes into. `null`
  /// for a job whose target was never recorded (a pre-#771 row).
  final int? targetBlockNumber;

  /// [AiImportTarget.seasonId] — the season this import is scoped to. It is
  /// what a late target attach (#829) needs to resolve the season's block list,
  /// and it exists from the first frame of a block-less upload because the
  /// declared season IS the upload's authorization scope.
  final String? targetSeasonId;

  /// [AiImportJob.applied] — an apply already recorded rows, so the target is
  /// frozen on both sides (issue #829).
  final bool applied;

  /// Whether the script itself states a block.
  bool get scriptStatesBlock => scriptBlockNumber != null;

  /// Whether this job still needs a target block (issue #829): it was uploaded
  /// block-less and no attach has happened yet. Only then may the preview offer
  /// "take it from the script".
  bool get targetBlockUnset =>
      targetBlockNumber == null && targetSeasonId != null;

  /// The block a surface shows as the association: what the script states,
  /// else the import target. `null` only when the job records no target either
  /// — the caller then renders its own "not recorded" copy rather than a
  /// blank field.
  int? get associatedBlockNumber => scriptBlockNumber ?? targetBlockNumber;

  /// The script's block and the import target disagree — the strongest
  /// early hint that the document is being imported into the wrong block.
  /// A missing value on either side is NOT a mismatch: two unknowns never
  /// equal a contradiction.
  bool get mismatch =>
      scriptBlockNumber != null &&
      targetBlockNumber != null &&
      scriptBlockNumber != targetBlockNumber;
}

/// The one-line "what the document states" value of a jobs row (issue #827):
/// the script's block, the discovered episodes, or both — never a blank and
/// never a duplicated clause.
///
/// The block joins the SAME line as the episodes rather than getting its own,
/// because the row is a scannable summary: two short clauses read faster than
/// two rows, and a job without a published block keeps the plain episode
/// value it had before.
String aiJobsRowDetectedValues(
  AppLocalizations l10n,
  AiImportProgress progress,
) {
  final blockNumber = progress.blockNumber;
  final episodes = progress.episodesSeen?.join(', ') ?? '';
  if (blockNumber != null && episodes.isNotEmpty) {
    return l10n.aiJobsRowBlockValues('$blockNumber', episodes);
  }
  if (blockNumber != null) {
    return l10n.aiJobsRowBlockOnly('$blockNumber');
  }
  return l10n.aiJobEpisodesSeenValues(episodes);
}

/// The job's script-block scope, or `null` when the job row is unreadable.
///
/// `getJobAndCache` (NOT the SSE watch) is the same single-snapshot read the
/// naming card uses (issue #831): the app keeps exactly one SSE consumer (the
/// job-status controller, battery contract D5), and the repository's
/// write-through caches the row for the sibling reads.
///
/// A FAILED read throws into Riverpod's error channel and the surfaces render
/// their quiet "not known" arm — a header fact must never invent a block, and
/// no value is derived from the currently selected block either.
@Riverpod(retry: _noAutoRetry)
Future<ScriptBlockScope?> aiJobBlockScope(Ref ref, String jobId) async {
  final repo = ref.read(aiImportRepositoryProvider);
  final job = await repo.getJobAndCache(jobId);
  return job.match(
    (err) => throw err,
    (job) => ScriptBlockScope(
      scriptBlockNumber: job.progress?.blockNumber,
      targetBlockNumber: job.target?.blockNumber,
      targetSeasonId: job.target?.seasonId,
      applied: job.applied ?? false,
    ),
  );
}

/// The `retry: null` policy for [aiJobBlockScope] — never retry on a timer
/// (Riverpod's exponential backoff is unbounded, wall-clock driven and would
/// flag the provider loading while it waits; AGENTS.md §6).
Duration? _noAutoRetry(int retryCount, Object error) => null;
