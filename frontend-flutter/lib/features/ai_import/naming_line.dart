// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ai_import_providers.dart';
import '../../l10n/app_localizations_provider.dart';

/// The configured provider/model labelling line (EU AI Act Art. 50
/// transparency, issue #608): ONE compact text line rendering the wire
/// naming of the caller's NON-secret `AiConfigView` — copy in every state,
/// never a spinner trap and never an invented name:
///
/// - configured → `aiNamingLine` (provider + assistant model)
/// - unconfigured or discovery failure → the disclosure's honest
///   degradation copy (`aiDisclosureNamingBodyUnconfigured`)
/// - still loading → `aiDisclosureNamingBodyLoading` (re-renders to the
///   wire naming as soon as the discovery resolves; reloads do not flicker
///   back to loading).
///
/// Shared by the import-submit disclosure card, the preview screen and the
/// apply section. `configuredAiNamingProvider` is container-cached, so the
/// three surfaces share ONE discovery per container. Callers pass their
/// own semantic key (e.g. `Key('ai-apply-naming')`).
class AiNamingLine extends ConsumerWidget {
  const AiNamingLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final naming = ref.watch(configuredAiNamingProvider);
    return Text(
      naming.when(
        data: (configured) => configured == null
            ? l10nOf(context).aiDisclosureNamingBodyUnconfigured
            // gen-l10n positional order: placeholders are bound
            // ALPHABETICALLY (model, provider), not in the template's
            // appearance order — pass the model first (verified against
            // the generated de/en bodies).
            : l10nOf(context).aiNamingLine(
                configured.assistantModel,
                configured.provider.name,
              ),
        error: (_, _) => l10nOf(context).aiDisclosureNamingBodyUnconfigured,
        loading: () => l10nOf(context).aiDisclosureNamingBodyLoading,
        skipLoadingOnReload: true,
      ),
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
