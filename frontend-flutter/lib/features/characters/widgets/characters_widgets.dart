// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter/material.dart';

import '../../../domain/reconciliation/reconciliation_scheduler.dart';
import '../characters_state.dart';

/// Pure presentation trees for `CharactersScreen`: plain data + callbacks
/// in, widgets out — no Riverpod imports, theme roles only, semantic labels
/// for `find.text`-paired tests.
class CharacterTile extends StatelessWidget {
  const CharacterTile({super.key, required this.row, this.onTap});

  final CharacterRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => switch (row) {
    ProjectedCharacterRow(:final character) => Semantics(
      label: 'Character ${character.name}',
      child: ListTile(
        key: Key('character-${character.id}'),
        minTileHeight: 48,
        title: Text(character.name, key: Key('character-name-${character.id}')),
        subtitle: Text(characterCategoryLabel(character)),
        trailing: const Icon(Icons.person_outline),
        onTap: onTap,
      ),
    ),
    OptimisticCharacterRow(:final overlay) => ListTile(
      key: Key('overlay-${overlay.id}'),
      minTileHeight: 48,
      title: Text(overlay.name ?? ''),
      subtitle: Text(
        overlay.status == OverlayStatus.stale
            ? (overlay.warning ?? kReconcileStaleWarning)
            : 'Just created — syncing…',
      ),
      trailing: overlay.status == OverlayStatus.stale
          ? const Icon(Icons.cloud_off, key: Key('overlay-warning'))
          : const SizedBox(
              key: Key('overlay-spinner'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
    ),
  };
}

class CharactersEmptyView extends StatelessWidget {
  const CharactersEmptyView({super.key, this.onCreate});

  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.person_outline, size: 48),
        const SizedBox(height: 8),
        // Honest empty state — never implies characters exist that do not.
        const Text('No characters yet', key: Key('characters-empty')),
        if (onCreate != null) ...[
          const SizedBox(height: 8),
          FilledButton.tonal(
            key: const Key('characters-empty-create'),
            onPressed: onCreate,
            child: const Text('Create character'),
          ),
        ],
      ],
    ),
  );
}

class CharactersNotFoundView extends StatelessWidget {
  const CharactersNotFoundView({super.key, required this.code, this.onBack});

  final String code;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('The season is gone ($code).', key: const Key('characters-gone')),
        if (onBack != null)
          FilledButton.tonal(onPressed: onBack, child: const Text('Back')),
      ],
    ),
  );
}
