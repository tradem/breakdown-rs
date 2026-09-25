// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/problem_error.dart';
import '../../../l10n/generated/app_localizations.dart';

part 'setup_wizard_state.freezed.dart';

/// The wizard's linear steps (design D1). The completion step is not a
/// navigation step — it is the [SetupWizardPhase.completed] /
/// [SetupWizardPhase.partialFailure] terminal phase rendered in place of
/// the review content.
enum SetupWizardStep { season, blocks, review }

/// The wizard's lifecycle phase (design D1: `editing | dispatching |
/// completed | partial-failure`; the design's `review` phase is the
/// [SetupWizardStep.review] step while [SetupWizardPhase.editing]).
enum SetupWizardPhase { editing, dispatching, completed, partialFailure }

/// One repeatable block draft of the Blocks step (spec `Block Draft With
/// Templates`): episode count with a default, optional title.
@freezed
abstract class BlockDraft with _$BlockDraft {
  const BlockDraft._();

  const factory BlockDraft({
    /// Episodes per block; the smart default (team decision: default small
    /// — the reference templates use 6/8).
    @Default(8) int episodeCount,

    /// Optional block title; empty means "no title" (the backend titles
    /// blocks by number).
    @Default('') String title,
  }) = _BlockDraft;
}

/// A season that was created during dispatch (created-so-far bookkeeping
/// for the completion / partial-failure summary).
@freezed
abstract class WizardCreatedSeason with _$WizardCreatedSeason {
  const factory WizardCreatedSeason({
    required String id,
    required int number,
    @Default('') String title,
  }) = _WizardCreatedSeason;
}

/// A block (and how many of its episodes) that was created during
/// dispatch. [episodesCreated] counts the acked episode commands for the
/// partial-failure summary ("Block 1 — 3 von 4 Episoden").
@freezed
abstract class WizardCreatedBlock with _$WizardCreatedBlock {
  const factory WizardCreatedBlock({
    required String id,
    required int number,
    @Default('') String title,
    required int episodeCount,
    @Default(0) int episodesCreated,
  }) = _WizardCreatedBlock;
}

/// The single wizard state (design D1): steps + drafts + phase + dispatch
/// progress + created-so-far refs. Owned by `SetupWizardController`;
/// widgets render it, they never branch on domain semantics themselves.
///
/// Nothing in here is ever persisted (decision 3: destructive abort — no
/// draft is written to Drift or any other store pre-submit).
@freezed
abstract class SetupWizardState with _$SetupWizardState {
  const SetupWizardState._();

  const factory SetupWizardState({
    /// Current navigation step (Season → Blocks → Review).
    @Default(SetupWizardStep.season) SetupWizardStep step,

    /// Lifecycle phase.
    @Default(SetupWizardPhase.editing) SetupWizardPhase phase,

    /// Season number (smart default = highest existing + 1).
    @Default(1) int seasonNumber,

    /// The first FREE series-scoped block number for this dispatch (derived
    /// from the series' existing blocks at wizard open — the backend
    /// enforces block-number uniqueness per SERIES,
    /// `idx_projection_block_series_number`, not per season). Draft `i`
    /// renders and dispatches as block `nextBlockNumber + i`; the number
    /// is read-only information, never a field.
    @Default(1) int nextBlockNumber,

    /// The first FREE series-scoped EPISODE number (`same backend pattern:
    /// `idx_projection_episode_series_number`). The whole hierarchy is
    /// numbered per series — the wizard assigns the drafts' episodes
    /// sequentially across blocks starting here; read-only info.
    @Default(1) int nextEpisodeNumber,

    /// Optional season name.
    @Default('') String seasonName,

    /// Block drafts (always ≥ 1 by default; removable).
    @Default(<BlockDraft>[]) List<BlockDraft> blocks,

    /// Created season (set during dispatch, kept for the summary).
    WizardCreatedSeason? createdSeason,

    /// Created blocks with their episode progress (created-so-far).
    @Default(<WizardCreatedBlock>[]) List<WizardCreatedBlock> createdBlocks,

    /// Number of acknowledged commands in the current dispatch plan.
    @Default(0) int dispatchDone,

    /// Total commands of the current dispatch plan.
    @Default(0) int dispatchTotal,

    /// The in-flight sub-step label (e.g. the block/episode being created).
    @Default('') String dispatchLabel,

    /// Whether the series-scoped number derivation has SETTLED (the async
    /// projection reads of `seedDerivedNumbers` completed — success OR the
    /// honest fallback). The screen gates the blocks/review advance and
    /// the review confirm on it: dispatching with the fallback numbers
    /// while the derivation is still running could create a season before
    /// a conflict stops the sequence.
    @Default(false) bool numbersSeeded,

    /// Whether the current step's inputs validate (reported by the step
    /// widget from the PURE validation functions on every user edit —
    /// parse-invalid text never reaches the controller's fields, so this
    /// is the "Weiter" gate). Reset on step navigation.
    @Default(true) bool stepValid,

    /// The failed command's problem (partial-failure phase), keyed on the
    /// stable `code` — the screen never renders backend `detail` text.
    ProblemError? failure,
  }) = _SetupWizardState;

  /// True while the user can still edit drafts (editing on any step).
  bool get isEditing => phase == SetupWizardPhase.editing;

  /// True between the confirm tap and the sequence settling — the cancel
  /// affordance is disabled and PopScope blocks (spec `Abort during
  /// dispatch`).
  bool get isDispatching => phase == SetupWizardPhase.dispatching;

  /// True once the sequence has settled (completion OR partial failure).
  bool get isSettled =>
      phase == SetupWizardPhase.completed ||
      phase == SetupWizardPhase.partialFailure;

  /// The created-so-far rows for the summary screens.
  int get totalDraftEpisodes =>
      blocks.fold(0, (sum, b) => sum + b.episodeCount);
}

/// Validation error codes surfaced as inline copy (keyed per error code —
/// the screen maps them to glossary copy, never platform dialogs).
enum WizardFieldError {
  /// A whole number > 0 is required (season number / episode count).
  notPositiveNumber,

  /// At least one block draft is required at submit time.
  noBlocks,
}

/// Parses a positive whole number; `null` when valid (the Form validator
/// convention: null = valid), otherwise [WizardFieldError.notPositiveNumber].
WizardFieldError? validatePositiveCount(String raw) {
  final value = int.tryParse(raw.trim());
  if (value == null || value <= 0) {
    return WizardFieldError.notPositiveNumber;
  }
  return null;
}

/// Smart-default block number (backend invariant: block numbers are
/// unique per SERIES — `idx_projection_block_series_number` — so the
/// wizard derives the first free number from the series' EXISTING blocks
/// projection, the same client-side append-order derivation discipline as
/// `nextOrderKey` for costume categories; never from a second projection
/// lookup of audit context). Gaps are not filled: `max + 1`, empty → 1.
int smartDefaultBlockNumber(Iterable<int> existingNumbers) {
  var highest = 0;
  for (final number in existingNumbers) {
    if (number > highest) highest = number;
  }
  return highest + 1;
}

/// Smart-default episode number (same backend pattern as blocks: episode
/// numbers are unique per SERIES — `idx_projection_episode_series_number`).
int smartDefaultEpisodeNumber(Iterable<int> existingNumbers) {
  var highest = 0;
  for (final number in existingNumbers) {
    if (number > highest) highest = number;
  }
  return highest + 1;
}

/// The derived series-scoped episode number of draft [blockIndex]'s
/// [episodeIndex]-th episode: the drafts' episodes are numbered
/// sequentially across the whole plan (block 0 first, then block 1, …).
int derivedEpisodeNumber(
  List<BlockDraft> drafts, {
  required int firstEpisodeNumber,
  required int blockIndex,
  required int episodeIndex,
}) {
  var prior = 0;
  for (var i = 0; i < blockIndex; i++) {
    prior += drafts[i].episodeCount;
  }
  return firstEpisodeNumber + prior + episodeIndex;
}

/// The Blocks step's submit-time validation: at least one draft exists.
WizardFieldError? validateHasBlocks(List<BlockDraft> blocks) =>
    blocks.isEmpty ? WizardFieldError.noBlocks : null;

/// The pre-dispatch guard's failure (issue #467): this build shipped
/// without `--dart-define=DEFAULT_SERIES_ID`, so the env-sourced series id
/// is empty and NO season can be created meaningfully. The wizard fails
/// fast with this actionable error instead of dispatching a request the
/// backend can only answer with a blind 422 `domain.validation` — the
/// guard owns the message, no network round-trip.
const missingSeriesIdProblem = ProblemError(
  code: 'config.series-id-missing',
  title: 'Build missing DEFAULT_SERIES_ID',
  detail: 'DEFAULT_SERIES_ID is empty in this build.',
);

/// True when [failure] is the build-misconfiguration guard (issue #467):
/// the wizard rendered zero partial work, so the completion view hides the
/// created-so-far summary and the in-session retry affordance (retrying a
/// rebuild-required state is pointless — only a rebuilt app can proceed).
bool isMissingSeriesIdFailure(ProblemError? failure) =>
    failure?.code == missingSeriesIdProblem.code;

/// Client-side inline copy for a validation error code (glossary
/// `wizard.errors.*`) — never a platform dialog.
String wizardErrorCopyForField(AppLocalizations l10n, WizardFieldError error) =>
    switch (error) {
      WizardFieldError.notPositiveNumber => l10n.wizardFieldPositive,
      WizardFieldError.noBlocks => l10n.wizardFieldBlocks,
    };

/// Smart-default season number (task 2.3): highest existing number + 1 —
/// an empty list defaults to 1, gaps are NOT filled (numbers identify a
/// season, they do not have to be contiguous; `max + 1` is the honest
/// "next free number at the top" and avoids 409 conflicts with any
/// existing row).
int smartDefaultSeasonNumber(List<SeasonView> seasons) {
  var highest = 0;
  for (final season in seasons) {
    if (season.number > highest) highest = season.number;
  }
  return highest + 1;
}

/// Total commands of the dispatch plan: 1 season create + per block 1
/// block create + one create per episode. The progress indicator's `n`.
int wizardDispatchTotal(List<BlockDraft> blocks) =>
    1 + blocks.fold(0, (sum, b) => sum + 1 + b.episodeCount);

/// Client-side copy for a wizard command failure, keyed on the stable
/// problem `code` (AGENTS.md §5 — never the backend's localized `detail`).
String wizardErrorCopy(AppLocalizations l10n, ProblemError error) =>
    switch (error.code) {
      // Real backend codes first (issue #443): the registry emits
      // `{context}.number-already-exists`, never the old `*.conflict` aliases
      // (kept only until stale unit fixtures are updated).
      'season.number-already-exists' ||
      'seasons.conflict' ||
      'season.conflict' => l10n.wizardErrorSeasonExists,
      'block.number-already-exists' || 'blocks.conflict' || 'block.conflict' =>
        // Series-scoped wording (backend invariant: block numbers are unique
        // per SERIES — `idx_projection_block_series_number` — not per season;
        // the copy must point the user at the ACTUAL conflict scope).
        l10n.wizardErrorBlockExistsSeries,
      'episode.number-already-exists' ||
      'episodes.conflict' ||
      'episode.conflict' =>
        // Same series-scope: episode numbers are unique per series
        // (`idx_projection_episode_series_number`), not per block.
        l10n.wizardErrorEpisodeExistsSeries,
      'authz.denied' || 'auth.session_required' => l10n.blocksCreateErrorSignIn,
      'config.series-id-missing' => l10n.wizardErrorSeriesIdMissing,
      _ when error.code.startsWith('transport.') => l10n.wizardErrorNetwork,
      _ => l10n.wizardErrorGeneric(error.code),
    };
