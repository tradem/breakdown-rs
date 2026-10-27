// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../auth/membership/capability.dart';
import '../../auth/membership/membership_providers.dart';
import '../../core/problem_error.dart';
import '../../data/photo_repository.dart';
import '../../l10n/app_localizations_provider.dart';
import '../blocks/active_block_gate.dart';
import '../blocks/blocks_controller.dart';
import 'piece_detail_screen.dart';
import 'pieces_controller.dart';
import 'pieces_state.dart';
import '../photos/widgets/photo_gallery.dart';
import 'widgets/pieces_widgets.dart';

/// `PiecesScreen` — the season's pieces and the inline piece editor.
///
/// Create dispatches the empty-body `POST /v1/pieces` after the session
/// AUTHZ-GATE. Selecting a tile opens the editor in this screen; there is no
/// separate detail route.
class PiecesScreen extends ConsumerStatefulWidget {
  const PiecesScreen({super.key, required this.season});

  final SeasonView season;

  @override
  ConsumerState<PiecesScreen> createState() => _PiecesScreenState();
}

class _PiecesScreenState extends ConsumerState<PiecesScreen> {
  String? _selectedId;
  final _editorAdapterKey = GlobalKey();
  SeasonView get season => widget.season;

  @override
  Widget build(BuildContext context) {
    ref.listen(authSessionControllerProvider, (_, session) {
      final signedOut =
          (session is AsyncData && session.value == null) ||
          session is AsyncError;
      if (signedOut && context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    final resolution = ref.watch(blockScopeResolutionProvider(season.id));
    switch (resolution) {
      case AsyncLoading():
        return BlockScopeLoadingScaffold(title: l10nOf(context).navWardrobe);
      case AsyncError(:final error):
        return BlockScopeErrorScaffold(
          title: l10nOf(context).navWardrobe,
          code: blockScopeErrorCode(error),
          onRetry: () => ref.refresh(blocksListFetchProvider(season.id)),
        );
      case AsyncData(:final value):
        // Issue #378: season-direct entry has no block in context —
        // resolve the sticky scope before any block-scoped fetch fires.
        // Ready scope falls through to the content below; otherwise a
        // placeholder is returned (no headerless request ever fires).
        if (value.scope == null) {
          final candidates = value.candidates;
          if (candidates != null) {
            return BlockScopePickerScaffold(
              title: l10nOf(context).navWardrobe,
              seasonId: season.id,
              candidates: candidates,
            );
          }
          return NoBlocksHintScaffold(title: l10nOf(context).navWardrobe);
        }
    }
    final state = ref.watch(piecesControllerProvider(season.id));
    final controller = ref.read(piecesControllerProvider(season.id).notifier);
    final rows = state.rows;
    final notFound = state.notFound;
    final canViewPhotos = switch (ref.watch(
      currentMembershipProvider(season.id),
    )) {
      AsyncData(:final value) => value.canUploadContinuityPhotos,
      _ => false,
    };
    // Do not construct the photo repository until the capability is known.
    // No photo repository means no bytes request.
    final photoRepository = canViewPhotos
        ? ref.watch(piecePhotoRepositoryProvider)
        : null;
    final photoBytesLru = ref.watch(photoBytesLruProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10nOf(context).navWardrobe)),
      body: Column(
        children: [
          if (state.commandError case final failure?)
            _Banner(
              key: const Key('piece-command-error-banner'),
              text: pieceCommandErrorCopy(l10nOf(context), failure),
              onDismiss: controller.dismissCommandError,
            ),
          if (state.isStale && notFound == null)
            _Banner(
              key: const Key('pieces-stale-banner'),
              text: l10nOf(context).piecesStaleBanner,
            ),
          Expanded(
            child: notFound != null
                ? PiecesNotFoundView(
                    code: notFound.code,
                    onBack: () => Navigator.of(context).pop(),
                  )
                : RefreshIndicator(
                    onRefresh: controller.refresh,
                    child: switch (state.projected) {
                      AsyncLoading() when rows.isEmpty => const Center(
                        child: CircularProgressIndicator(
                          key: Key('pieces-loading'),
                        ),
                      ),
                      AsyncError(:final error) when rows.isEmpty =>
                        _FetchErrorView(
                          code: error is ProblemError ? error.code : 'unknown',
                          onRetry: () => controller.refresh(),
                        ),
                      _ =>
                        rows.isEmpty
                            ? ListView(
                                key: const Key('pieces-list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 160),
                                  PiecesEmptyView(
                                    onCreate: _canCreate(ref)
                                        ? () => _createAndShowEditor(ref)
                                        : null,
                                  ),
                                ],
                              )
                            : _PieceOverview(
                                rows: rows,
                                season: season,
                                canViewPhotos: canViewPhotos,
                                photoRepository: photoRepository,
                                photoBytesLru: photoBytesLru,
                                selectedId: _selectedId,
                                editorAdapterKey: _editorAdapterKey,
                                onSelect: _selectPiece,
                              ),
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _canCreate(ref)
          ? FloatingActionButton(
              key: const Key('piece-add-fab'),
              onPressed: () => _createAndShowEditor(ref),
              tooltip: l10nOf(context).pieceAddFab,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  bool _canCreate(WidgetRef ref) {
    final session = ref.watch(authSessionControllerProvider);
    return session is AsyncData && session.value != null;
  }

  /// Catalogues a new piece and keeps the editor on the first screen.
  ///
  /// The aggregate requires a non-blank name (422 `piece.validation`), so the
  /// create path sends the localized fallback label; the crew renames it in
  /// the detail panel, which is the first thing the editor opens anyway.
  Future<void> _createAndShowEditor(WidgetRef ref) async {
    final result = await ref
        .read(piecesControllerProvider(season.id).notifier)
        .create(name: l10nOf(context).pieceTileLabelFallback);
    final id = result.match((_) => null, (ack) => ack.id);
    if (id != null && mounted) _selectPiece(id);
  }

  void _selectPiece(String id) {
    setState(() => _selectedId = id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final editorContext = _editorAdapterKey.currentContext;
      if (editorContext == null) return;
      unawaited(
        Scrollable.ensureVisible(
          editorContext,
          alignment: 0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    });
  }
}

class _PieceOverview extends StatelessWidget {
  const _PieceOverview({
    required this.rows,
    required this.season,
    required this.canViewPhotos,
    required this.photoRepository,
    required this.photoBytesLru,
    required this.selectedId,
    required this.editorAdapterKey,
    required this.onSelect,
  });

  final List<PieceRow> rows;
  final SeasonView season;
  final bool canViewPhotos;
  final PhotoRepository? photoRepository;
  final PhotoBytesLru photoBytesLru;
  final String? selectedId;
  final GlobalKey editorAdapterKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.sizeOf(context).width < 600 ? 2 : 3;
    return CustomScrollView(
      key: const Key('pieces-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.82,
            ),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return PieceTile(
                row: row,
                photoRepository: photoRepository,
                photoBytesLru: photoBytesLru,
                canViewPhotos: canViewPhotos,
                onTap: row is ProjectedPieceRow
                    ? () => onSelect(row.piece.id)
                    : null,
              );
            },
          ),
        ),
        if (selectedId != null)
          SliverToBoxAdapter(
            key: editorAdapterKey,
            child: PieceDetailPanel(
              key: Key('piece-editor-$selectedId'),
              season: season,
              pieceId: selectedId!,
            ),
          ),
      ],
    );
  }
}

class _FetchErrorView extends StatelessWidget {
  const _FetchErrorView({required this.code, this.onRetry});

  final String code;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('pieces-error'),
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 160),
      Center(child: Text(l10nOf(context).piecesFetchError(code))),
      const SizedBox(height: 8),
      Center(
        child: FilledButton.tonal(
          key: const Key('pieces-retry'),
          onPressed: onRetry,
          child: Text(l10nOf(context).commonRetry),
        ),
      ),
    ],
  );
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text, this.onDismiss});

  final String text;
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
                icon: const Icon(
                  Icons.close,
                  key: Key('piece-command-error-dismiss'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
