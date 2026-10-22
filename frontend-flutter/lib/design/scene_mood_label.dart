// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

import 'package:flutter/material.dart';

import 'material_icons.dart';

/// The visible set-shorthand mood label (`I/T`, `A/N`, `I/A/T`, …) with its
/// reinforcing Material icons (issue #721): the interior/exterior icon and
/// the time-of-day icon render NEXT TO the text and never replace it
/// (glossary rule — icons reinforce visible text only).
///
/// A mood the resolver cannot parse renders as plain text — the label stays
/// honest even when the server later widens the canonical set.
class SceneMoodLabel extends StatelessWidget {
  const SceneMoodLabel({
    super.key,
    required this.mood,
    this.label,
    this.textStyle,
  });

  final String mood;

  /// The visible text label. Defaults to the raw shorthand (`I/T`); callers
  /// that render localized copy (`"Stimmung: I/T"`) pass it here — the icons
  /// stay adjacent either way.
  final String? label;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final text = Text(label ?? mood, style: textStyle);
    final icons = BreakdownMaterialIcons.forSceneMood(mood);
    if (icons == null) {
      return text;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The icons are decorative reinforcement: the visible label right
        // next to them already carries the meaning for screen readers.
        ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icons.$1, size: 16),
              const SizedBox(width: 2),
              Icon(icons.$2, size: 16),
              const SizedBox(width: 4),
            ],
          ),
        ),
        text,
      ],
    );
  }
}
