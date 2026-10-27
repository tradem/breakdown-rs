// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';

import '../../../data/photo_repository.dart';
import '../../../design/material_icons.dart';
import '../../../l10n/app_localizations_provider.dart';
import '../../photos/widgets/photo_gallery.dart';
import '../piece_identity.dart';
import '../pieces_state.dart';

/// Pure presentation trees for `PiecesScreen`: plain data + callbacks in,
/// widgets out — no Riverpod imports, theme roles only, semantic labels for
/// `find.text`-paired tests.
class PieceTile extends StatelessWidget {
  const PieceTile({
    super.key,
    required this.row,
    required this.photoRepository,
    required this.photoBytesLru,
    required this.canViewPhotos,
    this.onTap,
  });

  final PieceRow row;
  final PhotoRepository? photoRepository;
  final PhotoBytesLru photoBytesLru;
  final bool canViewPhotos;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final piece = switch (row) {
      ProjectedPieceRow(:final piece) => piece,
      OptimisticPieceRow(:final overlay) => overlay.overlay,
    };
    final identity = pieceTileIdentity(piece);
    final l10n = l10nOf(context);
    final name = pieceDisplayName(piece, l10n.pieceTileLabelFallback);
    final category = identity.categoryName ?? l10n.costumeCategoryUncategorized;
    final status = switch (row) {
      ProjectedPieceRow() => null,
      OptimisticPieceRow(:final overlay) => overlay,
    };
    return Semantics(
      key: status == null ? null : Key('overlay-${piece.id}'),
      label: '$name · $category',
      child: Card(
        key: Key('piece-tile-${piece.id}'),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _TileSurface(
                piece: piece,
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
                  pieceId: piece.id,
                  status: status,
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
    required this.piece,
    required this.photo,
    required this.canViewPhotos,
    required this.repository,
    required this.bytesLru,
    required this.categoryName,
  });

  final PieceView piece;
  final PiecePhotoView? photo;
  final bool canViewPhotos;
  final PhotoRepository? repository;
  final PhotoBytesLru bytesLru;
  final String? categoryName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (canViewPhotos && photo != null && repository != null) {
      return Image(
        key: Key('piece-photo-${piece.id}'),
        image: PhotoVariantImage(
          pieceId: piece.id,
          photo: photo!,
          variant: 'Thumb',
          repository: repository!,
          lru: bytesLru,
        ),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            _PlaceholderSurface(categoryName: categoryName, pieceId: piece.id),
      );
    }
    return _PlaceholderSurface(
      categoryName: categoryName,
      pieceId: piece.id,
      color: scheme.surfaceContainerHighest,
    );
  }
}

class _PlaceholderSurface extends StatelessWidget {
  const _PlaceholderSurface({
    required this.categoryName,
    required this.pieceId,
    this.color,
  });

  final String? categoryName;
  final String pieceId;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final surface = color ?? Theme.of(context).colorScheme.surfaceContainer;
    return ColoredBox(
      key: Key('piece-placeholder-$pieceId'),
      color: surface,
      child: Center(
        child: Icon(
          BreakdownMaterialIcons.forCostumeCategory(categoryName),
          key: Key('piece-placeholder-icon-$pieceId'),
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
    required this.pieceId,
    required this.status,
  });

  final String name;
  final String category;
  final String text;
  final String? categoryName;
  final String pieceId;
  final PieceRowOverlay? status;

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
                    key: Key('piece-name-$pieceId'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: onScrim, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  BreakdownMaterialIcons.forCostumeCategory(categoryName),
                  key: Key('piece-category-icon-$pieceId'),
                  size: 20,
                  color: onScrim,
                ),
              ],
            ),
            Text(
              category,
              key: Key('piece-category-label-$pieceId'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: onScrim),
            ),
            if (text.isNotEmpty)
              Text(
                text,
                key: Key('piece-text-$pieceId'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: onScrim),
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

class PiecesEmptyView extends StatelessWidget {
  const PiecesEmptyView({super.key, this.onCreate});

  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.checkroom_outlined, size: 48),
        const SizedBox(height: 8),
        // Honest empty state — never implies pieces exist that do not.
        Text(l10nOf(context).piecesEmpty, key: const Key('pieces-empty')),
        if (onCreate != null) ...[
          const SizedBox(height: 8),
          FilledButton.tonal(
            key: const Key('pieces-empty-create'),
            onPressed: onCreate,
            child: Text(l10nOf(context).pieceAddFab),
          ),
        ],
      ],
    ),
  );
}

class PiecesNotFoundView extends StatelessWidget {
  const PiecesNotFoundView({super.key, required this.code, this.onBack});

  final String code;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10nOf(context).charactersGone(code),
          key: const Key('pieces-gone'),
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
/// the command carries the picked id + the scene/piece version echo).
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
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            // l10n rule (issue #546 side-finding 3): never hardcode
            // user-facing copy — the Key-Parity-Gate counts on ARB keys.
            l10nOf(context).assignCharacterSheetTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
