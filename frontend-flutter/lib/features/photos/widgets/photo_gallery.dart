// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: space-bunny-free (opencode)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/problem_error.dart';
import '../../../core/result.dart';
import '../../../data/photo_repository.dart';
import '../../../l10n/app_localizations_provider.dart';
import '../../../l10n/generated/app_localizations.dart';

/// In-memory LRU bytes cache for photo variants (Task 3.3).
///
/// Keyed by `(photoId, variant)`; memory only, never persisted to Drift (the
/// cache is a read-model store, not a blob store — views re-fetch after
/// process death, acceptable for 20 MB-capped variants, thumbnails first).
/// Large-image decode runs on a background isolate so the grid never janks.
class PhotoBytesLru {
  PhotoBytesLru({this.capacity = 32});

  final int capacity;
  final LinkedHashMap<String, Uint8List> _entries = LinkedHashMap();

  static String key(String photoId, String variant) => '$photoId@$variant';

  Uint8List? get(String photoId, String variant) {
    final bytes = _entries.remove(key(photoId, variant));
    if (bytes == null) return null;
    // Re-insert to mark most-recently-used.
    _entries[key(photoId, variant)] = bytes;
    return bytes;
  }

  void put(String photoId, String variant, Uint8List bytes) {
    _entries.remove(key(photoId, variant));
    _entries[key(photoId, variant)] = bytes;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  void remove(String photoId) {
    _entries.removeWhere((k, _) => k.startsWith('$photoId@'));
  }

  /// Drops all memoized bytes (sign-out: decoded photo bytes must not
  /// survive an identity change in the app-level provider scope).
  void clear() => _entries.clear();

  @visibleForTesting
  int get length => _entries.length;
}

final photoBytesLruProvider = Provider<PhotoBytesLru>((_) => PhotoBytesLru());

/// One photo rendered by the gallery: the id plus its variant set.
///
/// Both photo DTOs of the wardrobe split — [PiecePhotoView] (garment photos)
/// and [OutfitPhotoView] (fitting photos) — carry exactly this shape, so the
/// gallery works on this neutral row instead of forking per aggregate.
class GalleryPhoto {
  const GalleryPhoto({required this.id, required this.variants});

  factory GalleryPhoto.fromPiece(PiecePhotoView photo) =>
      GalleryPhoto(id: photo.id, variants: photo.variants);

  factory GalleryPhoto.fromOutfit(OutfitPhotoView photo) =>
      GalleryPhoto(id: photo.id, variants: photo.variants);

  final String id;
  final BuiltList<PhotoVariantView> variants;
}

/// Variant byte source for one owner (piece or outfit): the owning screen
/// supplies the AUTHZ-GATE'd fetch, so the gallery never issues the gate
/// itself and never knows which aggregate it renders.
typedef PhotoVariantFetch = Future<Result<Uint8List>> Function(
  String photoId,
  String variant,
);

/// Repository-backed [ImageProvider] for one photo variant.
///
/// Bytes come from [PhotoRepository.getBytes] (AUTHZ-GATE'd before the call
/// by the owning screen) and are memoized in [photoBytesLruProvider].
/// Decoding runs off the UI thread via [instantiateImageCodec]'s background
/// path (large images never jank the grid).
class PhotoVariantImage extends ImageProvider<PhotoVariantImageKey> {
  const PhotoVariantImage({
    required this.ownerId,
    required this.photoId,
    required this.variant,
    required this.fetch,
    required this.lru,
    this.scale = 1.0,
  });

  /// The owning aggregate id (piece or outfit — the fetch is already bound).
  final String ownerId;
  final String photoId;
  final String variant;
  final PhotoVariantFetch fetch;
  final PhotoBytesLru lru;
  final double scale;

  @override
  Future<PhotoVariantImageKey> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(
        PhotoVariantImageKey(
          ownerId,
          photoId,
          variant,
          configuration.devicePixelRatio,
        ),
      );
  @override
  ImageStreamCompleter loadImage(
    PhotoVariantImageKey key,
    ImageDecoderCallback decode,
  ) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      chunkEvents: chunkEvents.stream,
      codec: _loadBytes(key, chunkEvents, decode),
      scale: key.scale,
      debugLabel: 'PhotoVariantImage($photoId@$variant)',
    );
  }

  Future<ui.Codec> _loadBytes(
    PhotoVariantImageKey key,
    StreamController<ImageChunkEvent> chunkEvents,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await _resolveBytes();
    await chunkEvents.close();
    if (bytes == null) {
      throw StateError('photo.bytes_failed:$photoId@$variant');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  /// Resolves the variant bytes (LRU first, then the AUTHZ-GATE'd fetch).
  /// Returns `null` when the fetch fails (errors are values upstream — the
  /// image layer surfaces a broken-image icon via `errorBuilder`).
  Future<Uint8List?> _resolveBytes() async {
    final cached = lru.get(photoId, variant);
    if (cached != null) return cached;
    // The fetch never throws (failures are `Result` values, never
    // exceptions) — the match below exhaustively handles both branches.
    final result = await fetch(photoId, variant);
    return result.match((_) => null, (b) {
      lru.put(photoId, variant, b);
      return b;
    });
  }
}

@immutable
class PhotoVariantImageKey {
  const PhotoVariantImageKey(
    this.ownerId,
    this.photoId,
    this.variant,
    this.pixelRatio,
  );

  /// Owner id first: two aggregates cannot collide in Flutter's image cache.
  final String ownerId;
  final String photoId;
  final String variant;
  final double? pixelRatio;

  double get scale => 1.0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoVariantImageKey &&
          other.ownerId == ownerId &&
          other.photoId == photoId &&
          other.variant == variant;

  @override
  int get hashCode => Object.hash(ownerId, photoId, variant);
}

/// Grid columns for the photo gallery by width class (token breakpoints):
/// 2 columns below 400 dp, 3 below 800 dp, 4 above (spec
/// flutter-photos-feature).
int photoGridColumns(double width) {
  if (width < 400) return 2;
  if (width < 800) return 3;
  return 4;
}

/// Variant status chip label for a photo (worst status wins: any `Failed`
/// surfaces the explanation + capture-again affordance; any `Pending` shows
/// the spinner state; all `Ready` shows nothing).
enum PhotoRowStatus { ready, pending, failed }

PhotoRowStatus photoRowStatus(GalleryPhoto photo) {
  // No variants yet (upload ack racing the saga): still processing, like
  // Pending — consistent with `isPhotoWatchTerminal`, which only ends
  // the pass once every variant is terminal.
  if (photo.variants.isEmpty) return PhotoRowStatus.pending;
  var pending = false;
  for (final v in photo.variants) {
    // Direct enum comparison (never serialized wire strings): a wire-name
    // change cannot silently promote a non-ready variant to ready.
    if (v.status == VariantStatus.failed) return PhotoRowStatus.failed;
    if (v.status == VariantStatus.pending) pending = true;
  }
  return pending ? PhotoRowStatus.pending : PhotoRowStatus.ready;
}

/// Photo gallery rendering from the photo references embedded in
/// `PieceView.photos` (there is no separate photo-list route).
///
/// Pure presentation tree: plain data + callbacks in, widgets out — no
/// Riverpod imports (the owning screen wires the repository + AUTHZ-GATE).
class PhotoGallery extends StatelessWidget {
  const PhotoGallery({
    super.key,
    required this.ownerId,
    required this.photos,
    required this.fetch,
    required this.lru,
    this.canCapture = false,
    this.onCapture,
    this.onDelete,
    this.onRetryCapture,
  });

  /// The owning aggregate id (piece or outfit) whose `photos` projection
  /// renders (read-DTO snapshots).
  final String ownerId;

  /// The owner's photos, mapped onto the aggregate-neutral [GalleryPhoto].
  final List<GalleryPhoto> photos;

  /// Bytes-fetch backend, already bound to the owner's route and gated via
  /// `// AUTHZ-GATE:` by the screen — the gallery never issues the gate.
  final PhotoVariantFetch fetch;
  final PhotoBytesLru lru;

  /// Whether the (gated) capture affordance renders.
  final bool canCapture;
  final VoidCallback? onCapture;

  /// Delete (the screen confirms first — no destructive dark pattern).
  final void Function(GalleryPhoto photo)? onDelete;

  /// Capture-again affordance for `Failed` variants (there is no
  /// variant-retry command — a new capture is picked).
  final VoidCallback? onRetryCapture;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return _EmptyGallery(
        ownerId: ownerId,
        canCapture: canCapture,
        onCapture: onCapture,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = photoGridColumns(constraints.maxWidth);
        return GridView.builder(
          key: Key('photo-gallery-$ownerId'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: photos.length,
          itemBuilder: (context, i) {
            final photo = photos[i];
            return PhotoTile(
              ownerId: ownerId,
              photo: photo,
              fetch: fetch,
              lru: lru,
              onDelete: onDelete == null ? null : () => onDelete!(photo),
              onRetryCapture: onRetryCapture,
            );
          },
        );
      },
    );
  }
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery({
    required this.ownerId,
    required this.canCapture,
    this.onCapture,
  });

  final String ownerId;
  final bool canCapture;
  final VoidCallback? onCapture;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.photo_library_outlined, size: 48),
        const SizedBox(height: 8),
        // Explicit empty state — no placeholder images pretending to be
        // photos (spec flutter-photos-feature).
        Text(
          l10nOf(context).photoGalleryEmpty,
          key: Key('photo-gallery-empty-$ownerId'),
        ),
        if (canCapture && onCapture != null) ...[
          const SizedBox(height: 8),
          FilledButton.tonal(
            key: Key('photo-capture-$ownerId'),
            onPressed: onCapture,
            child: Text(l10nOf(context).photoGalleryAddPhoto),
          ),
        ],
      ],
    ),
  );
}

/// One gallery tile: thumbnail (via [PhotoVariantImage], `Thumb` variant
/// first), variant status chip, delete affordance.
class PhotoTile extends StatelessWidget {
  const PhotoTile({
    super.key,
    required this.ownerId,
    required this.photo,
    required this.fetch,
    required this.lru,
    this.onDelete,
    this.onRetryCapture,
  });

  final String ownerId;
  final GalleryPhoto photo;
  final PhotoVariantFetch fetch;
  final PhotoBytesLru lru;
  final VoidCallback? onDelete;
  final VoidCallback? onRetryCapture;

  @override
  Widget build(BuildContext context) {
    final status = photoRowStatus(photo);
    return Semantics(
      // Semantic label carries "photo of piece X" (spec §5).
      label: l10nOf(context).photoTileSemantics(ownerId),
      child: Card(
        key: Key('photo-tile-${photo.id}'),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            switch (status) {
              PhotoRowStatus.ready => Image(
                key: Key('photo-thumb-${photo.id}'),
                image: PhotoVariantImage(
                  ownerId: ownerId,
                  photoId: photo.id,
                  variant: 'Thumb',
                  fetch: fetch,
                  lru: lru,
                ),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
              ),
              PhotoRowStatus.pending => const Center(
                child: CircularProgressIndicator(
                  key: Key('photo-pending-spinner'),
                  strokeWidth: 2,
                ),
              ),
              PhotoRowStatus.failed => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline),
                    const SizedBox(height: 4),
                    Text(
                      l10nOf(context).photoGalleryProcessingFailed,
                      key: const Key('photo-failed-explanation'),
                    ),
                    if (onRetryCapture != null)
                      TextButton(
                        key: Key('photo-capture-again-${photo.id}'),
                        onPressed: onRetryCapture,
                        child: Text(l10nOf(context).photoGalleryCaptureAgain),
                      ),
                  ],
                ),
              ),
            },
            if (status != PhotoRowStatus.ready)
              Positioned(
                top: 4,
                left: 4,
                child: _StatusChip(status: status, photoId: photo.id),
              ),
            if (onDelete != null)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  key: Key('photo-delete-${photo.id}'),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10nOf(context).photoGalleryDeleteTooltip,
                  onPressed: onDelete,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.photoId});

  final PhotoRowStatus status;
  final String photoId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: Key('photo-status-$photoId'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(switch (status) {
        PhotoRowStatus.pending => 'Processing…',
        PhotoRowStatus.failed => 'Failed',
        PhotoRowStatus.ready => 'Ready',
      }, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

/// Localized copy for photo command failures, keyed on the stable problem
/// `code` (never `detail` text).
String photoErrorCopy(AppLocalizations l10n, ProblemError error) =>
    switch (error.code) {
      'photo.too_large' => l10n.photoErrorTooLarge,
      'photo.unsupported_media_type' => l10n.photoErrorUnsupported,
      'photo.forbidden' ||
      'authz.denied' ||
      'domain.forbidden' => l10n.photoErrorForbidden,
      // Issue #535: the piece's owning series could not be resolved (no
      // repertoire entry, no outfit referencing it) — the server answers 422
      // with this code.
      'piece.container-unresolved' => l10n.photoErrorContainerUnresolved,
      _ when error.code.startsWith('transport.') => l10n.photoErrorNetwork,
      _ => l10n.photoErrorGeneric(error.code),
    };
