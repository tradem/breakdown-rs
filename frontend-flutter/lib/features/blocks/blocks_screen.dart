// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../auth/season_membership_provider.dart';
import '../../core/problem_error.dart';
import '../episodes/episodes_screen.dart';
import 'blocks_controller.dart';
import 'blocks_state.dart';
import 'create_block_sheet.dart';
import 'widgets/blocks_widgets.dart';

/// Localized client-side copy for a create-block failure, keyed on the
/// stable problem `code` (never the server's localized `detail`).
String blockCreateErrorCopy(ProblemError error) => switch (error.code) {
  'blocks.conflict' ||
  'block.conflict' => 'A block with that number already exists.',
  'authz.denied' || 'auth.session_required' => 'Please sign in to continue.',
  _ when error.code.startsWith('transport.') =>
    'Network problem — the block was not created. Try again.',
  _ => 'The block could not be created (${error.code}).',
};

/// `BlocksScreen` — the season's blocks (`GET /v1/blocks?season_id=…`).
///
/// Pushed with the parent [SeasonView] as navigation context; block rows
/// push `EpisodesScreen` with the `BlockView`. Follows the seasons
/// reference pattern: `ConsumerWidget` container rendering the merged rows,
/// pure widgets under `widgets/`, family controller keyed by the season id.
class BlocksScreen extends ConsumerWidget {
  const BlocksScreen({super.key, required this.season});

  final SeasonView season;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 7.2: sign-out mid-navigation returns to the login gate. The root
    // gate swaps underneath; without this the pushed route would stay on
    // top showing the previous session's rows. Fail-closed: errors pop
    // too (the gate renders its error surface in that case).
    ref.listen(authSessionControllerProvider, (_, session) {
      final signedOut =
          (session is AsyncData && session.value == null) ||
          session is AsyncError;
      if (signedOut && context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    final state = ref.watch(blocksControllerProvider(season.id));
    final controller = ref.read(blocksControllerProvider(season.id).notifier);
    final rows = state.rows;
    final notFound = state.notFound;

    return Scaffold(
      appBar: AppBar(
        title: Text(season.title ?? 'Season ${season.number}'),
        actions: [_MembershipChip(seasonId: season.id)],
      ),
      body: Column(
        children: [
          if (state.commandError case final error?)
            _Banner(
              key: const Key('block-create-error-banner'),
              text: blockCreateErrorCopy(error),
              onDismiss: controller.dismissCommandError,
            ),
          if (state.isStale && notFound == null)
            const _Banner(
              key: Key('blocks-stale-banner'),
              text: 'Cached data may be outdated',
            ),
          Expanded(
            child: notFound != null
                ? BlocksNotFoundView(
                    code: notFound.code,
                    onBack: () => Navigator.of(context).pop(),
                  )
                : RefreshIndicator(
                    onRefresh: controller.refresh,
                    child: switch (state.projected) {
                      AsyncLoading() when rows.isEmpty => const Center(
                        child: CircularProgressIndicator(
                          key: Key('blocks-loading'),
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
                                key: const Key('blocks-list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 160),
                                  BlocksEmptyView(
                                    canCreate: _canCreate(ref),
                                    onCreate: () => showCreateBlockSheet(
                                      context,
                                      ref,
                                      season,
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                key: const Key('blocks-list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: rows.length,
                                itemBuilder: (context, i) => BlockTile(
                                  row: rows[i],
                                  onTap: rows[i] is ProjectedBlockRow
                                      ? () => Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => EpisodesScreen(
                                              block:
                                                  (rows[i] as ProjectedBlockRow)
                                                      .block,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _canCreate(ref)
          ? FloatingActionButton(
              key: const Key('block-add-fab'),
              onPressed: () => showCreateBlockSheet(context, ref, season),
              tooltip: 'Add block',
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

/// Season-membership capabilities chip (design.md §5, D6): display-only in
/// Phase 1 — the v1 capability vector contains only Phase-2 capabilities,
/// so the chip renders role state honestly without gating anything.
class _MembershipChip extends ConsumerWidget {
  const _MembershipChip({required this.seasonId});

  final String seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(seasonMembershipProvider(seasonId));
    return switch (membership) {
      AsyncData(:final value) => value.match(
        (err) => Chip(
          key: const Key('membership-chip-error'),
          label: Text('Role unknown (${err.code})'),
        ),
        (dto) => dto.hasActiveCostumeRoleInSeason
            ? Chip(
                key: const Key('membership-chip'),
                avatar: const Icon(Icons.check, size: 16),
                label: Text(
                  dto.capabilities.isEmpty
                      ? 'Costume role'
                      : dto.capabilities.join(', '),
                ),
              )
            : const Chip(
                key: Key('membership-chip-none'),
                label: Text('No role in this season'),
              ),
      ),
      AsyncError(:final error) => Chip(
        key: const Key('membership-chip-error'),
        label: Text(
          'Role unknown (${error is ProblemError ? error.code : 'unknown'})',
        ),
      ),
      _ => const Chip(
        key: Key('membership-chip-loading'),
        label: SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    };
  }
}

class _FetchErrorView extends StatelessWidget {
  const _FetchErrorView({required this.code, this.onRetry});

  final String code;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('blocks-error'),
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 160),
      Center(child: Text('Could not load blocks ($code).')),
      const SizedBox(height: 8),
      Center(
        child: FilledButton.tonal(
          key: const Key('blocks-retry'),
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
                  key: Key('block-create-error-dismiss'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
