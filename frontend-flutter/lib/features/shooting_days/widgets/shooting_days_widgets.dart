// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'package:flutter/material.dart';

import '../../../design/components/ai_provenance_badge.dart';
import '../../../domain/ai_provenance.dart';
import '../../../domain/reconciliation/reconciliation_scheduler.dart';
import '../../../l10n/app_localizations_provider.dart';
import '../../../l10n/locale_formatters.dart';
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
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return switch (row) {
      ProjectedShootingDayRow(:final day) => Semantics(
        label: l10n.shootingDaySemantics(day.label ?? day.id),
        child: Builder(
          builder: (_) => ListTile(
            key: Key('shooting-day-${day.id}'),
            minTileHeight: 48,
            // Provenance badge (issue #538, EU AI Act Art. 50): ONE
            // element only when the day's wire source is AI-extracted;
            // every other variant renders the plain label (no element,
            // no invented attribution). The badge scopes its test key by
            // row id so a tree-shuffled tile still fails the test.
            title: switch (dayProvenance(day.source_)) {
              AiProvenanceVariant.aiExtracted => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AiProvenanceBadge(
                    semanticKey: 'shooting-day-ai-badge-${day.id}',
                  ),
                  Flexible(
                    child: Text(
                      day.label ?? l10n.shootingDayUntitled,
                      key: Key('shooting-day-label-${day.id}'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              _ => Text(
                day.label ?? l10n.shootingDayUntitled,
                key: Key('shooting-day-label-${day.id}'),
              ),
            },
            subtitle: Text(
              [
                // Framework locale data performs the date formatting; no
                // hand-rolled locale math or fixed pattern is used.
                if (day.date != null)
                  l10n.shootingDayDate(
                    formatMediumDate(context, day.date!.toDateTime()),
                  ),
                if (day.archived) l10n.shootingDayArchived,
                if (day.wrappedAt != null) l10n.shootingDayWrapped,
              ].join(' · '),
            ),
            // Overflow menu (not six inline buttons): six 48×48 targets
            // consume the full 288 px content width of a 320 px tile, leaving
            // no title space. One menu button keeps the calendar row compact;
            // Escape closes the menu (macOS). Item keys stay stable for tests.
            trailing: PopupMenuButton<VoidCallback>(
              key: Key('shooting-day-menu-${day.id}'),
              tooltip: l10n.shootingDayActions,
              icon: const Icon(Icons.more_vert),
              onSelected: (action) => action(),
              itemBuilder: (_) => [
                if (onMoveUp != null)
                  PopupMenuItem(
                    key: Key('shooting-day-up-${day.id}'),
                    value: onMoveUp,
                    child: Text(l10n.shootingDayMoveEarlier),
                  ),
                if (onMoveDown != null)
                  PopupMenuItem(
                    key: Key('shooting-day-down-${day.id}'),
                    value: onMoveDown,
                    child: Text(l10n.shootingDayMoveLater),
                  ),
                if (onRename != null)
                  PopupMenuItem(
                    key: Key('shooting-day-rename-${day.id}'),
                    value: onRename,
                    child: Text(l10n.shootingDayRename),
                  ),
                if (onReschedule != null)
                  PopupMenuItem(
                    key: Key('shooting-day-reschedule-${day.id}'),
                    value: onReschedule,
                    child: Text(l10n.shootingDayReschedule),
                  ),
                if (onUnschedule != null && day.date != null)
                  // Ungated (issue #374): the repository now emits the
                  // explicit `{"version": N, "date": null}` body the backend
                  // requires since #372, so the affordance is fully wired.
                  PopupMenuItem(
                    key: Key('shooting-day-unschedule-${day.id}'),
                    value: onUnschedule,
                    child: Text(l10n.shootingDayUnschedule),
                  ),
                if (onArchive != null && !day.archived)
                  PopupMenuItem(
                    key: Key('shooting-day-archive-${day.id}'),
                    value: onArchive,
                    child: Text(l10n.shootingDayArchive),
                  ),
              ],
            ),
          ),
        ),
      ),
      OptimisticShootingDayRow(:final overlay) => ListTile(
        key: Key('overlay-${overlay.id}'),
        minTileHeight: 48,
        title: Text(overlay.label ?? l10n.shootingDayNew),
        subtitle: Text(
          overlay.status == OverlayStatus.stale
              // Stable warning code from the domain layer; localized here.
              ? (overlay.warning == kReconcileStaleWarningCode
                    ? l10n.reconcileStaleWarning
                    : (overlay.warning ?? l10n.reconcileStaleWarning))
              : l10n.seasonsSyncing,
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
}

class ShootingDaysEmptyView extends StatelessWidget {
  const ShootingDaysEmptyView({super.key, this.onCreate});

  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_month_outlined, size: 48),
          const SizedBox(height: 8),
          Text(l10n.shootingDaysEmpty, key: const Key('shooting-days-empty')),
          if (onCreate != null) ...[
            const SizedBox(height: 8),
            FilledButton.tonal(
              key: const Key('shooting-days-empty-create'),
              onPressed: onCreate,
              child: Text(l10n.shootingDaysCreate),
            ),
          ],
        ],
      ),
    );
  }
}

class ShootingDaysNotFoundView extends StatelessWidget {
  const ShootingDaysNotFoundView({super.key, required this.code, this.onBack});

  final String code;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.shootingDaysGone, key: const Key('shooting-days-gone')),
          if (onBack != null)
            FilledButton.tonal(onPressed: onBack, child: Text(l10n.commonBack)),
        ],
      ),
    );
  }
}
