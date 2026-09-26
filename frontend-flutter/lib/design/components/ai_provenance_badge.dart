// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

import 'package:flutter/material.dart';

import '../../l10n/app_localizations_provider.dart';

/// Shared EU-AI-Act provenance badge (spec `flutter-ai-import-workflow`
/// delta "Provenance badge on AI-derived read rows", issue #538).
///
/// AI-derived rows (`source = Some(AiExtracted)`) render ONE persistent,
/// semantically visible badge — on every read surface that carries the
/// discriminator. `Manual`, `absent` and unrecognized variants render
/// NOTHING — the badge element is withheld, never rendered as an
/// empty-text decoration (no false attribution in either direction).
///
/// Emblem: `smart_toy_outlined` (glossary "KI-Assistent *(info)"), icon
/// surface is `tertiaryContainer` so the badge reads distinct from select
/// chips' `secondaryContainer`. Copy is ARB-catalog only.
class AiProvenanceBadge extends StatelessWidget {
  const AiProvenanceBadge({super.key, this.semanticKey});

  /// Row-id-scoped test key (e.g. `shooting-day-ai-badge-<id>`).
  final String? semanticKey;

  @override
  Widget build(BuildContext context) => Container(
    key: semanticKey == null
        ? const Key('ai-provenance-badge')
        : Key(semanticKey!),
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.smart_toy_outlined,
          size: 12,
          color: Theme.of(context).colorScheme.tertiary,
        ),
        const SizedBox(width: 2),
        Text(
          l10nOf(context).aiProvenanceBadge,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onTertiaryContainer,
          ),
        ),
      ],
    ),
  );
}
