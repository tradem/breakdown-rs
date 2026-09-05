// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter/material.dart';

import '../../../domain/reconciliation/reconciliation_scheduler.dart';
import '../blocks_state.dart';

/// Pure presentation trees for `BlocksScreen` (seasons reference pattern):
/// plain data + callbacks in, widgets out — no Riverpod imports, theme
/// roles + design tokens only, semantic labels for `find.text`-paired tests.
class BlockTile extends StatelessWidget {
  const BlockTile({super.key, required this.row, this.onTap});

  final BlockRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => switch (row) {
    ProjectedBlockRow(:final block) => Semantics(
      label: 'Block ${block.number}',
      child: ListTile(
        key: Key('block-${block.id}'),
        minTileHeight: 48,
        title: Text('Block ${block.number}'),
        subtitle: Text('${block.startDate} – ${block.endDate}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    ),
    OptimisticBlockRow(:final overlay) => ListTile(
      key: Key('overlay-${overlay.id}'),
      minTileHeight: 48,
      title: Text('Block ${overlay.number ?? ''}'),
      subtitle: Text(
        overlay.status == OverlayStatus.stale
            ? (overlay.warning ?? kReconcileStaleWarning)
            : 'Just created — syncing…',
      ),
      trailing: overlay.status == OverlayStatus.stale
          ? const Icon(Icons.cloud_off, key: Key('overlay-warning'))
          : const SizedBox(
              key: Key('overlay-spinner'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
    ),
  };
}

/// Plain-language empty state with the create call to action (session-gated
/// by the caller via [canCreate]).
class BlocksEmptyView extends StatelessWidget {
  const BlocksEmptyView({super.key, required this.canCreate, this.onCreate});

  final bool canCreate;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'No blocks yet',
          key: const Key('blocks-empty'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (canCreate)
          FilledButton.tonal(
            key: const Key('blocks-empty-create'),
            onPressed: onCreate,
            child: const Text('Create the first block'),
          ),
      ],
    ),
  );
}

/// 404 narrative for a deleted parent (D5): no fabricated rows, back
/// affordance pops to the parent list.
class BlocksNotFoundView extends StatelessWidget {
  const BlocksNotFoundView({super.key, required this.code, this.onBack});

  final String code;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      key: const Key('blocks-not-found'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.search_off, size: 48),
        const SizedBox(height: 8),
        Text(
          'This season no longer exists ($code).',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const Key('blocks-not-found-back'),
          onPressed: onBack,
          child: const Text('Back to seasons'),
        ),
      ],
    ),
  );
}
