// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

/// The per-import cost card of the job-status screen (issues #675, #761 and
/// #768).
///
/// Issue #675 established WHAT is shown and, above all, what must never be
/// invented: a `known` snapshot renders its real figures, `unknown` renders the
/// localized "Unbekannt" / "Unknown" (never a fabricated `0`), and
/// `not_applicable` states that no AI model was billed. Issue #761 changed only
/// the PRESENTATION — the card was a flat column of equally weighted
/// `bodySmall` lines in which the two facts the user actually wants (what it
/// cost, which model produced it) were buried between token counts, snapshot
/// rates, energy figures and a price date. Issue #768 added a second priced
/// component (the Decision Model, possibly a different provider/model) plus an
/// explicit `CostTotal` whose status states whether a sum may be shown at all.
///
/// The layout that follows from that:
///
/// * **Header** — one icon + the visible title (the icon reinforces, it never
///   carries the meaning on its own — glossary contract).
/// * **Hero** — the headline figure, large and EXPLICITLY labelled
///   ([AiCostHero]): the money the user pays (`cost.total` when the wire
///   publishes one, otherwise the extraction token cost, labelled "Tokenkosten")
///   or — when the user's `cost_display_preference` is `energy` — the energy
///   figure. A refused total (`incomplete` / `mixed_currency`) states WHY it is
///   absent instead of presenting a component as if it were the sum.
/// * **Identity chips** — the model and provider that produced the rows, each as
///   a labelled chip (wrapped, two lines, ellipsized, full value in a tooltip),
///   so a long curated model id never overflows a narrow layout.
/// * **Details** — icon-prefixed, grouped, visually subordinate: usage, the
///   component costs, rates, the Decision-Model component, and `price_as_of`.
///   Nothing the #675 card rendered is dropped.
///
/// Integer nano-currency math only ([formatNanoCurrency]), snapshot rates only
/// (never a live lookup), and the preference-selected figure stays emphasised
/// in the detail rows as well, so the card and the jobs list agree on the
/// primary metric.
library;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/ai_import_providers.dart';
import '../../../design/material_icons.dart';
import '../../../design/spacing.dart';
import '../../../l10n/app_localizations_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/locale_formatters.dart';
import '../cost_format.dart';
import 'decision_outcome.dart';

/// The hero figure of the cost card (issue #761).
///
/// [label] is ALWAYS rendered next to the figure: the icon vocabulary of this
/// card only reinforces text, so a reader who never sees the hero figure still
/// learns what it means.
class AiCostHero {
  const AiCostHero({
    required this.label,
    required this.value,
    this.note,
    this.isUnknown = false,
  });

  /// The visible label of the figure ("Gesamtkosten", "Energiekosten", …).
  final String label;

  /// The formatted figure, or the localized unknown copy.
  final String value;

  /// Why the figure is a priced COMPONENT instead of the total (only for a
  /// #768 snapshot that explicitly refuses a sum). `null` when the figure is
  /// the total, or when the snapshot predates the total.
  final String? note;

  /// True for the honest unknown arm (`cost.status == unknown`, or a defensive
  /// snapshot that carries no currency). The widget renders that arm without a
  /// currency figure at all — never `0`.
  final bool isUnknown;
}

/// Chooses the hero figure for [cost] under the user's [preference] (pure,
/// Tier-1 testable).
///
/// The money arm prefers `cost.total` — the figure the user actually pays
/// (issue #768) — and falls back to the extraction token cost when the snapshot
/// carries no total (pre-#768 rows deserialize as `unknown`, which is an absence,
/// not an error, so no note is rendered for it). A snapshot whose total is
/// `incomplete` or `mixed_currency` renders the priced component AND the reason
/// the sum is missing.
///
/// The energy arm shows the energy component when the snapshot has one; a
/// snapshot without energy telemetry degrades to the money arm rather than
/// inventing an energy figure.
AiCostHero aiCostHero(
  AppLocalizations l10n,
  CostBreakdown cost,
  CostDisplayPreference preference,
) {
  final energy = cost.energyCost;
  final currency = cost.currency;
  final energyLabel = l10n.aiJobCostHeroEnergy;

  // The honest unknown (spec #675): no priced component to show at all. The
  // label still names the metric the user asked to see, the value is the
  // localized "Unbekannt" — never `0`.
  if (cost.status == CostStatus.unknown || currency == null) {
    return AiCostHero(
      label: preference == CostDisplayPreference.energy
          ? energyLabel
          : l10n.aiJobCostHeroTotal,
      value: l10n.commonUnknown,
      isUnknown: true,
    );
  }

  if (preference == CostDisplayPreference.energy && energy != null) {
    return AiCostHero(
      label: energyLabel,
      value: formatNanoCurrency(energy.effectiveCappedNano, currency),
    );
  }

  final total = cost.total;
  final totalNano = total?.totalNano;
  if (total != null &&
      total.status == CostTotalStatus.known &&
      totalNano != null) {
    return AiCostHero(
      label: l10n.aiJobCostHeroTotal,
      value: formatNanoCurrency(totalNano, total.currency ?? currency),
    );
  }

  // No sum is on offer: show the priced extraction component and, for a
  // snapshot that actively refuses a total, say why. `null` (an unknown /
  // not-applicable snapshot, whose total is absent by contract) and `unknown`
  // (every pre-#768 row) are absences, not errors — they render no note.
  final note = switch (total?.status) {
    CostTotalStatus.incomplete => l10n.aiJobCostTotalIncomplete,
    CostTotalStatus.mixedCurrency => l10n.aiJobCostTotalMixedCurrency,
    _ => null,
  };
  final token = cost.tokenCost;
  if (token != null) {
    return AiCostHero(
      label: l10n.aiJobCostHeroToken,
      value: formatNanoCurrency(token.totalNano, currency),
      note: note,
    );
  }
  if (energy != null) {
    return AiCostHero(
      label: energyLabel,
      value: formatNanoCurrency(energy.effectiveCappedNano, currency),
      note: note,
    );
  }
  // A `known` snapshot without any priced component is a defensive wire shape:
  // stay honest instead of rendering an empty hero.
  return AiCostHero(
    label: l10n.aiJobCostHeroTotal,
    value: l10n.commonUnknown,
    isUnknown: true,
  );
}

/// The glyph that stands for the metric the compact jobs-list cost line shows
/// (issue #761): the same preference-driven choice as [aiCostHero], so the list
/// and the job card never disagree about which figure is primary.
///
/// The icon only reinforces the line's visible "Kosten: …" text — the glossary
/// contract forbids an icon-only meaning.
IconData aiJobCostMetricIcon(
  CostBreakdown? cost,
  CostDisplayPreference preference,
) {
  if (cost == null) return BreakdownMaterialIcons.aiJobCostUnknown;
  if (cost.status == CostStatus.notApplicable) {
    return BreakdownMaterialIcons.aiJobCostNotApplicable;
  }
  if (cost.status == CostStatus.unknown) {
    return BreakdownMaterialIcons.aiJobCostUnknown;
  }
  if (preference == CostDisplayPreference.energy && cost.energyCost != null) {
    return BreakdownMaterialIcons.aiJobCostEnergy;
  }
  return BreakdownMaterialIcons.aiJobCostToken;
}

/// The per-import cost card (issue #675, redesigned by #761, extended by #768).
///
/// Reads the immutable snapshot the job already carries — no extra request, no
/// second projection lookup (the CQRS-boundary rule of AGENTS.md §1 applies to
/// the cost context too), and no SSE stream of its own: the terminal
/// `succeeded` frame populates `job.cost` (issue #664).
class AiJobCostCard extends ConsumerWidget {
  const AiJobCostCard({required this.job, super.key});

  final AiImportJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cost = job.cost;
    if (cost == null) return const SizedBox.shrink();
    final l10n = l10nOf(context);
    final preference = ref.watch(aiCostDisplayPreferenceProvider);

    final children = <Widget>[
      _header(context),
      const SizedBox(height: AppSpacing.space16),
    ];

    if (cost.status == CostStatus.notApplicable) {
      children.add(
        Column(
          key: const Key('ai-job-cost-not-applicable'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.aiJobCostNotApplicable),
            const SizedBox(height: AppSpacing.space8),
            // The Decision Model outcome belongs on the cost card (issue
            // #767): this is where an operator looks after a star-less
            // import, and the render is silent for a job that recorded no
            // outcome.
            AiDecisionOutcomeText(telemetry: job.decisionTelemetry),
          ],
        ),
      );
    } else {
      final identity = _identity(context);
      children.addAll([
        _hero(context, aiCostHero(l10n, cost, preference)),
        const SizedBox(height: AppSpacing.space16),
        if (identity != null) ...[
          identity,
          const SizedBox(height: AppSpacing.space16),
        ],
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        const SizedBox(height: AppSpacing.space12),
        ..._details(context, cost, preference),
      ]);
    }

    return Card(
      key: const Key('ai-job-cost-card'),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  /// One icon + the visible title. The icon reinforces only (glossary rule).
  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          BreakdownMaterialIcons.aiJobCostTitle,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.space8),
        Expanded(
          child: Text(
            l10nOf(context).aiJobCostTitle,
            key: const Key('ai-job-cost-title'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  /// The headline figure, large and explicitly labelled (issue #761).
  Widget _hero(BuildContext context, AiCostHero hero) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      key: const Key('ai-job-cost-hero'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hero.label,
          key: const Key('ai-job-cost-hero-label'),
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          hero.value,
          key: hero.isUnknown
              ? const Key('ai-job-cost-unknown')
              : const Key('ai-job-cost-hero-value'),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: hero.isUnknown ? scheme.onSurfaceVariant : scheme.onSurface,
          ),
        ),
        if (hero.note != null) ...[
          const SizedBox(height: AppSpacing.space4),
          _CostLine(
            icon: BreakdownMaterialIcons.aiJobCostTotalNote,
            text: hero.note!,
            textKey: const Key('ai-job-cost-total-note'),
            color: scheme.tertiary,
          ),
        ],
      ],
    );
  }

  /// Model + provider as labelled chips (issue #761): the "wesentliches
  /// Modell" the redesign exists for, and — since the provider was on the wire
  /// but never rendered — newly visible information.
  ///
  /// A [`Wrap`] (not a `Row`) so narrow/compact layouts wrap instead of
  /// overflowing, two lines of ellipsized text and the full value in a tooltip
  /// so a long curated model id stays readable without pushing the card wide.
  /// `null` when the job carries no telemetry identity at all (a pre-#609 row):
  /// an empty chip row would only add whitespace.
  Widget? _identity(BuildContext context) {
    final l10n = l10nOf(context);
    final telemetry = job.telemetry;
    final model = telemetry?.model;
    final provider = telemetry?.provider?.name;
    if ((model == null || model.isEmpty) &&
        (provider == null || provider.isEmpty)) {
      return null;
    }
    return Wrap(
      spacing: AppSpacing.space8,
      runSpacing: AppSpacing.space8,
      children: [
        if (model != null && model.isNotEmpty)
          _IdentityChip(
            key: const Key('ai-job-cost-model'),
            icon: BreakdownMaterialIcons.aiJobCostModel,
            label: l10n.aiJobCostModelLabel,
            value: model,
          ),
        if (provider != null && provider.isNotEmpty)
          _IdentityChip(
            key: const Key('ai-job-cost-provider'),
            icon: BreakdownMaterialIcons.aiJobCostProvider,
            label: l10n.aiJobCostProviderLabel,
            value: provider,
          ),
      ],
    );
  }

  /// The subordinate, icon-prefixed detail rows — grouped as usage → component
  /// costs → rates → the Decision-Model component → price date, in the order a
  /// reader reconstructs the figure in.
  List<Widget> _details(
    BuildContext context,
    CostBreakdown cost,
    CostDisplayPreference preference,
  ) {
    final l10n = l10nOf(context);
    final theme = Theme.of(context);
    final currency = cost.currency;
    final token = cost.tokenCost;
    final energy = cost.energyCost;
    final telemetry = job.telemetry;
    final rows = <Widget>[];

    // Usage. The recorded counts survive an `unknown` price (spec #675): an
    // unpriced model still states how much it consumed.
    if (telemetry != null) {
      rows
        ..add(
          _CostLine(
            icon: BreakdownMaterialIcons.aiJobCostUsageIn,
            text: l10n.aiJobCostTokensIn('${telemetry.tokensIn}'),
            textKey: const Key('ai-job-cost-tokens-in'),
          ),
        )
        ..add(
          _CostLine(
            icon: BreakdownMaterialIcons.aiJobCostUsageOut,
            text: l10n.aiJobCostTokensOut('${telemetry.tokensOut}'),
            textKey: const Key('ai-job-cost-tokens-out'),
          ),
        );
      if (telemetry.cachedTokensIn > 0) {
        rows.add(
          _CostLine(
            icon: BreakdownMaterialIcons.aiJobCostCached,
            text: l10n.aiJobCostCachedTokens('${telemetry.cachedTokensIn}'),
            textKey: const Key('ai-job-cost-cached-tokens'),
          ),
        );
      }
    }

    // Component costs. The preference-selected figure stays emphasised, so the
    // hero and the detail rows cannot present two different "primaries".
    final tokenPrimary = preference != CostDisplayPreference.energy;
    if (token != null && currency != null) {
      rows.add(
        _CostLine(
          icon: BreakdownMaterialIcons.aiJobCostToken,
          text: l10n.aiJobCostTokenTotal(
            formatNanoCurrency(token.totalNano, currency),
          ),
          textKey: const Key('ai-job-cost-token-total'),
          emphasised: tokenPrimary,
        ),
      );
    }
    if (energy != null && currency != null) {
      rows
        ..add(
          _CostLine(
            icon: BreakdownMaterialIcons.aiJobCostEnergy,
            text: l10n.aiJobCostEnergyConsumption(
              formatMillijoulesAsWh(energy.energyMillijoules),
            ),
            textKey: const Key('ai-job-cost-energy-consumption'),
          ),
        )
        ..add(
          _CostLine(
            icon: BreakdownMaterialIcons.aiJobCostToken,
            text: l10n.aiJobCostEnergyTotal(
              formatNanoCurrency(energy.effectiveCappedNano, currency),
            ),
            textKey: const Key('ai-job-cost-energy-total'),
            emphasised: !tokenPrimary,
          ),
        );
      if (energy.cappedByTokenCost) {
        // Neuralwatt surge protection (#794): the cap is a fact about the
        // figure above, so it stays visible next to it.
        rows.add(
          _CostLine(
            icon: BreakdownMaterialIcons.aiJobCostTotalNote,
            text: l10n.aiJobCostEnergyCapped,
            textKey: const Key('ai-job-cost-energy-capped'),
            color: theme.colorScheme.tertiary,
          ),
        );
      }
    }

    // Snapshot rates (never a live lookup — the snapshot is immutable).
    if (token != null && currency != null) {
      rows
        ..add(
          _CostLine(
            icon: BreakdownMaterialIcons.aiJobCostRate,
            text: l10n.aiJobCostRateInput(
              formatNanoCurrency(token.inputRateNanoPerMillion, currency),
            ),
            textKey: const Key('ai-job-cost-rate-input'),
          ),
        )
        ..add(
          _CostLine(
            icon: BreakdownMaterialIcons.aiJobCostRate,
            text: l10n.aiJobCostRateOutput(
              formatNanoCurrency(token.outputRateNanoPerMillion, currency),
            ),
            textKey: const Key('ai-job-cost-rate-output'),
          ),
        );
    }

    // The image component (issue #673 slot): priced into `cost.total`, so a
    // rendered total must stay explainable by the rows around it.
    final image = cost.imageCost;
    if (image != null && currency != null) {
      rows.add(
        _CostLine(
          icon: BreakdownMaterialIcons.aiJobCostImage,
          text: l10n.aiJobCostImageTotal(
            formatNanoCurrency(image.totalNano, currency),
          ),
          textKey: const Key('ai-job-cost-image-total'),
        ),
      );
    }

    final decision = cost.decision;
    if (decision != null) {
      rows
        ..add(const SizedBox(height: AppSpacing.space8))
        ..addAll(_decisionRows(context, decision));
    }

    final priceAsOf = cost.priceAsOf;
    if (priceAsOf != null) {
      rows.add(
        _CostLine(
          icon: BreakdownMaterialIcons.aiJobCostPriceAsOf,
          text: l10n.aiJobCostPriceAsOf(formatMediumDate(context, priceAsOf)),
          textKey: const Key('ai-job-cost-price-as-of'),
        ),
      );
    }

    // Which Decision Model scored this import — or why it did not (issue
    // #767). Silent when the job recorded no outcome (pre-#767 rows), so the
    // card never regresses a known-shaped payload into a guessed class.
    if (job.decisionTelemetry != null) {
      rows
        ..add(const SizedBox(height: AppSpacing.space8))
        ..add(AiDecisionOutcomeText(telemetry: job.decisionTelemetry));
    }

    return rows;
  }

  /// The Decision-Model component (issue #768): its OWN provider/model, its own
  /// usage counts and — when its `(provider, model)` had a pricing row — its own
  /// priced figures. An unpriced component keeps its usage counts and says so;
  /// it never borrows the extraction rates and never renders `0`.
  List<Widget> _decisionRows(
    BuildContext context,
    DecisionCostBreakdown decision,
  ) {
    final l10n = l10nOf(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = decision.currency;
    final priced = decision.status == CostStatus.known && currency != null;
    final tokenCost = decision.tokenCostNano;
    final energyCost = decision.energyCostNano;
    return [
      Row(
        key: const Key('ai-job-cost-decision'),
        children: [
          Icon(
            BreakdownMaterialIcons.aiJobCostDecision,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.space8),
          Expanded(
            child: Text(
              l10n.aiJobCostDecisionTitle,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(left: AppSpacing.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // A pure display join of the component's own wire pair (never a
              // derived or guessed id). The Decision Model may be a DIFFERENT
              // provider/model than the extraction model above — that is the
              // whole point of the split.
              '${decision.provider.name} / ${decision.model}',
              key: const Key('ai-job-cost-decision-identity'),
              style: theme.textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.space4),
            _CostLine(
              icon: BreakdownMaterialIcons.aiJobCostUsageIn,
              text: l10n.aiJobCostTokensIn('${decision.tokensIn}'),
              textKey: const Key('ai-job-cost-decision-tokens-in'),
            ),
            _CostLine(
              icon: BreakdownMaterialIcons.aiJobCostUsageOut,
              text: l10n.aiJobCostTokensOut('${decision.tokensOut}'),
              textKey: const Key('ai-job-cost-decision-tokens-out'),
            ),
            if (decision.cachedTokensIn > 0)
              _CostLine(
                icon: BreakdownMaterialIcons.aiJobCostCached,
                text: l10n.aiJobCostCachedTokens('${decision.cachedTokensIn}'),
                textKey: const Key('ai-job-cost-decision-cached-tokens'),
              ),
            if (tokenCost != null && priced)
              _CostLine(
                icon: BreakdownMaterialIcons.aiJobCostToken,
                text: l10n.aiJobCostDecisionTokenTotal(
                  formatNanoCurrency(tokenCost, currency),
                ),
                textKey: const Key('ai-job-cost-decision-token-total'),
              ),
            if (energyCost != null && priced) ...[
              _CostLine(
                icon: BreakdownMaterialIcons.aiJobCostEnergy,
                text: l10n.aiJobCostEnergyConsumption(
                  formatMillijoulesAsWh(decision.energyMillijoules),
                ),
                textKey: const Key('ai-job-cost-decision-energy-consumption'),
              ),
              _CostLine(
                icon: BreakdownMaterialIcons.aiJobCostToken,
                text: l10n.aiJobCostDecisionEnergyTotal(
                  formatNanoCurrency(energyCost, currency),
                ),
                textKey: const Key('ai-job-cost-decision-energy-total'),
              ),
            ],
            if (!priced) ...[
              // Honest unknown, PER COMPONENT (#768): the usage above is real,
              // the price is not missing because the import was free.
              _CostLine(
                icon: BreakdownMaterialIcons.aiJobCostTotalNote,
                text: l10n.aiJobCostDecisionUnpriced,
                textKey: const Key('ai-job-cost-decision-unpriced'),
                color: scheme.tertiary,
              ),
            ],
          ],
        ),
      ),
    ];
  }
}

/// One labelled identity chip (model / provider) of the cost card.
///
/// Sized by its content but capped by the surrounding [`Wrap`]: the value wraps
/// to at most two lines and is ellipsized beyond that, with the full value in a
/// tooltip. The visible label ("Modell" / "Anbieter") always accompanies the
/// icon, so the glyph is reinforcement only.
class _IdentityChip extends StatelessWidget {
  const _IdentityChip({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space12,
        vertical: AppSpacing.space8,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppSpacing.space8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.space8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Tooltip(
                  message: value,
                  child: Text(
                    value,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One icon-prefixed detail row (`bodySmall`, subordinate to the hero).
///
/// The single row primitive of the card keeps the rows visually uniform and the
/// icons decorative-but-labelled: every row's meaning is carried by its text.
class _CostLine extends StatelessWidget {
  const _CostLine({
    required this.icon,
    required this.text,
    this.textKey,
    this.emphasised = false,
    this.color,
  });

  final IconData icon;
  final String text;
  final Key? textKey;

  /// Renders the row's text in bold — the preference-selected metric only.
  final bool emphasised;

  /// Overrides both text and icon colour (tertiary for "why" notes, error for
  /// failures).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: tint),
          const SizedBox(width: AppSpacing.space8),
          Expanded(
            child: Text(
              text,
              key: textKey,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: emphasised ? FontWeight.bold : null,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
