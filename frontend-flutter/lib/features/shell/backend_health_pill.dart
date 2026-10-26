// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/spacing.dart';
import '../../l10n/app_localizations_provider.dart';
import '../../src/health/backend_health_providers.dart';
import 'backend_health_detail_sheet.dart';
import 'backend_health_presentation.dart';

/// Backend health-status pill (issue #657): sits at the TOP of the account
/// drawer (#653) and gives an at-a-glance quality signal for the backend,
/// derived from the public `GET /v1/health` readiness surface.
///
/// Color is never the sole carrier of meaning (glossary rule): the icon AND
/// the localized label always name the tier; screen readers announce the
/// label. The pill stays EMPTY (slot collapses) until the first probe has
/// answered (`null` state) so the drawer never flashes a wrong tier.
///
/// Tappable since issue #730: the whole pill is the tap target and opens
/// [showBackendHealthDetailSheet] — the drawer stays open underneath, so the
/// pill remains mounted and the autoDispose health controller keeps
/// polling while the sheet shows the per-dependency breakdown. The pill's
/// semantics node therefore carries an explicit BUTTON role, the localized
/// open hint, and the tap action itself (its child semantics are excluded to
/// keep the tier announcement single-sourced, #662).
///
/// Colors: the four tiers ride the DTCG semantic status tokens via
/// [backendHealthTierPresentation] (the sheet's aggregate row shares it).
/// They are placed as icon color on a neutral `surfaceContainerHighest`
/// surface; the material shape keeps the ink splash of the tap affordance
/// inside the pill's stadium outline.
class BackendHealthPill extends ConsumerWidget {
  const BackendHealthPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The pill only renders the coarse tier: select it so a poll that changes
    // nothing but the per-dependency list does not rebuild the drawer header.
    final tier = ref.watch(
      backendHealthControllerProvider.select((snapshot) => snapshot?.tier),
    );
    if (tier == null) {
      // No health data yet (first poll in flight): the slot stays empty
      // instead of asserting a tier nobody measured.
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final l10n = l10nOf(context);
    final presentation = backendHealthTierPresentation(
      tier,
      l10n: l10n,
      isLight: Theme.of(context).brightness == Brightness.light,
    );
    void openDetail() => unawaited(showBackendHealthDetailSheet(context));
    return Semantics(
      key: const Key('profile-health-pill-semantics'),
      label: presentation.label,
      hint: l10n.healthPillOpenHint,
      button: true,
      // The wrapper's label IS the announcement; exclude the child Text's
      // own semantics node so screen readers never announce the tier twice
      // (CodeRabbit #662 — same pattern as the OfflinePill). Excluding the
      // child also drops the InkWell's tap action, so this node carries it
      // (issue #730).
      excludeSemantics: true,
      onTap: openDetail,
      child: Material(
        key: const Key('profile-health-pill'),
        color: scheme.surfaceContainerHighest,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('profile-health-pill-tap'),
          onTap: openDetail,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space16,
              vertical: AppSpacing.space8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  presentation.icon,
                  key: const Key('profile-health-pill-icon'),
                  size: 18,
                  color: presentation.color,
                ),
                const SizedBox(width: AppSpacing.space8),
                // Flexible + ellipsis: the longest tier label ("Backend
                // nicht erreichbar") must never overflow a narrow drawer at
                // large text scales.
                Flexible(
                  child: Text(
                    presentation.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: scheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
