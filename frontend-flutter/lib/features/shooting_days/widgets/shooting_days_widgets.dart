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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onMoveUp != null)
              IconButton(
                key: Key('shooting-day-up-${day.id}'),
                icon: const Icon(Icons.arrow_upward),
                tooltip: 'Move earlier',
                onPressed: onMoveUp,
              ),
            if (onMoveDown != null)
              IconButton(
                key: Key('shooting-day-down-${day.id}'),
                icon: const Icon(Icons.arrow_downward),
                tooltip: 'Move later',
                onPressed: onMoveDown,
              ),
            if (onRename != null)
              IconButton(
                key: Key('shooting-day-rename-${day.id}'),
                icon: const Icon(Icons.edit),
                tooltip: 'Rename',
                onPressed: onRename,
              ),
            if (onReschedule != null)
              IconButton(
                key: Key('shooting-day-reschedule-${day.id}'),
                icon: const Icon(Icons.calendar_month),
                tooltip: 'Reschedule',
                onPressed: onReschedule,
              ),
            if (onUnschedule != null && day.date != null)
              IconButton(
                key: Key('shooting-day-unschedule-${day.id}'),
                icon: const Icon(Icons.event_busy),
                tooltip: 'Unschedule',
                onPressed: onUnschedule,
              ),
            if (onArchive != null && !day.archived)
              IconButton(
                key: Key('shooting-day-archive-${day.id}'),
                icon: const Icon(Icons.archive_outlined),
                tooltip: 'Archive',
                onPressed: onArchive,
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
