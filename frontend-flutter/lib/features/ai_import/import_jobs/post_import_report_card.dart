// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'post_import_report.dart';

/// The destination-side report of the last apply (issue #759).
///
/// After a successful apply the user is moved out of the review screen into the
/// Script view scoped to the imported episode — which is exactly where the
/// review's outcome would have been lost. The card carries it over: the applied
/// counts, the skipped day groups, every row that did NOT become a look (with
/// its reason) and the OTHER episodes of a multi-episode document, which the
/// episode scope would otherwise hide.
///
/// Dismissible, never auto-hiding: the report stays until the user closes it, so
/// a partially applied import cannot scroll away unnoticed. It renders nothing
/// when no apply has been reported.
class AiPostImportReportCard extends ConsumerWidget {
  const AiPostImportReportCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(aiPostImportReportProvider);
    if (report == null) return const SizedBox.shrink();
    final l10n = l10nOf(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // CodeRabbit #802: the card is a NON-FLEX child of the Script view's
    // `Column` (above an `Expanded` body), so it receives unbounded height — a
    // 57-row import with several unapplied looks could grow taller than the
    // screen and starve the script list to zero height. The detail lines scroll
    // inside a cap instead, while the title row (and its close action) stays
    // put; the cap leaves the majority of the viewport to the rows.
    final maxDetailHeight = (MediaQuery.sizeOf(context).height * 0.45).clamp(
      160.0,
      480.0,
    );

    return Card(
      key: const Key('ai-post-import-report'),
      // The container tint, not the surface: the card is a REPORT next to the
      // script, not another scene row.
      color: scheme.primaryContainer,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  // Glossary `docs/design/glossary.md`: the icon accompanies the
                  // visible title, it never carries the meaning alone.
                  Icons.playlist_add_check,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.aiPostImportReportTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('ai-post-import-report-dismiss'),
                  tooltip: l10n.aiPostImportReportDismiss,
                  onPressed: () =>
                      ref.read(aiPostImportReportProvider.notifier).dismiss(),
                  icon: const Icon(Icons.close),
                  color: scheme.onPrimaryContainer,
                ),
              ],
            ),
            ConstrainedBox(
              // The constraint is what makes a scroll view bounded: without it
              // the `SingleChildScrollView` would size to its content again.
              constraints: BoxConstraints(maxHeight: maxDetailHeight),
              child: SingleChildScrollView(
                key: const Key('ai-post-import-report-details'),
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      key: const Key('ai-post-import-report-outcome'),
                      aiApplyOutcomeLine(l10n, report.outcome),
                      style: TextStyle(color: scheme.onPrimaryContainer),
                    ),
                    if (report.skippedDayLabels.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          key: const Key('ai-post-import-report-skipped-days'),
                          l10n.aiApplySkippedDayGroups(
                            '${report.skippedDayLabels.length}',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    // Rows that did NOT become a look keep their reason here —
                    // the review screen's own report must not be the only place
                    // a partially applied import is visible (spec `ai-import`).
                    for (final unapplied in report.outcome.unappliedOutfits)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          key: Key(
                            'ai-post-import-unapplied-outfit-'
                            '${unapplied.draftRef}-${unapplied.ordinal}',
                          ),
                          l10n.aiApplyUnappliedOutfit(
                            unapplied.characterName,
                            unapplied.name,
                            aiUnappliedOutfitReasonCopy(l10n, unapplied.reason),
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                          ),
                        ),
                      ),
                    // A multi-episode document: the episode scope hides these
                    // rows, so the report NAMES them (with their row counts)
                    // instead of letting the user believe the import stopped at
                    // the episode that was opened.
                    if (report.others.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          key: const Key('ai-post-import-report-others-title'),
                          l10n.aiPostImportReportOthersTitle,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      for (final other in report.others)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            key: Key(
                              'ai-post-import-other-episode-${other.id}',
                            ),
                            l10n.aiPostImportReportOtherEpisode(
                              appliedEpisodeLabel(l10n, other),
                              other.appliedCount,
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How an [AppliedEpisode] is named in the report: "3 · Impuls" for a titled
/// episode, "Episode 3" for an untitled one, and the bare id only when the
/// wire carried neither (honest absence — never a fabricated number).
String appliedEpisodeLabel(AppLocalizations l10n, AppliedEpisode episode) {
  final name = episode.name;
  final number = episode.number;
  if (name != null && number != null) {
    return l10n.episodeNumberName(name, number);
  }
  if (name != null) return name;
  if (number != null) return l10n.episodeTileLabel('$number');
  return episode.id;
}
