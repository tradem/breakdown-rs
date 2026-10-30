// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ai_import_providers.dart';
import '../../l10n/app_localizations_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import 'ai_config/ai_config_screen.dart';

/// The configured provider/model surfaces (EU AI Act Art. 50 transparency,
/// issues #608/#517/#760): ONE shared resolution, three renderings.
///
/// [aiNamingSentence] is the single source of the transparency WORDING — the
/// wire naming of the caller's NON-secret `AiConfigView`, the disclosure's
/// honest degradation copy, or the loading note. Both [AiNamingLine] (the
/// compact line of the submit disclosure and the apply section) and
/// [AiNamingCard] (the prominent preview header) render exactly that sentence,
/// so the two surfaces can never drift apart.
///
/// [AiDecisionModelWarning] is the sibling disclosure for the Decision Model
/// SLOT: the same `configuredAiNamingProvider` read, a different fact — the
/// configuration exists but carries no Decision Model, so Pass-2 continuity and
/// the scoring pass will not run (issue #760).
///
/// `configuredAiNamingProvider` is container-cached, so every surface here
/// shares ONE discovery per container (`ref.watch`, never a second fetch).
/// Callers pass their own semantic key (e.g. `Key('ai-apply-naming')`).

/// The ONE localized transparency sentence every naming surface renders.
///
/// - configured → `aiNamingLine` (provider + assistant model)
/// - unconfigured or discovery failure → the disclosure's honest degradation
///   copy (`aiDisclosureNamingBodyUnconfigured`)
/// - still loading → `aiDisclosureNamingBodyLoading` (re-renders to the wire
///   naming as soon as the discovery resolves; reloads do not flicker back to
///   loading)
///
/// A failed discovery is deliberately the SAME sentence as "nothing
/// configured": both mean "this app cannot name a provider/model right now", so
/// neither may invent one.
String aiNamingSentence(
  AppLocalizations l10n,
  AsyncValue<AiConfigView?> naming,
) => naming.when(
  data: (configured) => configured == null
      ? l10n.aiDisclosureNamingBodyUnconfigured
      // gen-l10n positional order: placeholders are bound
      // ALPHABETICALLY (model, provider), not in the template's
      // appearance order — pass the model first (verified against
      // the generated de/en bodies).
      : l10n.aiNamingLine(configured.assistantModel, configured.provider.name),
  error: (_, _) => l10n.aiDisclosureNamingBodyUnconfigured,
  loading: () => l10n.aiDisclosureNamingBodyLoading,
  skipLoadingOnReload: true,
);

/// The COMPACT provider/model labelling line (EU AI Act Art. 50, issue #608):
/// ONE `bodySmall` text rendering [aiNamingSentence] — copy in every state,
/// never a spinner trap and never an invented name.
///
/// Shared by the import-submit disclosure card and the apply section, where a
/// quiet footnote is the right weight (the reviewer is acting on the content,
/// not on the configuration). The preview's header uses [AiNamingCard] instead.
class AiNamingLine extends ConsumerWidget {
  const AiNamingLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final naming = ref.watch(configuredAiNamingProvider);
    return Text(
      aiNamingSentence(l10nOf(context), naming),
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

/// The PROMINENT provider/model header card of the preview screen (issue #760).
///
/// The reported defect: provider and model were rendered as one tiny
/// `bodySmall` line wedged between the app bar and the scene cards, so they
/// disappeared in a long preview — the machinery that produced the rows was
/// effectively invisible. This card gives the same facts the weight the rest of
/// the preview has, while keeping the disclosure substance:
///
/// - **model** as the primary line (`titleSmall`, ONE line, ellipsized — a
///   curated model id can be long, and wrapping the header would push the rows
///   off screen; the full id stays in the caption below and in the semantics);
/// - **provider** as the secondary line (`labelLarge`);
/// - the unchanged EU AI Act sentence ([aiNamingSentence] →
///   `aiNamingLine`) as the caption, so the transparency statement is not
///   weakened by the visual promotion.
///
/// The honest degradation states are preserved unchanged: an unconfigured
/// account or a failed discovery renders the "unconfigured" copy (never a
/// guessed name), and a pending discovery renders the loading note. In those
/// states the card renders ONE line — there is no model/provider to promote.
class AiNamingCard extends ConsumerWidget {
  const AiNamingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final naming = ref.watch(configuredAiNamingProvider);
    final l10n = l10nOf(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // `value` keeps the last resolved configuration across a reload
    // (`skipLoadingOnReload` semantics): a refresh never blanks the header. A
    // FAILED discovery falls back to the honest "unconfigured" copy instead —
    // the same arm as [aiNamingSentence]'s error clause, so the header can
    // never name a provider/model the app could not read.
    final configured = naming.hasError ? null : naming.value;

    return Card(
      color: scheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.memory_outlined,
              size: 20,
              // Reinforcement only: the visible text carries the meaning
              // (glossary rule). Muted while there is nothing to name.
              color: configured == null
                  ? scheme.onSurfaceVariant
                  : scheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: configured == null
                  ? Text(
                      aiNamingSentence(l10n, naming),
                      key: const Key('ai-preview-naming-disclosure'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          configured.assistantModel,
                          key: const Key('ai-preview-naming-model'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.aiPreviewNamingProvider(
                            configured.provider.name,
                          ),
                          key: const Key('ai-preview-naming-provider'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          aiNamingSentence(l10n, naming),
                          key: const Key('ai-preview-naming-disclosure'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The non-blocking "no Decision Model configured" disclosure (issue #760).
///
/// A configuration WITHOUT a Decision Model is valid: the extraction runs
/// exactly as before and only the Pass-2 passes are skipped. Before this card
/// the preview silently ran without them, so the absent wardrobe-continuity
/// suggestions and the absent star ratings looked like a defect rather than a
/// configuration state.
///
/// The card states the TWO factual consequences and nothing else — no
/// speculation about quality — and offers the one action that resolves it
/// (open the AI configuration). It never blocks the apply.
///
/// ## Which configuration it keys off
///
/// [configuredAiNamingProvider] picks the caller's newest NON-revoked
/// configuration — the same one the import handler resolves and hands to the
/// worker, so the warning describes the configuration this import will actually
/// use (a multi-user/multi-config account cannot see a warning about somebody
/// else's config, nor a missing warning about its own).
///
/// ## Which STATES it renders in
///
/// Only a RESOLVED discovery can state the absence of a Decision Model:
///
/// - `hasValue && !hasError` → configured / unconfigured account: the warning
///   renders iff `decisionProvider`/`decisionModel` are missing;
/// - pending discovery → nothing (the naming card above already says
///   "loading");
/// - failed discovery → nothing, because a failed READ is not the same fact as
///   "no Decision Model is set": the [AiNamingCard] falls back to the
///   "unconfigured" copy instead of the app claiming something it did not read.
class AiDecisionModelWarning extends ConsumerWidget {
  const AiDecisionModelWarning({this.onConfigure, super.key});

  /// Opens the AI configuration screen. `null` (the default) pushes
  /// [AiConfigScreen] itself; tests pass their own callback to observe the tap
  /// without a route.
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final naming = ref.watch(configuredAiNamingProvider);
    // No resolved, non-failed read → no claim (see the class doc).
    if (!naming.hasValue || naming.hasError) return const SizedBox.shrink();
    final configured = naming.value;
    if (configured == null) return const SizedBox.shrink();
    final decisionProvider = configured.decisionProvider;
    final decisionModel = configured.decisionModel;
    if (decisionProvider != null && (decisionModel ?? '').trim().isNotEmpty) {
      return const SizedBox.shrink();
    }

    final l10n = l10nOf(context);
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Card(
      color: scheme.tertiaryContainer,
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 20, color: scheme.tertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.aiPreviewDecisionModelWarningTitle,
                    key: const Key('ai-preview-decision-model-warning-title'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.aiPreviewDecisionModelWarningBody,
              key: const Key('ai-preview-decision-model-warning-body'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('ai-preview-decision-model-warning-action'),
                onPressed: onConfigure ?? () => _openConfig(context),
                child: Text(l10n.aiPreviewDecisionModelWarningAction),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openConfig(BuildContext context) {
    // Fire-and-forget push (no result is consumed), the same seam the season
    // wizard's AI-config entry uses.
    unawaited(
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const AiConfigScreen())),
    );
  }
}
