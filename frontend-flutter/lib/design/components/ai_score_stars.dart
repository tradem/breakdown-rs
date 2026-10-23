// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

import 'package:flutter/material.dart';

import '../../l10n/app_localizations_provider.dart';
import '../../l10n/generated/app_localizations.dart';

/// Maps a normalized Decision Model score (`0.0..=1.0`, issue #722) to the
/// displayed 1–5 star rating.
///
/// The bucket boundaries mirror the OpenSpec change
/// `723-flutter-ai-import-scoring-stars-and-filter` (design D2):
///
/// * `>= 0.85` → 5 stars
/// * `0.70 ..< 0.85` → 4 stars
/// * `0.50 ..< 0.70` → 3 stars
/// * `0.30 ..< 0.50` → 2 stars
/// * `< 0.30` → 1 star
///
/// The minimum is 1 (never 0): a rendered rating always marks a scored
/// artifact, and a scored-but-weak artifact reads as ★☆☆☆☆, not as
/// "unscored" — the honest absence is reserved for `null`.
int aiScoreStarsFor(double score) {
  if (score >= 0.85) return 5;
  if (score >= 0.70) return 4;
  if (score >= 0.50) return 3;
  if (score >= 0.30) return 2;
  return 1;
}

/// True when [score] is at most 3 stars (`< 0.70`) — the low-score review
/// filter's predicate (issue #723). A `null` score is never "low": a row
/// without a score is not ranked, so the filter does not select it.
bool isLowAiScore(double? score) => score != null && score < 0.70;

/// The localized copy key for one star rating bucket (design D2 / glossary):
/// the visible label reads e.g. „3 von 5 Sternen" and the semantic
/// announcement names the score's meaning for screen readers.
String aiScoreStarsLabel(AppLocalizations l10n, int stars) =>
    l10n.aiScoreStarsLabel('$stars');

/// The reusable Material 3 star-rating indicator (issue #723).
///
/// Renders the localized label plus 1–5 star icons from a normalized
/// `0.0..=1.0` Decision Model score. A `null` score renders NOTHING
/// ([SizedBox.shrink]) — the honest absence when no Decision Model was
/// configured or the best-effort scoring pass failed; a fabricated
/// "unscored" rating would violate the EU AI Act Art. 50 framing.
///
/// Display-only: the widget never accepts input (the review decisions live
/// in the apply section's checkboxes/chips).
class AiScoreStars extends StatelessWidget {
  const AiScoreStars({required this.score, super.key});

  /// The normalized score (`0.0..=1.0`), or `null` when unscored — which
  /// renders nothing.
  final double? score;

  @override
  Widget build(BuildContext context) {
    final value = score;
    if (value == null) return const SizedBox.shrink();
    final stars = aiScoreStarsFor(value);
    final scheme = Theme.of(context).colorScheme;
    final label = aiScoreStarsLabel(l10nOf(context), stars);
    return Semantics(
      key: const Key('ai-score-stars'),
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              i <= stars ? Icons.star : Icons.star_border,
              key: Key('ai-score-star-$i'),
              size: 16,
              color: i <= stars ? scheme.tertiary : scheme.onSurfaceVariant,
            ),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
