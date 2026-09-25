// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode)
// Co-authored-by: omen-alpha (opencode-go)

import 'package:flutter/material.dart';

import '../../../../design/spacing.dart';
import '../../../../l10n/app_localizations_provider.dart';

/// Dispatch overlay of the setup wizard (tasks 3.2/4.5): the per-command
/// progress ("Season wird erstellt…", linear indicator, sub-step label).
///
/// Riverpod-free presentation (design D1). The cancel affordance is NOT
/// rendered here at all — during dispatch it is disabled by the screen's
/// PopScope and app bar (spec `Abort during dispatch`).
class WizardDispatchView extends StatelessWidget {
  const WizardDispatchView({
    super.key,
    required this.done,
    required this.total,
    required this.label,
  });

  /// Acknowledged commands so far.
  final int done;

  /// Total commands of the dispatch plan.
  final int total;

  /// The in-flight sub-step label (block/episode being created).
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const Key('wizard-dispatch-view'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10nOf(context).wizardDispatchProgress,
              key: const Key('wizard-dispatch-title'),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.space16),
            LinearProgressIndicator(
              key: const Key('wizard-dispatch-progress'),
              value: total == 0 ? null : done / total,
            ),
            const SizedBox(height: AppSpacing.space8),
            Text(
              '$done / $total',
              key: const Key('wizard-dispatch-count'),
              // Semantics: screen readers announce the sub-step, not just
              // the raw fraction (spec Accessibility).
              semanticsLabel: l10nOf(context)
                  .wizardDispatchSemantics('$done', '$total'),
            ),
            if (label.isNotEmpty)
              Text(
                label,
                key: const Key('wizard-dispatch-label'),
                style: theme.textTheme.bodyMedium,
              ),
          ],
        ),
      ),
    );
  }
}
