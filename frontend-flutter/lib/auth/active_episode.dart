// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:async' show unawaited;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'active_block.dart';
import 'active_episode_store.dart';

part 'active_episode.g.dart';

/// The client-side active-episode scope (issue #624).
///
/// The episode-level sibling of the active-block scope
/// (`active_block.dart`). The
/// shell's quick-create sheet needs an episode to resolve the two
/// context-sensitive entries ("Neue Szene" / "Neuer Drehtag") from, and the
/// shell tracks no episode today. This scope is set from the `EpisodeView`
/// the user acted on (CQRS boundary — never a second projection lookup)
/// whenever they enter an episode's context, and is changeable through the
/// shell's episode chip picker.
///
/// [episodeNumber] and [episodeName] carry the acted-on episode's
/// locale-neutral label parts so the chip renders a VISIBLE label without a
/// live fetch; the name wins when present, the number is the fallback.
///
/// The scope is persisted per season via [ActiveEpisodeStore] (issue #624):
/// every [set] writes through to secure storage so a cold start restores the
/// remembered pick. Persistence is best-effort — a store failure never
/// breaks the in-memory scope.
class ActiveEpisodeScope {
  const ActiveEpisodeScope({
    required this.seasonId,
    required this.blockId,
    required this.episodeId,
    required this.episodeNumber,
    this.episodeName,
  });

  /// The season the episode belongs to.
  final String seasonId;

  /// The block the episode belongs to (the picker's list scope).
  final String blockId;

  /// The episode id every create command sources its `episode_id` from.
  final String episodeId;

  /// The acted-on episode's number (label fallback).
  final int episodeNumber;

  /// The acted-on episode's name (`null` renders the number label).
  final String? episodeName;

  @override
  bool operator ==(Object other) =>
      other is ActiveEpisodeScope &&
      other.seasonId == seasonId &&
      other.blockId == blockId &&
      other.episodeId == episodeId &&
      other.episodeNumber == episodeNumber &&
      other.episodeName == episodeName;

  @override
  int get hashCode =>
      Object.hash(seasonId, blockId, episodeId, episodeNumber, episodeName);

  @override
  String toString() =>
      'ActiveEpisodeScope(seasonId: $seasonId, blockId: $blockId, '
      'episodeId: $episodeId, number: $episodeNumber)';
}

/// The sticky active-episode scope. `null` means no episode is in context
/// (fresh boot, signed out, or the scope was cleared) — the quick-create
/// sheet then offers only its context-free entries.
///
/// `keepAlive: true` so the scope survives screen pops; consumers set it on
/// navigation into episode context and clear it on sign-out.
@Riverpod(keepAlive: true)
class ActiveEpisode extends _$ActiveEpisode {
  @override
  ActiveEpisodeScope? build() => null;

  /// Sets the scope from the episode DTO the user acted on, and CASCADES the
  /// active-block scope from the same DTO (issue #765).
  ///
  /// **Invariant — an episode implies its block.** An episode belongs to
  /// exactly one block, so every write of the episode scope also establishes
  /// the block scope. That block scope is not cosmetic: `X-Active-Block` rides
  /// on every request (`ActiveBlockInterceptor`) and the backend rejects a
  /// MISSING header with 400 on the block-scoped routes (episodes, scenes,
  /// shooting days, scene shoots, pieces, characters) — an episode scope
  /// without its block scope would leave the app acting headerless. THIS
  /// method is the one seam: every `activeEpisodeProvider.notifier.set(...)`
  /// call site gets the block scope along, so no future picker or screen can
  /// forget it (the invariant is structural, not a review checklist item).
  ///
  /// The reverse direction — a BLOCK switch dropping an episode scope that no
  /// longer belongs to it — lives in `ActiveBlock.set`, so the two scopes can
  /// never disagree.
  ///
  /// The in-memory state updates synchronously (call sites must observe it
  /// before navigating); the per-season persistence follows fire-and-forget
  /// and refreshes [activeEpisodePersistedProvider] once settled so watchers
  /// converge. The refresh is `mounted`-guarded: the write may settle after
  /// the provider was invalidated or disposed (sign-out, test teardown).
  ///
  /// [blockNumber] is the acted-on block's number when the caller holds the
  /// `BlockView`; `null` is honest — the block chip's CACHE-ONLY number
  /// backfill then resolves the label (never a fabricated number, never a
  /// network fetch).
  void set({
    required String seasonId,
    required String blockId,
    required String episodeId,
    required int episodeNumber,
    String? episodeName,
    int? blockNumber,
  }) {
    state = ActiveEpisodeScope(
      seasonId: seasonId,
      blockId: blockId,
      episodeId: episodeId,
      episodeNumber: episodeNumber,
      episodeName: episodeName,
    );
    unawaited(
      ref
          .read(activeEpisodeStoreProvider)
          .saveScope(
            seasonId: seasonId,
            blockId: blockId,
            episodeId: episodeId,
            episodeNumber: episodeNumber,
            episodeName: episodeName,
          )
          .then((r) {
            r.fold((_) {}, (_) {});
            if (!ref.mounted) return;
            ref.invalidate(activeEpisodePersistedProvider);
          }),
    );
    _cascadeBlockScope(
      seasonId: seasonId,
      blockId: blockId,
      blockNumber: blockNumber,
    );
  }

  /// Establishes the block scope the acted-on episode belongs to (issue #765).
  ///
  /// A block scope that ALREADY names this season/block pair is left
  /// untouched: that preserves a `blockNumber` the chip resolved earlier (a
  /// cascade must never degrade a known label back to "unknown") and it is
  /// what keeps this from looping with `ActiveBlock.set`'s reverse cascade —
  /// the episode is already in place, so there is nothing to drop.
  void _cascadeBlockScope({
    required String seasonId,
    required String blockId,
    int? blockNumber,
  }) {
    final current = ref.read(activeBlockProvider);
    if (current != null &&
        current.seasonId == seasonId &&
        current.blockId == blockId) {
      return;
    }
    ref
        .read(activeBlockProvider.notifier)
        .set(seasonId: seasonId, blockId: blockId, blockNumber: blockNumber);
  }

  /// Drops the scope because the BLOCK scope moved to a different block
  /// (issue #765): an episode belongs to exactly one block, so the pair
  /// "Block B · Episode of block A" must never be displayable or acted on.
  ///
  /// The in-memory scope always goes (when it is foreign at all). A scope
  /// belonging to [seasonId] additionally has its persisted document evicted,
  /// so a cold start cannot resurrect the stale pair; a scope from ANOTHER
  /// season keeps its document — per-season memory is the season-switch
  /// path's concern (see [discard]).
  void clearForForeignBlock({
    required String seasonId,
    required String blockId,
  }) {
    final current = state;
    if (current == null || current.blockId == blockId) return;
    state = null;
    if (current.seasonId != seasonId) return;
    unawaited(
      ref.read(activeEpisodeStoreProvider).removeScope(seasonId).then((r) {
        r.fold((_) {}, (_) {});
        if (!ref.mounted) return;
        ref.invalidate(activeEpisodePersistedProvider);
      }),
    );
  }

  /// Clears the scope (sign-out / session teardown) including its persisted
  /// entry, so a new session never inherits it.
  void clear() {
    state = null;
    unawaited(
      ref.read(activeEpisodeStoreProvider).clear().then((r) {
        r.fold((_) {}, (_) {});
        if (!ref.mounted) return;
        ref.invalidate(activeEpisodePersistedProvider);
      }),
    );
  }

  /// Drops the IN-MEMORY scope without touching the persisted per-season
  /// documents (issue #624, CodeRabbit review): used when the active season
  /// changes and the new season has no remembered episode — the previous
  /// season's scope must not linger as a foreign chip, while each season
  /// keeps its own persisted entry. (A BLOCK switch uses
  /// [clearForForeignBlock] instead: there the pair is stale for good.)
  void discard() => state = null;
}
