// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

import 'package:flutter/material.dart';

import '../../design/spacing.dart';

/// Small labeled section header shared by the settings-family screens:
/// "Allgemein", the "Easter eggs" group, "KI" (AI section, issue #644),
/// "Entwicklung" (issue #516/#615) — and the dedicated Easter-eggs
/// screen's own switch/preview groups (issue #708).
///
/// Extracted from the settings screen so the settings entry list and the
/// screens it pushes render one identical grouping affordance instead of
/// duplicated private widgets.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space16,
        AppSpacing.space16,
        AppSpacing.space16,
        AppSpacing.space8,
      ),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
