// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';

import '../../../data/photo_repository.dart';
import '../../../design/material_icons.dart';
import '../../../l10n/app_localizations_provider.dart';
import '../../photos/widgets/photo_gallery.dart';
import '../costume_identity.dart';
import '../costumes_state.dart';

/// Pure presentation trees for `CostumesScreen`: plain data + callbacks in,
/// widgets out — no Riverpod imports, theme roles only, semantic labels for
/// `find.text`-paired tests.
class CostumeTile extends StatelessWidget {
  const CostumeTile({
    super.key,
    required this.row,
    required this.photoRepository,
    required this.photoBytesLru,
    required this.canViewPhotos,
    this.onTap,
  });

  final CostumeRow row;
  final PhotoRepository? photoRepository;
  final PhotoBytesLru photoBytesLru;
  final bool canViewPhotos;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final costume = switch (row) {
      ProjectedCostumeRow(:final costume) => costume,
      OptimisticCostumeRow(:final overlay) => overlay.overlay,
    };
    final identity = costumeTileIdentity(costume);
    final l10n = l10nOf(context);
    final name = costumeDisplayName(costume, l10n.costumeTileLabelFallback);
    final category = identity.categoryName ?? l10n.costumeCategoryUncategorized;
    final status = switch (row) {
      ProjectedCostumeRow() => null,
      OptimisticCostumeRow(:final overlay) => overlay,
    };
    final characterName = switch (row) {
      ProjectedCostumeRow(:final characterName) => characterName,
      OptimisticCostumeRow(:final characterName) => characterName,
    };

    return Semantics(
      key: status == null ? null : Key('overlay-${costume.id}'),
      label: '$name · $category',
      child: Card(
        key: Key('costume-tile-${costume.id}'),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _TileSurface(
                costume: costume,
                photo: identity.photo,
                canViewPhotos: canViewPhotos,
                repository: photoRepository,
                bytesLru: photoBytesLru,
                categoryName: identity.categoryName,
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _TileIdentityOverlay(
                  name: name,
                  category: category,
                  text: identity.text,
                  categoryName: identity.categoryName,
                  costumeId: costume.id,
                  status: status,
                  characterName: characterName,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TileSurface extends StatelessWidget {
  const _TileSurface({
    required this.costume,
    required this.photo,
    required this.canViewPhotos,
    required this.repository,
    required this.bytesLru,
    required this.categoryName,
  });

  final CostumeView costume;
  final CostumePhotoView? photo;
  final bool canViewPhotos;
  final PhotoRepository? repository;
  final PhotoBytesLru bytesLru;
  final String? categoryName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (canViewPhotos && photo != null && repository != null) {
      return Image(
        key: Key('costume-photo-${costume.id}'),
        image: PhotoVariantImage(
          costumeId: costume.id,
          photo: photo!,
          variant: 'Thumb',
          repository: repository!,
          lru: bytesLru,
        ),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _PlaceholderSurface(
          categoryName: categoryName,
          costumeId: costume.id,
        ),
      );
    }
    return _PlaceholderSurface(
      categoryName: categoryName,
      costumeId: costume.id,
      color: scheme.surfaceContainerHighest,
    );
  }
}

class _PlaceholderSurface extends StatelessWidget {
  const _PlaceholderSurface({
    required this.categoryName,
    required this.costumeId,
    this.color,
  });

  final String? categoryName;
  final String costumeId;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final surface = color ?? Theme.of(context).colorScheme.surfaceContainer;
    return ColoredBox(
      key: Key('costume-placeholder-$costumeId'),
      color: surface,
      child: Center(
        child: Icon(
          BreakdownMaterialIcons.forCostumeCategory(categoryName),
          key: Key('costume-placeholder-icon-$costumeId'),
          size: 48,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TileIdentityOverlay extends StatelessWidget {
  const _TileIdentityOverlay({
    required this.name,
    required this.category,
    required this.text,
    required this.categoryName,
    required this.costumeId,
    required this.status,
    required this.characterName,
  });

  final String name;
  final String category;
  final String text;
  final String? categoryName;
  final String costumeId;
  final CostumeRowOverlay? status;
  final String? characterName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The scrim remains dark in both color schemes, so its foreground must
    // remain light in both as well.
    const onScrim = Colors.white;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.scrim.withValues(alpha: 0.05),
            scheme.scrim.withValues(alpha: 0.86),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    key: Key('costume-name-$costumeId'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: onScrim, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  BreakdownMaterialIcons.forCostumeCategory(categoryName),
                  key: Key('costume-category-icon-$costumeId'),
                  size: 20,
                  color: onScrim,
                ),
              ],
            ),
            Text(
              category,
              key: Key('costume-category-label-$costumeId'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: onScrim),
            ),
            if (characterName != null)
              Text(
                l10nOf(context).costumeWornBy(characterName!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: onScrim),
              ),
            if (text.isNotEmpty)
              Text(
                text,
                key: Key('costume-text-$costumeId'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onInverseSurface),
              ),
            if (status != null)
              Row(
                children: [
                  if (status!.status == OverlayStatus.stale)
                    Icon(
                      Icons.cloud_off,
                      key: const Key('overlay-warning'),
                      size: 16,
                      color: onScrim,
                    )
                  else
                    const SizedBox(
                      key: Key('overlay-spinner'),
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      status!.status == OverlayStatus.stale
                          ? (status!.warning ?? '')
                          : '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: onScrim),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
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
        Text(l10nOf(context).costumesEmpty, key: const Key('costumes-empty')),
        if (onCreate != null) ...[
          const SizedBox(height: 8),
          FilledButton.tonal(
            key: const Key('costumes-empty-create'),
            onPressed: onCreate,
            child: Text(l10nOf(context).costumeAddFab),
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
        Text(
          l10nOf(context).charactersGone(code),
          key: const Key('costumes-gone'),
        ),
        if (onBack != null)
          FilledButton.tonal(
            onPressed: onBack,
            child: Text(l10nOf(context).commonBack),
          ),
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
