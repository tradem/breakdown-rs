// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:flutter/material.dart';

/// Loading skeleton of the Season tab (`redesign-seasons-home` task 3.5):
/// a lightweight list placeholder shown ONLY for the cold-start window
/// (projection loading, no cached rows) so the empty state never flashes.
///
/// M3-styled, static by design (D5): plain surface-toned placeholders
/// instead of a shimmer animation package dependency — no animation means
/// goldens are deterministic by construction (nothing to disable in
/// golden tests).
class SeasonsSkeleton extends StatelessWidget {
  const SeasonsSkeleton({super.key, this.cardCount = 3});

  /// How many placeholder cards to render (default mirrors the
  /// typical first-screen list density).
  final int cardCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = Theme.of(context).cardTheme.shape;

    return Column(
      key: const Key('seasons-skeleton'),
      children: [
        for (var i = 0; i < cardCount; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Card(
              margin: EdgeInsets.zero,
              shape: shape,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title placeholder (full-width bar).
                    Container(
                      width: double.infinity,
                      height: 20,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Metadata placeholder (half-width bar).
                    FractionallySizedBox(
                      widthFactor: 0.55,
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
