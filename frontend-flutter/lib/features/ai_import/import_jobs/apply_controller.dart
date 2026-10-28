// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:fpdart/fpdart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_of/one_of.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/problem_error.dart';
import '../../../core/result.dart';
import '../../../data/ai_import_providers.dart';
import '../../../data/ai_import_repository.dart';
import '../../../data/cache/seasons_cache_providers.dart';
import '../../../domain/reconciliation/reconciliation_scheduler.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../blocks/blocks_controller.dart';
import '../../episodes/episodes_controller.dart';
import 'continuity_gap.dart';
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

/// Mirrors `breakdown_core::ai::DraftShootingDay::group_key` BYTE-FOR-BYTE
/// (issue #706): `day:<n>` when the marker carried a number, else
/// `day-l:<trimmed label>` for a day the model reported without a parseable
/// number. The apply request's day refs must match the backend's derivation
/// exactly or the validation rejects the decision. `null` = the row cannot
/// be grouped (it applies unscheduled).
String? draftShootingDayGroupRef(DraftShootingDay day) {
  final number = day.number;
  if (number != null) return 'day:$number';
  final label = day.label;
  if (label != null && label.trim().isNotEmpty) return 'day-l:${label.trim()}';
  return null;
}

/// The reviewer-facing day label: the marker's verbatim text when one was
/// captured, else the backend's synthesized display form — mirrors
/// `DraftShootingDay::display_label`. Empty only when the day carries
/// neither (such a day yields no group ref either).
String draftShootingDayLabel(DraftShootingDay day) {
  final label = day.label?.trim();
  if (label != null && label.isNotEmpty) return label;
  final number = day.number;
  return number == null ? '' : 'Tag $number';
}

/// One extracted piece of a draft row, with the reviewer's decision.
///
/// A piece is decided *independently of its scene* (spec `ai-import`): the
/// reviewer can reject one garment without rejecting the scene it came from.
/// The default is accepted, and only rejections travel on the wire — the backend
/// treats an absent ordinal as accepted, so an untouched row keeps sending
/// nothing and stays a genuine `accept_as_is`.
class PreviewOutfit {
  const PreviewOutfit({
    required this.ordinal,
    required this.characterName,
    required this.name,
    required this.sourceQuote,
    this.origin,
    this.provenance,
    this.pieces = const <PreviewOutfitPiece>[],
    this.accepted = true,
  });

  /// Index into the draft row's `outfits` list — the mapping key the backend
  /// addresses this row by, alongside the row's `draft_ref`.
  final int ordinal;
  final String characterName;

  /// The look's display name ("OP-Kleidung", "ölverschmierter
  /// Mechaniker-Overall") — what the reviewer recognises, not a garment list.
  final String name;

  /// The quoted script fragment the extraction claims to be based on. Shown next
  /// to [name] so the reviewer can verify the extraction WITHOUT opening the
  /// document (spec `ai-import`).
  final String sourceQuote;

  /// Where the look came from (`DraftOutfit.origin`, issue #745): a Pass-1
  /// quote/derivation, or one of the two Pass-2 forms. `null` on a preview
  /// stored before the field existed and on an unrecognized future value —
  /// both render no provenance badge rather than an invented one.
  final DraftOutfitOrigin? origin;

  /// The Pass-2 payload behind [origin]: the source row + scene number of a
  /// continuation and the Decision Model's confidence (design D5 of
  /// `ai-import-decision-outfit-continuity`). `null` whenever the wire carries
  /// none (every Pass-1 row, an older stored preview).
  final DraftOutfitProvenance? provenance;

  /// The garments the look decomposes into. Read-only here: the backend grounds
  /// the look and derives its pieces, so the reviewer decides the LOOK (the
  /// pieces belong to it and are not individually addressable).
  final List<PreviewOutfitPiece> pieces;

  final bool accepted;

  PreviewOutfit withAccepted(bool accepted) => PreviewOutfit(
    ordinal: ordinal,
    characterName: characterName,
    name: name,
    sourceQuote: sourceQuote,
    origin: origin,
    provenance: provenance,
    pieces: pieces,
    accepted: accepted,
  );
}

/// One derived garment of a [PreviewOutfit]: the display name plus the category
/// hint the model proposed (the server resolves it against the season's
/// vocabulary; an unknown hint simply leaves the piece uncategorized).
class PreviewOutfitPiece {
  const PreviewOutfitPiece({required this.name, this.categoryHint});

  final String name;
  final String? categoryHint;
}

/// One preview row with its current decision (controller state;
/// immutable — decisions are replaced, never mutated in place).
class PreviewRow {
  const PreviewRow({
    required this.draftRef,
    required this.label,
    this.decision = const CreateDecision(),
    this.outfits = const <PreviewOutfit>[],
    this.episode,
    this.shootingDay,
  });

  final String draftRef;

  /// Human-readable row label from the typed payload (never fabricated).
  final String label;

  final RowDecision decision;

  /// The row's extracted outfits with their per-row decisions. Empty for a
  /// preview stored before the field existed, and for a row the script gave no
  /// wardrobe to — both are correct, not failures.
  final List<PreviewOutfit> outfits;

  /// The draft episode the row's `Ep.:` marker carried (issue #581). `null`
  /// for previews stored before the field existed and for rows without a
  /// marker — both apply to the explicitly picked target episode (the
  /// single-episode flow), which is correct, not a failure.
  final DraftEpisode? episode;

  /// The shooting day the row was extracted for (issue #706). `null` for
  /// previews stored before the field existed and for rows without a day
  /// marker — both apply unscheduled, which is correct, not a failure.
  final DraftShootingDay? shootingDay;

  PreviewRow withDecision(RowDecision decision) => PreviewRow(
    draftRef: draftRef,
    label: label,
    decision: decision,
    outfits: outfits,
    episode: episode,
    shootingDay: shootingDay,
  );

  /// Replaces one outfit row's decision by [ordinal]; an unknown ordinal is
  /// ignored rather than fabricating a row the payload does not carry.
  PreviewRow withOutfitDecision(int ordinal, bool accepted) => PreviewRow(
    draftRef: draftRef,
    label: label,
    decision: decision,
    outfits: [
      for (final outfit in outfits)
        if (outfit.ordinal == ordinal)
          outfit.withAccepted(accepted)
        else
          outfit,
    ],
    episode: episode,
    shootingDay: shootingDay,
  );
}

/// Sentinel for [AiApplyState.copyWith]: distinguishes "keep the current
/// value" from an explicit `null` on the nullable fields.
const Object _unset = Object();

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
    this.dayDecisions = const <String, bool>{},
    this.blockingUncertainties = const <Uncertainty>[],
    this.acknowledgedKeys = const <String>{},
    this.continuityGaps = const <ContinuityGap>[],
    this.continuitySelections = const <String, OutfitContinuityCandidate>{},
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

  /// The reviewer's per-day-group decisions (issue #706), keyed by the
  /// backend-derived day group ref. ABSENT entries fall back to the seeded
  /// default (accepted — the extraction-as-extracted default; the reviewer
  /// unchecks a day to leave its scene rows unscheduled). Only explicit
  /// toggles land here, so the map stays small and the default lives in one
  /// place. The client always sends ONE decision per day group on the wire,
  /// so the backend's missing-decision gate never trips.
  final Map<String, bool> dayDecisions;

  /// The preview's blocking (`field_ambiguity`) uncertainties (issue #663).
  /// Advisory (`dropped_row`) entries are filtered out at seed time — they
  /// never gate. Apply stays disabled until every entry is acknowledged;
  /// the server's gate answers `ai-import.apply-blocked` otherwise.
  final List<Uncertainty> blockingUncertainties;

  /// The acknowledged blocking uncertainties, keyed by
  /// [uncertaintyAcknowledgementKey]. Acknowledge semantics: the reviewer
  /// confirms the ambiguous (or absent) value is acceptable and the row
  /// applies as extracted.
  final Set<String> acknowledgedKeys;

  /// The preview's reviewer-selectable wardrobe gaps (issue #745): Pass-2
  /// `dropped_row` uncertainties that carry script-derivable candidates, each
  /// paired with the scene figure it belongs to. Empty when the preview has no
  /// Pass-2 gaps — then nothing about gaps renders and the request stays
  /// byte-identical to the pre-#745 client.
  final List<ContinuityGap> continuityGaps;

  /// The reviewer's per-gap picks, keyed by [gapKey]. ABSENT means
  /// the gap stays WITHOUT a look (the script-grounded default: never an
  /// invented one) — only explicit picks land here, so the map stays small.
  final Map<String, OutfitContinuityCandidate> continuitySelections;

  /// The stable key one wardrobe gap is decided by: its scene index plus the
  /// figure's preview-wide identity, exactly the pair the wire selection
  /// carries.
  static String gapKey(int sceneIndex, String characterIdentity) =>
      '$sceneIndex\u0000$characterIdentity';

  /// The reviewer's pick for [gap], or `null` when the gap stays empty.
  OutfitContinuityCandidate? candidateFor(ContinuityGap gap) =>
      continuitySelections[gapKey(gap.sceneIndex, gap.characterIdentity)];

  /// Builds the request's `continuity_selections`: one entry per gap the
  /// reviewer resolved, in the state's gap order (stable, testable). An empty
  /// list keeps the field absent on the wire.
  BuiltList<OutfitContinuitySelection> buildContinuitySelections() =>
      BuiltList<OutfitContinuitySelection>([
        for (final gap in continuityGaps)
          if (candidateFor(gap) case final candidate?)
            OutfitContinuitySelection(
              (b) => b
                ..sceneIndex = gap.sceneIndex
                ..characterIdentity = gap.characterIdentity
                ..candidate = candidate,
            ),
      ]);

  /// [AiApplyState] with the given fields replaced; every other field keeps its
  /// current value.
  ///
  /// The nullable fields distinguish "keep" from "clear" through the [_unset]
  /// sentinel, so a site that must drop the outcome or the command error can
  /// still say so explicitly. Every reviewer decision travels through here: a
  /// re-construction that forgets one field silently discards a decision the
  /// reviewer made (and the previous hand-written re-constructions did exactly
  /// that for `dayDecisions`).
  AiApplyState copyWith({
    List<PreviewRow>? rows,
    Object? context = _unset,
    Object? outcome = _unset,
    Object? commandError = _unset,
    Map<String, EpisodeGroupTarget>? groupTargets,
    Map<String, bool>? dayDecisions,
    List<Uncertainty>? blockingUncertainties,
    Set<String>? acknowledgedKeys,
    List<ContinuityGap>? continuityGaps,
    Map<String, OutfitContinuityCandidate>? continuitySelections,
  }) => AiApplyState(
    rows: rows ?? this.rows,
    context: identical(context, _unset)
        ? this.context
        : context as AiJobContext?,
    outcome: identical(outcome, _unset)
        ? this.outcome
        : outcome as ApplyAiImportResponse?,
    commandError: identical(commandError, _unset)
        ? this.commandError
        : commandError as ProblemError?,
    groupTargets: groupTargets ?? this.groupTargets,
    dayDecisions: dayDecisions ?? this.dayDecisions,
    blockingUncertainties: blockingUncertainties ?? this.blockingUncertainties,
    acknowledgedKeys: acknowledgedKeys ?? this.acknowledgedKeys,
    continuityGaps: continuityGaps ?? this.continuityGaps,
    continuitySelections: continuitySelections ?? this.continuitySelections,
  );

  /// True while at least one blocking uncertainty is unacknowledged — the
  /// client-side mirror of the backend apply gate, so the button explains
  /// itself instead of producing a guaranteed 409.
  bool get hasUnacknowledgedBlockers => blockingUncertainties.any(
    (uncertainty) => !acknowledgedKeys.contains(
      AiApplyController.acknowledgementKey(
        uncertainty.sceneIndex,
        uncertainty.field,
      ),
    ),
  );

  /// Every group target RESOLVES to an existing episode (found via the
  /// project's live list, created in-preview, or picked by the reviewer).
  /// UX rule (user report 2026-10-19): the apply button activates only when
  /// the episode side is settled — an unresolved create target keeps it
  /// disabled, so a half-created import can never be dispatched by accident.
  bool get hasResolvedGroupTargets =>
      groupRefs.every((ref) => targetFor(ref) is ExistingEpisodeGroupTarget);

  /// The wire acknowledgements: one entry per acknowledged key, in the
  /// preview's own order (stable, testable).
  BuiltList<UncertaintyAcknowledgement> buildAcknowledgements() =>
      BuiltList<UncertaintyAcknowledgement>([
        for (final uncertainty in blockingUncertainties)
          if (acknowledgedKeys.contains(
            AiApplyController.acknowledgementKey(
              uncertainty.sceneIndex,
              uncertainty.field,
            ),
          ))
            UncertaintyAcknowledgement(
              (b) => b
                ..sceneIndex = uncertainty.sceneIndex
                ..field = uncertainty.field,
            ),
      ]);

  /// True when the user made zero decision edits.
  bool get acceptAsIs => editDistance == 0;

  /// The real selection-state edit distance: the number of rows whose
  /// decision the user changed away from the default (Create), PLUS the number
  /// of piece rows rejected away from their default (accepted). A toggled
  /// piece is an edit: reporting `accept_as_is` over one would be a false
  /// statement about the review, and the backend rejects the combination.
  int get editDistance =>
      rows.where((r) => r.decision is! CreateDecision).length +
      rows.fold<int>(
        0,
        (sum, row) =>
            sum + row.outfits.where((outfit) => !outfit.accepted).length,
      ) +
      _groupEdits +
      _dayEdits +
      // A resolved wardrobe gap changes what the apply creates (a look for a
      // figure the script left undressed), so it is a review edit like any
      // other: reporting `accept_as_is` over picks would be a false statement
      // about what was reviewed.
      continuitySelections.length;

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
      // server-side, so an untouched row sends no wardrobe payload at all.
      final rejected = row.outfits
          .where((outfit) => !outfit.accepted)
          .map(
            (outfit) => OutfitDecision(
              (b) => b
                ..ordinal = outfit.ordinal
                ..accepted = false,
            ),
          )
          .toList();
      // `rebuild` RETURNS the replaced value — a built_value is immutable, so
      // calling it for its side effect would silently drop every rejection.
      mappings.add(
        rejected.isEmpty
            ? mapping
            : mapping.rebuild((m) => m.outfitDecisions.replace(rejected)),
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

  /// The preview's day-group refs in first-appearance order (verbatim
  /// backend `group_key` derivations — the apply request carries exactly
  /// these). Empty for a preview without day metadata: the request then
  /// carries no `shooting_days` and stays byte-identical to the pre-#706
  /// client.
  List<String> get dayRefs {
    final refs = <String>[];
    for (final row in rows) {
      final day = row.shootingDay;
      if (day == null) continue;
      final ref = draftShootingDayGroupRef(day);
      if (ref != null && !refs.contains(ref)) refs.add(ref);
    }
    return refs;
  }

  /// The day metadata of [ref]'s first row (the marker the group was
  /// extracted from); `null` for an unknown ref (never dispatched).
  DraftShootingDay? shootingDayOfGroup(String ref) {
    for (final row in rows) {
      final day = row.shootingDay;
      if (day != null && draftShootingDayGroupRef(day) == ref) return day;
    }
    return null;
  }

  /// The effective decision for [ref]: the reviewer's toggle, else the
  /// seeded default (accepted — extraction-as-extracted).
  bool dayAccepted(String ref) => dayDecisions[ref] ?? true;

  /// Day-decision edits: a group whose effective decision deviates from the
  /// accepted default (an explicit REJECTION) is an edit — `accept_as_is`
  /// must stay a truthful statement about the review. An explicit accept
  /// equals the seeded default, so it is not an edit.
  int get _dayEdits =>
      dayRefs.where((ref) => dayDecisions[ref] == false).length;

  /// Builds the request's per-day-group decisions (issue #706): one entry
  /// per preview day ref, accepted from the reviewer's toggle (default
  /// accepted). The backend refuses a referenced group without a decision
  /// (`409 ai-import.apply-missing-shooting-day-group`), so EVERY group is
  /// decided here — an uncheck travels as `accepted: false`, never as an
  /// absent entry. Empty when no row carries day metadata.
  BuiltList<ApplyShootingDayRequest> buildShootingDays() =>
      BuiltList<ApplyShootingDayRequest>([
        for (final ref in dayRefs)
          ApplyShootingDayRequest(
            (b) => b
              ..dayRef = ref
              ..accepted = dayAccepted(ref),
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
  /// The payload's blocking uncertainties seed the acknowledgement panel
  /// (issue #663); advisory `dropped_row` entries are filtered out — they
  /// never gate the apply. The reviewer-selectable wardrobe gaps (issue
  /// #745) seed [AiApplyState.continuityGaps]; their picks are fresh too,
  /// because a new payload is a new review.
  void seedRows(
    List<PreviewRow> rows,
    AiJobContext? context, {
    List<Uncertainty> uncertainties = const <Uncertainty>[],
    List<ContinuityGap> continuityGaps = const <ContinuityGap>[],
  }) {
    state = AiApplyState(
      rows: rows,
      context: context,
      blockingUncertainties: uncertainties
          .where(
            (uncertainty) => uncertainty.kind == UncertaintyKind.fieldAmbiguity,
          )
          .toList(),
      // Issue #745: the preview's reviewer-selectable wardrobe gaps. A fresh
      // payload is a fresh review — no pick survives it.
      continuityGaps: continuityGaps,
    );
  }

  /// The stable key one blocking uncertainty is acknowledged by: the
  /// `(scene_index, field)` pair the extraction reports it with.
  static String acknowledgementKey(int sceneIndex, String field) =>
      '$sceneIndex\u0000$field';

  /// Acknowledge (or revoke) ONE blocking uncertainty (issue #663).
  void acknowledgeUncertainty(int sceneIndex, String field, bool acknowledged) {
    final key = AiApplyController.acknowledgementKey(sceneIndex, field);
    final next = {...state.acknowledgedKeys};
    if (acknowledged) {
      next.add(key);
    } else {
      next.remove(key);
    }
    state = state.copyWith(acknowledgedKeys: next);
  }

  /// Auto-assigns each episode group against the project's live episode
  /// list (user report 2026-10-19): a group whose `Ep.:` number already
  /// EXISTS as an episode defaults to assign-EXISTING — the reviewer no
  /// longer hits the 409 `number-already-exists` recovery dance for an
  /// episode they (or a previous import) created. Groups whose number does
  /// not exist keep the create-new default: the backend creates that
  /// episode during apply, BEFORE the scenes (issue #581 apply order), and
  /// — since the title-page heading extraction — carries the document's
  /// episode title into the created episode's name.
  ///
  /// Explicit reviewer picks (`setGroupTarget`) always win; a fetch failure
  /// is silently ignored by the caller (resolve is an optimization, never
  /// a gate — the backend 409 recovery remains the backstop).
  void resolveGroupDefaults(
    List<EpisodeView> episodes, {
    String jobBlockId = '',
  }) {
    if (episodes.isEmpty || state.rows.isEmpty) return;
    final byNumber = {
      for (final episode in episodes)
        // BLOCK-AWARE (user report, the 403 apply loop): the apply's
        // cross-block IDOR guard requires the context episode to live in the
        // JOB'S block — an episode with the same NUMBER in a different block
        // must NOT be adopted (it made every apply answer 403 forever).
        if (jobBlockId.isEmpty || episode.blockId == jobBlockId)
          episode.number: episode,
    };
    final next = <String, EpisodeGroupTarget>{...state.groupTargets};
    var changed = false;
    EpisodeView? firstAdopted;
    for (final ref in state.groupRefs) {
      if (next.containsKey(ref)) continue; // reviewer pick wins
      final number = state.episodeOfGroup(ref)?.number;
      if (number == null) continue;
      final existing = byNumber[number];
      if (existing == null) continue;
      next[ref] = ExistingEpisodeGroupTarget(
        episodeId: existing.id,
        label: existing.name ?? '${existing.number}',
      );
      firstAdopted ??= existing;
      changed = true;
    }
    if (!changed) return;
    // CodeRabbit review: groups can resolve entirely via defaults while the
    // remembered context episode stays in ANOTHER block — apply() sends
    // context.episodeId, and the backend cross-block guard would 403 every
    // apply. For imports WITHOUT ungrouped rows the context moves to the
    // first matched job-block episode; mixed imports keep the remembered
    // context (ungrouped rows apply to it) — adoptCreatedEpisode's rule.
    final hasUngroupedRows = state.rows.any(
      (row) =>
          row.episode == null || draftEpisodeGroupRef(row.episode!) == null,
    );
    final adopted = firstAdopted;
    state = state.copyWith(
      context: hasUngroupedRows || adopted == null || jobBlockId.isEmpty
          ? state.context
          : AiJobContext(
              episodeId: adopted.id,
              projectId: adopted.projectId,
              blockId: jobBlockId,
            ),
      groupTargets: next,
    );
  }

  /// Adopts a just-created episode for [groupRef] — the in-preview episode
  /// creation (user request, found via the 294.pdf empty-picker flow): the
  /// group target flips to assign-EXISTING and the apply context moves to
  /// the created episode. The created episode lives in the JOB'S block, so
  /// the apply's cross-block IDOR guard passes even when the remembered
  /// context episode belonged to another block (or was missing entirely —
  /// the job's block had zero episodes, making apply unreachable before).
  void adoptCreatedEpisode(
    String groupRef, {
    required String episodeId,
    required int number,
    required String projectId,
    String? label,
  }) {
    final nextTargets = {
      ...state.groupTargets,
      groupRef: ExistingEpisodeGroupTarget(
        episodeId: episodeId,
        label: label ?? '$number',
      ),
    };
    // Rows WITHOUT episode metadata apply to the TOP-LEVEL context episode —
    // replacing it would silently retarget ungrouped rows to the adopted
    // group's episode (CodeRabbit review, mixed-import data integrity). The
    // remembered context stays authoritative for ungrouped rows; the apply
    // path validates it against the job's block.
    final hasUngroupedRows = state.rows.any(
      (row) =>
          row.episode == null || draftEpisodeGroupRef(row.episode!) == null,
    );
    // CodeRabbit review: a stale RESOLUTION error must not outlive the fix
    // it describes — the reviewer just resolved a group through "Ziel
    // ändern", yet the card would keep saying the creation failed next to an
    // enabled apply button. The transient `episode_create_failed` copy is
    // disproven by ANY successful adoption (a retry re-sets it on the next
    // failure). The cross-block refusal carries no per-group attribution, so
    // it is cleared only when this adoption resolves the LAST unresolved
    // group — every resolved group's episode lives in the job's block, so no
    // group can still carry that conflict. Every other error stays.
    final error = state.commandError;
    final allGroupsResolved = state.groupRefs.isNotEmpty
        ? state.groupRefs.every(
            (ref) => nextTargets[ref] is ExistingEpisodeGroupTarget,
          )
        : false;
    final keepError =
        error == null ||
        (error.code != 'ai_import.episode_create_failed' &&
            (error.code != 'ai_import.episode_number_other_block' ||
                !allGroupsResolved));
    state = state.copyWith(
      context: hasUngroupedRows
          ? state.context
          : AiJobContext(
              episodeId: episodeId,
              projectId: projectId,
              blockId: state.context?.blockId ?? '',
            ),
      commandError: keepError ? error : null,
      groupTargets: nextTargets,
    );
  }

  /// Records the reviewer's target for one episode group (existing episode
  /// id or create number/name). Absent keys keep the seeded create-default.
  void setGroupTarget(String groupRef, EpisodeGroupTarget target) {
    state = state.copyWith(
      groupTargets: {...state.groupTargets, groupRef: target},
    );
  }

  /// Records the reviewer's decision for one shooting-day group (issue
  /// #706): `accepted` creates the day and schedules the group's scene rows;
  /// a rejection leaves them unscheduled (reported in the response's
  /// `skipped_day_groups`). Absent keys keep the seeded accepted-default.
  void decideDay(String dayRef, bool accepted) {
    state = state.copyWith(
      dayDecisions: {...state.dayDecisions, dayRef: accepted},
    );
  }

  /// Overrides the persisted context with the user's explicit episode
  /// pick (the missing-context → picker-required path; apply is never
  /// dispatched with a guessed episode_id).
  void setContext(AiJobContext context) {
    state = state.copyWith(context: context);
  }

  void decide(String draftRef, RowDecision decision) {
    state = state.copyWith(
      rows: [
        for (final row in state.rows)
          if (row.draftRef == draftRef) row.withDecision(decision) else row,
      ],
    );
  }

  /// Accept or reject ONE piece row of a draft row, leaving the scene row's
  /// own decision untouched (spec `ai-import`: piece rows are decided
  /// independently).
  void decideOutfit(String draftRef, int ordinal, bool accepted) {
    state = state.copyWith(
      rows: [
        for (final row in state.rows)
          if (row.draftRef == draftRef)
            row.withOutfitDecision(ordinal, accepted)
          else
            row,
      ],
    );
  }

  /// Records the reviewer's resolution of ONE wardrobe gap (issue #745): the
  /// picked candidate, or `null` to leave the scene WITHOUT a look.
  ///
  /// A pick can only ever be dispatched for a gap the preview offers:
  /// [AiApplyState.buildContinuitySelections] iterates the state's own gap list,
  /// so a key no gap matches never reaches the wire (the server would refuse it
  /// with `409 ai-import.apply-unknown-continuity-candidate`).
  void decideContinuityGap(ContinuityGap gap, OutfitContinuityCandidate? pick) {
    final key = AiApplyState.gapKey(gap.sceneIndex, gap.characterIdentity);
    final next = {...state.continuitySelections};
    if (pick == null) {
      next.remove(key);
    } else {
      next[key] = pick;
    }
    state = state.copyWith(continuitySelections: next);
  }

  /// Surfaces a review-level refusal without a dispatch (the in-preview
  /// resolution found a state apply cannot proceed in — e.g. the group's
  /// number is taken by an episode in a DIFFERENT block).
  void setCommandError(ProblemError error) {
    state = state.copyWith(commandError: error);
  }

  void dismissCommandError() {
    state = state.copyWith(commandError: null);
  }

  bool get canApply =>
      state.context != null &&
      state.rows.isNotEmpty &&
      state.outcome == null &&
      // A group create target without its wire-required number (a marker
      // without `Ep.: <n>`) or two groups on one number keep apply disabled.
      state.hasCompleteGroupTargets &&
      !state.hasDuplicateCreateNumbers &&
      // UX rule (user report 2026-10-19): every group's episode must be
      // RESOLVED — found in the project, created in-preview, or picked via
      // "Ziel ändern". An unresolved create target keeps apply disabled (the
      // in-preview creation is expected to have settled it before review).
      (state.groupRefs.isEmpty || state.hasResolvedGroupTargets) &&
      // Issue #663: apply stays disabled while a blocking uncertainty is
      // unacknowledged — the client-side mirror of the backend gate, so the
      // button explains itself instead of producing a guaranteed 409.
      !state.hasUnacknowledgedBlockers;

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
      state = state.copyWith(context: null, outcome: null, commandError: error);
      return const Left(error);
    }
    final repo = ref.read(aiImportRepositoryProvider);
    final episodeGroups = state.buildEpisodeGroups();
    final shootingDays = state.buildShootingDays();
    final continuitySelections = state.buildContinuitySelections();
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
            : episodeGroups.toBuilder()
        // Issue #706: one decision per extracted day group (default
        // accepted); absent when the preview carries no day metadata — the
        // request then stays byte-identical to the pre-#706 client.
        ..shootingDays = shootingDays.isEmpty ? null : shootingDays.toBuilder()
        // Issue #663: the reviewer's acknowledgements travel with the other
        // reviewer decisions; empty stays absent on the wire.
        ..uncertaintyAcknowledgements = state.buildAcknowledgements().isEmpty
            ? null
            : state.buildAcknowledgements().toBuilder()
        // Issue #745: the reviewer's wardrobe-gap picks travel with the other
        // review decisions; a preview without resolved gaps stays byte-identical
        // to the pre-#745 client (the backend treats empty as absent).
        ..continuitySelections = continuitySelections.isEmpty
            ? null
            : continuitySelections.toBuilder(),
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
        // Issue #666: the apply created episodes server-side without any
        // client-side cache invalidation — the scope pickers served a stale
        // list until the TTL expired. Invalidate the whole episode/block
        // fetch families (the affected block's instances included) so the
        // new episode is visible in the pill navigation without leaving the
        // flow; the refetch rewrites the Drift cache rows for the block.
        ref
          ..invalidate(episodesListFetchProvider)
          ..invalidate(blocksListFetchProvider);
        state = state.copyWith(
          context: context,
          outcome: response,
          // A successful (re-)apply disproves every earlier command failure:
          // keeping it would render the old error next to the outcome card.
          commandError: null,
        );
        return Right(response);
      case ApplyBlocked(:final error):
        if (!ref.mounted) return Left(error);
        state = state.copyWith(
          context: context,
          outcome: null,
          commandError: error,
        );
        return Left(error);
      case ApplyUnresolved(:final error):
        if (!ref.mounted) return Left(error);
        state = state.copyWith(
          context: context,
          outcome: null,
          commandError: error,
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
      // The group's number is taken by an episode in a DIFFERENT block: the
      // import cannot apply in this block scope (cross-block IDOR guard +
      // project-unique numbers). Issue #705: the client-resolved home
      // location names season and block — and the recovery button under the
      // card offers the one-tap scope switch + re-upload. The extension-less
      // degradation keeps the honest bare narrative.
      'ai_import.episode_number_other_block' => otherBlockCopy(l10n, error),
      // The in-preview episode creation failed (offline / transport): the
      // reviewer retries via "Ziel ändern" — apply stays disabled.
      'ai_import.episode_create_failed' => l10n.aiApplyErrorEpisodeCreateFailed,
      // Issue #663: dedicated apply-gate codes. `apply-blocked` surfaces the
      // blocking items from its extensions inline (the widget appends them);
      // the copy here is the narrative header.
      'ai-import.apply-blocked' => l10n.aiApplyErrorApplyBlocked,
      'ai-import.apply-missing-mapping' => l10n.aiApplyErrorMissingMapping,
      'ai-import.apply-missing-episode-group' =>
        l10n.aiApplyErrorMissingEpisodeGroup,
      // Issue #706: a day group the preview references without a decision —
      // the client always sends one per group, so this is a stale-review
      // signal; the S1 `day_ref` extension names the group.
      'ai-import.apply-missing-shooting-day-group' =>
        l10n.aiApplyErrorMissingShootingDayGroup,
      // Issue #745: a wardrobe-gap pick the preview no longer offers (the
      // preview was regenerated, or a stale screen kept a pick) — refreshing
      // is the only honest resolution, the pick cannot be re-derived here.
      'ai-import.apply-unknown-continuity-candidate' =>
        l10n.aiApplyErrorUnknownContinuityCandidate,
      _ when error.code.startsWith('transport.') => l10n.aiApplyErrorNetwork,
      _ => l10n.aiApplyErrorGeneric(error.code),
    };

/// Parses the S1 `blocking_uncertainties` extension of an
/// `ai-import.apply-blocked` problem (issue #663) into renderable
/// `(scene_index, field, note)` triples. Defensive by design: the extension
/// is optional wire metadata; a shape the client does not understand
/// degrades to an empty list — the narrative copy still explains the
/// refusal, and the apply card's acknowledge panel carries the actions.
List<(int, String, String)> blockingUncertaintyItems(ProblemError error) {
  final items = error.extensions?['blocking_uncertainties'];
  if (items is! List) return const [];
  return [
    for (final item in items)
      if (item is Map &&
          item['scene_index'] is int &&
          item['field'] is String &&
          item['note'] is String)
        (
          item['scene_index'] as int,
          item['field'] as String,
          item['note'] as String,
        ),
  ];
}

/// Parses the S1 extensions of `409 episode.number-already-exists` (issue
/// #665): the existing episode's id and the requested create number.
/// `null` when the problem is not that code or the extensions are absent
/// (an older backend — the client then falls back to the manual re-pick).
(String episodeId, int number)? episodeNumberConflict(ProblemError error) {
  if (error.code != 'episode.number-already-exists') return null;
  final ext = error.extensions;
  final id = ext?['existing_episode_id'];
  final number = ext?['number'];
  if (id is! String || id.isEmpty || number is! int) return null;
  return (id, number);
}

/// The cross-block refusal copy (issue #705): with the client-resolved home
/// location it names the season and block that hold the conflicting
/// episode; without (resolution failure) it degrades to the extension-less
/// narrative — never a code the reviewer cannot act on.
String otherBlockCopy(AppLocalizations l10n, ProblemError error) {
  final ext = error.extensions;
  final seasonNumber = ext?['existing_season_number'];
  final seasonTitle = ext?['existing_season_title'];
  final blockNumber = ext?['existing_block_number'];
  if (seasonNumber is! int || blockNumber is! int) {
    return l10n.aiApplyErrorEpisodeNumberOtherBlock;
  }
  final seasonLabel = seasonTitle is String && seasonTitle.isNotEmpty
      ? seasonTitle
      : l10n.blockSeasonNumber('$seasonNumber');
  return l10n.aiApplyErrorEpisodeNumberOtherBlockIn(
    seasonLabel,
    l10n.blockTileLabel('$blockNumber'),
  );
}

/// The issue #705 scope-switch recovery target carried by an apply refusal
/// — `null` when the error offers none:
///
/// - `ai_import.episode_number_other_block` with the client-resolved
///   `existing_block_id` (cross-block by construction — the same-block
///   case was adopted, never refused);
/// - `episode.number-already-exists` (the #665 409) whose
///   `existing_block_id` DIFFERS from [jobBlockId] — assign-existing would
///   403 at the apply's cross-block IDOR gate, so only the scope switch
///   helps. Same-block conflicts return `null` (the #665 assign-existing
///   button owns that path), and an extension-less older backend degrades
///   to the bare narrative.
({String blockId})? crossBlockScopeRecovery(
  ProblemError error, {
  required String? jobBlockId,
}) {
  final blockId = error.extensions?['existing_block_id'];
  if (blockId is! String || blockId.isEmpty) return null;
  switch (error.code) {
    case 'ai_import.episode_number_other_block':
      return (blockId: blockId);
    case 'episode.number-already-exists':
      if (jobBlockId == null || jobBlockId.isEmpty) return null;
      return blockId != jobBlockId ? (blockId: blockId) : null;
    default:
      return null;
  }
}

/// The group refs whose effective target CREATES [number] — the group(s) a
/// `episode.number-already-exists` 409 is about (issue #665).
List<String> groupRefsForCreateNumber(AiApplyState state, int number) => [
  for (final ref in state.groupRefs)
    if (state.targetFor(ref) case CreateEpisodeGroupTarget(number: final n)
        when n == number)
      ref,
];

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

/// Ensures the episode behind [target] EXISTS and the group adopts it — the
/// in-preview creation (user report 2026-10-19, the 294.pdf empty-picker
/// flow): an existing project episode with the target's number is adopted,
/// a missing one is CREATED in the job's block right here. Either way the
/// group target flips to assign-EXISTING and the apply context moves into
/// the job's block, so the apply's cross-block IDOR guard always has a valid
/// `episode_id` — before this, a block with zero episodes made apply
/// unreachable (empty picker + create-at-apply requiring a context episode).
///
/// Returns `true` when the group now resolves. Any failure (offline, 409
/// the recovery can settle, missing block info) returns `false` and leaves
/// the reviewer's state untouched — the backend 409 recovery stays the
/// backstop. Called from the preview seeding AND from the "Ziel ändern"
/// sheet's create branch.
Future<bool> ensureGroupEpisodeResolved(
  WidgetRef ref,
  String jobId,
  String groupRef,
  CreateEpisodeGroupTarget target,
) async {
  final number = target.number;
  if (number == null) return false;
  final blockInfo = await ref.read(aiJobBlockInfoProvider(jobId).future);
  if (blockInfo == null) return false;
  var projectId = blockInfo.projectId;
  if (projectId.isEmpty) {
    // No remembered project: the block carries it. Repository seam (Result —
    // a transport failure is a failed resolution, never a thrown
    // DioException through the sheet, CodeRabbit review).
    final block = await ref
        .read(episodeRepositoryProvider)
        .blockById(blockInfo.blockId);
    projectId = block.fold((_) => '', (b) => b.projectId);
  }
  if (projectId.isEmpty) return false;
  final controller = ref.read(aiApplyControllerProvider(jobId).notifier);

  // An episode with the number may already exist (created by an earlier
  // review/import, or the reviewer created it by hand): adopt it instead of
  // racing the numbering reservation into a 409 — but ONLY when it lives in
  // the job's block. An episode with the same number in a DIFFERENT block
  // cannot be adopted (the apply's cross-block IDOR guard would 403) and
  // cannot be created again (the number is project-unique): the import in
  // THIS block scope is genuinely blocked, surfaced honestly.
  final episodes = await ref
      .read(episodeRepositoryProvider)
      .listBySeries(projectId);
  final rows = episodes.fold((_) => const <EpisodeView>[], (rows) => rows);
  final inJobBlock = rows
      .where(
        (episode) =>
            episode.number == number && episode.blockId == blockInfo.blockId,
      )
      .toList();
  if (inJobBlock.isNotEmpty) {
    final episode = inJobBlock.first;
    controller.adoptCreatedEpisode(
      groupRef,
      episodeId: episode.id,
      number: number,
      projectId: projectId,
      label: target.name == null ? '$number' : '$number \u00b7 ${target.name}',
    );
    return true;
  }
  final elsewhere = rows.where((episode) => episode.number == number).toList();
  if (elsewhere.isNotEmpty) {
    // Issue #705: the refusal NAMes the conflict's home — a reviewer in a
    // one-block season otherwise gets an unactionable "switch the block".
    // The location resolves best-effort; on any failure the error carries
    // only the ids (the copy degrades to the extension-less narrative and
    // the recovery button stays hidden).
    final conflicting = elsewhere.first;
    final home = await _episodeHomeLocation(ref, conflicting);
    controller.setCommandError(
      ProblemError(
        code: 'ai_import.episode_number_other_block',
        extensions: {
          'existing_episode_id': conflicting.id,
          'existing_block_id': conflicting.blockId,
          ...?home,
        },
      ),
    );
    return false;
  }

  final created = await ref
      .read(episodeRepositoryProvider)
      .create(
        CreateEpisodeRequest(
          (b) => b
            ..projectId = projectId
            ..blockId = blockInfo.blockId
            ..number = number
            ..name = target.name,
        ),
      );
  return created.match((_) => false, (idVersion) {
    controller.adoptCreatedEpisode(
      groupRef,
      episodeId: idVersion.id,
      number: number,
      projectId: projectId,
      label: target.name == null ? '$number' : '$number \u00b7 ${target.name}',
    );
    return true;
  });
}

/// Resolves the display location of a conflicting episode's home (issue
/// #705) — its block number plus the owning season's id/number/title —
/// best-effort. Any read failure degrades to `null`: the refusal then
/// carries only the ids, the copy falls back, and the recovery button's tap
/// re-resolves on demand.
Future<Map<String, dynamic>?> _episodeHomeLocation(
  WidgetRef ref,
  EpisodeView episode,
) async {
  final block = await ref
      .read(episodeRepositoryProvider)
      .blockById(episode.blockId);
  final blockView = block.fold((_) => null, (b) => b);
  if (blockView == null) return null;
  final season = await ref
      .read(seasonRepositoryProvider)
      .get(blockView.seasonId);
  final seasonView = season.fold((_) => null, (s) => s);
  return {
    'existing_block_number': blockView.number,
    if (seasonView != null) ...{
      'existing_season_id': seasonView.id,
      'existing_season_number': seasonView.number,
      if (seasonView.title != null) 'existing_season_title': seasonView.title!,
    },
  };
}
