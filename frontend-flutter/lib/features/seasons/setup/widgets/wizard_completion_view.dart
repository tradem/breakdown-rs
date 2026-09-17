// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:flutter/material.dart';

import '../../../../core/problem_error.dart';
import '../../../../design/spacing.dart';
import '../setup_wizard_state.dart';

/// Completion step of the setup wizard (task 4.4): the result overview
/// with the CONDITIONAL AI-import CTA (team decision 6).
///
/// Riverpod-free presentation (design D1): the screen resolves the AI
/// configuration availability (via the existing ai-config read) BEFORE
/// render and passes it in — no configuration renders the prerequisite
/// info card instead of the import CTA (spec `Conditional AI-Import
/// Completion CTA`).
///
/// [phase] distinguishes the happy completion
/// ([SetupWizardPhase.completed]) from the partial failure
/// ([SetupWizardPhase.partialFailure]): the latter renders the
/// created-so-far summary, the problem-code copy, and the in-session
/// retry of the remaining commands — never a background queue.
class WizardCompletionView extends StatelessWidget {
  const WizardCompletionView({
    super.key,
    required this.phase,
    required this.createdSeason,
    required this.createdBlocks,
    required this.failure,
    required this.aiConfigAvailable,
    required this.onRetry,
    required this.onOpenAiConfig,
    required this.onImport,
    required this.onDone,
  });

  final SetupWizardPhase phase;
  final WizardCreatedSeason? createdSeason;
  final List<WizardCreatedBlock> createdBlocks;
  final ProblemError? failure;

  /// True when an AI provider/model configuration exists (checked
  /// client-side before render).
  final bool aiConfigAvailable;

  /// Retries the remaining commands in-session (partial failure only).
  final VoidCallback onRetry;

  /// Opens the AI configuration screen (info-card action).
  final VoidCallback onOpenAiConfig;

  /// Starts the AI-import flow for the created season (CTA).
  final VoidCallback onImport;

  /// Closes the wizard.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final season = createdSeason;
    final blocksCreated = createdBlocks.fold<int>(
      0,
      (sum, b) => sum + (b.episodesCreated > 0 ? 1 : 0),
    );
    final episodesCreated = createdBlocks.fold<int>(
      0,
      (sum, b) => sum + b.episodesCreated,
    );
    final partial = phase == SetupWizardPhase.partialFailure;

    return ListView(
      key: const Key('wizard-completion'),
      padding: const EdgeInsets.all(AppSpacing.space24),
      children: [
        Icon(
          partial ? Icons.error_outline : Icons.check_circle_outline,
          size: 48,
        ),
        const SizedBox(height: AppSpacing.space16),
        // Headline keyed per glossary `wizard.completion.title`
        // ("Season {n} angelegt"); the optional name stays in the summary.
        Text(
          partial
              ? 'Teilweise erstellt'
              : (season == null
                    ? 'Season angelegt'
                    : 'Season ${season.number} angelegt'),
          key: partial
              ? const Key('wizard-completion-partial-title')
              : const Key('wizard-completion-title'),
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.space8),
        Text(
          '$blocksCreated Blöcke · $episodesCreated Episoden',
          key: const Key('wizard-completion-summary'),
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.space24),
        if (partial) ...[
          if (failure != null)
            Text(
              wizardErrorCopy(failure!),
              key: const Key('wizard-completion-error'),
              style: TextStyle(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: AppSpacing.space16),
          FilledButton.icon(
            key: const Key('wizard-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Fortsetzen'),
          ),
          const SizedBox(height: AppSpacing.space8),
          OutlinedButton(
            key: const Key('wizard-completion-done'),
            onPressed: onDone,
            child: const Text('Fertig'),
          ),
        ] else ...[
          // Conditional AI-import CTA (decision 6): with a configuration
          // the CTA renders; without it the prerequisite info card does.
          if (aiConfigAvailable)
            FilledButton.icon(
              key: const Key('wizard-completion-import-cta'),
              onPressed: onImport,
              icon: const Icon(Icons.smart_toy_outlined),
              label: const Text('KI-Import starten'),
            )
          else
            Card(
              key: const Key('wizard-completion-ai-info'),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space16),
                child: Column(
                  children: [
                    const Text(
                      'Für den KI-Import ist eine KI-Konfiguration nötig.',
                    ),
                    const SizedBox(height: AppSpacing.space8),
                    OutlinedButton.icon(
                      key: const Key('wizard-completion-ai-info-cta'),
                      onPressed: onOpenAiConfig,
                      icon: const Icon(Icons.psychology_alt_outlined),
                      label: const Text('KI-Konfiguration öffnen'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.space16),
          FilledButton(
            key: const Key('wizard-completion-done'),
            onPressed: onDone,
            child: const Text('Fertig'),
          ),
        ],
      ],
    );
  }
}
