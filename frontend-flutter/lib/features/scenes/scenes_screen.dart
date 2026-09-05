// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import 'create_scene_sheet.dart';
import 'scenes_controller.dart';
import 'widgets/scenes_widgets.dart';

/// Localized client-side copy for a create-scene failure, keyed on the
/// stable problem `code` (never the server's localized `detail`).
String sceneCreateErrorCopy(ProblemError error) => switch (error.code) {
  'scenes.conflict' ||
  'scene.conflict' => 'A scene with that number already exists.',
  'authz.denied' || 'auth.session_required' => 'Please sign in to continue.',
  _ when error.code.startsWith('transport.') =>
    'Network problem — the scene was not created. Try again.',
  _ => 'The scene could not be created (${error.code}).',
};

/// `ScenesScreen` — the episode's scenes with read-only detail data
/// (`GET /v1/scenes?episode_id=…`).
///
/// Pushed with the parent [EpisodeView] as navigation context (leaf screen
/// of the Phase-1b spine).
class ScenesScreen extends ConsumerWidget {
  const ScenesScreen({super.key, required this.episode});

  final EpisodeView episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 7.2: sign-out mid-navigation returns to the login gate (see
    // BlocksScreen for the rationale).
    ref.listen(authSessionControllerProvider, (_, session) {
      final signedOut =
          (session is AsyncData && session.value == null) ||
          session is AsyncError;
      if (signedOut && context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    final state = ref.watch(scenesControllerProvider(episode.id));
    final controller = ref.read(scenesControllerProvider(episode.id).notifier);
    final rows = state.rows;
    final notFound = state.notFound;

    return Scaffold(
      appBar: AppBar(title: Text(episode.name ?? 'Episode ${episode.number}')),
      body: Column(
        children: [
          if (state.commandError case final error?)
            _Banner(
              key: const Key('scene-create-error-banner'),
              text: sceneCreateErrorCopy(error),
              onDismiss: controller.dismissCommandError,
            ),
          if (state.isStale && notFound == null)
            const _Banner(
              key: Key('scenes-stale-banner'),
              text: 'Cached data may be outdated',
            ),
          Expanded(
            child: notFound != null
                ? ScenesNotFoundView(
                    code: notFound.code,
                    onBack: () => Navigator.of(context).pop(),
                  )
                : RefreshIndicator(
                    onRefresh: controller.refresh,
                    child: switch (state.projected) {
                      AsyncLoading() when rows.isEmpty => const Center(
                        child: CircularProgressIndicator(
                          key: Key('scenes-loading'),
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
                                key: const Key('scenes-list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 160),
                                  ScenesEmptyView(
                                    canCreate: _canCreate(ref),
                                    onCreate: () => showCreateSceneSheet(
                                      context,
                                      ref,
                                      episode,
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                key: const Key('scenes-list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: rows.length,
                                itemBuilder: (context, i) =>
                                    SceneTile(row: rows[i]),
                              ),
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _canCreate(ref)
          ? FloatingActionButton(
              key: const Key('scene-add-fab'),
              onPressed: () => showCreateSceneSheet(context, ref, episode),
              tooltip: 'Add scene',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  bool _canCreate(WidgetRef ref) {
    final session = ref.watch(authSessionControllerProvider);
    return session is AsyncData && session.value != null;
  }
}

class _FetchErrorView extends StatelessWidget {
  const _FetchErrorView({required this.code, this.onRetry});

  final String code;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('scenes-error'),
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 160),
      Center(child: Text('Could not load scenes ($code).')),
      const SizedBox(height: 8),
      Center(
        child: FilledButton.tonal(
          key: const Key('scenes-retry'),
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
              GestureDetector(
                onTap: onDismiss,
                child: IconTheme(
                  data: IconThemeData(color: scheme.onErrorContainer),
                  child: const Icon(
                    Icons.close,
                    key: Key('scene-create-error-dismiss'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
