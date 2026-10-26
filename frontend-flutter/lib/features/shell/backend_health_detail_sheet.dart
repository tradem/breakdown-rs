// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/components/section_header.dart';
import '../../design/spacing.dart';
import '../../l10n/app_localizations_provider.dart';
import '../../src/health/backend_health_providers.dart';
import 'backend_health_presentation.dart';

/// Modal bottom sheet pushed by the account drawer's health pill
/// (issue #730): the pill only names the coarse tier, this sheet answers
/// *which* dependency the backend reports as broken.
///
/// Surface decision (issue #730): a modal bottom sheet opened from inside
/// the STILL-OPEN drawer — never a route pushed after a drawer pop. The
/// drawer is the health controller's only keeping-alive listener
/// (autoDispose, #657 battery rule), so popping first would stop the poll
/// loop and blank the data; keeping it open keeps the pill mounted and the
/// numbers live while the sheet is on top. Dismissing returns to the open
/// drawer.
///
/// Copy: every label is localized (ARB), never the backend's sanitized
/// English `description` — the mapping of wire check keys to functional,
/// topology-free labels lives in [backendHealthCheckLabel].
Future<void> showBackendHealthDetailSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      // The root navigator hosts the sheet so it covers the drawer overlay
      // and the shell — the same seam the quick-create sheet uses.
      useRootNavigator: true,
      builder: (_) => const BackendHealthDetailSheet(),
    );

/// The sheet body: the aggregate tier plus one row per dependency check.
class BackendHealthDetailSheet extends ConsumerWidget {
  const BackendHealthDetailSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(backendHealthControllerProvider);
    final l10n = l10nOf(context);
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.space8),
          child: Column(
            key: const Key('backend-health-detail-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space24,
                  AppSpacing.space16,
                  AppSpacing.space8,
                  AppSpacing.space8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.healthDetailTitle,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const Key('backend-health-detail-close'),
                      icon: const Icon(Icons.close),
                      tooltip: l10n.commonClose,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              if (snapshot == null)
                // Only reachable if the sheet outlives the pill's data
                // (first probe still in flight): honest "not measured yet"
                // instead of asserting a tier nobody measured.
                _SheetBody(
                  key: const Key('backend-health-detail-pending'),
                  text: l10n.healthDetailPending,
                )
              else ...[
                _AggregateRow(snapshot: snapshot),
                if (snapshot.tier == BackendHealthTier.offline)
                  _SheetBody(
                    key: const Key('backend-health-detail-offline'),
                    text: l10n.healthDetailOfflineBody,
                  )
                else if (snapshot.checks.isEmpty)
                  _SheetBody(
                    key: const Key('backend-health-detail-empty'),
                    text: l10n.healthDetailNoDependencies,
                  )
                else ...[
                  SectionHeader(label: l10n.healthDetailDependencies),
                  for (final check in backendHealthChecksBySeverity(
                    snapshot.checks,
                  ))
                    _DependencyRow(check: check, isLight: isLight),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The aggregate tier line: tier icon + tier label (the same vocabulary and
/// tokens the pill uses, so both surfaces read identically).
class _AggregateRow extends StatelessWidget {
  const _AggregateRow({required this.snapshot});

  final BackendHealthSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final theme = Theme.of(context);
    final presentation = backendHealthTierPresentation(
      snapshot.tier,
      l10n: l10n,
      isLight: theme.brightness == Brightness.light,
    );
    return Semantics(
      key: const Key('backend-health-detail-aggregate-semantics'),
      // Single merged announcement: the wrapper's label IS what a screen
      // reader says, so the row's own Text/Icon nodes are excluded (same
      // discipline as the pill, #662).
      label: presentation.label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space24,
          vertical: AppSpacing.space8,
        ),
        child: Row(
          key: const Key('backend-health-detail-aggregate'),
          children: [
            Icon(presentation.icon, size: 20, color: presentation.color),
            const SizedBox(width: AppSpacing.space8),
            Expanded(
              child: Text(
                presentation.label,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One dependency row: status icon, functional label, localized status word.
class _DependencyRow extends StatelessWidget {
  const _DependencyRow({required this.check, required this.isLight});

  final BackendHealthCheck check;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final theme = Theme.of(context);
    final presentation = backendHealthCheckPresentation(
      check.status,
      isLight: isLight,
    );
    final label = backendHealthCheckLabel(l10n, check.name);
    final statusLabel = backendHealthCheckStatusLabel(l10n, check.status);
    return Semantics(
      key: Key('backend-health-detail-check-semantics-${check.name}'),
      // "Datenbank: gestört" in ONE announcement — the visible label and
      // the visible status word stay on screen (color is never the sole
      // carrier), the semantics node merges them so a screen reader cannot
      // read the two columns out of context.
      label: '$label: $statusLabel',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space24,
          vertical: AppSpacing.space8,
        ),
        child: Row(
          key: Key('backend-health-detail-check-${check.name}'),
          children: [
            Icon(presentation.icon, size: 20, color: presentation.color),
            const SizedBox(width: AppSpacing.space8),
            Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
            const SizedBox(width: AppSpacing.space8),
            Text(
              statusLabel,
              style: theme.textTheme.labelLarge?.copyWith(
                color: presentation.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explanatory paragraph for the three non-list states (pending, offline,
/// no entries reported).
class _SheetBody extends StatelessWidget {
  const _SheetBody({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space24,
        AppSpacing.space8,
        AppSpacing.space24,
        AppSpacing.space16,
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
