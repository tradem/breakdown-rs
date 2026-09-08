// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import '../blocks/active_block_gate.dart';
import '../blocks/blocks_controller.dart';
import 'character_detail_screen.dart';
import 'characters_controller.dart';
import 'characters_state.dart';
import 'widgets/characters_widgets.dart';

/// `CharactersScreen` — the season's characters (season-scoped list with
/// category chips, create, detail with contact + measurements editors).
///
/// Create dispatches `POST /v1/characters` with `season_id` from the season
/// read DTO after the session AUTHZ-GATE; unknown category values strictly
/// reject the DTO (no guessed meaning).
class CharactersScreen extends ConsumerWidget {
  const CharactersScreen({super.key, required this.season});

  final SeasonView season;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        return const BlockScopeLoadingScaffold(title: 'Characters');
      case AsyncError(:final error):
        return BlockScopeErrorScaffold(
          title: 'Characters',
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
              title: 'Characters',
              seasonId: season.id,
              candidates: candidates,
            );
          }
          return const NoBlocksHintScaffold(title: 'Characters');
        }
    }
    final state = ref.watch(charactersControllerProvider(season.id));
    final controller = ref.read(
      charactersControllerProvider(season.id).notifier,
    );
    final rows = state.rows;
    final notFound = state.notFound;

    return Scaffold(
      appBar: AppBar(title: const Text('Characters')),
      body: Column(
        children: [
          if (state.commandError case final error?)
            _Banner(
              key: const Key('character-command-error-banner'),
              text: characterErrorCopy(error),
              onDismiss: controller.dismissCommandError,
            ),
          if (state.isStale && notFound == null)
            const _Banner(
              key: Key('characters-stale-banner'),
              text: 'Cached data may be outdated',
            ),
          Expanded(
            child: notFound != null
                ? CharactersNotFoundView(
                    code: notFound.code,
                    onBack: () => Navigator.of(context).pop(),
                  )
                : RefreshIndicator(
                    onRefresh: controller.refresh,
                    child: switch (state.projected) {
                      AsyncLoading() when rows.isEmpty => const Center(
                        child: CircularProgressIndicator(
                          key: Key('characters-loading'),
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
                                key: const Key('characters-list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 160),
                                  CharactersEmptyView(
                                    onCreate: _canCreate(ref)
                                        ? () => _showCreateSheet(context, ref)
                                        : null,
                                  ),
                                ],
                              )
                            : ListView.builder(
                                key: const Key('characters-list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: rows.length,
                                itemBuilder: (context, i) {
                                  final row = rows[i];
                                  return CharacterTile(
                                    row: row,
                                    onTap: row is ProjectedCharacterRow
                                        ? () => Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  CharacterDetailScreen(
                                                    season: season,
                                                    characterId:
                                                        row.character.id,
                                                  ),
                                            ),
                                          )
                                        : null,
                                  );
                                },
                              ),
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _canCreate(ref)
          ? FloatingActionButton(
              key: const Key('character-add-fab'),
              onPressed: () => _showCreateSheet(context, ref),
              tooltip: 'Create character',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  bool _canCreate(WidgetRef ref) {
    final session = ref.watch(authSessionControllerProvider);
    return session is AsyncData && session.value != null;
  }

  Future<void> _showCreateSheet(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    String categoryWire = 'main_cast';
    final formKey = GlobalKey<FormState>();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Create character',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextFormField(
                    key: const Key('create-character-name'),
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'A name is required'
                        : null,
                  ),
                  DropdownButtonFormField<String>(
                    key: const Key('create-character-category'),
                    decoration: const InputDecoration(labelText: 'Category'),
                    initialValue: categoryWire,
                    items: const [
                      DropdownMenuItem(
                        value: 'main_cast',
                        child: Text('Main cast'),
                      ),
                      DropdownMenuItem(value: 'guest', child: Text('Guest')),
                      DropdownMenuItem(value: 'extra', child: Text('Extra')),
                    ],
                    onChanged: (v) {
                      if (v != null) setSheetState(() => categoryWire = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('create-character-submit'),
                    onPressed: () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      // Handled: the controller surfaces failures via the
                      // command-error provider (keyed copy in the screen).
                      final createResult = await ref
                          .read(
                            charactersControllerProvider(season.id).notifier,
                          )
                          .create(
                            name: nameController.text.trim(),
                            categoryWire: categoryWire,
                          );
                      createResult.match<void>((_) {}, (_) {});
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                    },
                    child: const Text('Create'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FetchErrorView extends StatelessWidget {
  const _FetchErrorView({required this.code, this.onRetry});

  final String code;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('characters-error'),
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 160),
      Center(child: Text('Could not load characters ($code).')),
      const SizedBox(height: 8),
      Center(
        child: FilledButton.tonal(
          key: const Key('characters-retry'),
          onPressed: onRetry,
          child: const Text('Retry'),
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
                tooltip: 'Dismiss',
                icon: const Icon(
                  Icons.close,
                  key: Key('character-command-error-dismiss'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
