// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

/// The effective Decision Model and the scoring outcome of one import job
/// (issue #767).
///
/// The reported defect: a configured Decision Model produced no star ratings
/// and **no explanation**. Four different causes collapsed into the same empty
/// space, because the app read neither the per-row rubric nor anything on the
/// job:
///
/// * the saved configuration never reached the worker (`skipped_no_config`);
/// * the decision client could not be built (`client_unavailable`);
/// * the scoring call failed after the retry (`scoring_failed`, plus a
///   `scoringFailed` rubric on every affected row);
/// * the provider answered only partially (scores honestly `null`).
///
/// This file turns the two wire records the backend already carries into the
/// two localized surfaces:
///
/// * [aiDecisionSummary] — the header/cost-card line: WHICH Decision Model
///   scored the import, or why it did not (the job-level
///   `DecisionTelemetry`, additive on the wire).
/// * [AiScoringFailedNote] — the per-row degradation note for a row whose own
///   scoring request failed (`DecisionRubric.scoringFailed`), rendered instead
///   of unexplained empty space.
///
/// Nothing is fabricated. A job that recorded no outcome (`null` — every
/// pre-#767 row) renders nothing at all rather than a guessed class, a failed
/// pass never invents a star rating, and the copy is keyed on the stable
/// outcome enum — never on backend prose.
library;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/ai_import_providers.dart';
import '../../../l10n/app_localizations_provider.dart';
import '../../../l10n/generated/app_localizations.dart';

part 'decision_outcome.g.dart';

/// The job's recorded Decision Model outcome (issue #767).
///
/// `null` means "the wire carries no outcome" — a job recorded before the field
/// existed, or a read that failed. The provider never invents one: an
/// unreadable job renders no line at all, which is the honest degradation for
/// data that does not exist.
///
/// `getJobAndCache` (NOT the SSE watch) keeps this a single cheap snapshot: the
/// preview and the job screen read one authoritative fact, and the app's single
/// SSE consumer stays the job-status controller (battery contract D5).
@riverpod
Future<DecisionTelemetry?> aiJobDecisionTelemetry(Ref ref, String jobId) async {
  final repo = ref.read(aiImportRepositoryProvider);
  final job = await repo.getJobAndCache(jobId);
  return job.match((_) => null, (job) => job.decisionTelemetry);
}

/// How prominently the outcome line states its class.
enum AiDecisionTone {
  /// The pass ran — an informational line naming the model.
  info,

  /// The pass could not run at all (no configuration, or an unbuildable
  /// client): the import is complete, the stars are simply absent.
  warning,

  /// The pass ran and (at least partly) failed: affected rows carry no stars.
  failed,
}

/// One localized outcome line: the tone that colours it and its text.
class AiDecisionSummary {
  const AiDecisionSummary({required this.tone, required this.label});

  final AiDecisionTone tone;
  final String label;
}

/// The display join of the resolved `(provider, model)` pair.
///
/// A pure display join of wire values — the client never derives or guesses a
/// model id. Absent parts degrade honestly: a telemetry carrying only a model
/// names that model, only a provider names the provider, and neither names the
/// localized "unnamed model" (the wire contract always carries the pair for
/// `ran`/`client_unavailable`/`scoring_failed`, so this is a defensive arm, not
/// an expected state).
String aiDecisionPairLabel(AppLocalizations l10n, DecisionTelemetry telemetry) {
  final provider = telemetry.provider?.name;
  final model = telemetry.model;
  if (provider == null || provider.isEmpty) {
    final namedModel = model;
    if (namedModel == null || namedModel.isEmpty) {
      return l10n.aiDecisionModelUnnamed;
    }
    return namedModel;
  }
  if (model == null || model.isEmpty) return provider;
  return '$provider / $model';
}

/// The localized one-line summary of [telemetry] (issue #767): the effective
/// Decision Model and what the scoring pass did with it.
///
/// Every arm keys on the stable `DecisionOutcome` class — an unknown future
/// value degrades to the warning tone with the neutral "no scoring recorded"
/// copy instead of crashing or inventing a reason.
AiDecisionSummary aiDecisionSummary(
  AppLocalizations l10n,
  DecisionTelemetry telemetry,
) {
  final pair = aiDecisionPairLabel(l10n, telemetry);
  final failedRows = telemetry.failedRows ?? 0;
  switch (telemetry.outcome) {
    case DecisionOutcome.ran:
      return AiDecisionSummary(
        tone: AiDecisionTone.info,
        label: l10n.aiDecisionRan(pair),
      );
    case DecisionOutcome.skippedNoConfig:
      return AiDecisionSummary(
        tone: AiDecisionTone.warning,
        label: l10n.aiDecisionSkippedNoConfig,
      );
    case DecisionOutcome.clientUnavailable:
      return AiDecisionSummary(
        tone: AiDecisionTone.warning,
        label: l10n.aiDecisionClientUnavailable(pair),
      );
    case DecisionOutcome.scoringFailed:
      return AiDecisionSummary(
        tone: AiDecisionTone.failed,
        // gen-l10n binds placeholders ALPHABETICALLY (count, pair) and types
        // the plural placeholder as `num` — pass the count as a number.
        label: l10n.aiDecisionScoringFailed(failedRows, pair),
      );
    case DecisionOutcome.skippedNotApplicable:
      return AiDecisionSummary(
        tone: AiDecisionTone.info,
        label: l10n.aiDecisionSkippedNotApplicable,
      );
    default:
      return AiDecisionSummary(
        tone: AiDecisionTone.warning,
        label: l10n.aiDecisionNotRecorded,
      );
  }
}

/// The effective-Decision-Model line of the preview header (issue #767).
///
/// Resolves the outcome through [aiJobDecisionTelemetryProvider] so the preview
/// — which does not otherwise hold the job — can state which Decision Model
/// scored the import. The job status screen already holds the job and renders
/// [AiDecisionOutcomeText] directly (no second read).
///
/// Renders [SizedBox.shrink] while loading, for an unrecorded outcome
/// (pre-#767 jobs) and for a failed read: the line explains a *recorded*
/// outcome, and silence without a record is honest.
class AiDecisionOutcomeLine extends ConsumerWidget {
  const AiDecisionOutcomeLine({required this.jobId, super.key});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `AsyncValue.value` keeps the last resolved outcome across a reload
    // (Riverpod 3 `skipLoadingOnReload` semantics): a refresh never blanks the
    // line, and an unrecorded/unreadable outcome stays silent.
    final telemetry = ref.watch(aiJobDecisionTelemetryProvider(jobId)).value;
    return AiDecisionOutcomeText(telemetry: telemetry);
  }
}

/// The outcome line for a caller that ALREADY holds the job (issue #767) — the
/// job status cost card. Never triggers a second read, never invents an
/// outcome: `null` renders nothing at all.
class AiDecisionOutcomeText extends StatelessWidget {
  const AiDecisionOutcomeText({required this.telemetry, super.key});

  final DecisionTelemetry? telemetry;

  @override
  Widget build(BuildContext context) {
    final value = telemetry;
    if (value == null) return const SizedBox.shrink();
    final summary = aiDecisionSummary(l10nOf(context), value);
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (summary.tone) {
      AiDecisionTone.info => (
        Icons.auto_awesome_outlined,
        scheme.onSurfaceVariant,
      ),
      AiDecisionTone.warning => (Icons.info_outline, scheme.tertiary),
      AiDecisionTone.failed => (Icons.report_outlined, scheme.error),
    };
    return Semantics(
      key: const Key('ai-decision-outcome'),
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              summary.label,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// The per-row degradation note for a row whose own scoring request failed
/// (issue #767).
///
/// Rendered in the same visual language as the other degradation surfaces
/// (icon + short localized line, never a blocking dialog): the row states why
/// it has no stars instead of leaving the reviewer with unexplained empty
/// space. It NEVER renders a rating — the star widget stays silent because
/// there is no score.
class AiScoringFailedNote extends StatelessWidget {
  const AiScoringFailedNote({this.draftRef, super.key});

  /// The preview row's `draft_ref`, used to key one note per row (several rows
  /// of one import may fail independently).
  final String? draftRef;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      key: Key('ai-preview-scoring-failed-${draftRef ?? 'row'}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.report_outlined, size: 16, color: scheme.error),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            l10nOf(context).aiPreviewScoringFailed,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.error),
          ),
        ),
      ],
    );
  }
}
