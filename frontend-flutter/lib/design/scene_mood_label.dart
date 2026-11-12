// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

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
              // One icon per named location (`A/I/T` names two, the canonical
              // INT./EXT. pair collapses to the threshold icon), then the
              // time-of-day icon — the same set the import preview renders.
              for (final location in icons.locations) ...[
                Icon(location, size: 16),
                const SizedBox(width: 2),
              ],
              Icon(icons.time, size: 16),
              const SizedBox(width: 4),
            ],
          ),
        ),
        text,
      ],
    );
  }
}

/// The canonical set-shorthand moods the scene editor offers as chips
/// (issue #834): the set-shorthand grammar the mood resolver already parses
/// (`<I|A|I/A>/<T|N|D|M|AB>`), enumerated in stable display order. A stored
/// value OUTSIDE this set stays selectable in the editor as its own chip and
/// is never destroyed by a save — the resolver renders it as plain text.
const canonicalSceneMoods = <String>[
  'I/T',
  'I/N',
  'I/D',
  'I/M',
  'I/AB',
  'A/T',
  'A/N',
  'A/D',
  'A/M',
  'A/AB',
  'I/A/T',
  'I/A/N',
  'I/A/D',
  'I/A/M',
  'I/A/AB',
  // `A/I/*` is the same mixed scene from the script's other side ("Erfurt /
  // Straße" outside, then "Eingang + Flur / vor OP" inside). The parser only
  // ever produces `I/A/*` (from `INT./EXT.`), so these are the values a script
  // such as the one above states verbatim — offering them keeps the editor from
  // forcing `I/A` onto a scene that plays A→I.
  'A/I/T',
  'A/I/N',
  'A/I/D',
  'A/I/M',
  'A/I/AB',
];
