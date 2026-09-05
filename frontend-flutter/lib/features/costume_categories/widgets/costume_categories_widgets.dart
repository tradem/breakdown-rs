// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter/material.dart';

import '../../../domain/reconciliation/reconciliation_scheduler.dart';
import '../costume_categories_state.dart';

/// Pure presentation trees for `CostumeCategoriesScreen`: plain data +
/// callbacks in, widgets out — no Riverpod imports, theme roles only,
/// semantic labels for `find.text`-paired tests.
class CostumeCategoryTile extends StatelessWidget {
  const CostumeCategoryTile({
    super.key,
    required this.row,
    this.onRename,
    this.onArchive,
  });

  final CostumeCategoryRow row;
  final VoidCallback? onRename;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) => switch (row) {
    ProjectedCostumeCategoryRow(:final category) => Semantics(
      label: 'Category ${category.name}',
      child: ListTile(
        key: Key('category-${category.id}'),
        minTileHeight: 48,
        title: Text(category.name),
        subtitle: category.archived ? const Text('Archived') : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onRename != null)
              IconButton(
                key: Key('category-rename-${category.id}'),
                icon: const Icon(Icons.edit),
                tooltip: 'Rename',
                onPressed: onRename,
              ),
            if (onArchive != null && !category.archived)
              IconButton(
                key: Key('category-archive-${category.id}'),
                icon: const Icon(Icons.archive_outlined),
                tooltip: 'Archive',
                onPressed: onArchive,
              ),
          ],
        ),
      ),
    ),
    OptimisticCostumeCategoryRow(:final overlay) => ListTile(
      key: Key('overlay-${overlay.id}'),
      minTileHeight: 48,
      title: Text(overlay.name ?? ''),
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

class CostumeCategoriesEmptyView extends StatelessWidget {
  const CostumeCategoriesEmptyView({
    super.key,
    required this.canCreate,
    this.onCreate,
  });

  final bool canCreate;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'No categories yet',
          key: const Key('categories-empty'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (canCreate)
          FilledButton.tonal(
            key: const Key('categories-empty-create'),
            onPressed: onCreate,
            child: const Text('Create the first category'),
          ),
      ],
    ),
  );
}

class CostumeCategoriesNotFoundView extends StatelessWidget {
  const CostumeCategoriesNotFoundView({
    super.key,
    required this.code,
    this.onBack,
  });

  final String code;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      key: const Key('categories-not-found'),
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
          key: const Key('categories-not-found-back'),
          onPressed: onBack,
          child: const Text('Back to seasons'),
        ),
      ],
    ),
  );
}
