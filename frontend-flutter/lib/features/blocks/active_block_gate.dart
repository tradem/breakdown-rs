// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/active_block.dart';
import '../../auth/active_block_store.dart';
import '../../core/problem_error.dart';
import 'blocks_controller.dart';

part 'active_block_gate.g.dart';

/// Resolution outcome for the season-direct active-block scope (issue #378).
///
/// `CostumesScreen`/`CharactersScreen` are entered from season level with
/// only a `SeasonView` — no block in context — yet their routes are
/// `BlockMember` server-side. Exactly one of the three states holds:
/// [scope] (ready — render content), [candidates] (ambiguous — pick once,
/// remembered via the sticky scope), or neither (no block exists yet).
class BlockScopeResolution {
  const BlockScopeResolution.ready(this.scope)
    : candidates = null,
      isEmpty = false;

  const BlockScopeResolution.needsPick(this.candidates)
    : scope = null,
      isEmpty = false;

  const BlockScopeResolution.empty()
    : scope = null,
      candidates = null,
      isEmpty = true;

  /// Resolved scope — content may render (requests carry `X-Active-Block`).
  final ActiveScope? scope;

  /// Candidate blocks for the one-tap remembered pick (multi-block season,
  /// no matching sticky scope). Non-empty when set.
  final List<BlockView>? candidates;

  /// `true` when the season has no blocks at all (hint instead of content).
  final bool isEmpty;
}

/// Resolves the active-block scope for a season-direct entry.
///
/// - Sticky scope matches `seasonId` → ready immediately (zero taps).
/// - Otherwise consults the persisted per-season scope (issue #382) once
///   the blocks fetch yields rows: a remembered block id that still exists
///   is restored silently (zero taps for returning users); a stale entry
///   (block deleted on the backend) is evicted and falls through below —
///   never a hard failure. The persisted provider degrades a store failure
///   to "nothing remembered", so this path runs as if nothing were
///   stored (the `AsyncError` tolerance below is defensive only).
/// - Otherwise consults the existing `blocksListFetchProvider` seam
///   (`GET /v1/blocks?season_id=…` is `Authenticated` — works headerless):
///   - exactly one block → sets the sticky scope and yields one loading
///     frame, so content (and its controller fetches) only builds after
///     the Dio carries the header — no headerless-400 flash;
///   - several → `needsPick` (one-tap remembered picker);
///   - none → `empty` (inline hint);
///   - fetch failure → `AsyncError` (screen renders its retry surface).
///
/// The single-block set is guarded by equality, so the resulting
/// Dio/client/controller rebuilds converge instead of looping.
@riverpod
AsyncValue<BlockScopeResolution> blockScopeResolution(
  Ref ref,
  String seasonId,
) {
  final scope = ref.watch(activeBlockProvider);
  if (scope != null && scope.seasonId == seasonId) {
    return AsyncValue.data(BlockScopeResolution.ready(scope));
  }
  // Hoisted (unconditional): `ref.watch` must run on every build, never
  // inside the fetch-match closure below.
  final persisted = ref.watch(activeBlockPersistedProvider);
  final fetch = ref.watch(blocksListFetchProvider(seasonId));
  return switch (fetch) {
    AsyncLoading() => const AsyncValue.loading(),
    AsyncError(:final error, :final stackTrace) => AsyncValue.error(
      error,
      stackTrace,
    ),
    AsyncData(:final value) => value.match(
      (err) => AsyncValue<BlockScopeResolution>.error(err, StackTrace.current),
      (rows) {
        if (rows.isEmpty) {
          return AsyncValue.data(const BlockScopeResolution.empty());
        }
        // Persisted restore (issue #382): withhold the picker while the
        // FIRST load is in flight; a remembered id that still exists is
        // adopted silently, a stale one is evicted with fall-through to
        // the existing path. A load failure (`AsyncError` — or the
        // `AsyncLoading`-with-error seeded while a Riverpod 3 auto-retry
        // is pending) behaves as if nothing were remembered, so a broken
        // store can never withhold content behind a spinner.
        if (persisted is AsyncLoading && !persisted.hasError) {
          return const AsyncValue<BlockScopeResolution>.loading();
        }
        final remembered = switch (persisted) {
          AsyncData(:final value) => value[seasonId],
          _ => null,
        };
        if (remembered != null) {
          if (rows.any((b) => b.id == remembered)) {
            final restored = ActiveScope(
              seasonId: seasonId,
              blockId: remembered,
            );
            if (ref.read(activeBlockProvider) != restored) {
              // Same deferred-set pattern as the single-block path below.
              unawaited(
                Future.microtask(() {
                  if (!ref.mounted) return;
                  if (ref.read(activeBlockProvider) != restored) {
                    ref
                        .read(activeBlockProvider.notifier)
                        .set(seasonId: seasonId, blockId: remembered);
                  }
                }),
              );
            }
            return const AsyncValue<BlockScopeResolution>.loading();
          }
          // Stale: the block is gone server-side. Evict the entry, then
          // fall through to the live re-resolution (never a hard failure).
          unawaited(
            ref.read(activeBlockStoreProvider).removeScope(seasonId).then((r) {
              r.fold((_) {}, (_) {});
              if (!ref.mounted) return;
              ref.invalidate(activeBlockPersistedProvider);
            }),
          );
        }
        if (rows.length == 1) {
          final picked = ActiveScope(
            seasonId: seasonId,
            blockId: rows.single.id,
          );
          if (ref.read(activeBlockProvider) != picked) {
            // Deferred: setting the scope synchronously here would modify
            // a provider during this build's flush (throws). The microtask
            // runs before the next frame; the loading frame below
            // withholds content (and its fetches) until the Dio carries
            // the header — no headerless-400 flash. Double-guarded so the
            // resulting rebuilds converge instead of looping.
            unawaited(
              Future.microtask(() {
                if (!ref.mounted) return;
                if (ref.read(activeBlockProvider) != picked) {
                  ref
                      .read(activeBlockProvider.notifier)
                      .set(seasonId: seasonId, blockId: rows.single.id);
                }
              }),
            );
          }
          return const AsyncValue<BlockScopeResolution>.loading();
        }
        return AsyncValue.data(BlockScopeResolution.needsPick(rows));
      },
    ),
  };
}

/// Loading placeholder while the scope resolves. Full scaffold so
/// season-direct screens can early-return it without re-indenting content.
class BlockScopeLoadingScaffold extends StatelessWidget {
  const BlockScopeLoadingScaffold({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: const Center(
      child: CircularProgressIndicator(key: Key('block-scope-loading')),
    ),
  );
}

/// Fetch-failure placeholder for scope resolution, keyed on the stable
/// problem `code` (never server `detail`), with a retry affordance.
class BlockScopeErrorScaffold extends StatelessWidget {
  const BlockScopeErrorScaffold({
    super.key,
    required this.title,
    required this.code,
    required this.onRetry,
  });

  final String title;
  final String code;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Column(
        key: const Key('block-scope-error'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Could not load blocks ($code).'),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('block-scope-retry'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

/// Hint shown when the season has no blocks yet: every block-scoped request
/// would 400, so content is withheld until a block exists.
class NoBlocksHintScaffold extends StatelessWidget {
  const NoBlocksHintScaffold({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: const Center(
      child: Text(
        'No blocks yet — create a block first, then come back.',
        key: Key('no-blocks-hint'),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

/// One-tap remembered block picker for multi-block seasons without a
/// matching sticky scope. The choice sets the sticky scope, so subsequent
/// entries reuse it silently (zero taps from then on).
class BlockScopePickerScaffold extends ConsumerWidget {
  const BlockScopePickerScaffold({
    super.key,
    required this.title,
    required this.seasonId,
    required this.candidates,
  });

  final String title;
  final String seasonId;
  final List<BlockView> candidates;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView.builder(
      key: const Key('block-scope-picker'),
      itemCount: candidates.length,
      itemBuilder: (context, i) {
        final block = candidates[i];
        return ListTile(
          key: Key('block-scope-pick-${block.id}'),
          title: Text('Block ${block.number}'),
          onTap: () => ref
              .read(activeBlockProvider.notifier)
              .set(seasonId: seasonId, blockId: block.id),
        );
      },
    ),
  );
}

/// Maps a resolution failure to its stable problem `code` for
/// [BlockScopeErrorScaffold]. Non-`ProblemError` failures (transport
/// breakdowns surfacing raw) report as `unknown`.
String blockScopeErrorCode(Object error) =>
    error is ProblemError ? error.code : 'unknown';
