// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

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
  /// unique per series, not per season) from the series' EXISTING blocks
  /// projection. Live network refetch, never the boot-time `seasonsView`/
  /// Drift cache: the derivation must hold against accumulated,
  /// concurrently-mutated dev-series state (issue #455 — the boot-time
  /// `seasonsView` can be empty (see below) or a stale snapshot of a
  /// concurrently-seeded backend, and a caching read that degrades on
  /// failure starts the plan at a taken base number). The DERIVED NUMBER
  /// is the only command payload this feeds (append-order derivation,
  /// `nextOrderKey` discipline), never audit context.
  ///
  /// Reads go through the injected list-fetch seams the screens use
  /// (`seasonsListFetchProvider` / `blocksListFetchProvider`) plus the
  /// series-scoped episode read ([EpisodeRepository.listBySeries]), all
  /// forced FRESH on every run via the established refetch boundary
  /// (`ref.invalidate` → `ref.read(...future)` — the same pattern the
  /// blocks/episodes controllers' `_refetchProjection` uses). In
  /// production each run is therefore a live network refetch, in the
  /// controller tests the overridden seam:
  /// * `GET /v1/seasons` (paginated, series-filtered) — the series'
  ///   seasons. The boot-time `seasonsView` can serve an EMPTY retained
  ///   snapshot during the boot window, which emptied the old derivation
  ///   to block 1; a live fetch closes that;
  /// * per season `GET /v1/blocks?season_id=…` — that season's blocks
  ///   (all pages; the backend REQUIRES `season_id`, so one call per
  ///   season is the honest single-scope block read);
  /// * `GET /v1/episodes?series_id=…` (one call via
  ///   [EpisodeRepository.listBySeries]) — the series' episode numbers
  ///   (episodes are numbered per series too,
  ///   `idx_projection_episode_series_number`).
  ///
  /// A failed fetch degrades to base 1 (the honest fallback for an empty
  /// series — and for a momentarily unreachable backend, the submit-time
  /// re-derive and the mid-dispatch 409 then surface as partial failure
  /// with the in-session retry). Never reverts to a cached/retained
  /// snapshot: that is exactly the poisoning this repair removes.
  ///
  /// The method is repeatable and re-invokable while editing (issue #455:
  /// the derivation must hold against state that changed after a previous
  /// run); [SetupWizardState.numbersSeeded] is set only when a run
  /// settles.
  Future<void> seedDerivedNumbers({required String seriesId}) async {
    if (!state.isEditing) return;
    await _deriveNumbers(seriesId: seriesId);
  }

  /// Un-guarded core of the derivation (the editing-phase guard lives on
  /// [seedDerivedNumbers]; the dispatch runs this during `dispatching`, so
  /// it must NOT gate on editing). See [seedDerivedNumbers] for the
  /// contract. Writes state only if `ref.mounted` (the autoDispose
  /// controller may be disposed across the network awaits).
  ///
  /// Returns the first **season or block** read error, or `null` on
  /// success (CodeRabbit #464: the wizard must never dispatch against a
  /// degraded `max + 1` — a failed live read is propagated so the dispatch
  /// caller can fail closed). The wizard-open path ([seedDerivedNumbers])
  /// ignores the return and treats the failure as the honest empty
  /// fallback (base 1, `numbersSeeded` still lifts so the user can
  /// continue); the dispatch path (`_runDispatch`) stops on a non-null
  /// return.
  Future<ProblemError?> _deriveNumbers({required String seriesId}) async {
    ProblemError? error;
    final blockNumbers = <int>[];

    // The series' seasons forced FRESH from the injected live fetch (never
    // the boot-time seasonsView — issue #455 derive repair; an invalidated
    // re-run refetches, so a repeatable derivation reflects accumulation).
    ref.invalidate(seasonsListFetchProvider);
    final seasonsResult = await ref.read(seasonsListFetchProvider.future);
    final seasonsError = seasonsResult.getLeft().toNullable();
    if (seasonsError != null) {
      error = seasonsError;
    } else {
      final seasons = seasonsResult
          .getOrElse((_) => const <SeasonView>[])
          .where((s) => s.seriesId == seriesId)
          .toList();
      for (final season in seasons) {
        if (!ref.mounted) return null;
        ref.invalidate(blocksListFetchProvider(season.id));
        final blocksResult = await ref.read(
          blocksListFetchProvider(season.id).future,
        );
        final blockError = blocksResult.getLeft().toNullable();
        if (blockError != null) {
          error = blockError;
          break;
        }
        blockNumbers.addAll(
          blocksResult
              .getOrElse((_) => const <BlockView>[])
              .map((b) => b.number),
        );
      }
    }

    // Episode base is NON-fatal here (CodeRabbit #464): at dispatch start
    // the caller has no block membership yet, so the BlockMember-scoped
    // episodes read is EXPECTED to 400 — the authoritative base is set by
    // the post-first-block re-derive in `_runDispatch`. Its error is
    // ignored; a failure leaves `nextEpisodeNumber` at its prior value.
    await _deriveEpisodeNumbers(seriesId: seriesId);
    if (!ref.mounted) return null;
    state = state.copyWith(
      nextBlockNumber: smartDefaultBlockNumber(blockNumbers),
      // The derivation has SETTLED (success or honest fallback): the
      // screen's advance/confirm gates lift from here (never dispatch on
      // the fallback numbers while the reads are still running).
      numbersSeeded: true,
    );
    return error;
  }

  /// Derives ONLY the series' first free EPISODE number (the series'
  /// episodes from a live series-scoped read).
  ///
  /// Episodes are `BlockMember`-scoped server-side
  /// (`GET /v1/episodes` requires `X-Active-Block`): at wizard open the
  /// caller has NO block membership yet, so the read 400s and honestly
  /// degrades (no state mutation — the prior `nextEpisodeNumber` stays;
  /// at open that is the default 1). But a freshly created block grants
  /// its creator ownership (the dispatch's own `AUTHZ-GATE` scope-set), so
  /// the dispatch re-derives the episode base AFTER the first block create
  /// — see `_runDispatch` (issue #455 episode side).
  ///
  /// Returns the read error, or `null` on success (CodeRabbit #464). On a
  /// failure the derivation does NOT fabricate base 1 — it leaves
  /// `nextEpisodeNumber` untouched so the caller can fail closed; the
  /// post-block-1 dispatch caller stops before any episode create.
  Future<ProblemError?> _deriveEpisodeNumbers({
    required String seriesId,
  }) async {
    if (!ref.mounted) return null;
    final episodeResult = await ref
        .read(episodeRepositoryProvider)
        .listBySeries(seriesId);
    if (!ref.mounted) return null;
    final episodeError = episodeResult.getLeft().toNullable();
    if (episodeError != null) return episodeError;
    final episodeNumbers = episodeResult
        .getOrElse((_) => const <EpisodeView>[])
        .map((e) => e.number)
        .toList();
    state = state.copyWith(
      nextEpisodeNumber: smartDefaultEpisodeNumber(episodeNumbers),
    );
    return null;
  }

  /// Re-runs [seedDerivedNumbers] against the live backend (issue #455):
  /// the series accumulates state concurrently while the wizard is open,
  /// so the plan's derived block number must be re-checked before the
  /// user advances. No-op outside the editing phase; keeps draft state.
  Future<void> rederive({required String seriesId}) async {
    if (!state.isEditing) return;
    await seedDerivedNumbers(seriesId: seriesId);
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
  ///
  /// Pre-dispatch guard (issue #467): an empty env-sourced `seriesId` (a
  /// rebuild without `--dart-define=DEFAULT_SERIES_ID`) fails fast with
  /// the actionable [missingSeriesIdProblem] — NO network round-trip that
  /// the backend could only answer with a blind 422 `domain.validation`.
  Future<void> submit({required String seriesId}) async {
    if (!state.isEditing) return;
    if (seriesId.trim().isEmpty) {
      _failPreDispatchConfig();
      return;
    }
    await _runDispatch(seriesId: seriesId);
  }

  /// Retries the remaining commands of a partially failed dispatch
  /// in-session (spec `Partial failure`): skips every command already
  /// acknowledged (the created refs are the resume cursor) and continues
  /// from the failed one. The plan's numbers stay LOCKED to the acked
  /// ones (recomputing would renumber already-created rows), so a retry
  /// never re-derives.
  ///
  /// The issue #467 guard applies here too: a retry on a build without
  /// `DEFAULT_SERIES_ID` re-trips the same fail-fast (no network), keeping
  /// the retry honest for a rebuild-required state.
  Future<void> retryRemaining({required String seriesId}) async {
    if (state.phase != SetupWizardPhase.partialFailure) return;
    if (seriesId.trim().isEmpty) {
      _failPreDispatchConfig();
      return;
    }
    await _runDispatch(seriesId: seriesId);
  }

  /// The fail-fast branch of both dispatch entry points: renders the
  /// actionable build-misconfiguration error as the settled failure (zero
  /// partial work), never an HTTP round-trip.
  void _failPreDispatchConfig() {
    state = state.copyWith(
      phase: SetupWizardPhase.partialFailure,
      failure: missingSeriesIdProblem,
      dispatchLabel: '',
    );
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

    // Issue #455 derive repair: the number derivation must hold against
    // state that accumulated AFTER the wizard opened (concurrent harness
    // writes / a boot snapshot). Re-run the live refetch derivation at the
    // START of the dispatch (phase is already `dispatching`, so the
    // screen's settle detection and the autoDispose keep-alive stay
    // correct): the plan then dispatches against the freshest possible
    // numbers, and a still-taken number 409s as a partial failure with the
    // in-session retry instead of silently creating a conflicting block.
    // Never reverts to a cached/retained snapshot.
    //
    // Gated to a FRESH dispatch (nothing acked yet): a retry re-enters
    // with an already-started plan whose numbers are LOCKED to the acked
    // commands — re-deriving then would renumber created rows.
    if (_completedCommandsSoFar() == 0) {
      final deriveError = await _deriveNumbers(seriesId: seriesId);
      if (!ref.mounted) return;
      if (deriveError != null) {
        // Fail closed (CodeRabbit #464): never dispatch against a degraded
        // max + 1 that could 409 or create a wrong plan. The read failure
        // surfaces as partial failure; a retry re-derives (nothing acked
        // yet).
        _fail(deriveError);
        return;
      }
      if (state.phase != SetupWizardPhase.dispatching) return;
    }

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

      // Issue #455 episode side: the episodes route is `BlockMember`
      // scoped, so at wizard open the caller had no block membership and
      // the episode-base derive degraded to 1. A freshly created block
      // grants the creator ownership — NOW the series' episodes are
      // readable (the scope set above), so re-derive the episode base
      // before ANY episode create. Only needed once (block 0, no acked
      // episodes yet); later blocks reuse the derived base.
      if (i == 0 && createdBlock.episodesCreated == 0) {
        final episodeError = await _deriveEpisodeNumbers(seriesId: seriesId);
        if (!ref.mounted) return;
        if (episodeError != null) {
          // Fail closed (CodeRabbit #464): no episode create without an
          // authoritative series episode base (a degraded base-1 would 409
          // on accumulated series episodes). Created-so-far: the season + this
          // block.
          _fail(episodeError);
          return;
        }
        if (state.phase != SetupWizardPhase.dispatching) return;
      }

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
        _ackEpisode(episode, updated, episodeNumber, seasonId);
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
    int episodeNumber,
    String seasonId,
  ) {
    ref
        .read(episodesOverlaysProvider(block.id, seasonId).notifier)
        .add(
          EpisodeOverlay(
            id: res.id,
            // The DERIVED series-scoped episode number (the wire payload's
            // number), not the per-block ack count — the overlay row must
            // match what the projection will render.
            number: episodeNumber,
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
