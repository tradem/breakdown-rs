// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations_provider.dart';

/// The labelled app-bar action that pushes the aggregated Soll-Ist screen
/// (issue #571): shared by the season-level entry (blocks screen,
/// season scope) and the episode-level entry (report index, episode
/// scope). A LABELLED control per the glossary visible-label norm — a
/// `TextButton.icon` at realistic widths, collapsing into a LABELLED
/// overflow item when the app bar is too narrow to carry the label next to
/// a readable title. Never a bare icon: the entry must be findable without
/// hover (the #549 norm).
///
/// The Gherkin contract key sits on the tap target in BOTH branches and the
/// overflow item is `<baseKey>-overflow-item`, so the same two-step
/// discipline as the day-board and index entries applies.
class ReportsAggregateAppBarAction extends StatelessWidget {
  const ReportsAggregateAppBarAction({
    super.key,
    required this.baseKey,
    required this.roomForLabel,
    required this.onOpen,
  });

  /// The contract key for the tap target (both branches).
  final String baseKey;

  /// Whether the app bar has room for the visible label (`true` at
  /// realistic widths; `false` collapses into the labelled overflow item).
  final bool roomForLabel;

  final VoidCallback onOpen;

  static const _icon = Icon(Icons.analytics_outlined);

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final label = l10n.shootingDaysReportsAggregateLabel;
    if (roomForLabel) {
      // No tooltip: the label is already visible (same rationale as #549).
      return TextButton.icon(
        key: Key(baseKey),
        onPressed: onOpen,
        icon: _icon,
        label: Text(label),
      );
    }
    // The item carries an explicit value, not `void`: a
    // `PopupMenuItem<void>` silently never invokes
    // `PopupMenuButton.onSelected` (verified in #549), which would leave
    // the overflow entry inert.
    return PopupMenuButton<_AggregateReportsMenuAction>(
      key: Key(baseKey),
      tooltip: label,
      icon: const Icon(Icons.more_vert),
      onSelected: (_) => onOpen(),
      itemBuilder: (context) => [
        PopupMenuItem<_AggregateReportsMenuAction>(
          key: Key('$baseKey-overflow-item'),
          value: _AggregateReportsMenuAction.open,
          // A Row, not a ListTile: `PopupMenuItem` is a fixed-height box,
          // and a ListTile inside it is not laid out to fit.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _icon,
              const SizedBox(width: 12),
              Flexible(child: Text(label)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Single action of the aggregate-reports overflow fallback (see
/// [ReportsAggregateAppBarAction]).
enum _AggregateReportsMenuAction { open }
