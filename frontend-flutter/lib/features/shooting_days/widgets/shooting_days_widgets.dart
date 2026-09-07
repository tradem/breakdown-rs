// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter/material.dart';

import '../../../domain/reconciliation/reconciliation_scheduler.dart';
import '../shooting_days_state.dart';

/// Pure presentation trees for `ShootingDaysScreen`: plain data + callbacks
/// in, widgets out — no Riverpod imports, theme roles only, semantic labels
/// for `find.text`-paired tests. Rendering uses the server order exactly
/// (no client re-sort).
class ShootingDayTile extends StatelessWidget {
  const ShootingDayTile({
    super.key,
    required this.row,
    this.onRename,
    this.onReschedule,
    this.onUnschedule,
    this.onArchive,
    this.onMoveUp,
    this.onMoveDown,
  });

  final ShootingDayRow row;
  final VoidCallback? onRename;
  final VoidCallback? onReschedule;
  final VoidCallback? onUnschedule;
  final VoidCallback? onArchive;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) => switch (row) {
    ProjectedShootingDayRow(:final day) => Semantics(
      label: 'Shooting day ${day.label ?? day.id}',
      child: ListTile(
        key: Key('shooting-day-${day.id}'),
        minTileHeight: 48,
        // Compact date/label calendar-row layout on Android (spec §5).
        title: Text(
          day.label ?? 'Untitled day',
          key: Key('shooting-day-label-${day.id}'),
        ),
        subtitle: Text(
          [
            if (day.date != null) 'Date: ${day.date}',
            if (day.archived) 'Archived',
            if (day.wrappedAt != null) 'Wrapped',
          ].join(' · '),
        ),
        // Overflow menu (not six inline buttons): six 48×48 targets
        // consume the full 288 px content width of a 320 px tile, leaving
        // no title space. One menu button keeps the calendar row compact;
        // Escape closes the menu (macOS). Item keys stay stable for tests.
        trailing: PopupMenuButton<VoidCallback>(
          key: Key('shooting-day-menu-${day.id}'),
          tooltip: 'Day actions',
          icon: const Icon(Icons.more_vert),
          onSelected: (action) => action(),
          itemBuilder: (_) => [
            if (onMoveUp != null)
              PopupMenuItem(
                key: Key('shooting-day-up-${day.id}'),
                value: onMoveUp,
                child: const Text('Move earlier'),
              ),
            if (onMoveDown != null)
              PopupMenuItem(
                key: Key('shooting-day-down-${day.id}'),
                value: onMoveDown,
                child: const Text('Move later'),
              ),
            if (onRename != null)
              PopupMenuItem(
                key: Key('shooting-day-rename-${day.id}'),
                value: onRename,
                child: const Text('Rename'),
              ),
            if (onReschedule != null)
              PopupMenuItem(
                key: Key('shooting-day-reschedule-${day.id}'),
                value: onReschedule,
                child: const Text('Reschedule'),
              ),
            if (onUnschedule != null && day.date != null)
              PopupMenuItem(
                key: Key('shooting-day-unschedule-${day.id}'),
                value: onUnschedule,
                child: const Text('Unschedule date'),
              ),
            if (onArchive != null && !day.archived)
              PopupMenuItem(
                key: Key('shooting-day-archive-${day.id}'),
                value: onArchive,
                child: const Text('Archive'),
              ),
          ],
        ),
      ),
    ),
    OptimisticShootingDayRow(:final overlay) => ListTile(
      key: Key('overlay-${overlay.id}'),
      minTileHeight: 48,
      title: Text(overlay.label ?? 'New shooting day'),
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

class ShootingDaysEmptyView extends StatelessWidget {
  const ShootingDaysEmptyView({super.key, this.onCreate});

  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.calendar_month_outlined, size: 48),
        const SizedBox(height: 8),
        const Text('No shooting days yet', key: Key('shooting-days-empty')),
        if (onCreate != null) ...[
          const SizedBox(height: 8),
          FilledButton.tonal(
            key: const Key('shooting-days-empty-create'),
            onPressed: onCreate,
            child: const Text('Create shooting day'),
          ),
        ],
      ],
    ),
  );
}

class ShootingDaysNotFoundView extends StatelessWidget {
  const ShootingDaysNotFoundView({super.key, required this.code, this.onBack});

  final String code;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'The episode is gone ($code).',
          key: const Key('shooting-days-gone'),
        ),
        if (onBack != null)
          FilledButton.tonal(onPressed: onBack, child: const Text('Back')),
      ],
    ),
  );
}
