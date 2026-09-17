// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/active_block.dart';
import '../../../auth/auth_providers.dart';
import '../../../core/problem_error.dart';
import '../../../data/block_repository.dart';
import '../../../data/cache/seasons_cache_providers.dart';
import '../../../data/episode_repository.dart';
import '../../../data/season_repository.dart';
import '../../blocks/blocks_controller.dart';
import '../../blocks/blocks_state.dart';
import '../../episodes/episodes_controller.dart';
import '../../episodes/episodes_state.dart';
import '../../seasons/seasons_controller.dart';
import '../../seasons/seasons_state.dart';
import 'setup_wizard_state.dart';

part 'setup_wizard_controller.g.dart';

/// The season setup wizard controller (design D1/D2).
///
/// A single `@riverpod` notifier owning the whole [SetupWizardState]:
/// step navigation, draft editing, template application, and the
/// sequential dispatch reduction over the **existing repositories** the
/// individual screens use ([SeasonRepository], [BlockRepository],
/// [EpisodeRepository]) — the wizard adds only sequencing and progress.
///
/// Auto-dispose: the state is ephemeral by design (decision 3 — no draft
/// persistence); leaving the wizard disposes it, reopening starts fresh.
@riverpod
class SetupWizardController extends _$SetupWizardController {
  @override
  SetupWizardState build() =>
      const SetupWizardState(blocks: <BlockDraft>[BlockDraft()]);

  // --- Draft editing (editing phase only; guards are total no-ops
  // otherwise so a late widget callback can never corrupt a dispatch) ---

  /// Seeds the smart-default season number (task 2.3) from the seasons
  /// projection the screen already loaded. A failed projection is the
  /// empty list (default 1) — the honest fallback, never a fabricated
  /// number that could conflict.
  void seedSeasonNumber(List<SeasonView> seasons) {
    if (!state.isEditing) return;
    state = state.copyWith(seasonNumber: smartDefaultSeasonNumber(seasons));
  }

  void setSeasonNumber(int number) {
    if (!state.isEditing) return;
    state = state.copyWith(seasonNumber: number);
  }

  /// Derives the first free SERIES-scoped block number (task: backend
  /// invariant `idx_projection_block_series_number` — block numbers are
  /// unique per series, not per season) from the series' existing blocks
  /// projection. Walks the series' seasons (the projection rows the screen
  /// opened on) and fetches each season's blocks — the same read-model
  /// data the blocks screens render; the DERIVED NUMBER is the only
  /// command payload this feeds (append-order derivation, `nextOrderKey`
  /// discipline), never audit context.
  ///
  /// A failed fetch degrades to base 1 (the honest fallback for an empty
  /// series); a mid-dispatch 409 then surfaces as partial failure with
  /// the in-session retry.
  Future<void> seedDerivedNumbers({required String seriesId}) async {
    if (!state.isEditing) return;
    final seasons = ref
        .read(seasonsView)
        .rows
        .where((s) => s.seriesId == seriesId)
        .toList();
    final blockNumbers = <int>[];
    final episodeNumbers = <int>[];
    final blockRepo = ref.read(blockRepositoryProvider);
    final episodeRepo = ref.read(episodeRepositoryProvider);
    for (final season in seasons) {
      final blocks = await blockRepo
          .listBySeason(season.id)
          .then((res) => res.match((_) => const <BlockView>[], (rows) => rows));
      blockNumbers.addAll(blocks.map((b) => b.number));
      for (final block in blocks) {
        final episodes = await episodeRepo
            .listByBlock(block.id)
            .then(
              (res) => res.match((_) => const <EpisodeView>[], (rows) => rows),
            );
        episodeNumbers.addAll(episodes.map((e) => e.number));
      }
    }
    if (!ref.mounted || !state.isEditing) return;
    state = state.copyWith(
      nextBlockNumber: smartDefaultBlockNumber(blockNumbers),
      nextEpisodeNumber: smartDefaultEpisodeNumber(episodeNumbers),
    );
  }

  void setSeasonName(String name) {
    if (!state.isEditing) return;
    state = state.copyWith(seasonName: name);
  }

  void addBlock() {
    if (!state.isEditing) return;
    state = state.copyWith(blocks: [...state.blocks, const BlockDraft()]);
  }

  /// Removes one draft (spec: no confirmation — removal never empties the
  /// list silently at submit time; the Next button re-validates).
  void removeBlockAt(int index) {
    if (!state.isEditing) return;
    if (index < 0 || index >= state.blocks.length) return;
    final next = [...state.blocks]..removeAt(index);
    state = state.copyWith(blocks: next);
  }

  void setBlockEpisodeCount(int index, int count) {
    if (!state.isEditing) return;
    if (index < 0 || index >= state.blocks.length) return;
    state = state.copyWith(
      blocks: [
        for (var i = 0; i < state.blocks.length; i++)
          if (i == index)
            state.blocks[i].copyWith(episodeCount: count)
          else
            state.blocks[i],
      ],
    );
  }

  void setBlockTitle(int index, String title) {
    if (!state.isEditing) return;
    if (index < 0 || index >= state.blocks.length) return;
    state = state.copyWith(
      blocks: [
        for (var i = 0; i < state.blocks.length; i++)
          if (i == index)
            state.blocks[i].copyWith(title: title)
          else
            state.blocks[i],
      ],
    );
  }

  /// Reports the current step's input validity (from the step widget's
  /// PURE validators on every user edit). Event-driven only — never
  /// called during a build phase.
  void setStepValid(bool valid) {
    if (!state.isEditing) return;
    state = state.copyWith(stepValid: valid);
  }

  /// Applies a template suggestion: expands [count] drafts of
  /// [episodesPerBlock] each, appended after the existing drafts
  /// (spec `Applying a template` — each draft stays editable).
  void applyTemplate({required int count, required int episodesPerBlock}) {
    if (!state.isEditing) return;
    state = state.copyWith(
      blocks: [
        ...state.blocks,
        for (var i = 0; i < count; i++)
          BlockDraft(episodeCount: episodesPerBlock),
      ],
    );
  }

  // --- Step navigation (editing phase only) ---

  /// Advances Season → Blocks → Review. Returns the validation error that
  /// blocked the move, or `null` on success (the widget renders the inline
  /// copy; no platform exception surfaces).
  WizardFieldError? next() {
    if (!state.isEditing) return null;
    switch (state.step) {
      case SetupWizardStep.season:
        state = state.copyWith(step: SetupWizardStep.blocks, stepValid: true);
        return null;
      case SetupWizardStep.blocks:
        final invalid = validateHasBlocks(state.blocks);
        if (invalid != null) return invalid;
        state = state.copyWith(step: SetupWizardStep.review, stepValid: true);
        return null;
      case SetupWizardStep.review:
        return null;
    }
  }

  /// Returns to the previous step (never discards anything itself — the
  /// abort dialog owns destruction).
  void back() {
    if (!state.isEditing) return;
    state = state.copyWith(
      step: switch (state.step) {
        SetupWizardStep.review => SetupWizardStep.blocks,
        _ => SetupWizardStep.season,
      },
      stepValid: true,
    );
  }

  /// Resets the wizard to its initial state (the reopen-fresh contract of
  /// a confirmed abort; also used by tests).
  void reset() =>
      state = const SetupWizardState(blocks: <BlockDraft>[BlockDraft()]);

  // --- Dispatch (design D2: sequential state machine over the existing
  // repositories) ---

  /// Submits the review step: dispatches season → blocks → episodes
  /// sequentially. Ids flow **exclusively** from command responses into
  /// the subsequent commands' payloads (CQRS boundary — the wizard never
  /// derives a `series_id`/`season_id`/`block_id` from a second
  /// projection lookup; the season id comes from the create ack, block
  /// ids from their acks, and the series id from the env-sourced config
  /// the caller passes in).
  ///
  /// Progress: [SetupWizardState.dispatchDone] / [dispatchTotal] plus the
  /// per-command [SetupWizardState.dispatchLabel] sub-step display.
  ///
  /// Partial failure stops the sequence: created-so-far refs are retained,
  /// the phase flips to [SetupWizardPhase.partialFailure], and
  /// [retryRemaining] re-runs exactly the un-acked commands in-session
  /// (no background queue, no offline persistence).
  ///
  /// AUTHZ-GATE: the underlying create commands (`POST /v1/seasons`,
  /// `POST /v1/blocks`, `POST /v1/episodes`) are `CurrentUser`-gated
  /// server-side (auth-only). The client mirrors that gate here — the
  /// session is resolved (awaited, never denial-by-absence) BEFORE the
  /// first network call and no command is dispatched without it.
  Future<void> submit({required String seriesId}) async {
    if (!state.isEditing) return;
    await _runDispatch(seriesId: seriesId);
  }

  /// Retries the remaining commands of a partially failed dispatch
  /// in-session (spec `Partial failure`): skips every command already
  /// acknowledged (the created refs are the resume cursor) and continues
  /// from the failed one.
  Future<void> retryRemaining({required String seriesId}) async {
    if (state.phase != SetupWizardPhase.partialFailure) return;
    await _runDispatch(seriesId: seriesId);
  }

  Future<void> _runDispatch({required String seriesId}) async {
    final drafts = state.blocks;
    final total = wizardDispatchTotal(drafts);
    state = state.copyWith(
      phase: SetupWizardPhase.dispatching,
      dispatchDone: _completedCommandsSoFar(),
      dispatchTotal: total,
      dispatchLabel: '',
      // A retried dispatch re-enters with a clean failure field; the
      // created-so-far refs are deliberately KEPT (resume cursor).
      failure: null,
    );

    // AUTHZ-GATE: resolve the authenticated session before ANY command.
    // Awaited (not read): a pending restore must resolve before the gate
    // decision, never be treated as denial-by-absence. A failed restore is
    // an error state → deny.
    AuthSession? session;
    try {
      session = await ref.read(authSessionControllerProvider.future);
    } on Object {
      session = null;
    }
    if (session == null) {
      _fail(
        const ProblemError(
          code: 'authz.denied',
          title: 'An authenticated session is required to create seasons',
          status: 403,
        ),
      );
      return;
    }

    final seasonRepo = ref.read(seasonRepositoryProvider);
    final blockRepo = ref.read(blockRepositoryProvider);
    // The episode repository is resolved PER BLOCK below — after the
    // active-block scope is set from the create-block ack (the Dio rebuilds
    // with the new `X-Active-Block` header; the episodes route is
    // BlockMember-scoped server-side).

    // 1. Season create — skipped on retry when already acked (its id is
    // the resume cursor for every subsequent command payload).
    if (state.createdSeason == null) {
      state = state.copyWith(dispatchLabel: _seasonLabel());
      // AUTHZ-GATE: authenticated session resolved above.
      final ack = await seasonRepo.create(
        CreateSeasonRequest(
          (b) => b
            ..seriesId = seriesId
            ..number = state.seasonNumber
            ..title = state.seasonName.isEmpty ? null : state.seasonName,
        ),
      );
      final season = ack.getRight().toNullable();
      if (season == null) {
        _fail(ack.getLeft().toNullable()!);
        return;
      }
      _ackSeason(season, state.seasonNumber);
    }
    final seasonId = state.createdSeason!.id;

    // 2. Per block: block create, then its episode creates.
    for (var i = 0; i < drafts.length; i++) {
      final draft = drafts[i];
      // The series-scoped number derived at wizard open (`nextBlockNumber`
      // + draft position) — read-only info shown on the Blocks step,
      // never a field.
      final blockNumber = state.nextBlockNumber + i;
      final existing = i < state.createdBlocks.length
          ? state.createdBlocks[i]
          : null;
      final WizardCreatedBlock createdBlock;
      if (existing == null) {
        state = state.copyWith(dispatchLabel: _blockLabel(i));
        // AUTHZ-GATE: authenticated session resolved above. The
        // `season_id`/`series_id` come from the create-season RESPONSE and
        // the caller-supplied config — never from a projection lookup.
        final ack = await blockRepo.create(
          CreateBlockRequest(
            (b) => b
              ..seriesId = seriesId
              ..seasonId = seasonId
              ..number = blockNumber,
          ),
        );
        final block = ack.getRight().toNullable();
        if (block == null) {
          _fail(ack.getLeft().toNullable()!);
          return;
        }
        createdBlock = WizardCreatedBlock(
          id: block.id,
          number: blockNumber,
          title: draft.title,
          episodeCount: draft.episodeCount,
        );
        _ackBlock(createdBlock, seasonId);
      } else {
        createdBlock = existing;
      }

      // `blockId` is hoisted to a non-null local so the request-builder
      // closure reads a promoted value (CQRS boundary: response-sourced).
      final blockId = createdBlock.id;

      // AUTHZ-GATE: the episodes routes are BlockMember-scoped
      // server-side — the request carries `X-Active-Block` of the block
      // the episodes belong to, set here from the create-block RESPONSE
      // (CQRS boundary — the same implicit scope-set the BlocksScreen
      // navigation performs from the acted-on DTO). The freshly created
      // block grants the creator owner membership, so the gate passes.
      if (existing == null) {
        ref
            .read(activeBlockProvider.notifier)
            .set(seasonId: seasonId, blockId: createdBlock.id);
      }
      // Resolved AFTER the scope set: `apiDioProvider` rebuilds with the
      // new header and the repository re-resolves through it.
      final episodeRepo = ref.read(episodeRepositoryProvider);

      // 3. The block's episodes (resume at the first un-acked number).
      // The series-scoped numbers are PLAN-SEQUENTIAL across blocks
      // (derived once at wizard open; recomputing on a retry reproduces
      // the acked episodes' numbers exactly — the plan is locked during a
      // partial failure).
      for (var e = createdBlock.episodesCreated; e < draft.episodeCount; e++) {
        final episodeNumber = derivedEpisodeNumber(
          drafts,
          firstEpisodeNumber: state.nextEpisodeNumber,
          blockIndex: i,
          episodeIndex: e,
        );
        state = state.copyWith(dispatchLabel: _episodeLabel(i, e));
        // AUTHZ-GATE: authenticated session resolved above. The
        // `block_id` comes from the create-block RESPONSE (CQRS boundary).
        final ack = await episodeRepo.create(
          CreateEpisodeRequest(
            (b) => b
              ..seriesId = seriesId
              ..blockId = blockId
              ..number = episodeNumber,
          ),
        );
        final episode = ack.getRight().toNullable();
        if (episode == null) {
          // The created-so-far count is persisted INTO the ref so the
          // retry resumes exactly here.
          _fail(
            ack.getLeft().toNullable()!,
            createdBlocks: [
              for (var j = 0; j < state.createdBlocks.length; j++)
                if (j == i)
                  state.createdBlocks[j].copyWith(episodesCreated: e)
                else
                  state.createdBlocks[j],
            ],
          );
          return;
        }
        final updated = createdBlock.copyWith(episodesCreated: e + 1);
        _ackEpisode(episode, updated, seasonId);
        state = state.copyWith(
          createdBlocks: [
            for (var j = 0; j < state.createdBlocks.length; j++)
              if (j == i) updated else state.createdBlocks[j],
          ],
          dispatchDone: state.dispatchDone + 1,
        );
      }
    }

    // Settled: every command acked.
    state = state.copyWith(
      phase: SetupWizardPhase.completed,
      dispatchLabel: '',
    );
    _reconcileCreatedFamilies(seasonId, drafts);
  }

  /// Command failure → partial-failure phase (created-so-far refs
  /// retained, error keyed on its stable `code`).
  void _fail(ProblemError error, {List<WizardCreatedBlock>? createdBlocks}) {
    state = state.copyWith(
      phase: SetupWizardPhase.partialFailure,
      failure: error,
      createdBlocks: createdBlocks ?? state.createdBlocks,
      dispatchLabel: '',
    );
    // Reconcile what DID get created so the user's screens are consistent
    // when they leave via the escape hatch.
    final season = state.createdSeason;
    if (season != null) {
      _reconcileCreatedFamilies(
        season.id,
        state.blocks.take(state.createdBlocks.length).toList(),
      );
    }
  }

  int _completedCommandsSoFar() {
    var done = state.createdSeason != null ? 1 : 0;
    for (final b in state.createdBlocks) {
      done += 1 + b.episodesCreated;
    }
    return done;
  }

  String _seasonLabel() {
    final name = state.seasonName;
    return name.isEmpty ? 'Season ${state.seasonNumber}' : name;
  }

  String _blockLabel(int index) => 'Block ${state.nextBlockNumber + index}';

  String _episodeLabel(int blockIndex, int episodeIndex) =>
      'Block ${state.nextBlockNumber + blockIndex} · '
      'Episode ${derivedEpisodeNumber(state.blocks, firstEpisodeNumber: state.nextEpisodeNumber, blockIndex: blockIndex, episodeIndex: episodeIndex)}';

  // --- Optimistic overlay bookkeeping (the established stores the
  // individual screens render; the wizard inserts, the owning controllers
  // reconcile) ---

  void _ackSeason(IdVersionResponse res, int number) {
    ref
        .read(seasonOverlaysProvider.notifier)
        .add(
          SeasonOverlay(
            id: res.id,
            name: state.seasonName.isEmpty ? null : state.seasonName,
            number: number,
            status: OverlayStatus.acknowledged,
          ),
        );
    state = state.copyWith(
      createdSeason: WizardCreatedSeason(
        id: res.id,
        number: number,
        title: state.seasonName,
      ),
      dispatchDone: state.dispatchDone + 1,
    );
  }

  void _ackBlock(WizardCreatedBlock block, String seasonId) {
    ref
        .read(blocksOverlaysProvider(seasonId).notifier)
        .add(
          BlockOverlay(
            id: block.id,
            number: block.number,
            status: OverlayStatus.acknowledged,
          ),
        );
    state = state.copyWith(
      createdBlocks: [...state.createdBlocks, block],
      dispatchDone: state.dispatchDone + 1,
    );
  }

  void _ackEpisode(
    IdVersionResponse res,
    WizardCreatedBlock block,
    String seasonId,
  ) {
    ref
        .read(episodesOverlaysProvider(block.id, seasonId).notifier)
        .add(
          EpisodeOverlay(
            id: res.id,
            number: block.episodesCreated,
            status: OverlayStatus.acknowledged,
          ),
        );
  }

  /// Reconciliation at sequence settle (the batched analog of the
  /// per-command ack-reconcile the individual screens run): every affected
  /// family's bounded-retry pass confirms the created ids against their
  /// projections and drops the overlays. Fire-and-forget — the wizard
  /// never blocks on projector lag.
  void _reconcileCreatedFamilies(String seasonId, List<BlockDraft> _) {
    unawaited(ref.read(seasonsControllerProvider.notifier).reconcile());
    final created = state.createdBlocks;
    if (created.isEmpty) return;
    unawaited(
      ref.read(blocksControllerProvider(seasonId).notifier).reconcile(),
    );
    for (final block in created) {
      if (block.episodesCreated == 0) continue;
      unawaited(
        ref
            .read(episodesControllerProvider(block.id, seasonId).notifier)
            .reconcile(),
      );
    }
  }
}
