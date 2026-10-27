// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:async';
import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/membership/membership_providers.dart';
import '../../core/problem_error.dart';
import '../../core/result.dart';
import '../../data/photo_repository.dart';
import '../../design/material_icons.dart';
import '../../l10n/app_localizations_provider.dart';
import '../photos/capture.dart';
import '../photos/prepare.dart';
import '../photos/widgets/photo_gallery.dart';
import '../pieces/piece_detail_screen.dart';
import '../pieces/pieces_controller.dart';
import 'outfit_list_section.dart';
import 'outfits_controller.dart';
import 'outfits_state.dart';

part 'outfit_detail_screen.g.dart';

/// Foreground-only variant watch for one look's fitting photos: bounded
/// backoff over `GET /v1/outfits/{id}` until every variant is terminal; the
/// subscription dies with the screen (no background polling).
@riverpod
Stream<PhotoWatchEvent<OutfitView>> outfitPhotoWatch(
  Ref ref,
  String characterId,
  String outfitId,
) async* {
  final photos = ref.watch(outfitPhotoRepositoryProvider);
  final controller = ref.read(outfitsControllerProvider(characterId).notifier);
  yield* photos.watchOutfit(outfitId, () => controller.loadDetail(outfitId));
}

/// One character's look: rename, notes, ordered garments with add/remove,
/// variant lineage + fork, and fitting photos.
///
/// Every write runs the client-side AUTHZ-GATE mirror (season-scoped role,
/// awaited) and applies the optimistic-after-2xx overlay with the version
/// fence; a read of the look itself is the authoritative row.
class OutfitDetailScreen extends ConsumerStatefulWidget {
  const OutfitDetailScreen({
    super.key,
    required this.season,
    required this.characterId,
    required this.outfitId,
  });

  final SeasonView season;
  final String characterId;
  final String outfitId;

  @override
  ConsumerState<OutfitDetailScreen> createState() => _OutfitDetailScreenState();
}

class _OutfitDetailScreenState extends ConsumerState<OutfitDetailScreen> {
  /// The single-look read (authoritative, includes photos + variants).
  OutfitView? _detail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetail());
  }

  Future<void> _loadDetail() async {
    if (!mounted) return;
    final res = await ref
        .read(outfitsControllerProvider(widget.characterId).notifier)
        .loadDetail(widget.outfitId);
    if (!mounted) return;
    res.match<void>((_) {}, (view) {
      if (!mounted) return;
      setState(() => _detail = view);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final state = ref.watch(outfitsControllerProvider(widget.characterId));
    final controller = ref.read(
      outfitsControllerProvider(widget.characterId).notifier,
    );
    // The freshest row: the optimistic overlay (if any) wins over the
    // projected list row; the single-look read is the last resort.
    final outfit =
        state.rowById(widget.outfitId) ??
        _detail ??
        _projectedRow(state, widget.outfitId);

    // AUTHZ-GATE: every outfit mutation is gated by the backend's
    // handler-internal season-scoped role check; mirror it with the awaited
    // membership (pending disables, a resolved denial never issues a request).
    final membership = ref.watch(currentMembershipProvider(widget.season.id));
    final canManage = switch (membership) {
      AsyncData(:final value) => value.hasActiveCostumeRoleInSeason,
      _ => false,
    };
    final denied = switch (membership) {
      AsyncData(:final value) => !value.hasActiveCostumeRoleInSeason,
      _ => false,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(outfit?.name ?? l10n.outfitDetailTitle),
        actions: [
          if (outfit != null && canManage)
            IconButton(
              key: const Key('outfit-rename'),
              tooltip: l10n.outfitRenameTitle,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _rename(outfit, controller),
            ),
        ],
      ),
      body: switch (outfit) {
        final row? => RefreshIndicator(
          onRefresh: _loadDetail,
          child: ListView(
            key: Key('outfit-detail-${widget.outfitId}'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (denied)
                Text(
                  l10n.outfitErrorForbidden,
                  key: const Key('outfit-denied-narrative'),
                ),
              if (state.commandError case final failure?)
                Card(
                  key: const Key('outfit-command-error'),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: Text(outfitCommandErrorCopy(l10n, failure)),
                    trailing: IconButton(
                      onPressed: controller.clearError,
                      icon: const Icon(Icons.close),
                      tooltip: l10n.commonClose,
                    ),
                  ),
                ),
              if (row.variantOf case final source?)
                _VariantLineage(
                  sourceId: source,
                  characterId: widget.characterId,
                  onOpen: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => OutfitDetailScreen(
                        season: widget.season,
                        characterId: widget.characterId,
                        outfitId: source,
                      ),
                    ),
                  ),
                ),
              _PiecesSection(
                season: widget.season,
                outfit: row,
                canManage: canManage,
                onAdd: () => _addPiece(row, controller),
                onRemove: (pieceId) => _removePiece(row, pieceId, controller),
                onOpenPiece: (pieceId) => unawaited(_openPiece(pieceId)),
              ),
              const Divider(height: 32),
              _NotesSection(
                outfit: row,
                canManage: canManage,
                onSave: (notes) => controller.saveNotes(
                  row,
                  notes,
                  seasonId: widget.season.id,
                ),
              ),
              const Divider(height: 32),
              _OutfitPhotosSection(
                season: widget.season,
                characterId: widget.characterId,
                outfit: row,
                canManage: canManage,
                onRefreshDetail: _loadDetail,
              ),
              if (canManage) ...[
                const Divider(height: 32),
                FilledButton.tonalIcon(
                  key: const Key('outfit-create-variant'),
                  onPressed: () => _createVariant(row, controller),
                  icon: const Icon(Icons.copy_all_outlined),
                  label: Text(l10n.outfitCreateVariant),
                ),
              ],
            ],
          ),
        ),
        null => Center(
          child: state.projected is AsyncLoading
              ? const CircularProgressIndicator(key: Key('outfit-loading'))
              : _MissingLook(onBack: () => Navigator.of(context).pop()),
        ),
      },
    );
  }

  OutfitView? _projectedRow(OutfitsScreenState state, String id) {
    for (final row in state.cachedRows) {
      if (row.id == id) return row;
    }
    return null;
  }

  Future<void> _rename(OutfitView outfit, OutfitsController controller) async {
    final name = await showOutfitNameDialog(
      context,
      title: l10nOf(context).outfitRenameTitle,
      initial: outfit.name,
    );
    if (name == null || name == outfit.name) return;
    // Handled: failures surface through the command-error banner.
    final result = await controller.rename(
      outfit,
      name,
      seasonId: widget.season.id,
    );
    if (result.isRight() && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10nOf(context).outfitSaved)));
      await _loadDetail();
    }
  }

  Future<void> _createVariant(
    OutfitView outfit,
    OutfitsController controller,
  ) async {
    // Handled: failures surface through the command-error banner.
    final result = await controller.createVariant(
      outfit,
      seasonId: widget.season.id,
    );
    result.match<void>((_) {}, (id) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10nOf(context).outfitVariantCreated)),
      );
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OutfitDetailScreen(
            season: widget.season,
            characterId: widget.characterId,
            outfitId: id,
          ),
        ),
      );
    });
  }

  Future<void> _addPiece(
    OutfitView outfit,
    OutfitsController controller,
  ) async {
    final pieces = await _seasonPiecesForPicker();
    if (!mounted) return;
    final failure = pieces.fold<ProblemError?>((err) => err, (_) => null);
    if (failure != null) {
      // A failed fetch must never read as an empty repertoire: the picker's
      // empty state answers "this season has no garments", which is a
      // different (and false) claim — and it offers no way back. The failure
      // gets its own localized narrative, the dropped fetch makes the retry
      // re-request, and the dialog never opens with a phantom-empty list.
      ref.invalidate(piecesListFetchProvider(widget.season.id));
      final l10n = l10nOf(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('outfit-piece-fetch-error'),
          content: Text(l10n.outfitPieceListFetchError(failure.code)),
          action: SnackBarAction(
            label: l10n.commonRetry,
            onPressed: () => _addPiece(outfit, controller),
          ),
        ),
      );
      return;
    }
    final held = outfit.pieces.map((p) => p.pieceId).toSet();
    final candidates = [
      for (final piece in pieces.getOrElse((_) => const <PieceView>[]))
        if (!held.contains(piece.id)) piece,
    ];
    final picked = await showPickPieceDialog(context, candidates);
    if (picked == null) return;
    // Handled: failures surface through the command-error banner.
    final result = await controller.addPiece(
      outfit,
      picked,
      seasonId: widget.season.id,
    );
    if (result.isRight()) await _loadDetail();
  }

  /// The season's garment projection for the picker, awaited through its fetch
  /// seam. The picker reads the projection the user acts on — never a second
  /// lookup to fill the command payload — and the seam is awaited first because
  /// the detail route is reachable straight from the character surface
  /// (Character → Looks → detail) without the piece chain ever having been
  /// watched.
  ///
  /// The fetch provider is auto-dispose and a bare `ref.read(...future)` holds
  /// no listener: the request could outlive the provider and its generation
  /// fence would then reject the cache write. The subscription is held for the
  /// duration of the await and released afterwards.
  Future<Result<List<PieceView>>> _seasonPiecesForPicker() async {
    final fetch = piecesListFetchProvider(widget.season.id);
    final subscription = ref.listenManual(fetch, (_, _) {});
    try {
      return await ref.read(fetch.future);
    } finally {
      subscription.close();
    }
  }

  Future<void> _removePiece(
    OutfitView outfit,
    String pieceId,
    OutfitsController controller,
  ) async {
    final l10n = l10nOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.outfitPiecesTitle('${outfit.pieces.length}')),
        content: Text(l10n.outfitRemovePieceTooltip),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: Key('outfit-remove-piece-confirm-$pieceId'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // Handled: failures surface through the command-error banner.
    final result = await controller.removePiece(
      outfit,
      pieceId,
      seasonId: widget.season.id,
    );
    if (result.isRight()) await _loadDetail();
  }

  /// Piece ↔ look navigation: the garment opens in the look's season.
  ///
  /// The route future is handled (the navigation can be dismissed by a
  /// system back gesture; nothing awaits the popped value).
  Future<void> _openPiece(String pieceId) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          PieceDetailScreen(season: widget.season, pieceId: pieceId),
    ),
  );
}

class _VariantLineage extends ConsumerWidget {
  const _VariantLineage({
    required this.sourceId,
    required this.characterId,
    required this.onOpen,
  });

  final String sourceId;
  final String characterId;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final view = ref.watch(outfitsViewProvider(characterId));
    final sourceName = view.rows
        .where((o) => o.id == sourceId)
        .map((o) => o.name)
        .firstOrNull;
    return ListTile(
      key: const Key('outfit-variant-lineage'),
      leading: const Icon(Icons.copy_all_outlined),
      title: Text(
        sourceName == null
            ? l10n.outfitVariantMarker
            : l10n.outfitVariantOf(sourceName),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onOpen,
    );
  }
}

class _PiecesSection extends StatelessWidget {
  const _PiecesSection({
    required this.season,
    required this.outfit,
    required this.canManage,
    required this.onAdd,
    required this.onRemove,
    required this.onOpenPiece,
  });

  final SeasonView season;
  final OutfitView outfit;
  final bool canManage;
  final VoidCallback onAdd;
  final void Function(String pieceId) onRemove;
  final void Function(String pieceId) onOpenPiece;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final ordered = [...outfit.pieces]
      ..sort((a, b) => a.position.compareTo(b.position));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.outfitPiecesTitle('${ordered.length}'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            TextButton.icon(
              key: const Key('outfit-add-piece'),
              onPressed: canManage ? onAdd : null,
              icon: const Icon(Icons.add),
              label: Text(l10n.outfitAddPiece),
            ),
          ],
        ),
        if (ordered.isEmpty)
          Text(l10n.outfitPiecesEmpty, key: const Key('outfit-pieces-empty'))
        else
          for (final piece in ordered)
            ListTile(
              key: Key('outfit-piece-row-${piece.pieceId}'),
              leading: Icon(_categoryIcon(piece.categoryName)),
              title: Text(piece.name ?? piece.categoryName ?? ''),
              subtitle: Text(
                piece.categoryName ?? l10n.costumeCategoryUncategorized,
              ),
              trailing: canManage
                  ? IconButton(
                      key: Key('outfit-piece-remove-${piece.pieceId}'),
                      tooltip: l10n.outfitRemovePieceTooltip,
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => onRemove(piece.pieceId),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: () => onOpenPiece(piece.pieceId),
            ),
      ],
    );
  }

  IconData _categoryIcon(String? categoryName) =>
      BreakdownMaterialIcons.forCostumeCategory(categoryName);
}

class _NotesSection extends StatefulWidget {
  const _NotesSection({
    required this.outfit,
    required this.canManage,
    required this.onSave,
  });

  final OutfitView outfit;
  final bool canManage;
  final Future<Object?> Function(String notes) onSave;

  @override
  State<_NotesSection> createState() => _NotesSectionState();
}

class _NotesSectionState extends State<_NotesSection> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.outfit.notes,
  );

  @override
  void didUpdateWidget(covariant _NotesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A fresh projected row replaces the buffer only when the user is not
    // editing (identical text is a no-op).
    if (oldWidget.outfit.id != widget.outfit.id ||
        (oldWidget.outfit.version != widget.outfit.version &&
            _controller.text == oldWidget.outfit.notes)) {
      _controller.text = widget.outfit.notes;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final dirty = _controller.text.trim() != widget.outfit.notes.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.outfitNotes, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          key: const Key('outfit-notes-field'),
          controller: _controller,
          enabled: widget.canManage,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(hintText: l10n.outfitNotesHint),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const Key('outfit-notes-save'),
            onPressed: widget.canManage && dirty
                ? () => widget.onSave(_controller.text.trim())
                : null,
            child: Text(l10n.outfitSaveNotes),
          ),
        ),
      ],
    );
  }
}

class _OutfitPhotosSection extends ConsumerStatefulWidget {
  const _OutfitPhotosSection({
    required this.season,
    required this.characterId,
    required this.outfit,
    required this.canManage,
    required this.onRefreshDetail,
  });

  final SeasonView season;
  final String characterId;
  final OutfitView outfit;
  final bool canManage;
  final Future<void> Function() onRefreshDetail;

  @override
  ConsumerState<_OutfitPhotosSection> createState() =>
      _OutfitPhotosSectionState();
}

class _OutfitPhotosSectionState extends ConsumerState<_OutfitPhotosSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final watch = ref.watch(
      outfitPhotoWatchProvider(widget.characterId, widget.outfit.id),
    );
    // The watch's terminal/progress view is the freshest photo set; fall back
    // to the row while the stream warms up.
    final live = watch.value?.view;
    final view = live ?? widget.outfit;
    final repo = widget.canManage
        ? ref.watch(outfitPhotoRepositoryProvider)
        : null;
    final lru = ref.watch(photoBytesLruProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.outfitPhotos, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (repo != null)
          PhotoGallery(
            ownerId: view.id,
            photos: [
              for (final photo in view.photos) GalleryPhoto.fromOutfit(photo),
            ],
            fetch: (photoId, variant) =>
                repo.getOutfitBytes(view.id, photoId, variant),
            lru: lru,
            canCapture: widget.canManage,
            onCapture: widget.canManage
                ? () => _capture(ImageSource.camera)
                : null,
            onDelete: widget.canManage
                ? (photo) => _confirmDelete(photo.id)
                : null,
            onRetryCapture: widget.canManage
                ? () => _capture(ImageSource.camera)
                : null,
          )
        else
          Text(
            l10n.photoGalleryEmpty,
            key: Key('outfit-photo-gallery-empty-${view.id}'),
          ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(key: Key('outfit-photo-progress')),
          ),
        if (widget.canManage) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.tonalIcon(
                key: const Key('outfit-photo-camera'),
                onPressed: _busy ? null : () => _capture(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: Text(l10n.pieceDetailCamera),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                key: const Key('outfit-photo-gallery'),
                onPressed: _busy ? null : () => _capture(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: Text(l10n.pieceDetailGallery),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _capture(ImageSource source) async {
    final picker = ref.read(imagePickerProvider);
    final seen = ref.read(photoRationaleSeenProvider);
    setState(() => _busy = true);
    try {
      final outcome = await runCaptureIntent(
        source: source,
        picker: picker,
        rationaleSeen: seen,
        markRationaleSeen: () =>
            ref.read(photoRationaleSeenProvider.notifier).markSeen(),
        showRationale: _showRationale,
      );
      if (!mounted) return;
      switch (outcome) {
        case CapturePicked(:final file):
          await _prepareAndUpload(file);
        case CaptureDenied(:final source):
          await _showDenied(source);
        case CaptureUnavailable():
          _showUnavailable();
        case CaptureCancelled():
          break;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _showRationale() async {
    final l10n = l10nOf(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.pieceDetailPromptTitle),
        content: Text(l10n.pieceDetailPromptBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.pieceDetailNotNow),
          ),
          FilledButton(
            key: const Key('outfit-photo-rationale-accept'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.pieceDetailContinue),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }

  Future<void> _showDenied(ImageSource source) {
    final denied = CaptureDenied(source);
    final l10n = l10nOf(context);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(captureDeniedTitle(l10n, denied)),
        content: Text(captureOutcomeCopy(l10n, denied)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.settingsClose),
          ),
          FilledButton(
            key: const Key('outfit-photo-open-settings'),
            onPressed: () async {
              await ref.read(openAppSettingsProvider)();
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: Text(l10n.pieceDetailOpenSettings),
          ),
        ],
      ),
    );
  }

  void _showUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          captureOutcomeCopy(l10nOf(context), const CaptureUnavailable()),
        ),
      ),
    );
  }

  Future<void> _prepareAndUpload(XFile file) async {
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on Object {
      if (!mounted) return;
      _showError(const ProblemError(code: 'photo.read_failed'));
      return;
    }
    final contentType =
        contentTypeForExtension(file.name.split('.').lastOrNull ?? '') ??
        'image/jpeg';
    final prepared = await ref.read(preparePhotoProvider)(
      PrepareInput(bytes: bytes, contentType: contentType),
    );
    if (!mounted) return;
    switch (prepared) {
      case PrepareReady(:final bytes, :final contentType):
        // Handled: failures surface through the command-error banner.
        final result = await ref
            .read(outfitsControllerProvider(widget.characterId).notifier)
            .uploadPhoto(
              outfit: widget.outfit,
              bytes: bytes,
              contentType: contentType,
              seasonId: widget.season.id,
            );
        result.match<void>((_) {}, (_) {});
        if (result.isRight()) await widget.onRefreshDetail();
      case PrepareFailure(:final code):
        _showError(ProblemError(code: code));
    }
  }

  Future<void> _confirmDelete(String photoId) {
    final l10n = l10nOf(context);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.photoDeleteTitle),
        content: Text(l10n.pieceDetailDeletePhotoMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: Key('outfit-photo-delete-confirm-$photoId'),
            onPressed: () async {
              // Handled: failures surface through the command-error banner.
              final result = await ref
                  .read(outfitsControllerProvider(widget.characterId).notifier)
                  .deletePhoto(
                    outfit: widget.outfit,
                    photoId: photoId,
                    seasonId: widget.season.id,
                  );
              result.match<void>((_) {}, (_) {});
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              if (result.isRight()) await widget.onRefreshDetail();
            },
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
  }

  void _showError(ProblemError error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(photoErrorCopy(l10nOf(context), error))),
    );
  }
}

/// Garment picker for one look: the season's pieces the look does not hold
/// yet. A selection-only sheet (editing stays on the piece screens).
Future<PieceView?> showPickPieceDialog(
  BuildContext context,
  List<PieceView> candidates,
) {
  final l10n = l10nOf(context);
  return showDialog<PieceView>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.outfitPickPieceTitle),
      content: SizedBox(
        width: 480,
        child: candidates.isEmpty
            ? Text(
                l10n.outfitPickPieceEmpty,
                key: const Key('outfit-pick-piece-empty'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final piece in candidates)
                    ListTile(
                      key: Key('outfit-pick-piece-${piece.id}'),
                      leading: Icon(
                        BreakdownMaterialIcons.forCostumeCategory(
                          piece.categoryName,
                        ),
                      ),
                      title: Text(piece.name),
                      subtitle: Text(
                        piece.categoryName ?? l10n.costumeCategoryUncategorized,
                      ),
                      onTap: () => Navigator.of(dialogContext).pop(piece),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.commonCancel),
        ),
      ],
    ),
  );
}

class _MissingLook extends StatelessWidget {
  const _MissingLook({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10nOf(context).outfitDetailGone,
          key: const Key('outfit-detail-gone'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: onBack,
          child: Text(l10nOf(context).commonBack),
        ),
      ],
    ),
  );
}
