// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import '../costume_categories/next_order_key.dart';
import 'order_keys.dart';
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
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreateShootingDaySheet(episode: episode),
    );
  }

  Future<void> _showRenameSheet(
    BuildContext context,
    WidgetRef ref,
    ShootingDayView day,
  ) {
    return showDialog<void>(
      context: context,
      builder: (_) => _RenameShootingDaySheet(episode: episode, day: day),
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    WidgetRef ref,
    ShootingDayView day,
  ) async {
    final picked = await showDatePicker(
      context: context,
      // Start on the day's date when set (Material-localized picker);
      // unset days start today.
      initialDate: day.date == null
          ? DateTime.now()
          : DateTime(day.date!.year, day.date!.month, day.date!.day),
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
          'The calendar date is removed. The day keeps its order and '
          'label.',
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

  /// Reorder: issues a single new key strictly between the target
  /// neighbors (midpoint rule — never an append that duplicates or skips
  /// keys). When no valid key fits (dense floor, see `midpointKey`), no
  /// command issues and an explanatory copy renders instead of corrupting
  /// the total order.
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
    final from = days.indexWhere((d) => d.id == day.id);
    if (from < 0) return;
    final to = (from + delta).clamp(0, days.length - 1);
    if (to == from) return;
    final others = [...days]..removeAt(from);
    final insertAt = to.clamp(0, others.length);
    final lo = insertAt > 0 ? others[insertAt - 1].orderKey : null;
    final hi = insertAt < others.length ? others[insertAt].orderKey : null;
    final String orderKey;
    if (lo != null && hi != null) {
      final mid = midpointKey(lo, hi);
      if (mid == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cannot move here — the neighboring order keys leave no '
              'room. Archive or recreate days to rebalance.',
            ),
          ),
        );
        return;
      }
      orderKey = mid;
    } else if (hi != null) {
      // Prepend edge: midpoint below the first key (null only when the
      // first key sits at the alphabet floor — then the same copy).
      final mid = midpointKey('', hi);
      if (mid == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cannot move here — the neighboring order keys leave no '
              'room. Archive or recreate days to rebalance.',
            ),
          ),
        );
        return;
      }
      orderKey = mid;
    } else {
      // Append edge: the shared append rule always has room.
      orderKey = nextOrderKey([lo!]);
    }
    // Handled: failures surface via the command-error provider.
    final reorderResult = await ref
        .read(shootingDaysControllerProvider(episode.id).notifier)
        .reorder(day: day, orderKey: orderKey);
    reorderResult.match<void>((_) {}, (_) {});
  }
}

/// Create-sheet content: owns its controllers in widget state so they
/// dispose exactly when the sheet unmounts (a `whenComplete` chain would
/// race the sheet's exit transition, which rebuilds fields after the
/// sheet future completes).
class _CreateShootingDaySheet extends ConsumerStatefulWidget {
  const _CreateShootingDaySheet({required this.episode});

  final EpisodeView episode;

  @override
  ConsumerState<_CreateShootingDaySheet> createState() =>
      _CreateShootingDaySheetState();
}

class _CreateShootingDaySheetState
    extends ConsumerState<_CreateShootingDaySheet> {
  late final TextEditingController _label;
  late final GlobalKey<FormState> _formKey;
  Date? _date;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController();
    _formKey = GlobalKey<FormState>();
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Create shooting day',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextFormField(
              key: const Key('create-shooting-day-label'),
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Label (e.g. 1. Tag)',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _date == null ? 'No date yet' : 'Date: $_date',
                    key: const Key('create-shooting-day-date-text'),
                  ),
                ),
                TextButton(
                  key: const Key('create-shooting-day-date-pick'),
                  onPressed: () async {
                    // Material date utilities localize the picker (no
                    // hand-rolled date math for locale — spec §5).
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() => _date = picked.toDate());
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
                      shootingDaysControllerProvider(widget.episode.id)
                          .notifier,
                    )
                    .create(
                      label: _label.text.trim().isEmpty
                          ? null
                          : _label.text.trim(),
                      date: _date,
                    );
                createResult.match<void>((_) {}, (_) {});
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Rename-dialog content: owns its controller in widget state (same
/// dispose discipline as [_CreateShootingDaySheet]).
class _RenameShootingDaySheet extends ConsumerStatefulWidget {
  const _RenameShootingDaySheet({required this.episode, required this.day});

  final EpisodeView episode;
  final ShootingDayView day;

  @override
  ConsumerState<_RenameShootingDaySheet> createState() =>
      _RenameShootingDaySheetState();
}

class _RenameShootingDaySheetState
    extends ConsumerState<_RenameShootingDaySheet> {
  late final TextEditingController _label;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.day.label ?? '');
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename shooting day'),
    content: TextField(
      key: const Key('rename-shooting-day-label'),
      controller: _label,
      decoration: const InputDecoration(labelText: 'Label'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('rename-shooting-day-submit'),
        onPressed: () async {
          // Handled: failures surface via the command-error provider.
          final renameResult = await ref
              .read(shootingDaysControllerProvider(widget.episode.id).notifier)
              .rename(
                day: widget.day,
                label: _label.text.trim().isEmpty ? null : _label.text.trim(),
              );
          renameResult.match<void>((_) {}, (_) {});
          if (context.mounted) Navigator.of(context).pop();
        },
        child: const Text('Rename'),
      ),
    ],
  );
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
