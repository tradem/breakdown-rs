// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny (opencode-go)

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations_provider.dart';
import '../shooting_days/shooting_days_screen.dart';
import '../shooting_days/season_schedule_controller.dart';
import 'planning_location.dart';
import 'profile_menu_button.dart';
import 'shell_controller.dart';
import 'view_states.dart';

/// The Schedule/Dispo view (issue #610, destination 3): the active season's
/// shooting days in calendar order — which scenes and characters are up on
/// which day.
///
/// `GET /v1/episodes/{id}/shooting-days` is episode-scoped, so the season
/// board is composed client-side by [seasonScheduleFetchProvider]
/// (blocks → episodes → days, read-only, through the existing authenticated
/// seams), mirroring the Script composition's partial-load honesty.
///
/// A row pushes the episode's shooting-day board (`ShootingDaysScreen`) with
/// the day board's own navigation context — the same entry the episode
/// drill-down uses, so the day board's action set (and its reports anchor,
/// design D8) is unchanged.
class ScheduleTabScreen extends ConsumerWidget {
  const ScheduleTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final season = ref.watch(shellControllerProvider).activeSeason;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navSchedule),
        actions: const [ProfileMenuButton()],
      ),
      body: season == null
          ? const SeasonRequiredView(emptyKey: Key('schedule-no-season'))
          : _ScheduleBody(season: season),
    );
  }
}

/// The season board body: loading, error, partial, empty and data states.
class _ScheduleBody extends ConsumerWidget {
  const _ScheduleBody({required this.season});

  final SeasonView season;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final schedule = ref.watch(seasonScheduleFetchProvider(season));
    return schedule.when(
      loading: () => const Center(
        child: CircularProgressIndicator(key: Key('schedule-loading')),
      ),
      error: (error, _) => ViewErrorState(
        errorKey: const Key('schedule-error'),
        message: l10n.scheduleFetchError('$error'),
        onRetry: () => ref.invalidate(seasonScheduleFetchProvider(season)),
      ),
      data: (result) => result.match(
        (error) => ViewErrorState(
          errorKey: const Key('schedule-error'),
          message: l10n.scheduleFetchError(error.code),
          onRetry: () => ref.invalidate(seasonScheduleFetchProvider(season)),
        ),
        (data) {
          // Empty with no failure → plain empty state; empty WITH failures
          // → the partial notice (never silently swallowed).
          if (data.isEmpty && !data.isPartial) {
            return ViewEmptyState(
              emptyKey: const Key('schedule-empty'),
              message: l10n.scheduleNoDays,
              icon: Icons.calendar_month_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.refresh(seasonScheduleFetchProvider(season).future),
            child: ListView.builder(
              key: const Key('schedule-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: data.rows.length + (data.isPartial ? 1 : 0),
              itemBuilder: (context, index) {
                if (data.isPartial && index == 0) {
                  return ViewPartialNotice(
                    noticeKey: const Key('schedule-partial-notice'),
                    message: l10n.schedulePartialLoad(
                      data.failedEpisodes.length,
                    ),
                  );
                }
                final rowIndex = index - (data.isPartial ? 1 : 0);
                final row = data.rows[rowIndex];
                return ListTile(
                  key: Key('schedule-day-${row.day.id}'),
                  leading: const Icon(Icons.event_outlined),
                  title: Text(
                    row.day.label ??
                        l10n.scheduleDayLabel('${row.day.date ?? ''}'),
                  ),
                  subtitle: Text(
                    l10n.scriptEpisodeLabel(
                      row.episode.name ?? '${row.episode.number}',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  // Fire-and-forget navigation (no result consumed).
                  onTap: () => unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        settings: RouteSettings(
                          arguments: PlanningLocation.episode(
                            season,
                            row.block,
                            row.episode,
                          ),
                        ),
                        builder: (_) => ShootingDaysScreen(
                          episode: row.episode,
                          seasonId: season.id,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
