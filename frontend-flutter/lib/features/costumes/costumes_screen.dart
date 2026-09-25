// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

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
import 'costume_detail_screen.dart';
import 'costumes_controller.dart';
import 'costumes_state.dart';
import '../photos/widgets/photo_gallery.dart';
import 'widgets/costumes_widgets.dart';

/// `CostumesScreen` — the season's costumes and the inline costume editor.
///
/// Create dispatches the empty-body `POST /v1/costumes` after the session
/// AUTHZ-GATE. Selecting a tile opens the editor in this screen; there is no
/// separate detail route.
class CostumesScreen extends ConsumerStatefulWidget {
  const CostumesScreen({super.key, required this.season});

  final SeasonView season;

  @override
  ConsumerState<CostumesScreen> createState() => _CostumesScreenState();
}

class _CostumesScreenState extends ConsumerState<CostumesScreen> {
  String? _selectedId;
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
        return BlockScopeLoadingScaffold(title: l10nOf(context).navCostumes);
      case AsyncError(:final error):
        return BlockScopeErrorScaffold(
          title: l10nOf(context).navCostumes,
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
              title: l10nOf(context).navCostumes,
              seasonId: season.id,
              candidates: candidates,
            );
          }
          return NoBlocksHintScaffold(title: l10nOf(context).navCostumes);
        }
    }
    final state = ref.watch(costumesControllerProvider(season.id));
    final controller = ref.read(costumesControllerProvider(season.id).notifier);
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
        ? ref.watch(costumePhotoRepositoryProvider)
        : null;
    final photoBytesLru = ref.watch(photoBytesLruProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10nOf(context).navCostumes)),
      body: Column(
        children: [
          if (state.commandError case final failure?)
            _Banner(
              key: const Key('costume-command-error-banner'),
              text: costumeCommandErrorCopy(l10nOf(context), failure),
              onDismiss: controller.dismissCommandError,
            ),
          if (state.isStale && notFound == null)
            _Banner(
              key: const Key('costumes-stale-banner'),
              text: l10nOf(context).costumesStaleBanner,
            ),
          Expanded(
            child: notFound != null
                ? CostumesNotFoundView(
                    code: notFound.code,
                    onBack: () => Navigator.of(context).pop(),
                  )
                : RefreshIndicator(
                    onRefresh: controller.refresh,
                    child: switch (state.projected) {
                      AsyncLoading() when rows.isEmpty => const Center(
                        child: CircularProgressIndicator(
                          key: Key('costumes-loading'),
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
                                key: const Key('costumes-list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 160),
                                  CostumesEmptyView(
                                    onCreate: _canCreate(ref)
                                        ? () =>
                                              _createAndShowEditor(context, ref)
                                        : null,
                                  ),
                                ],
                              )
                            : _CostumeOverview(
                                rows: rows,
                                season: season,
                                canViewPhotos: canViewPhotos,
                                photoRepository: photoRepository,
                                photoBytesLru: photoBytesLru,
                                selectedId: _selectedId,
                                onSelect: (id) =>
                                    setState(() => _selectedId = id),
                              ),
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _canCreate(ref)
          ? FloatingActionButton(
              key: const Key('costume-add-fab'),
              onPressed: () => _createAndShowEditor(context, ref),
              tooltip: l10nOf(context).costumeAddFab,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  bool _canCreate(WidgetRef ref) {
    final session = ref.watch(authSessionControllerProvider);
    return session is AsyncData && session.value != null;
  }

  /// Creates the empty shell and keeps the editor on the first screen.
  Future<void> _createAndShowEditor(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(costumesControllerProvider(season.id).notifier)
        .create();
    final id = result.match((_) => null, (ack) => ack.id);
    if (id != null && mounted) setState(() => _selectedId = id);
  }
}

class _CostumeOverview extends StatelessWidget {
  const _CostumeOverview({
    required this.rows,
    required this.season,
    required this.canViewPhotos,
    required this.photoRepository,
    required this.photoBytesLru,
    required this.selectedId,
    required this.onSelect,
  });

  final List<CostumeRow> rows;
  final SeasonView season;
  final bool canViewPhotos;
  final PhotoRepository? photoRepository;
  final PhotoBytesLru photoBytesLru;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.sizeOf(context).width < 600 ? 2 : 3;
    return CustomScrollView(
      key: const Key('costumes-list'),
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
              return CostumeTile(
                row: row,
                photoRepository: photoRepository,
                photoBytesLru: photoBytesLru,
                canViewPhotos: canViewPhotos,
                onTap: row is ProjectedCostumeRow
                    ? () => onSelect(row.costume.id)
                    : null,
              );
            },
          ),
        ),
        if (selectedId != null)
          SliverToBoxAdapter(
            child: CostumeDetailPanel(
              key: Key('costume-editor-$selectedId'),
              season: season,
              costumeId: selectedId!,
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
    key: const Key('costumes-error'),
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 160),
      Center(child: Text(l10nOf(context).costumesFetchError(code))),
      const SizedBox(height: 8),
      Center(
        child: FilledButton.tonal(
          key: const Key('costumes-retry'),
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
                  key: Key('costume-command-error-dismiss'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
