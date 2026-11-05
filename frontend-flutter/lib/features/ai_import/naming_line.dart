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
import 'import_jobs/job_telemetry.dart';

/// The configured provider/model surfaces (EU AI Act Art. 50 transparency,
/// issues #608/#517/#760): ONE shared resolution, three renderings.
///
/// [aiNamingSentence] is the single source of the transparency WORDING — the
/// wire naming of the caller's NON-secret `AiConfigView`, the disclosure's
/// honest degradation copy, or the loading note. Both [AiNamingLine] (the
/// compact line of the submit disclosure and the apply section) and the
/// CONFIGURED fallback of [AiNamingCard] (the prominent preview header) render
/// exactly that sentence, so the two surfaces can never drift apart.
///
/// [AiNamingCard] additionally names the pair the JOB actually ran with, from
/// the job's content-free telemetry (issue #831) — see [aiNamingComparison].
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
/// This line names the CONFIGURED pair (that is what the submit and apply
/// surfaces can know before a job exists). The preview's header card names the
/// USED pair instead — see [AiNamingCard].
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

/// The display join of ONE wire `(model, provider)` pair — `model (provider)`.
///
/// A pure formatting of wire values, never a guess: a pair carrying only one
/// half names that half, and a pair carrying neither is `null`, so the caller
/// renders no pair at all instead of an empty parenthesis. The same shape the
/// Decision-Model line uses ([aiDecisionPairLabel]), so the two headers of the
/// preview read alike.
String? aiNamingPairLabel({String? model, String? provider}) {
  final namedModel = model?.trim() ?? '';
  final namedProvider = provider?.trim() ?? '';
  if (namedModel.isEmpty && namedProvider.isEmpty) return null;
  if (namedModel.isEmpty) return namedProvider;
  if (namedProvider.isEmpty) return namedModel;
  return '$namedModel ($namedProvider)';
}

/// One job's provider/model identity, as the preview header renders it
/// (issue #831): what the job USED, plus the configured pair when — and only
/// when — it differs.
class AiNamingComparison {
  const AiNamingComparison({this.usedPair, this.configuredDiffersPair});

  /// The pair the job ACTUALLY ran with, from its content-free
  /// `AiImportJob.telemetry`. `null` when the wire records none (an old job),
  /// or when the snapshot could not be read — either way the app does not know
  /// which model produced the rows and claims nothing.
  final String? usedPair;

  /// The currently configured pair, present ONLY when it differs from
  /// [usedPair]. `null` when they agree (no redundant second line), when there
  /// is no configuration to compare, and above all when [usedPair] is unknown
  /// — no comparison is ever invented.
  final String? configuredDiffersPair;

  /// Whether the card can name the model that produced the rows.
  bool get hasUsed => usedPair != null;
}

/// Resolves an [AiNamingComparison] from the job's telemetry plus the caller's
/// configuration (pure, Tier-1 testable).
///
/// "Used" and "configured" are two different facts: the extraction may have run
/// with a configuration the caller has since changed (or revoked), and an old
/// job may carry no telemetry at all. The comparison is therefore FIELD-WISE and
/// treats a blank telemetry half as UNKNOWN (code review): a snapshot carrying
/// only the provider never claims the configured *model* differs — the used
/// model simply was not recorded — and a snapshot carrying only the model never
/// claims the provider differs. A half-empty "differs" claim is exactly the
/// invented comparison this card must not make.
AiNamingComparison aiNamingComparison(
  AiConfigView? configured,
  JobTelemetrySummary? telemetry,
) {
  final usedModel = telemetry?.model?.trim() ?? '';
  final usedProvider = telemetry?.provider?.name.trim() ?? '';
  final usedPair = aiNamingPairLabel(model: usedModel, provider: usedProvider);
  if (usedPair == null) return const AiNamingComparison();
  if (configured == null) return AiNamingComparison(usedPair: usedPair);
  final configuredModel = configured.assistantModel.trim();
  final configuredProvider = configured.provider.name.trim();
  final differs =
      (usedModel.isNotEmpty && usedModel != configuredModel) ||
      (usedProvider.isNotEmpty && usedProvider != configuredProvider);
  return AiNamingComparison(
    usedPair: usedPair,
    configuredDiffersPair: differs
        ? aiNamingPairLabel(
            model: configuredModel,
            provider: configuredProvider,
          )
        : null,
  );
}

/// The PROMINENT provider/model header card of the preview screen (issues #760
/// and #831).
///
/// Issue #760 promoted provider and model from one tiny `bodySmall` line to a
/// header card, because the machinery that produced the rows had become
/// invisible in a long preview. Issue #831 fixed what that promotion NAMED: the
/// card rendered the currently configured `AiConfigView` as the primary line,
/// its provider beneath it, and then repeated the same pair in the caption —
/// the configured model twice, the model that actually produced the rows never.
///
/// The card now renders, in this order:
///
/// - **what the job USED** — `aiPreviewNamingUsed`, one `titleSmall` line,
///   ellipsized (a curated model id can be long, and wrapping the header would
///   push the rows off screen), sourced from the job's telemetry, never from the
///   configuration;
/// - **the configured pair, only when it differs by provider or model** —
///   `aiPreviewNamingConfiguredDiffers`, so a changed configuration is visible
///   without claiming the import ran with it.
///
/// Equal configurations render no second line, and the caption that repeated the
/// configured pair is gone: the pair is named once.
///
/// ## Honest degradation
///
/// - **no telemetry** (an old job) or an unreadable job snapshot: the card cannot
///   name the used pair, so it names the configured pair ONCE
///   ([aiNamingSentence] → `aiNamingLine`, whose wording is explicitly "currently
///   configured") and invents no comparison;
/// - **unconfigured account or failed discovery**: the unchanged
///   `aiDisclosureNamingBodyUnconfigured` copy (never a guessed name);
/// - **pending discovery**: the unchanged `aiDisclosureNamingBodyLoading` note.
///
/// The used-pair line survives an unconfigured account: a job that ran with a
/// model still names it, because deleting a configuration later does not undo
/// the import that already happened.
class AiNamingCard extends ConsumerWidget {
  const AiNamingCard({required this.jobId, super.key});

  /// The job whose ACTUAL provider/model this header names (issue #831). The
  /// preview holds only the job id, so the card reads the job's content-free
  /// telemetry snapshot itself ([aiJobTelemetryProvider]) — one cheap read, no
  /// SSE watch.
  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final naming = ref.watch(configuredAiNamingProvider);
    // `value` keeps the last resolved telemetry across a reload: a refresh never
    // blanks the header, and an unreadable snapshot degrades to "no used pair"
    // instead of an invented one (the copy then claims no comparison).
    final telemetry = ref.watch(aiJobTelemetryProvider(jobId)).value;
    final l10n = l10nOf(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // `value` keeps the last resolved configuration across a reload
    // (`skipLoadingOnReload` semantics): a refresh never blanks the header. A
    // FAILED discovery falls back to the honest "unconfigured" copy instead —
    // the same arm as [aiNamingSentence]'s error clause, so the header can
    // never name a provider/model the app could not read.
    final configured = naming.hasError ? null : naming.value;
    final comparison = aiNamingComparison(configured, telemetry);

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
              color: comparison.hasUsed
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: comparison.hasUsed
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.aiPreviewNamingUsed(comparison.usedPair!),
                          key: const Key('ai-preview-naming-used'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        if (comparison.configuredDiffersPair != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            l10n.aiPreviewNamingConfiguredDiffers(
                              comparison.configuredDiffersPair!,
                            ),
                            key: const Key(
                              'ai-preview-naming-configured-differs',
                            ),
                            // Bounded like the used line (code review): a long
                            // configured model id must not wrap the header and
                            // push the review rows down.
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    )
                  : Text(
                      aiNamingSentence(l10n, naming),
                      key: const Key('ai-preview-naming-disclosure'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
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
