// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'package:flutter/material.dart';

/// One rounded Spotify-style scope pill (issue #638).
///
/// The three shell scope levels (Season · Block · Episode) share this
/// presentational widget so their shape, fill and typography cannot drift:
/// a fully rounded `ActionChip` whose fill is the level's own container
/// color when the scope is set and a neutral surface color when it is not.
///
/// Why `ActionChip` and not a hand-rolled `Material` + `InkWell`: the chip
/// keeps `MaterialTapTargetSize.padded`, i.e. the 48×48dp touch target the
/// shell's accessibility contract requires, while `shape: StadiumBorder()`
/// gives the pill look (design D5 of `638-shell-top-bar-redesign`).
///
/// Color is never the sole carrier of meaning (glossary rule): the visible
/// [label] always names the level and its state.
class ScopePill extends StatelessWidget {
  const ScopePill({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.selectedForegroundColor,
    required this.tooltip,
    required this.onPressed,
  });

  /// Level icon (glossary: icons reinforce the visible label only).
  final IconData icon;

  /// Visible label naming the level and its state.
  final String label;

  /// Whether the level's scope is currently set.
  final bool selected;

  /// Level-specific container fill when [selected] is true.
  final Color selectedColor;

  /// Foreground paired with [selectedColor].
  final Color selectedForegroundColor;

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected
        ? selectedColor
        : scheme.surfaceContainerHighest;
    final foreground = selected
        ? selectedForegroundColor
        : scheme.onSurfaceVariant;
    return ActionChip(
      avatar: Icon(icon, size: 18, color: foreground),
      label: Text(label),
      tooltip: tooltip,
      onPressed: onPressed,
      shape: const StadiumBorder(),
      backgroundColor: background,
      // An unset pill carries a subtle outline so the neutral fill still
      // reads as an affordance against the surface; a set pill has no
      // outline (the container fill carries it).
      side: BorderSide(
        color: selected ? Colors.transparent : scheme.outlineVariant,
      ),
      labelStyle: TextStyle(
        color: foreground,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
      // Explicit for the shell's touch-target contract: the 48dp tap target
      // survives the visual pill height.
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}
