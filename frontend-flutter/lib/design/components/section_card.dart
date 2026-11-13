// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

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
///
/// Deliberate exceptions (issues #902 and #903): neither the scene detail's CAST
/// table nor its SHOOTING-DAYS table uses this component. A cast list ("who is
/// in this scene, in which look") and the days a scene is planned on are page
/// CONTENT, not secondary details, so both render an always-visible section
/// header plus their own table chrome — and a settings/config surface hidden
/// behind a collapse cannot be read at a glance. This card stays the component
/// for sections that legitimately collapse.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.header,
    required this.children,
    this.initiallyExpanded = false,
    this.pageStorageKey,
  });

  /// The section header (title + count). Rendered as the tile title; keep
  /// the count inside the label so the collapsed state stays informative.
  final Widget header;

  /// The section body, padded by the card's content inset.
  final List<Widget> children;

  /// Whether the section starts expanded. Defaults to `false` (collapsed by
  /// default, issue #834 PO requirement).
  final bool initiallyExpanded;

  /// Stable, UNIQUE-per-section identity for the tile's [PageStorageKey]
  /// (CodeRabbit #868): a [ListView] destroys the subtrees of sections that
  /// scroll out of the retained viewport — without storage the tile comes
  /// back COLLAPSED and hides its controls. Callers pass one stable value
  /// per section (e.g. `'scene-section-characters'`).
  final Object? pageStorageKey;

  @override
  Widget build(BuildContext context) => Card(
    // Clip so the tile's ink stays inside the rounded card corners.
    clipBehavior: Clip.antiAlias,
    margin: EdgeInsets.zero,
    child: ExpansionTile(
      key: pageStorageKey == null ? null : PageStorageKey(pageStorageKey),
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
