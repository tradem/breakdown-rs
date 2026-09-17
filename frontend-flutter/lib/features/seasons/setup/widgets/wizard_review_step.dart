// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:flutter/material.dart';

import '../../../../design/spacing.dart';
import '../setup_wizard_state.dart';

/// Review step of the setup wizard (task 4.3): the summary (season +
/// blocks + total episodes) and the dispatch confirm CTA.
///
/// Riverpod-free presentation (design D1): state in, callbacks out.
class WizardReviewStep extends StatelessWidget {
  const WizardReviewStep({
    super.key,
    required this.firstBlockNumber,
    required this.seasonNumber,
    required this.seasonName,
    required this.blocks,
    required this.numbersSeeded,
    required this.onConfirm,
  });

  /// The derived series-scoped first block number (read-only info).
  final int firstBlockNumber;
  final int seasonNumber;
  final String seasonName;
  final List<BlockDraft> blocks;

  /// Whether the derived series-scoped numbers have settled — the confirm
  /// CTA stays disabled until then (dispatching on the fallback numbers
  /// while the derivation runs could create the season before a conflict
  /// stops the sequence).
  final bool numbersSeeded;

  /// Starts the sequential dispatch (the screen wires the series id and
  /// the controller call — this widget only renders and dispatches).
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalEpisodes = blocks.fold<int>(0, (sum, b) => sum + b.episodeCount);
    final seasonTitle = seasonName.trim().isEmpty
        ? 'Season $seasonNumber'
        : 'Season $seasonNumber · ${seasonName.trim()}';
    return ListView(
      key: const Key('wizard-step-review'),
      padding: const EdgeInsets.all(AppSpacing.space16),
      children: [
        Card(
          key: const Key('wizard-review-summary'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Prüfen & erstellen', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.space8),
                Text(seasonTitle, style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.space8),
                Text('$totalEpisodes Episoden in ${blocks.length} Blöcke'),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space12),
        for (var i = 0; i < blocks.length; i++)
          Card(
            child: ListTile(
              title: Text(
                blocks[i].title.trim().isEmpty
                    ? 'Block ${firstBlockNumber + i}'
                    : 'Block ${firstBlockNumber + i} · '
                          '${blocks[i].title.trim()}',
              ),
              subtitle: Text('${blocks[i].episodeCount} Episoden'),
            ),
          ),
        const SizedBox(height: AppSpacing.space12),
        // The derivation is still running: an honest disabled state beats
        // a silent fallback dispatch (glossary `wizard.review.numbersPending`).
        if (!numbersSeeded)
          Text(
            'Nummern werden ermittelt …',
            key: const Key('wizard-review-seeding'),
            style: theme.textTheme.bodySmall,
          ),
        const SizedBox(height: AppSpacing.space24),
        FilledButton.icon(
          key: const Key('wizard-confirm'),
          onPressed: numbersSeeded ? onConfirm : null,
          icon: const Icon(Icons.check),
          label: const Text('Season erstellen'),
        ),
      ],
    );
  }
}
