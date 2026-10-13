// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'package:flutter/material.dart';

import '../../l10n/app_localizations_provider.dart';

/// The inline command-failure banner shared by the create forms (issue #624).
///
/// Renders the localized copy (keyed on the stable problem `code`, never the
/// server's `detail`) in the theme's error container, with an optional
/// dismiss affordance. The forms use it so a full-screen create page and the
/// in-context sheet both surface a failure inline, instead of relying on the
/// list screen behind the sheet.
class CreateErrorBanner extends StatelessWidget {
  const CreateErrorBanner({
    super.key,
    required this.text,
    required this.dismissKey,
    this.onDismiss,
  });

  /// Localized failure copy.
  final String text;

  /// Test key for the dismiss button (each caller uses a distinct key so a
  /// form banner and the list screen's banner never collide in a finder).
  final Key dismissKey;

  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                onPressed: onDismiss,
                color: scheme.onErrorContainer,
                tooltip: l10nOf(context).episodesDismiss,
                icon: Icon(Icons.close, key: dismissKey),
              ),
          ],
        ),
      ),
    );
  }
}
