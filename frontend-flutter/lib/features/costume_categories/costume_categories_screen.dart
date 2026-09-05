// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import 'costume_categories_controller.dart';
import 'costume_categories_state.dart';
import 'widgets/costume_categories_widgets.dart';

/// Localized client-side copy for category command failures, keyed on the
/// stable problem `code` (never the server's localized `detail`).
String costumeCategoryErrorCopy(ProblemError error) => switch (error.code) {
  'costume_category.conflict' ||
  'costume_categories.conflict' => 'A category with that name already exists.',
  'costume_category.version_conflict' ||
  'concurrency.conflict' => 'Changed elsewhere — refresh and try again.',
  'authz.denied' || 'auth.session_required' => 'Please sign in to continue.',
  _ when error.code.startsWith('transport.') =>
    'Network problem — the change was not saved. Try again.',
  _ => 'The category could not be saved (${error.code}).',
};

/// `CostumeCategoriesScreen` — the season's costume-category vocabulary
/// ordered ascending by `order_key` (server `ORDER BY order_key ASC`).
///
/// Entered from the season context with the parent [SeasonView]; archived
/// categories hide behind an explicit toggle (default off); rename echoes
/// the read row's `version`; archive reconciles via the bounded refetch.
class CostumeCategoriesScreen extends ConsumerWidget {
  const CostumeCategoriesScreen({super.key, required this.season});

  final SeasonView season;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 7.2: sign-out mid-navigation returns to the login gate (see
    // BlocksScreen for the rationale).
    ref.listen(authSessionControllerProvider, (_, session) {
      final signedOut =
          (session is AsyncData && session.value == null) ||
          session is AsyncError;
      if (signedOut && context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    final state = ref.watch(costumeCategoriesControllerProvider(season.id));
    final controller = ref.read(
      costumeCategoriesControllerProvider(season.id).notifier,
    );
    final rows = state.rows;
    final notFound = state.notFound;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Costume categories'),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Archived'),
              Switch(
                key: const Key('categories-archived-toggle'),
                value: state.showArchived,
                onChanged: (_) => controller.toggleArchivedVisibility(),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.commandError case final error?)
            _Banner(
              key: const Key('category-command-error-banner'),
              text: costumeCategoryErrorCopy(error),
              onDismiss: controller.dismissCommandError,
            ),
          if (state.isStale && notFound == null)
            const _Banner(
              key: Key('categories-stale-banner'),
              text: 'Cached data may be outdated',
            ),
          Expanded(
            child: notFound != null
                ? CostumeCategoriesNotFoundView(
                    code: notFound.code,
                    onBack: () => Navigator.of(context).pop(),
                  )
                : RefreshIndicator(
                    onRefresh: controller.refresh,
                    child: switch (state.projected) {
                      AsyncLoading() when rows.isEmpty => const Center(
                        child: CircularProgressIndicator(
                          key: Key('categories-loading'),
                        ),
                      ),
                      AsyncError(:final error) when rows.isEmpty =>
                        _FetchErrorView(
                          code: error is ProblemError ? error.code : 'unknown',
                          onRetry: () => controller.refresh(),
                        ),
                      _ =>
                        rows.isEmpty
                            ? ListView(
                                key: const Key('categories-list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 160),
                                  CostumeCategoriesEmptyView(
                                    canCreate: _canCreate(ref),
                                    onCreate: () =>
                                        _showCreateDialog(context, ref),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                key: const Key('categories-list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: rows.length,
                                itemBuilder: (context, i) {
                                  final row = rows[i];
                                  return CostumeCategoryTile(
                                    row: row,
                                    onRename: row is ProjectedCostumeCategoryRow
                                        ? () => _showRenameDialog(
                                            context,
                                            ref,
                                            row.category,
                                          )
                                        : null,
                                    onArchive:
                                        row is ProjectedCostumeCategoryRow
                                        ? () => _confirmArchive(
                                            context,
                                            ref,
                                            row.category,
                                          )
                                        : null,
                                  );
                                },
                              ),
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _canCreate(ref)
          ? FloatingActionButton(
              key: const Key('category-add-fab'),
              onPressed: () => _showCreateDialog(context, ref),
              tooltip: 'Add category',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  bool _canCreate(WidgetRef ref) {
    final session = ref.watch(authSessionControllerProvider);
    return session is AsyncData && session.value != null;
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create category'),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: const Key('create-category-name'),
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'A name is required' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('create-category-submit'),
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final result = await ref
                  .read(costumeCategoriesControllerProvider(season.id).notifier)
                  .create(name: nameController.text.trim());
              result.match<void>((_) {}, (_) {});
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    CostumeCategoryView category,
  ) {
    final nameController = TextEditingController(text: category.name);
    final formKey = GlobalKey<FormState>();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename category'),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: const Key('rename-category-name'),
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'A name is required' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('rename-category-submit'),
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final result = await ref
                  .read(costumeCategoriesControllerProvider(season.id).notifier)
                  .rename(category: category, name: nameController.text.trim());
              result.match<void>((_) {}, (_) {});
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmArchive(
    BuildContext context,
    WidgetRef ref,
    CostumeCategoryView category,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive category?'),
        content: Text(
          '"${category.name}" will be hidden from the active vocabulary. '
          'Use the Archived toggle to reveal it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('archive-category-confirm'),
            onPressed: () async {
              final result = await ref
                  .read(costumeCategoriesControllerProvider(season.id).notifier)
                  .archive(category: category);
              result.match<void>((_) {}, (_) {});
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }
}

class _FetchErrorView extends StatelessWidget {
  const _FetchErrorView({required this.code, this.onRetry});

  final String code;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('categories-error'),
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 160),
      Center(child: Text('Could not load categories ($code).')),
      const SizedBox(height: 8),
      Center(
        child: FilledButton.tonal(
          key: const Key('categories-retry'),
          onPressed: onRetry,
          child: const Text('Retry'),
        ),
      ),
    ],
  );
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text, this.onDismiss});

  final String text;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            if (onDismiss != null)
              GestureDetector(
                onTap: onDismiss,
                child: IconTheme(
                  data: IconThemeData(color: scheme.onErrorContainer),
                  child: const Icon(
                    Icons.close,
                    key: Key('category-command-error-dismiss'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
