// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter/material.dart';

import '../../../domain/reconciliation/reconciliation_scheduler.dart';
import '../costumes_state.dart';

/// Pure presentation trees for `CostumesScreen`: plain data + callbacks in,
/// widgets out — no Riverpod imports, theme roles only, semantic labels for
/// `find.text`-paired tests.
class CostumeTile extends StatelessWidget {
  const CostumeTile({super.key, required this.row, this.onTap});

  final CostumeRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => switch (row) {
    ProjectedCostumeRow(:final costume, :final characterName) => Semantics(
      label: 'Costume ${costume.id}',
      child: ListTile(
        key: Key('costume-${costume.id}'),
        minTileHeight: 48,
        title: Text(
          costume.notes.isNotEmpty ? costume.notes : 'Costume ${costume.id}',
          key: Key('costume-title-${costume.id}'),
        ),
        subtitle: Text(
          [
            if (characterName != null) 'Worn by $characterName',
            if (costume.details.isNotEmpty) '${costume.details.length} details',
            if (costume.photos.isNotEmpty) '${costume.photos.length} photos',
          ].join(' · '),
        ),
        trailing: characterName != null
            ? const Icon(Icons.checkroom)
            : const Icon(Icons.checkroom_outlined),
        onTap: onTap,
      ),
    ),
    OptimisticCostumeRow(:final overlay) => ListTile(
      key: Key('overlay-${overlay.id}'),
      minTileHeight: 48,
      title: Text(
        overlay.overlay.notes.isNotEmpty
            ? overlay.overlay.notes
            : 'Costume ${overlay.id}',
      ),
      subtitle: Text(
        overlay.status == OverlayStatus.stale
            ? (overlay.warning ?? kReconcileStaleWarning)
            : 'Just saved — syncing…',
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

class CostumesEmptyView extends StatelessWidget {
  const CostumesEmptyView({super.key, this.onCreate});

  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.checkroom_outlined, size: 48),
        const SizedBox(height: 8),
        // Honest empty state — never implies costumes exist that do not.
        const Text('No costumes yet', key: Key('costumes-empty')),
        if (onCreate != null) ...[
          const SizedBox(height: 8),
          FilledButton.tonal(
            key: const Key('costumes-empty-create'),
            onPressed: onCreate,
            child: const Text('Create costume'),
          ),
        ],
      ],
    ),
  );
}

class CostumesNotFoundView extends StatelessWidget {
  const CostumesNotFoundView({super.key, required this.code, this.onBack});

  final String code;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('The season is gone ($code).', key: const Key('costumes-gone')),
        if (onBack != null)
          FilledButton.tonal(onPressed: onBack, child: const Text('Back')),
      ],
    ),
  );
}

/// Character picker sheet for assign (lists the season's `CharacterView`s;
/// the command carries the picked id + the scene/costume version echo).
class AssignCharacterSheet extends StatelessWidget {
  const AssignCharacterSheet({
    super.key,
    required this.characters,
    required this.assignedId,
  });

  final List<({String id, String name, String category})> characters;
  final String? assignedId;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Assign character',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: characters.length,
            itemBuilder: (context, i) {
              final c = characters[i];
              final selected = c.id == assignedId;
              return ListTile(
                key: Key('assign-character-${c.id}'),
                title: Text(c.name),
                subtitle: Text(c.category),
                trailing: selected ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(c.id),
              );
            },
          ),
        ),
      ],
    ),
  );
}
