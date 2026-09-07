// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import 'costume_detail_screen.dart';
import 'costumes_controller.dart';
import 'costumes_state.dart';
import 'widgets/costumes_widgets.dart';

/// `CostumesScreen` — the season's costumes (season-scoped list + create).
///
/// Create dispatches the empty-body `POST /v1/costumes` after the session
/// AUTHZ-GATE; on 201 the overlay row (server id) renders and immediately
/// chains to the first detail/assignment flow so the created row never
/// dead-ends (D1). Detail navigation pushes [CostumeDetailScreen].
class CostumesScreen extends ConsumerWidget {
  const CostumesScreen({super.key, required this.season});

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
    final state = ref.watch(costumesControllerProvider(season.id));
    final controller = ref.read(costumesControllerProvider(season.id).notifier);
    final rows = state.rows;
    final notFound = state.notFound;

    return Scaffold(
      appBar: AppBar(title: const Text('Costumes')),
      body: Column(
        children: [
          if (state.commandError case final error?)
            _Banner(
              key: const Key('costume-command-error-banner'),
              text: costumeErrorCopy(error),
              onDismiss: controller.dismissCommandError,
            ),
          if (state.isStale && notFound == null)
            const _Banner(
              key: Key('costumes-stale-banner'),
              text: 'Cached data may be outdated',
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
                                              _createAndOpenDetail(context, ref)
                                        : null,
                                  ),
                                ],
                              )
                            : ListView.builder(
                                key: const Key('costumes-list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: rows.length,
                                itemBuilder: (context, i) {
                                  final row = rows[i];
                                  return CostumeTile(
                                    row: row,
                                    onTap: row is ProjectedCostumeRow
                                        ? () => Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  CostumeDetailScreen(
                                                    season: season,
                                                    costumeId: row.costume.id,
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
              key: const Key('costume-add-fab'),
              onPressed: () => _createAndOpenDetail(context, ref),
              tooltip: 'Create costume',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  bool _canCreate(WidgetRef ref) {
    final session = ref.watch(authSessionControllerProvider);
    return session is AsyncData && session.value != null;
  }

  /// Creates the empty shell and chains to the detail screen so the first
  /// detail/assignment flow starts immediately (D1 — no dead-end row).
  Future<void> _createAndOpenDetail(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(costumesControllerProvider(season.id).notifier)
        .create();
    final id = result.match((_) => null, (ack) => ack.id);
    if (id != null && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CostumeDetailScreen(season: season, costumeId: id),
        ),
      );
    }
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
      Center(child: Text('Could not load costumes ($code).')),
      const SizedBox(height: 8),
      Center(
        child: FilledButton.tonal(
          key: const Key('costumes-retry'),
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
                  key: Key('costume-command-error-dismiss'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
