// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/spacing.dart';
import '../../l10n/app_localizations_provider.dart';
import '../../src/connectivity/connectivity_providers.dart';

/// Offline-mode pill (issue #654): a clearly visible, theme-token-only pill
/// rendered by the shell below the sticky top bar whenever the device is
/// offline or the connection is degraded (OS carrier without a usable
/// route), so users understand why read data may be stale (Drift cache, §8)
/// and commands fail with a retry affordance (§4).
///
/// Placement (settled decision for issue #654): the shell content column —
/// one surface visible on all three destinations and every pushed route
/// inside the tabs. The pill animates in/out (no user interaction needed on
/// either transition) and hides entirely when connectivity returns.
///
/// Color is never the sole carrier of meaning (glossary rule): the visible
/// localized label always names the offline state; the icon reinforces it.
/// Colors are color-scheme roles (`errorContainer`/`onErrorContainer`) —
/// no hardcoded colors (machine-checkable at review).
class OfflinePill extends ConsumerWidget {
  const OfflinePill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectivityControllerProvider);
    final visible = connectivityShowsPill(status);
    final scheme = Theme.of(context).colorScheme;
    final l10n = l10nOf(context);
    return ClipRect(
      // AnimatedSize collapses the slot to zero height when the pill hides,
      // so the content below reflows without user interaction (issue #654).
      child: AnimatedSize(
        key: const Key('shell-offline-pill'),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: visible
            ? Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space16,
                  AppSpacing.space8,
                  AppSpacing.space16,
                  AppSpacing.space4,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Semantics(
                    key: const Key('shell-offline-pill-semantics'),
                    liveRegion: true,
                    label: l10n.offlinePillLabel,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.space16,
                        vertical: AppSpacing.space8,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.wifi_off,
                            size: 18,
                            color: scheme.onErrorContainer,
                          ),
                          const SizedBox(width: AppSpacing.space8),
                          Text(
                            l10n.offlinePillLabel,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: scheme.onErrorContainer),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
    );
  }
}
