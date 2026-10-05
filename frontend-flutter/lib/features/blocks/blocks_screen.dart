// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/active_block.dart';
import '../../auth/auth_providers.dart';
import '../../auth/season_membership_provider.dart';
import '../../core/problem_error.dart';
import '../../l10n/app_localizations_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../episodes/episodes_screen.dart';
import '../reports/reports_aggregate_screen.dart';
import '../reports/reports_aggregate_state.dart';
import '../reports/widgets/reports_aggregate_entry.dart';
import '../shell/planning_location.dart';
import 'blocks_controller.dart';
import 'blocks_state.dart';
import 'create_block_sheet.dart';
import 'widgets/blocks_widgets.dart';

/// The season-level aggregated Soll-Ist entry (issue #571): pushes the
/// season-scope aggregate screen with the acted-on [SeasonView] as nav
/// context (client CQRS boundary: no second projection lookup). Width is
/// resolved live via [LayoutBuilder] — the same deliberate-width pattern
/// as the #549/#577 entries, never a platform check.
class _AggregateReportsEntry extends StatelessWidget {
  const _AggregateReportsEntry({
    required this.season,
    required this.roomForLabel,
  });

  final SeasonView season;
  final bool roomForLabel;

  @override
  Widget build(BuildContext context) => ReportsAggregateAppBarAction(
    baseKey: 'reportsAggregateOpen',
    roomForLabel: roomForLabel,
    // The push is the closure's expression value (VoidCallback coerces it
    // — intentional fire-and-forget navigation, never a discarded Future
    // statement).
    onOpen: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          final l10n = l10nOf(context);
          return ReportsAggregateScreen(
            scope: ReportsAggregateScope(
              kind: ReportAggregateScopeKind.season,
              id: season.id,
              seasonId: season.id,
              // Catalog copy only (check_inline_copy.sh) — never an inline
              // label: the same fallback the app bar title uses.
              label: season.title ?? l10n.blockSeasonNumber('${season.number}'),
            ),
          );
        },
      ),
    ),
  );
}

/// Localized client-side copy for a create-block failure, keyed on the
/// stable problem `code` (never the server's localized `detail`).
String blockCreateErrorCopy(AppLocalizations l10n, ProblemError error) =>
    switch (error.code) {
      // Real backend code first (issue #443); legacy aliases kept for stale
      // fixtures.
      'block.number-already-exists' ||
      'blocks.conflict' ||
      'block.conflict' => l10n.blocksCreateErrorExists,
      'authz.denied' || 'auth.session_required' => l10n.blocksCreateErrorSignIn,
      _ when error.code.startsWith('transport.') =>
        l10n.blocksCreateErrorNetwork,
      _ => l10n.blocksCreateErrorGeneric(error.code),
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
    final l10n = l10nOf(context);

    // The width-resolved reports entry needs the scaffold's viewport
    // width (the #549 pattern): the LayoutBuilder wraps the Scaffold, not
    // the action slot — an action slot is laid out at intrinsic width and
    // reports an unbounded constraint.
    return LayoutBuilder(
      builder: (context, constraints) => Scaffold(
        appBar: AppBar(
          title: Text(
            season.title ?? l10n.blockSeasonNumber('${season.number}'),
          ),
          actions: [
            // Season-level aggregated Soll-Ist entry (issue #571): labelled
            // per the visible-label norm; pushes the season-scope aggregate
            // screen. Nav context = the acted-on SeasonView (CQRS boundary:
            // no second projection lookup).
            _AggregateReportsEntry(
              season: season,
              roomForLabel: constraints.maxWidth >= 520,
            ),
            _MembershipChip(seasonId: season.id),
          ],
        ),
        body: Column(
          children: [
            if (state.commandError case final error?)
              _Banner(
                key: const Key('block-create-error-banner'),
                text: blockCreateErrorCopy(l10n, error),
                onDismiss: controller.dismissCommandError,
              ),
            if (state.isStale && notFound == null)
              _Banner(
                key: const Key('blocks-stale-banner'),
                text: l10n.blocksStaleBanner,
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
                            code: error is ProblemError
                                ? error.code
                                : 'unknown',
                            onRetry: () => controller.refresh(),
                          ),
                        _ =>
                          rows.isEmpty
                              ? ListView(
                                  key: const Key('blocks-list'),
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
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
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  itemCount: rows.length,
                                  itemBuilder: (context, i) => BlockTile(
                                    row: rows[i],
                                    onTap: rows[i] is ProjectedBlockRow
                                        ? () {
                                            // Issue #378: entering block
                                            // context sets the sticky
                                            // active-block scope (from the
                                            // DTO acted on — CQRS boundary)
                                            // so every block-scoped request
                                            // below carries X-Active-Block.
                                            final block =
                                                (rows[i] as ProjectedBlockRow)
                                                    .block;
                                            ref
                                                .read(
                                                  activeBlockProvider.notifier,
                                                )
                                                .set(
                                                  seasonId: block.seasonId,
                                                  blockId: block.id,
                                                  blockNumber: block.number,
                                                );
                                            // Scope first (synchronous — the
                                            // pushed screen's fetches must see
                                            // it), then navigate. The push
                                            // future is intentionally
                                            // unawaited (fire-and-forget
                                            // navigation, no result consumed).
                                            // Issue #548: the route carries
                                            // the block-level location (season
                                            // included) for the shell's strip.
                                            unawaited(
                                              Navigator.of(context).push(
                                                MaterialPageRoute<void>(
                                                  settings: RouteSettings(
                                                    arguments:
                                                        PlanningLocation.block(
                                                          season,
                                                          block,
                                                        ),
                                                  ),
                                                  builder: (_) =>
                                                      EpisodesScreen(
                                                        block: block,
                                                      ),
                                                ),
                                              ),
                                            );
                                          }
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
                tooltip: l10n.blocksAddFab,
                child: const Icon(Icons.add),
              )
            : null,
      ),
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
    // Display-only chip (D6): capped so a long unknown-capability code can
    // never overflow the app bar next to the reports entry (issue #571).
    // The full code stays visible in tests via the semantic finder — the
    // ellipsis is a visual cap only.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: switch (membership) {
        AsyncData(:final value) => value.match(
          (err) => Chip(
            key: const Key('membership-chip-error'),
            label: Text(
              l10nOf(context).blocksRoleUnknown(err.code),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          (dto) => dto.hasActiveCostumeRoleInSeason
              ? Chip(
                  key: const Key('membership-chip'),
                  avatar: const Icon(Icons.check, size: 16),
                  label: Text(
                    dto.capabilities.isEmpty
                        ? l10nOf(context).blocksRoleCostume
                        : dto.capabilities.join(', '),
                  ),
                )
              : Chip(
                  key: const Key('membership-chip-none'),
                  label: Text(l10nOf(context).blocksRoleNone),
                ),
        ),
        AsyncError(:final error) => Chip(
          key: const Key('membership-chip-error'),
          label: Text(
            l10nOf(
              context,
            ).blocksRoleUnknown(error is ProblemError ? error.code : 'unknown'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
      },
    );
  }
}

class _FetchErrorView extends StatelessWidget {
  const _FetchErrorView({required this.code, this.onRetry});

  final String code;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return ListView(
      key: const Key('blocks-error'),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 160),
        Center(child: Text(l10n.blocksFetchError(code))),
        const SizedBox(height: 8),
        Center(
          child: FilledButton.tonal(
            key: const Key('blocks-retry'),
            onPressed: onRetry,
            child: Text(l10n.commonRetry),
          ),
        ),
      ],
    );
  }
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
                  key: Key('block-create-error-dismiss'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
