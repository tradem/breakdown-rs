// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/gen/design_tokens.g.dart';
import '../../design/spacing.dart';
import '../../l10n/app_localizations_provider.dart';
import '../../src/health/backend_health_providers.dart';

/// Backend health-status pill (issue #657): sits at the TOP of the account
/// drawer (#653) and gives an at-a-glance quality signal for the backend,
/// derived from the public `GET /v1/health` readiness surface.
///
/// Color is never the sole carrier of meaning (glossary rule): the icon AND
/// the localized label always name the tier; screen readers announce the
/// label. The pill stays EMPTY (slot collapses) until the first probe has
/// answered (`null` state) so the drawer never flashes a wrong tier.
///
/// Colors: the four tiers ride the DTCG semantic status tokens
/// (`colorSemanticSuccess` / `Warning` / `Error`, light variant on light
/// surfaces and dark variant on dark surfaces — the tokens are accent colors
/// designed per brightness, see `design/tokens/color.json`). They are placed
/// as icon color on a neutral `surfaceContainerHighest` container: M3 has no
/// `successContainer`/`warningContainer` roles, and the tokens are specified
/// as accent-on-surface colors, not container backgrounds. The two red tiers
/// (unhealthy/offline) share the error token with the #654 offline pill;
/// only the localized label and icon differ.
class BackendHealthPill extends ConsumerWidget {
  const BackendHealthPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tier = ref.watch(backendHealthControllerProvider);
    if (tier == null) {
      // No health data yet (first poll in flight): the slot stays empty
      // instead of asserting a tier nobody measured.
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final l10n = l10nOf(context);
    final (icon, label, color) = switch (tier) {
      BackendHealthTier.healthy => (
        Icons.check_circle,
        l10n.healthPillHealthy,
        isLight
            ? DesignTokens.colorSemanticSuccessLight
            : DesignTokens.colorSemanticSuccessDark,
      ),
      BackendHealthTier.degraded => (
        Icons.warning_amber_rounded,
        l10n.healthPillDegraded,
        isLight
            ? DesignTokens.colorSemanticWarningLight
            : DesignTokens.colorSemanticWarningDark,
      ),
      BackendHealthTier.unhealthy => (
        Icons.report,
        l10n.healthPillUnhealthy,
        isLight
            ? DesignTokens.colorSemanticErrorLight
            : DesignTokens.colorSemanticErrorDark,
      ),
      BackendHealthTier.offline => (
        Icons.cloud_off,
        l10n.healthPillOffline,
        isLight
            ? DesignTokens.colorSemanticErrorLight
            : DesignTokens.colorSemanticErrorDark,
      ),
    };
    return Semantics(
      key: const Key('profile-health-pill-semantics'),
      label: label,
      // The wrapper's label IS the announcement; exclude the child Text's
      // own semantics node so screen readers never announce the tier twice
      // (CodeRabbit #662 — same pattern as the OfflinePill).
      excludeSemantics: true,
      child: Container(
        key: const Key('profile-health-pill'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space16,
          vertical: AppSpacing.space8,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: AppSpacing.space8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: scheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
