// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

import 'package:flutter/material.dart';

import '../../l10n/app_localizations_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../design/material_icons.dart';
import 'planning_location.dart';

/// Production [PlanningLocationCopy] adapter over the generated
/// localizations (the ladder itself stays tier-1 pure — see
/// `planning_location.dart`).
class L10nPlanningLocationCopy implements PlanningLocationCopy {
  const L10nPlanningLocationCopy(this.l10n);

  final AppLocalizations l10n;

  @override
  String seasonLabel(String? title, int number) =>
      title ?? l10n.seasonsDefaultTitle('$number');

  @override
  String blockLabel(int number) => l10n.blockTileLabel('$number');

  @override
  String episodeLabel(int number, String? name) =>
      name ?? l10n.episodeTileLabel('$number');

  @override
  String sceneLabel(int? sceneNumber, String? summary) =>
      summary?.isNotEmpty == true
      ? summary!
      : l10n.sceneTileLabel('${sceneNumber ?? ''}');
}

/// Glossary icon per hierarchy level (docs/design/glossary.md — context
/// segments show icon AND visible text; icons reinforce only).
IconData iconForPlanningLevel(PlanningLevel level) => switch (level) {
  PlanningLevel.season => BreakdownMaterialIcons.locationSeason,
  PlanningLevel.block => BreakdownMaterialIcons.locationBlock,
  PlanningLevel.episode => BreakdownMaterialIcons.locationEpisode,
  PlanningLevel.scene => BreakdownMaterialIcons.locationScene,
};

/// The hierarchy context strip (issue #548): renders the active route's
/// [PlanningLocation] as level segments — each segment is an icon plus a
/// VISIBLE text (glossary `categories.icon` rule: icons reinforce, text
/// always visible).
///
/// Overflow (issue #638): at most [maxSegments] trailing segments are
/// rendered (the shell passes 3 on compact, 4 on medium+; the deepest level
/// wins because it names the current screen). The rendered chain then
/// WRAPS onto as many lines as the available width requires, so a deep
/// chain shows its full path instead of losing its outermost levels — e.g.
/// `Season › Block` on the first line and `Episode` on the next. Each
/// segment carries its own trailing separator, so a wrapped line never
/// starts with a dangling `›`. A single segment too wide for the line
/// ellipsizes; the merged semantics node ALWAYS announces the full path, so
/// a `…` is never the sole carrier of the hierarchy.
class LocationStrip extends StatelessWidget {
  const LocationStrip({
    super.key,
    required this.location,
    this.maxSegments = 3,
  });

  final PlanningLocation location;

  /// Maximum rendered segments (the DEEPEST levels win); the rendered chain
  /// wraps onto as many lines as it needs.
  final int maxSegments;

  @override
  Widget build(BuildContext context) {
    final copy = L10nPlanningLocationCopy(l10nOf(context));
    final all = location.segments(copy);
    final shown = all.length <= maxSegments
        ? all
        : all.sublist(all.length - maxSegments);
    final fullLabel = l10nOf(context)
        .locationStripSemantics(location.pathLabel(copy));

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: fullLabel,
      child: _WrappingRow(key: const Key('location-strip'), segments: shown),
    );
  }
}

/// Lays the segments out as a WRAPPING breadcrumb (issue #638): the chain
/// fills the available width and continues on the next line.
///
/// The separator is the TRAILING element of each segment (except the last),
/// so a run break can never leave a `›` stranded at the start of a line —
/// the alternatives are a trailing `›` (reads as "continues below") or no
/// separator at all. No text measurement is needed: `Wrap` decides the
/// breaks, which keeps the layout honest under any text scale (the previous
/// implementation measured with `TextPainter` to decide what to DROP).
class _WrappingRow extends StatelessWidget {
  const _WrappingRow({super.key, required this.segments});

  final List<PlanningSegment> segments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    final iconColor = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kHorizontalPadding),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < segments.length; i++)
            Row(
              key: Key('location-segment-${segments[i].$1.name}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(iconForPlanningLevel(segments[i].$1), size: 14),
                const SizedBox(width: 3),
                // Flexible so a single over-wide segment ellipsizes inside
                // the line instead of overflowing it.
                Flexible(
                  child: Text(
                    segments[i].$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
                if (i < segments.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _kSeparatorIndent,
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      size: _kSeparatorWidth,
                      color: iconColor,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

const double _kHorizontalPadding = 12;
const double _kSeparatorIndent = 2;
const double _kSeparatorWidth = 16;
