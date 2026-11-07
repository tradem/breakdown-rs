// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

import 'package:flutter/material.dart';

import '../spacing.dart';

/// Collapsible section card WITHOUT divider chrome (issue #834).
///
/// The scene detail screen's sections used to be raw `ExpansionTile`s: the
/// Material 3 default draws top+bottom borders in `dividerColor` while
/// expanded, which the reporter read as "hässliche horizontale Linien". This
/// component replaces that chrome everywhere a screen needs a Spotify-ish
/// card section: separation comes from the [Card] surface and token spacing,
/// never from a drawn line.
///
/// Contract (spec `flutter-scene-detail`):
/// * no shape borders in ANY expansion state — the widget tree contains no
///   `Divider` and no ExpansionTile border;
/// * collapsed by default ([initiallyExpanded] defaults to `false`) — a
///   screen opts into open only deliberately;
/// * the caller keeps the count in the header text (e.g. „Figuren (3)"), so
///   a collapsed section still tells its story.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.header,
    required this.children,
    this.initiallyExpanded = false,
  });

  /// The section header (title + count). Rendered as the tile title; keep
  /// the count inside the label so the collapsed state stays informative.
  final Widget header;

  /// The section body, padded by the card's content inset.
  final List<Widget> children;

  /// Whether the section starts expanded. Defaults to `false` (collapsed by
  /// default, issue #834 PO requirement).
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => Card(
    // Clip so the tile's ink stays inside the rounded card corners.
    clipBehavior: Clip.antiAlias,
    margin: EdgeInsets.zero,
    child: ExpansionTile(
      // No borders in either state — THE point of the component (issue #834).
      shape: const Border(),
      collapsedShape: const Border(),
      initiallyExpanded: initiallyExpanded,
      tilePadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space16,
        vertical: AppSpacing.space4,
      ),
      childrenPadding: const EdgeInsets.fromLTRB(
        AppSpacing.space16,
        0,
        AppSpacing.space16,
        AppSpacing.space12,
      ),
      title: header,
      children: children,
    ),
  );
}
