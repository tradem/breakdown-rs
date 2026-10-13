// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/active_block.dart';
import '../../l10n/app_localizations_provider.dart';
import '../blocks/active_block_gate.dart';
import '../blocks/blocks_controller.dart';
import 'planning_location.dart';
import 'scope_pill.dart';
import 'shell_controller.dart';

part 'active_scope_chip.g.dart';

/// Cache-only backfill of a label-less scope's block number (issue #548).
///
/// A scope restored from the pre-#548 persisted document shape carries no
/// block number, so the chip cannot render `blockTileLabel(number)`. The
/// honest source is the block the user picked — but on this degradation
/// path no `BlockView` is in hand. This provider re-resolves the number
/// ONCE from `blockRepository.readCached(seasonId)` — pure Drift, NEVER a
/// live fetch on a hot path — and `null` when the cache has no row for the
/// block (the chip keeps its explicit "unknown" narrative; a silent filter
/// is never rendered as if unfiltered).
@riverpod
Future<int?> resolvedScopeBlockNumber(
  Ref ref,
  String seasonId,
  String blockId,
) async {
  final res = await ref.watch(blockRepositoryProvider).readCached(seasonId);
  return res.match((_) => null, (rows) {
    for (final block in rows) {
      if (block.id == blockId) return block.number;
    }
    return null;
  });
}

/// The scope chip (issue #548): says WHAT FILTERS YOUR REQUESTS.
///
/// Separate from the `LocationStrip` by design — different facts with
/// different lifetimes (the location is per-route; the scope is sticky
/// across seasons and cold starts). Rendered by the shell's context bar
/// whenever a scope is set; a tap opens the block picker so the scope
/// becomes changeable, not just visible.
///
/// Arms (issue #638 adds the prerequisite + neutral arm):
/// - **no season and no scope** → hidden (`SizedBox.shrink`);
/// - **season active, no scope** → the neutral "Block wählen" pill, whose
///   tap opens the block picker for the active season;
/// - **scoped + number known** → `Filter: Block {n}` (localized) in the
///   block highlight color;
/// - **scoped, label unknown** (old persisted document) → the explicit
///   "unknown" narrative while the cache-only backfill resolves the
///   number and writes it back;
/// - **foreign season** (the scope's season differs from the navigated
///   season in [location]) → the chip says so instead of presenting the
///   foreign block as if it applied — the reuse rule (seasonId must match)
///   exists exactly because browsing season B must not send season A's
///   block.
///
/// // AUTHZ-GATE: the chip is display + navigation only — it dispatches no
/// command and performs no network call itself (the picker's own resolution
/// path is unchanged), so it needs no membership check.
class ActiveScopeChip extends ConsumerStatefulWidget {
  const ActiveScopeChip({super.key, required this.onOpenPicker, this.location});

  /// The active tab's location — only used for the foreign-season check.
  final PlanningLocation? location;

  /// Opens the block picker for the scope's season (injected so the chip
  /// stays a leaf widget the tests can pump standalone).
  final void Function(String seasonId) onOpenPicker;

  @override
  ConsumerState<ActiveScopeChip> createState() => _ActiveScopeChipState();
}

class _ActiveScopeChipState extends ConsumerState<ActiveScopeChip> {
  /// Cache-only backfill guard: one attempt per (season, block) scope.
  (String, String)? _backfilled;

  @override
  Widget build(BuildContext context) {
    final season = ref.watch(shellControllerProvider).activeSeason;
    final scope = ref.watch(activeBlockProvider);
    // Issue #638 prerequisite: a block belongs to a season, so the pill is
    // hidden until a season is active — or a block scope is already set
    // (legacy persisted scope restored before the season resolves).
    if (season == null && scope == null) return const SizedBox.shrink();

    final l10n = l10nOf(context);
    final scheme = Theme.of(context).colorScheme;
    final foreign =
        scope != null &&
        widget.location != null &&
        widget.location!.seasonId != scope.seasonId;
    final label = scope == null
        ? l10n.scopeChipBlockUnset
        : foreign
        ? l10n.scopeChipForeignSeason
        : scope.blockNumber == null
        ? l10n.scopeChipUnknownBlock
        : l10n.scopeChipBlock(l10n.blockTileLabel('${scope.blockNumber}'));

    // Degradation path (issue #548): a label-less scope re-resolves its
    // number ONCE, cache-only, and writes it back — then renders the real
    // label on the next build. The guard compares against the CURRENT
    // (season, block) pair, so a later DIFFERENT label-less scope (sign-out
    // + legacy restore, etc.) gets its own attempt; the same failed pair is
    // never retried (no busy loop).
    if (scope != null &&
        !foreign &&
        scope.blockNumber == null &&
        _backfilled != (scope.seasonId, scope.blockId)) {
      _backfilled = (scope.seasonId, scope.blockId);
      unawaited(_backfill(scope));
    }

    // Unset arm: the picker targets the ACTIVE season (guaranteed non-null
    // here — the pill is hidden when neither a season nor a scope is set).
    final targetSeasonId = scope?.seasonId ?? season!.id;
    return ScopePill(
      key: const Key('active-scope-chip'),
      icon: Icons.filter_alt_outlined,
      label: label,
      selected: scope != null,
      selectedColor: scheme.secondaryContainer,
      selectedForegroundColor: scheme.onSecondaryContainer,
      tooltip: scope == null
          ? l10n.scopeChipBlockUnsetTooltip
          : l10n.scopeChipTooltip,
      onPressed: () => widget.onOpenPicker(targetSeasonId),
    );
  }

  /// Writes the cache-resolved number back into the scope (which persists
  /// it with the next `set`), guarded against a scope that changed or was
  /// cleared in the meantime — never resurrects a stale entry.
  Future<void> _backfill(ActiveScope scope) async {
    final number = await ref.read(
      resolvedScopeBlockNumberProvider(scope.seasonId, scope.blockId).future,
    );
    if (!mounted) return;
    if (number == null) return;
    final current = ref.read(activeBlockProvider);
    if (current == null ||
        current.seasonId != scope.seasonId ||
        current.blockId != scope.blockId ||
        current.blockNumber != null) {
      return;
    }
    ref
        .read(activeBlockProvider.notifier)
        .set(
          seasonId: scope.seasonId,
          blockId: scope.blockId,
          blockNumber: number,
        );
  }
}

/// The chip's block picker: resolves the scope season's blocks through the
/// SAME seam the season-direct gate uses (`blocksListFetchProvider`,
/// `GET /v1/blocks` is `Authenticated` and works headerless) and reuses
/// `BlockScopePickerScaffold`'s one-tap remembered-pick semantics — the
/// pick sets the sticky scope (with the acted-on block's number) and pops
/// back, so the scope is changeable from anywhere.
class ScopeChipPickerScreen extends ConsumerWidget {
  const ScopeChipPickerScreen({super.key, required this.seasonId});

  final String seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final fetch = ref.watch(blocksListFetchProvider(seasonId));
    return switch (fetch) {
      AsyncLoading() => BlockScopeLoadingScaffold(
        title: l10n.scopeChipPickTitle,
      ),
      AsyncError(:final error) => BlockScopeErrorScaffold(
        title: l10n.scopeChipPickTitle,
        code: blockScopeErrorCode(error),
        onRetry: () => ref.refresh(blocksListFetchProvider(seasonId)),
      ),
      AsyncData(:final value) => value.match(
        (err) => BlockScopeErrorScaffold(
          title: l10n.scopeChipPickTitle,
          code: err.code,
          onRetry: () => ref.refresh(blocksListFetchProvider(seasonId)),
        ),
        (rows) => BlockScopePickerScaffold(
          title: l10n.scopeChipPickTitle,
          seasonId: seasonId,
          candidates: rows,
          onPicked: () => Navigator.of(context).pop(),
        ),
      ),
    };
  }
}
