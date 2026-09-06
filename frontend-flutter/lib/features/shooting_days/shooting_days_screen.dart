// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import 'shooting_days_controller.dart';
import 'shooting_days_state.dart';
import 'widgets/shooting_days_widgets.dart';

/// `ShootingDaysScreen` — the episode's shooting days in server
/// `order_key ASC` (the client never re-sorts).
///
/// Entered from the episode context with the parent [EpisodeView]; create
/// derives the append `order_key` (`Manual` source); updates are
/// single-intent (reorder / reschedule+unschedule / rename — one PATCH per
/// action); archive reconciles via the bounded refetch. The Soll/Ist
/// execution UI is out of scope (own change).
class ShootingDaysScreen extends ConsumerWidget {
  const ShootingDaysScreen({super.key, required this.episode});

  final EpisodeView episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authSessionControllerProvider, (_, session) {
      final signedOut =
          (session is AsyncData && session.value == null) ||
          session is AsyncError;
      if (signedOut && context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    final state = ref.watch(shootingDaysControllerProvider(episode.id));
    final controller = ref.read(
      shootingDaysControllerProvider(episode.id).notifier,
    );
    final rows = state.rows;
    final notFound = state.notFound;

    return Scaffold(
      appBar: AppBar(title: const Text('Shooting days')),
      body: Column(
        children: [
          if (state.commandError case final error?)
            _Banner(
              key: const Key('shooting-day-command-error-banner'),
              text: shootingDayErrorCopy(error),
              onDismiss: controller.dismissCommandError,
            ),
          if (state.isStale && notFound == null)
            const _Banner(
              key: Key('shooting-days-stale-banner'),
              text: 'Cached data may be outdated',
            ),
          Expanded(
            child: notFound != null
                ? ShootingDaysNotFoundView(
                    code: notFound.code,
                    onBack: () => Navigator.of(context).pop(),
                  )
                : RefreshIndicator(
                    onRefresh: controller.refresh,
                    child: switch (state.projected) {
                      AsyncLoading() when rows.isEmpty => const Center(
                        child: CircularProgressIndicator(
                          key: Key('shooting-days-loading'),
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
                                key: const Key('shooting-days-list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 160),
                                  ShootingDaysEmptyView(
                                    onCreate: _canCreate(ref)
                                        ? () => _showCreateSheet(context, ref)
                                        : null,
                                  ),
                                ],
                              )
                            : ListView.builder(
                                key: const Key('shooting-days-list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: rows.length,
                                itemBuilder: (context, i) {
                                  final row = rows[i];
                                  return ShootingDayTile(
                                    row: row,
                                    onRename: row is ProjectedShootingDayRow
                                        ? () => _showRenameSheet(
                                            context,
                                            ref,
                                            row.day,
                                          )
                                        : null,
                                    onReschedule: row is ProjectedShootingDayRow
                                        ? () => _pickDate(context, ref, row.day)
                                        : null,
                                    onUnschedule: row is ProjectedShootingDayRow
                                        ? () => _confirmUnschedule(
                                            context,
                                            ref,
                                            row.day,
                                          )
                                        : null,
                                    onArchive: row is ProjectedShootingDayRow
                                        ? () => _confirmArchive(
                                            context,
                                            ref,
                                            row.day,
                                          )
                                        : null,
                                    onMoveUp:
                                        row is ProjectedShootingDayRow && i > 0
                                        ? () => _move(context, ref, rows, i, -1)
                                        : null,
                                    onMoveDown:
                                        row is ProjectedShootingDayRow &&
                                            i < rows.length - 1 &&
                                            rows[i + 1]
                                                is ProjectedShootingDayRow
                                        ? () => _move(context, ref, rows, i, 1)
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
              key: const Key('shooting-day-add-fab'),
              onPressed: () => _showCreateSheet(context, ref),
              tooltip: 'Create shooting day',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  bool _canCreate(WidgetRef ref) {
    final session = ref.watch(authSessionControllerProvider);
    return session is AsyncData && session.value != null;
  }

  Future<void> _showCreateSheet(BuildContext context, WidgetRef ref) {
    final labelController = TextEditingController();
    Date? date;
    final formKey = GlobalKey<FormState>();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Create shooting day',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextFormField(
                    key: const Key('create-shooting-day-label'),
                    controller: labelController,
                    decoration: const InputDecoration(
                      labelText: 'Label (e.g. 1. Tag)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          date == null ? 'No date yet' : 'Date: $date',
                          key: const Key('create-shooting-day-date-text'),
                        ),
                      ),
                      TextButton(
                        key: const Key('create-shooting-day-date-pick'),
                        onPressed: () async {
                          // Material date utilities localize the picker (no
                          // hand-rolled date math for locale — spec §5).
                          final picked = await showDatePicker(
                            context: sheetContext,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setSheetState(() => date = picked.toDate());
                          }
                        },
                        child: const Text('Pick date'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('create-shooting-day-submit'),
                    onPressed: () async {
                      // Handled: failures surface via the command-error
                      // provider (keyed copy in the screen).
                      final createResult = await ref
                          .read(
                            shootingDaysControllerProvider(episode.id).notifier,
                          )
                          .create(
                            label: labelController.text.trim().isEmpty
                                ? null
                                : labelController.text.trim(),
                            date: date,
                          );
                      createResult.match<void>((_) {}, (_) {});
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                    },
                    child: const Text('Create'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showRenameSheet(
    BuildContext context,
    WidgetRef ref,
    ShootingDayView day,
  ) {
    final labelController = TextEditingController(text: day.label ?? '');
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename shooting day'),
        content: TextField(
          key: const Key('rename-shooting-day-label'),
          controller: labelController,
          decoration: const InputDecoration(labelText: 'Label'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('rename-shooting-day-submit'),
            onPressed: () async {
              // Handled: failures surface via the command-error provider.
              final renameResult = await ref
                  .read(shootingDaysControllerProvider(episode.id).notifier)
                  .rename(
                    day: day,
                    label: labelController.text.trim().isEmpty
                        ? null
                        : labelController.text.trim(),
                  );
              renameResult.match<void>((_) {}, (_) {});
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    WidgetRef ref,
    ShootingDayView day,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !context.mounted) return;
    // Handled: failures surface via the command-error provider.
    final rescheduleResult = await ref
        .read(shootingDaysControllerProvider(episode.id).notifier)
        .reschedule(day: day, date: picked.toDate());
    rescheduleResult.match<void>((_) {}, (_) {});
  }

  Future<void> _confirmUnschedule(
    BuildContext context,
    WidgetRef ref,
    ShootingDayView day,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unschedule date?'),
        content: const Text(
          'The calendar date is cleared (`date: null`); the day keeps its '
          'order and label.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: Key('shooting-day-unschedule-confirm-${day.id}'),
            onPressed: () async {
              // Handled: failures surface via the command-error provider.
              final unscheduleResult = await ref
                  .read(shootingDaysControllerProvider(episode.id).notifier)
                  .unschedule(day: day);
              unscheduleResult.match<void>((_) {}, (_) {});
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Unschedule'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmArchive(
    BuildContext context,
    WidgetRef ref,
    ShootingDayView day,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive shooting day?'),
        content: const Text(
          'Archived days stay in the projection but hide from scheduling '
          'pickers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: Key('shooting-day-archive-confirm-${day.id}'),
            onPressed: () async {
              // Handled: failures surface via the command-error provider.
              final archiveResult = await ref
                  .read(shootingDaysControllerProvider(episode.id).notifier)
                  .archive(day: day);
              archiveResult.match<void>((_) {}, (_) {});
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  /// Reorder: issues a single new key derived from the read model's neighbor
  /// keys (append rule over the visible order — the server owns the order).
  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    List<ShootingDayRow> rows,
    int index,
    int delta,
  ) async {
    final days = [
      for (final r in rows)
        if (r is ProjectedShootingDayRow) r.day,
    ];
    final day = (rows[index] as ProjectedShootingDayRow).day;
    final neighborKeys = [for (final d in days) d.orderKey];
    // Neighbor-key reorder: derive an append-after-neighbor key with the
    // shared rule over the keys up to the target position.
    final target = (index + delta).clamp(0, neighborKeys.length - 1);
    final prefix = target < index
        ? neighborKeys.sublist(0, target + 1)
        : neighborKeys.sublist(0, target + 1);
    final orderKey = _reorderKey(prefix, day.orderKey);
    // Handled: failures surface via the command-error provider.
    final reorderResult = await ref
        .read(shootingDaysControllerProvider(episode.id).notifier)
        .reorder(day: day, orderKey: orderKey);
    reorderResult.match<void>((_) {}, (_) {});
  }

  /// Derives a single new key strictly inside the neighbor prefix (append
  /// rule — insertion is append-only by construction).
  String _reorderKey(List<String> prefix, String current) {
    final without = prefix.where((k) => k != current).toList();
    return _nextKey(without);
  }

  String _nextKey(List<String> keys) {
    var greatest = '';
    var found = false;
    for (final key in keys) {
      if (!found || key.compareTo(greatest) > 0) {
        greatest = key;
        found = true;
      }
    }
    if (!found) return '!';
    final units = greatest.codeUnits;
    final last = units.last;
    if (last >= 0x7E) return '$greatest!';
    return String.fromCharCodes([
      ...units.sublist(0, units.length - 1),
      last + 1,
    ]);
  }
}

class _FetchErrorView extends StatelessWidget {
  const _FetchErrorView({required this.code, this.onRetry});

  final String code;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('shooting-days-error'),
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 160),
      Center(child: Text('Could not load shooting days ($code).')),
      const SizedBox(height: 8),
      Center(
        child: FilledButton.tonal(
          key: const Key('shooting-days-retry'),
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
              IconButton(
                onPressed: onDismiss,
                color: scheme.onErrorContainer,
                tooltip: 'Dismiss',
                icon: const Icon(
                  Icons.close,
                  key: Key('shooting-day-command-error-dismiss'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
