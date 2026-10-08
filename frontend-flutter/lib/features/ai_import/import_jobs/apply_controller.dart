// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:fpdart/fpdart.dart';
import 'package:one_of/one_of.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/problem_error.dart';
import '../../../core/result.dart';
import '../../../data/ai_import_providers.dart';
import '../../../data/ai_import_repository.dart';
import '../../../domain/reconciliation/reconciliation_scheduler.dart';
import '../../../l10n/generated/app_localizations.dart';
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

/// The per-group episode target (issue #581). The backend requires a target
/// for EVERY group the preview carries (`MissingEpisodeGroup`), so groups are
/// pre-mapped to a create-new target pre-filled from the heading and the
/// reviewer can switch any group to an existing episode.
sealed class EpisodeGroupTarget {
  const EpisodeGroupTarget();
}

/// Create a NEW episode under the job's block. `number` is REQUIRED on the
/// wire (`EpisodeTargetOneOf1.number`) — a marker without a number leaves this
/// incomplete and keeps apply disabled until the reviewer enters one.
class CreateEpisodeGroupTarget extends EpisodeGroupTarget {
  const CreateEpisodeGroupTarget({this.number, this.name});

  final int? number;

  /// The heading's title, kept verbatim; nullable on the wire.
  final String? name;
}

/// Apply the group to the EXISTING episode the reviewer picked (id from the
/// picked read DTO — never invented).
class ExistingEpisodeGroupTarget extends EpisodeGroupTarget {
  const ExistingEpisodeGroupTarget({required this.episodeId, this.label});

  final String episodeId;

  /// Human-readable label captured at pick time (never re-derived).
  final String? label;
}

/// Mirrors `breakdown_core::ai::DraftEpisode::group_key` BYTE-FOR-BYTE:
/// `ep:<n>` when the marker carried a number, else `ep-t:<trimmed title>`.
/// The apply request's group refs must match the backend's derivation exactly
/// or the validation rejects the mapping. `null` = no grouping (the row
/// applies to the explicitly picked target episode).
String? draftEpisodeGroupRef(DraftEpisode episode) {
  final number = episode.number;
  if (number != null) return 'ep:$number';
  final title = episode.title;
  if (title != null && title.trim().isNotEmpty) return 'ep-t:${title.trim()}';
  return null;
}

/// One extracted costume of a draft row, with the reviewer's decision.
///
/// A costume is decided *independently of its scene* (spec `ai-import`): the
/// reviewer can reject one garment without rejecting the scene it came from.
/// The default is accepted, and only rejections travel on the wire — the backend
/// treats an absent ordinal as accepted, so an untouched row keeps sending
/// nothing and stays a genuine `accept_as_is`.
class PreviewCostume {
  const PreviewCostume({
    required this.ordinal,
    required this.characterName,
    required this.description,
    required this.sourceQuote,
    this.accepted = true,
  });

  /// Index into the draft row's `costumes` list — the mapping key the backend
  /// addresses this row by, alongside the row's `draft_ref`.
  final int ordinal;
  final String characterName;
  final String description;

  /// The quoted script fragment the extraction claims to be based on. Shown next
  /// to [description] so the reviewer can verify the extraction WITHOUT opening
  /// the document (spec `ai-import`).
  final String sourceQuote;

  final bool accepted;

  PreviewCostume withAccepted(bool accepted) => PreviewCostume(
    ordinal: ordinal,
    characterName: characterName,
    description: description,
    sourceQuote: sourceQuote,
    accepted: accepted,
  );
}

/// One preview row with its current decision (controller state;
/// immutable — decisions are replaced, never mutated in place).
class PreviewRow {
  const PreviewRow({
    required this.draftRef,
    required this.label,
    this.decision = const CreateDecision(),
    this.costumes = const <PreviewCostume>[],
    this.episode,
  });

  final String draftRef;

  /// Human-readable row label from the typed payload (never fabricated).
  final String label;

  final RowDecision decision;

  /// The row's extracted costumes with their per-row decisions. Empty for a
  /// preview stored before the field existed, and for a row the script gave no
  /// costuming to — both are correct, not failures.
  final List<PreviewCostume> costumes;

  /// The draft episode the row's `Ep.:` marker carried (issue #581). `null`
  /// for previews stored before the field existed and for rows without a
  /// marker — both apply to the explicitly picked target episode (the
  /// single-episode flow), which is correct, not a failure.
  final DraftEpisode? episode;

  PreviewRow withDecision(RowDecision decision) => PreviewRow(
    draftRef: draftRef,
    label: label,
    decision: decision,
    costumes: costumes,
    episode: episode,
  );

  /// Replaces one costume row's decision by [ordinal]; an unknown ordinal is
  /// ignored rather than fabricating a row the payload does not carry.
  PreviewRow withCostumeDecision(int ordinal, bool accepted) => PreviewRow(
    draftRef: draftRef,
    label: label,
    decision: decision,
    costumes: [
      for (final costume in costumes)
        if (costume.ordinal == ordinal)
          costume.withAccepted(accepted)
        else
          costume,
    ],
    episode: episode,
  );
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
    this.groupTargets = const <String, EpisodeGroupTarget>{},
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

  /// The reviewer's per-group episode targets, keyed by the backend-derived
  /// group ref. ABSENT entries fall back to the seeded default (create-new,
  /// pre-filled from the heading — [targetFor]); only explicit picks land
  /// here, so the map stays small and the default derivation lives in one
  /// place.
  final Map<String, EpisodeGroupTarget> groupTargets;

  /// True when the user made zero decision edits.
  bool get acceptAsIs => editDistance == 0;

  /// The real selection-state edit distance: the number of rows whose
  /// decision the user changed away from the default (Create), PLUS the number
  /// of costume rows rejected away from their default (accepted). A toggled
  /// costume is an edit: reporting `accept_as_is` over one would be a false
  /// statement about the review, and the backend rejects the combination.
  int get editDistance =>
      rows.where((r) => r.decision is! CreateDecision).length +
      rows.fold<int>(
        0,
        (sum, row) =>
            sum + row.costumes.where((costume) => !costume.accepted).length,
      ) +
      _groupEdits;

  /// The preview's group refs in first-appearance order (verbatim backend
  /// `group_key` derivations — the apply request carries exactly these).
  List<String> get groupRefs {
    final refs = <String>[];
    for (final row in rows) {
      final episode = row.episode;
      if (episode == null) continue;
      final ref = draftEpisodeGroupRef(episode);
      if (ref != null && !refs.contains(ref)) refs.add(ref);
    }
    return refs;
  }

  /// The episode metadata of [ref]'s first row (the heading the group was
  /// extracted from); `null` for an unknown ref (never dispatched).
  DraftEpisode? episodeOfGroup(String ref) {
    for (final row in rows) {
      final episode = row.episode;
      if (episode != null && draftEpisodeGroupRef(episode) == ref) {
        return episode;
      }
    }
    return null;
  }

  /// The effective target for [ref]: the reviewer's pick, else the seeded
  /// default (create-new, pre-filled from the heading — the user-confirmed
  /// default; the backend rejects a forgotten group outright).
  EpisodeGroupTarget targetFor(String ref) {
    final picked = groupTargets[ref];
    if (picked != null) return picked;
    final episode = episodeOfGroup(ref);
    if (episode == null) return const CreateEpisodeGroupTarget();
    return CreateEpisodeGroupTarget(
      number: episode.number,
      name: episode.title,
    );
  }

  /// Group-target edits: a group whose effective target deviates from its
  /// seeded create-default (switched to existing, or number/name changed) is
  /// an edit — `accept_as_is` must stay a truthful statement about the review.
  int get _groupEdits {
    var edits = 0;
    for (final ref in groupRefs) {
      final target = targetFor(ref);
      final episode = episodeOfGroup(ref);
      final isDefault =
          target is CreateEpisodeGroupTarget &&
          episode != null &&
          target.number == episode.number &&
          target.name == episode.title;
      if (!isDefault) edits++;
    }
    return edits;
  }

  /// Every create target must carry its wire-required number; a marker
  /// without one leaves the target incomplete and apply disabled.
  bool get hasCompleteGroupTargets => groupRefs.every((ref) {
    final target = targetFor(ref);
    return target is! CreateEpisodeGroupTarget || target.number != null;
  });

  /// Client-side mirror of the backend's "two groups create the same episode
  /// number" 422 — caught before the wire, not after.
  bool get hasDuplicateCreateNumbers {
    final numbers = <int>{};
    for (final ref in groupRefs) {
      final target = targetFor(ref);
      if (target is CreateEpisodeGroupTarget) {
        final number = target.number;
        if (number != null && !numbers.add(number)) return true;
      }
    }
    return false;
  }

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
      if (mapping == null) continue;
      // Only rejections go on the wire: an absent ordinal means accepted
      // server-side, so an untouched row sends no costume payload at all and the
      // request stays byte-identical to a pre-costume client's.
      final rejected = row.costumes
          .where((costume) => !costume.accepted)
          .map(
            (costume) => CostumeDecision(
              (b) => b
                ..ordinal = costume.ordinal
                ..accepted = false,
            ),
          )
          .toList();
      // `rebuild` RETURNS the replaced value — a built_value is immutable, so
      // calling it for its side effect would silently drop every rejection.
      mappings.add(
        rejected.isEmpty
            ? mapping
            : mapping.rebuild((m) => m.costumeDecisions.replace(rejected)),
      );
    }
    return mappings;
  }

  /// Builds the request's per-group episode targets (issue #581): one entry
  /// per preview group ref, existing id from the picked read DTO / create
  /// with the (required) number. Empty when no row carries episode metadata —
  /// the request then stays byte-identical to the single-episode flow.
  BuiltList<ApplyEpisodeGroupRequest> buildEpisodeGroups() =>
      BuiltList<ApplyEpisodeGroupRequest>([
        for (final ref in groupRefs)
          ApplyEpisodeGroupRequest(
            (b) => b
              ..episodeRef = ref
              ..target.replace(_wireTarget(targetFor(ref))),
          ),
      ]);

  EpisodeTarget _wireTarget(EpisodeGroupTarget target) => switch (target) {
    ExistingEpisodeGroupTarget(:final episodeId) => EpisodeTarget(
      (e) => e
        ..oneOf = OneOf.fromValue1<EpisodeTargetOneOf>(
          value: EpisodeTargetOneOf(
            (v) => v
              ..episodeId = episodeId
              ..kind = EpisodeTargetOneOfKindEnum.existing,
          ),
        ),
    ),
    CreateEpisodeGroupTarget(:final number, :final name) => EpisodeTarget(
      (e) =>
          e
            ..oneOf = OneOf.fromValue2<EpisodeTargetOneOf, EpisodeTargetOneOf1>(
              value: EpisodeTargetOneOf1(
                (v) => v
                  ..number = number!
                  ..name = name
                  ..kind = EpisodeTargetOneOf1KindEnum.create,
              ),
            ),
    ),
  };
}

/// The apply controller (task 4.2): builds + submits the mappings.
@Riverpod(keepAlive: false)
class AiApplyController extends _$AiApplyController {
  @override
  AiApplyState build(String jobId) => const AiApplyState(rows: []);

  /// Seeds the actionable rows from the typed preview payload (D1) and
  /// the persisted episode context. Called by the preview screen once the
  /// typed payload is in hand; the rows carry the payload's verbatim
  /// `draft_ref`s. Group targets RESET to the seeded defaults: a fresh
  /// payload is a fresh review, never one carrying over stale picks.
  void seedRows(List<PreviewRow> rows, AiJobContext? context) {
    state = AiApplyState(rows: rows, context: context);
  }

  /// Records the reviewer's target for one episode group (existing episode
  /// id or create number/name). Absent keys keep the seeded create-default.
  void setGroupTarget(String groupRef, EpisodeGroupTarget target) {
    state = AiApplyState(
      rows: state.rows,
      context: state.context,
      outcome: state.outcome,
      commandError: state.commandError,
      groupTargets: {...state.groupTargets, groupRef: target},
    );
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
      groupTargets: state.groupTargets,
    );
  }

  /// Accept or reject ONE costume row of a draft row, leaving the scene row's
  /// own decision untouched (spec `ai-import`: costume rows are decided
  /// independently).
  void decideCostume(String draftRef, int ordinal, bool accepted) {
    state = AiApplyState(
      rows: [
        for (final row in state.rows)
          if (row.draftRef == draftRef)
            row.withCostumeDecision(ordinal, accepted)
          else
            row,
      ],
      context: state.context,
      outcome: state.outcome,
      commandError: state.commandError,
      groupTargets: state.groupTargets,
    );
  }

  void dismissCommandError() {
    state = AiApplyState(
      rows: state.rows,
      context: state.context,
      outcome: state.outcome,
      groupTargets: state.groupTargets,
    );
  }

  bool get canApply =>
      state.context != null &&
      state.rows.isNotEmpty &&
      state.outcome == null &&
      // A group create target without its wire-required number (a marker
      // without `Ep.: <n>`) or two groups on one number keep apply disabled.
      state.hasCompleteGroupTargets &&
      !state.hasDuplicateCreateNumbers;

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
    final episodeGroups = state.buildEpisodeGroups();
    final request = ApplyAiImportRequest(
      (b) => b
        ..episodeId = context.episodeId
        ..projectId = context.projectId.isEmpty ? null : context.projectId
        ..mappings.replace(state.buildMappings())
        ..acceptAsIs = state.acceptAsIs
        ..editDistance = state.editDistance
        // Absent on a flat script: the wire request stays byte-identical to
        // the single-episode flow (backend treats empty as absent).
        ..episodeGroups = episodeGroups.isEmpty
            ? null
            : episodeGroups.toBuilder(),
    );
    final outcome = await repo.applyWithReconciliation(
      jobId,
      request,
      scheduler: ref.read(reconciliationSchedulerProvider),
    );
    switch (outcome) {
      case ApplySucceeded(:final response):
        // The apply can span seconds (ambiguous-timeout retries): the
        // autoDispose notifier may have lost its only listener while the
        // user left the preview — writing `state` on a disposed notifier
        // throws. The RESULT still returns (the caller is gone anyway).
        if (!ref.mounted) return Right(response);
        state = AiApplyState(
          rows: state.rows,
          context: context,
          outcome: response,
          groupTargets: state.groupTargets,
        );
        return Right(response);
      case ApplyBlocked(:final error):
        if (!ref.mounted) return Left(error);
        state = AiApplyState(
          rows: state.rows,
          context: context,
          outcome: null,
          commandError: error,
          groupTargets: state.groupTargets,
        );
        return Left(error);
      case ApplyUnresolved(:final error):
        if (!ref.mounted) return Left(error);
        state = AiApplyState(
          rows: state.rows,
          context: context,
          outcome: null,
          commandError: error,
          groupTargets: state.groupTargets,
        );
        return Left(error);
    }
  }
}

/// Localized copy for an apply failure, keyed on the stable problem
/// `code` (never the server `detail`). `ai-import.forbidden` is the scoped
/// wire code the backend emits for ALL AI-import job denials — ownership,
/// season-scope AND cross-resource (episode/scene mismatch) — so the copy is
/// access-neutral rather than role/block-specific (CodeRabbit #480). The
/// apply screen has no client pre-gate, so only the server code reaches this
/// switch.
String aiApplyErrorCopy(AppLocalizations l10n, ProblemError error) =>
    switch (error.code) {
      'ai-import.forbidden' => l10n.jobWatchForbidden,
      'ai_import.apply_job_not_succeeded' => l10n.aiApplyErrorNotSucceeded,
      'ai_import.apply_unresolved' => l10n.aiApplyErrorUnresolved,
      'ai_import.apply_context_missing' => l10n.aiApplyErrorContextMissing,
      // Issue #581: the API-edge create-number pre-check (#404 doctrine) —
      // the reviewer picked a number the series already uses.
      'episode.number-already-exists' => l10n.aiApplyErrorEpisodeNumberTaken,
      _ when error.code.startsWith('transport.') => l10n.aiApplyErrorNetwork,
      _ => l10n.aiApplyErrorGeneric(error.code),
    };

/// Composed human label for a draft episode: `Episode 3 · Titel` /
/// `Episode 3` / `„Titel“`. Empty only when both parts are absent — such a
/// draft episode yields no group ref either ([draftEpisodeGroupRef]).
String draftEpisodeLabel(AppLocalizations l10n, int? number, String? title) {
  final numberLabel = number == null ? null : l10n.episodeTileLabel('$number');
  final trimmedTitle = title?.trim();
  final hasTitle = trimmedTitle != null && trimmedTitle.isNotEmpty;
  if (numberLabel == null) return hasTitle ? '\u201e$trimmedTitle\u201c' : '';
  return hasTitle ? '$numberLabel \u00b7 $trimmedTitle' : numberLabel;
}

/// Localized target label for ONE episode group: what the reviewer sees next
/// to the group heading and in the apply card's summary. A create target
/// without its wire-required number says so instead of inventing one.
String groupTargetLabel(AppLocalizations l10n, EpisodeGroupTarget target) =>
    switch (target) {
      ExistingEpisodeGroupTarget(:final label, :final episodeId) =>
        l10n.aiApplyGroupTargetExisting(label ?? episodeId),
      CreateEpisodeGroupTarget(:final number, :final name) =>
        number == null
            ? l10n.aiApplyGroupTargetCreateNoNumber
            : l10n.aiApplyGroupTargetCreate(
                draftEpisodeLabel(l10n, number, name),
              ),
    };

/// The apply card's per-group summary line (EU AI Act review gate): WHICH
/// episode the group lands in, right at the dispatch point.
String groupTargetSummaryLine(
  AppLocalizations l10n,
  AiApplyState state,
  String groupRef,
) {
  final episode = state.episodeOfGroup(groupRef);
  final heading = episode == null
      ? groupRef
      : draftEpisodeLabel(l10n, episode.number, episode.title);
  return l10n.aiApplyGroupTargetSummary(
    heading,
    groupTargetLabel(l10n, state.targetFor(groupRef)),
  );
}
