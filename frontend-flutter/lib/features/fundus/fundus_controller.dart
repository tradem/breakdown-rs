// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/result.dart';
import '../../data/cache/cache_generation.dart';
import '../../data/cache/piece_domains_cache_dao.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../../data/fundus_repository.dart';
import 'fundus_model.dart';

part 'fundus_controller.g.dart';

/// Fundus repository: owns the project-scoped network fetch + Drift cache
/// writes (OpenSpec change `flutter-fundus-search`, tasks §2/§3).
@riverpod
FundusRepository fundusRepository(Ref ref) => FundusRepository(
  ref.watch(apiClientProvider),
  FundusPieceCacheDao(ref.watch(cacheDatabaseProvider)),
);

/// The project's cached fundus inputs — THE QUERY PATH (design D3).
///
/// READ-ONLY cache composition; the search itself NEVER issues a network
/// call. Freshness arrives via the bounded prefetch pass
/// ([FundusController.refresh]), the only seam that may touch the network.
///
/// The project's seasons come from the seasons projection (a read-DTO join,
/// never a second projection lookup for a command).
@riverpod
Future<Result<FundusInputs>> fundusInputs(Ref ref, String projectId) async {
  final repo = ref.watch(fundusRepositoryProvider);
  final clock = ref.watch(clockProvider);
  final seasons = [
    for (final season in ref.watch(seasonsView).rows)
      if (season.projectId == projectId) season,
  ];
  final cached = await repo.readCachedFresh(projectId, clock: clock);
  return cached.map(
    (fresh) => FundusInputs(
      projectId: projectId,
      pieces: fresh.rows,
      seasons: seasons,
      stale: fresh.stale,
    ),
  );
}

/// Whether a bounded prefetch pass has completed for a project (empty vs.
/// not-yet-loaded honesty). Written by the refresher pass, read by the
/// controller.
@riverpod
class FundusLoaded extends _$FundusLoaded {
  @override
  bool build(String projectId) => false;

  void markLoaded() => state = true;
}

/// The typed fundus query: text prefilter plus the selected season chips.
class FundusQueryState {
  const FundusQueryState({this.text = '', this.selectedSeasonIds = const {}});

  final String text;
  final Set<String> selectedSeasonIds;
}

/// Query notifier family per project (the project switch recomputes over the
/// new project only — the family key IS the scope).
@riverpod
class FundusQuery extends _$FundusQuery {
  @override
  FundusQueryState build(String projectId) => const FundusQueryState();

  void setText(String text) => state = FundusQueryState(
    text: text,
    selectedSeasonIds: state.selectedSeasonIds,
  );

  /// Toggle a season chip. No chip selected = the whole fundus (design D4).
  void toggleSeason(String seasonId) {
    final selected = {...state.selectedSeasonIds};
    if (!selected.remove(seasonId)) selected.add(seasonId);
    state = FundusQueryState(text: state.text, selectedSeasonIds: selected);
  }
}

/// The fundus-surface controller (tasks §3.1): maps the inputs `Result` into
/// a [FundusViewState], never discarding an `Err` (storage failure SURFACES
/// as the error state with a retry — the client analog of `discard-result`).
@Riverpod(keepAlive: false)
class FundusController extends _$FundusController {
  /// Retained last-good view across input reloads (the retained-rows pattern
  /// the read screens use) — the prefetch invalidation must not flash a
  /// spinner over an already-rendered fundus.
  FundusViewState? _retained;

  @override
  AsyncValue<FundusViewState> build(String projectId) {
    final inputs = ref.watch(fundusInputsProvider(projectId));
    return switch (inputs) {
      AsyncLoading() =>
        _retained == null
            ? const AsyncValue<FundusViewState>.loading()
            : AsyncValue<FundusViewState>.data(_retained!),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<FundusViewState>.error(error, stackTrace),
      AsyncData(:final value) => value.match(
        (error) => AsyncValue<FundusViewState>.error(error, StackTrace.current),
        (data) => AsyncValue<FundusViewState>.data(_retained = _derive(data)),
      ),
    };
  }

  FundusViewState _derive(FundusInputs inputs) {
    final query = ref.watch(fundusQueryProvider(projectId));
    final matched = matchFundus(
      pieces: inputs.pieces,
      projectSeasonIds: inputs.seasonIds,
      selectedSeasonIds: query.selectedSeasonIds,
      text: query.text,
    );
    final loaded = ref.watch(fundusLoadedProvider(projectId));
    return FundusViewState(
      text: query.text,
      selectedSeasonIds: query.selectedSeasonIds,
      projectSeasons: inputs.seasons,
      rows: matched,
      zeroMatch: query.text.trim().isNotEmpty && matched.isEmpty && loaded,
      loaded: loaded,
      stale: inputs.stale,
    );
  }

  void setText(String text) =>
      ref.read(fundusQueryProvider(projectId).notifier).setText(text);

  void toggleSeason(String seasonId) =>
      ref.read(fundusQueryProvider(projectId).notifier).toggleSeason(seasonId);

  /// Bounded prefetch (tasks §3.2): one project-scoped fetch through the
  /// repository (which snapshot-replaces the cache), then re-read the cache.
  /// Failures are honest degradation — the cached rows keep rendering; the
  /// error state is reserved for storage failures on the read path. A failed
  /// fetch does NOT mark the project loaded (the not-yet-loaded note stays).
  Future<void> refresh() async {
    final repo = ref.read(fundusRepositoryProvider);
    final clock = ref.read(clockProvider);
    final generation = ref.read(cacheGenerationProvider);
    // The Result is CONSUMED (never silently discarded — the
    // `discard_result` lint): a failed prefetch is honest degradation, so
    // the value is inspected, not swallowed.
    final fetched = await repo.listByProject(
      projectId,
      clock: clock,
      fence: CacheWriteFence(
        generation: generation,
        isCurrentGeneration: (g) =>
            ref.mounted && ref.read(cacheGenerationProvider) == g,
      ),
    );
    if (!ref.mounted) return;
    if (fetched.isRight()) {
      ref.read(fundusLoadedProvider(projectId).notifier).markLoaded();
    }
    ref.invalidate(fundusInputsProvider(projectId));
  }

  /// Retry after the ERROR state: re-read the cache (the error is about the
  /// cache being unreadable, not about connectivity).
  void retryAfterError() => ref.invalidate(fundusInputsProvider(projectId));
}
