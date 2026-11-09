// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import '../../l10n/generated/app_localizations.dart';

/// The single composition rule for a season's visible label (issue #825).
///
/// Mirrors the episode pill's rule (issue #709: the number ALWAYS precedes
/// the name): the season's position in the hierarchy must stay visible even
/// when the season carries a title.
///
/// * **no name** (`null`, `''`, or whitespace-only) → `seasonsDefaultTitle`
///   = „Season {number}". The blank arm is not hypothetical: the title comes
///   straight off the wire as `String?`, so `''` is a legal value and a bare
///   `?? ` fallback would render an empty pill.
/// * **name** → `seasonNumberName` = „{number} · {name}", the season
///   counterpart of `episodeNumberName`.
///
/// The season number is never dropped, and no `Season: ` wrapper is applied
/// here — the pill and the episode pill next to it both lead with the number.
///
/// Issue #840: this is the ONLY place a season label is composed. Every
/// surface that renders a season — the scope pill and its picker, the
/// production overview, the location strip, the seasons cards, the blocks
/// AppBar, the fundus chips/rows and the piece detail's repertoire list —
/// calls this helper, so a blank title can never render an empty label on
/// one screen while another screen gets it right.
String seasonDisplayLabel(
  AppLocalizations l10n, {
  required int number,
  String? title,
}) {
  final name = title?.trim();
  if (name == null || name.isEmpty) return l10n.seasonsDefaultTitle(number);
  // Positional order follows the generated signature (placeholders are
  // emitted alphabetically: `name` before `number`), same as the episode
  // counterpart's call site.
  return l10n.seasonNumberName(name, number);
}
