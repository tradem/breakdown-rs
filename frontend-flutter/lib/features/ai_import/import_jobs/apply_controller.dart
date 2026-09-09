// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';
import 'package:one_of/one_of.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/problem_error.dart';
import '../../../core/result.dart';
import '../../../data/ai_import_providers.dart';
import '../../../data/ai_import_repository.dart';
import '../../../domain/reconciliation/reconciliation_scheduler.dart';
import 'job_status_controller.dart';

part 'apply_controller.g.dart';

/// The typed preview fetch (D1). NEVER cached (regenerable, potentially
/// large — design §3): the provider is auto-dispose and re-armed by the
/// refresh affordance. Tests override this seam.
@riverpod
Future<Result<AiImportPreviewResponse>> aiPreview(Ref ref, String jobId) =>
    ref.watch(aiImportRepositoryProvider).getPreview(jobId);

/// The per-row apply decision (task 4.2). The `draft_ref` is carried
/// VERBATIM from the preview row the user acted on — never recomputed,
/// never re-typed (D1).
sealed class RowDecision {
  const RowDecision();
}

/// Create the draft as a new aggregate.
class CreateDecision extends RowDecision {
  const CreateDecision();
}

/// Update the existing aggregate the user picked (id + version from the
/// picked read DTO — never invented).
class UpdateDecision extends RowDecision {
  const UpdateDecision({required this.aggregateId, required this.version});

  final String aggregateId;
  final int version;
}

/// Skip the draft (excluded from the mappings — the request carries
/// exactly the acted-on rows).
class SkipDecision extends RowDecision {
  const SkipDecision();
}

/// One preview row with its current decision (controller state;
/// immutable — decisions are replaced, never mutated in place).
class PreviewRow {
  const PreviewRow({
    required this.draftRef,
    required this.label,
    this.decision = const CreateDecision(),
  });

  final String draftRef;

  /// Human-readable row label from the typed payload (never fabricated).
  final String label;

  final RowDecision decision;

  PreviewRow withDecision(RowDecision decision) =>
      PreviewRow(draftRef: draftRef, label: label, decision: decision);
}

/// The apply selection state (task 4.2): rows, the persisted episode
/// context, and the mapping-request builder inputs.
///
/// `accept_as_is` is true exactly when the user made zero edits
/// (`edit_distance == 0`) — the backend rejects any other combination
/// ("accept_as_is requires edit_distance = 0"); both values are REPORTED
/// by the selection state, never invented.
class AiApplyState {
  const AiApplyState({
    required this.rows,
    this.context,
    this.outcome,
    this.commandError,
  });

  /// The actionable rows with their decisions. Degraded/unmatched rows
  /// are NOT here — they render as excluded info cards.
  final List<PreviewRow> rows;

  /// The persisted apply context (episode + series, design §2.3) read
  /// from the job's persisted record — NOT navigation state. `null`
  /// means the explicit episode picker is REQUIRED before apply is
  /// enabled (apply is never dispatched with a guessed/empty episode_id).
  final AiJobContext? context;

  /// The 200 outcome summary card (`applied_count`, `created_days`,
  /// `planned_scene_shoots`).
  final ApplyAiImportResponse? outcome;

  /// The last command failure, keyed on the stable problem `code`.
  final ProblemError? commandError;

  /// True when the user made zero decision edits.
  bool get acceptAsIs => editDistance == 0;

  /// The real selection-state edit distance: the number of rows whose
  /// decision the user changed away from the default (Create).
  int get editDistance =>
      rows.where((r) => r.decision is! CreateDecision).length;

  /// Builds the request's mappings: verbatim `draft_ref`s, Create /
  /// Update-from-picked-DTO / skip (skipped rows are EXCLUDED).
  List<ApplyMapping> buildMappings() {
    final mappings = <ApplyMapping>[];
    for (final row in rows) {
      final mapping = switch (row.decision) {
        CreateDecision() => ApplyMapping(
          (m) => m
            ..draftRef = row.draftRef
            ..decision.replace(
              ApplyMappingDecision(
                (d) => d..oneOf = OneOf.fromValue1(value: 'Create'),
              ),
            ),
        ),
        UpdateDecision(:final aggregateId, :final version) => ApplyMapping(
          (m) => m
            ..draftRef = row.draftRef
            ..decision.replace(
              ApplyMappingDecision(
                (d) => d
                  ..oneOf = OneOf.fromValue2<String, ApplyMappingDecisionOneOf>(
                    value: ApplyMappingDecisionOneOf(
                      (u) => u
                        ..decisionUpdate.replace(
                          ApplyMappingDecisionOneOfUpdate(
                            (x) => x
                              ..aggregateId = aggregateId
                              ..version = version,
                          ),
                        ),
                    ),
                  ),
              ),
            ),
        ),
        SkipDecision() => null,
      };
      if (mapping != null) mappings.add(mapping);
    }
    return mappings;
  }
}

/// The apply controller (task 4.2): builds + submits the mappings.
@Riverpod(keepAlive: false)
class AiApplyController extends _$AiApplyController {
  @override
  AiApplyState build(String jobId) => const AiApplyState(rows: []);

  /// Seeds the actionable rows from the typed preview payload (D1) and
  /// the persisted episode context. Called by the preview screen once the
  /// typed payload is in hand; the rows carry the payload's verbatim
  /// `draft_ref`s.
  void seedRows(List<PreviewRow> rows, AiJobContext? context) {
    state = AiApplyState(rows: rows, context: context);
  }

  /// Overrides the persisted context with the user's explicit episode
  /// pick (the missing-context → picker-required path; apply is never
  /// dispatched with a guessed episode_id).
  void setContext(AiJobContext context) {
    state = AiApplyState(
      rows: state.rows,
      context: context,
      outcome: state.outcome,
      commandError: state.commandError,
    );
  }

  void decide(String draftRef, RowDecision decision) {
    state = AiApplyState(
      rows: [
        for (final row in state.rows)
          if (row.draftRef == draftRef) row.withDecision(decision) else row,
      ],
      context: state.context,
      outcome: state.outcome,
      commandError: state.commandError,
    );
  }

  void dismissCommandError() {
    state = AiApplyState(
      rows: state.rows,
      context: state.context,
      outcome: state.outcome,
    );
  }

  bool get canApply =>
      state.context != null && state.rows.isNotEmpty && state.outcome == null;

  /// The explicit apply dispatch with the ambiguous-timeout
  /// reconciliation (task 4.2 / design §1): a timeout re-reads the
  /// job/outcome first and reconciles (bounded retry — the server-side
  /// apply is idempotent, reserve-before-create, backend issue #338);
  /// never a blind re-dispatch, never a duplicate import implied.
  Future<Result<ApplyAiImportResponse>> apply() async {
    final context = state.context;
    if (context == null) {
      // Structural impossibility: the button is disabled without context;
      // the guard keeps the request honest (no guessed episode_id).
      const error = ProblemError(
        code: 'ai_import.apply_context_missing',
        status: 400,
      );
      state = AiApplyState(
        rows: state.rows,
        context: null,
        outcome: null,
        commandError: error,
      );
      return const Left(error);
    }
    final repo = ref.read(aiImportRepositoryProvider);
    final request = ApplyAiImportRequest(
      (b) => b
        ..episodeId = context.episodeId
        ..seriesId = context.seriesId.isEmpty ? null : context.seriesId
        ..mappings.replace(state.buildMappings())
        ..acceptAsIs = state.acceptAsIs
        ..editDistance = state.editDistance,
    );
    final outcome = await repo.applyWithReconciliation(
      jobId,
      request,
      scheduler: ref.read(reconciliationSchedulerProvider),
    );
    switch (outcome) {
      case ApplySucceeded(:final response):
        state = AiApplyState(
          rows: state.rows,
          context: context,
          outcome: response,
        );
        return Right(response);
      case ApplyBlocked(:final error):
        state = AiApplyState(
          rows: state.rows,
          context: context,
          outcome: null,
          commandError: error,
        );
        return Left(error);
      case ApplyUnresolved(:final error):
        state = AiApplyState(
          rows: state.rows,
          context: context,
          outcome: null,
          commandError: error,
        );
        return Left(error);
    }
  }
}

/// Localized copy for an apply failure, keyed on the stable problem
/// `code` (never the server `detail`).
String aiApplyErrorCopy(ProblemError error) => switch (error.code) {
  'ai_import.forbidden' => 'You need an active costume role in this season.',
  'ai_import.apply_job_not_succeeded' =>
    'The preview can no longer be applied — check the job status.',
  'ai_import.apply_unresolved' =>
    'The apply outcome is unknown — the server may still have applied '
        'it. Check the affected episode before retrying.',
  'ai_import.apply_context_missing' =>
    'Pick the target episode before applying.',
  _ when error.code.startsWith('transport.') =>
    'Network problem — the apply may not have gone through. Check the '
        'affected episode before retrying.',
  _ => 'The apply failed (${error.code}).',
};
