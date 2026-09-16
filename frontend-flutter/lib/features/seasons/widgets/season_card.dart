// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:flutter/material.dart';

/// One season rendered as a Material 3 card (`redesign-seasons-home`
/// task 3.1 — pure presentation: no Riverpod, no domain branching).
///
/// Visual contract (glossary + screen spec `seasons-home`):
/// * title: season name or fallback "Season {number}" (caller resolves);
/// * metadata line: cached counts ("3 Blöcke · 42 Szenen · 118 Kostüme"),
///   omitted entirely when `metadata` is `null` — never fabricated;
/// * stale indicator: the `history` icon (glossary `seasons.stale`) plus
///   the caller-computed relative-time label ("Stand: vor 2 h"), rendered
///   only when the caller resolved a stale cache entry (D2: per-card
///   timestamp, not a banner; the label is computed with the injectable
///   clock upstream so goldens stay deterministic);
/// * trailing: the drill-down chevron, or the caller's overlay trailing
///   (sync spinner / cloud-off warning) for optimistic rows.
///
/// Card variant (D3): `Card.outlined` on light surfaces, `Card.filled`
/// in dark — resolved by [AppCards.variant], the single theme-level
/// decision point; colors are the M3 theme's, never hardcoded.
class SeasonCard extends StatelessWidget {
  const SeasonCard({
    super.key,
    required this.title,
    this.metadata,
    this.staleLabel,
    this.trailing,
    this.onTap,
  });

  final String title;

  /// Supporting text (cached counts line, or an overlay's status copy);
  /// `null` omits the line entirely (no cached metadata → no line).
  final String? metadata;

  /// Relative staleness label ("Stand: vor 2 h") or `null` when the
  /// metadata is fresh / absent.
  final String? staleLabel;

  /// Trailing affordance override (overlay spinner / warning icon);
  /// defaults to the drill-down chevron.
  final Widget? trailing;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasStale = staleLabel != null;
    final supporting = metadata;
    Widget? subtitle;
    if (supporting != null || hasStale) {
      subtitle = Row(
        children: [
          if (hasStale) ...[
            Icon(Icons.history, size: 16, color: scheme.tertiary),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text([?supporting, if (hasStale) staleLabel!].join('  ·  ')),
          ),
        ],
      );
    }

    return Semantics(
      label: _semanticLabel,
      button: onTap != null,
      child: AppCards.variant(
        brightness: Theme.of(context).brightness,
        child: ListTile(
          title: Text(title),
          subtitle: subtitle,
          trailing: trailing ?? const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }

  String get _semanticLabel {
    final parts = [
      title,
      ?metadata,
      if (staleLabel != null) '$staleLabel (veraltet)',
    ];
    return parts.join(', ');
  }
}

/// Card variant resolution (D3): ONE theme-level decision point — light
/// surfaces use the outlined card, dark surfaces the filled card. Colors
/// are the theme's own (no hardcoded values); the widgets stay free of
/// per-widget brightness branching.
abstract final class AppCards {
  static Widget variant({
    required Brightness brightness,
    required Widget child,
  }) => switch (brightness) {
    Brightness.light => Card.outlined(child: child),
    Brightness.dark => Card.filled(child: child),
  };
}
