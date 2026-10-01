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
/// Overflow: at most [maxSegments] trailing segments are rendered (the
/// shell passes 3 on compact, 4 on medium+; the deepest level wins because
/// it names the current screen). When the available width is still
/// insufficient, leading segments are dropped (never below one) and the
/// surviving texts ellipsize — the merged semantics node ALWAYS announces
/// the full path, so a `…` is never the sole carrier of the hierarchy.
class LocationStrip extends StatelessWidget {
  const LocationStrip({
    super.key,
    required this.location,
    this.maxSegments = 3,
  });

  final PlanningLocation location;

  /// Maximum rendered segments before leading segments are dropped.
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
      child: _FittingRow(
        key: const Key('location-strip'),
        copy: copy,
        segments: shown,
      ),
    );
  }
}

/// Measures the rendered segment widths against the available width and
/// drops LEADING segments (never below one) until the row fits — the
/// "collapse to the last segments" overflow behaviour. Text measurement is
/// synchronous TextPainter layout (deterministic, no frame pumping).
class _FittingRow extends StatelessWidget {
  const _FittingRow({super.key, required this.copy, required this.segments});

  final PlanningLocationCopy copy;
  final List<PlanningSegment> segments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    final iconColor = theme.colorScheme.onSurfaceVariant;

    return LayoutBuilder(
      builder: (context, constraints) {
        var kept = segments;
        while (kept.length > 1 &&
            _measureWidth(context, kept, style) >
                constraints.maxWidth - _kHorizontalPadding * 2) {
          // Drop the LEADING (outermost) segment; keep at least one.
          kept = kept.sublist(1);
        }

        final children = <Widget>[];
        for (var i = 0; i < kept.length; i++) {
          if (i > 0) {
            children.add(
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
            );
          }
          final (level, label) = kept[i];
          children.add(
            Flexible(
              child: Row(
                key: Key('location-segment-${level.name}'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(iconForPlanningLevel(level), size: 14),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kHorizontalPadding),
          child: Row(children: children),
        );
      },
    );
  }

  double _measureWidth(
    BuildContext context,
    List<PlanningSegment> segments,
    TextStyle style,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    const separatorWidth = _kSeparatorIndent * 2 + _kSeparatorWidth;
    var width = 0.0;
    for (var i = 0; i < segments.length; i++) {
      if (i > 0) width += separatorWidth;
      width += 14 + 3; // icon + gap
      final painter = TextPainter(
        text: TextSpan(text: segments[i].$2, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      width += painter.maxIntrinsicWidth;
      painter.dispose();
    }
    return width;
  }
}

const double _kHorizontalPadding = 12;
const double _kSeparatorIndent = 2;
const double _kSeparatorWidth = 16;
