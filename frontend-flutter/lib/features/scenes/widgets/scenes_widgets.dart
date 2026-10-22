// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'package:flutter/material.dart';

import '../../../design/components/ai_provenance_badge.dart';
import '../../../design/scene_mood_label.dart';
import '../../../domain/ai_provenance.dart';

import '../../../l10n/app_localizations_provider.dart';
import '../scenes_state.dart';

/// Pure presentation trees for `ScenesScreen`: plain data + callbacks in,
/// widgets out — no Riverpod imports, theme roles only, semantic labels for
/// `find.text`-paired tests.
///
/// Scene detail data (mood, location, summary, script day, schedule flag,
/// character / shooting-day counts) renders read-only in Phase 1b.
///
/// Agreed list design (issue #668): the tile TITLE is the scene number,
/// below it a TRUNCATED EXCERPT of the summary — first sentence, then `…`
/// (no mid-sentence hard cut). An empty/`null` summary omits the excerpt
/// row entirely. The full summary stays visible in the scene detail
/// screen; the excerpt only fixes the list, which previously rendered a
/// whole meta-summary as one giant ellipsized title line.
String? sceneSummaryExcerpt(String? summary) {
  final trimmed = summary?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  // First TRUE sentence end (CodeRabbit review): a `.`, `!` or `?` only
  // ends the excerpt when it is a real sentence boundary — never an
  // abbreviation period ("Dr. Müller enters.") and never a decimal point
  // ("Version 3.5"). No mid-sentence hard cut.
  for (final match in RegExp(r'[.!?]').allMatches(trimmed)) {
    if (!_isSentenceEnd(trimmed, match.end)) continue;
    final firstSentence = trimmed.substring(0, match.end);
    final remainder = trimmed.substring(match.end).trim();
    return remainder.isEmpty ? firstSentence : '$firstSentence …';
  }
  return trimmed;
}

/// Common German/English abbreviations the excerpt must not split at
/// (conservative closed list; anything longer than these tokens is a
/// word, not a title).
const _sentenceAbbreviations = <String>{
  'dr',
  'prof',
  'nr',
  'z.b',
  'bzw',
  'usw',
  'evtl',
  'ggf',
  'inkl',
  'zzgl',
  'ca',
  'mr',
  'mrs',
  'ms',
  'st',
  'str',
  'bd',
  'aufl',
};

bool _isSentenceEnd(String text, int end) {
  // A sentence end must be followed by whitespace or end of text — a
  // period inside a token ("3.5", "z.B.") never splits.
  if (end < text.length && RegExp(r'\S').hasMatch(text[end])) return false;
  // Decimal protection: "Version 3.5 ist fertig" — a period between two
  // digits is a decimal point, not a sentence end.
  if (end < text.length &&
      end > 0 &&
      RegExp(r'[0-9]').hasMatch(text[end - 1]) &&
      RegExp(r'\s*[0-9]').hasMatch(text.substring(end))) {
    return false;
  }
  // Abbreviation protection: the token immediately before the punctuation
  // is a known abbreviation or a single initial ("Dr.", "A.").
  final before = text.substring(0, end - 1); // strip the punctuation
  final lastWord = before.split(RegExp(r'\s')).last.toLowerCase();
  if (_sentenceAbbreviations.contains(lastWord)) return false;
  if (lastWord.length == 1 && RegExp(r'[a-zA-ZäöüÄÖÜ]').hasMatch(lastWord)) {
    return false;
  }
  return true;
}

class SceneTile extends StatelessWidget {
  const SceneTile({super.key, required this.row, this.onTap});

  final SceneRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    String tileLabel(Object? identifier) => l10n.sceneTileLabel('$identifier');
    return switch (row) {
      ProjectedSceneRow(:final scene) => Semantics(
        label: tileLabel(scene.sceneNumber ?? scene.id),
        child: ListTile(
          key: Key('scene-${scene.id}'),
          onTap: onTap,
          minTileHeight: 48,
          // Provenance badge (issue #538, EU AI Act Art. 50): ONE element
          // only when the scene's wire source is AI-extracted; `Manual`
          // and pre-#538 null rows never carry it (no invented
          // attribution in either direction).
          title: switch (sceneProvenance(scene.source_)) {
            AiProvenanceVariant.aiExtracted => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AiProvenanceBadge(semanticKey: 'scene-ai-badge-${scene.id}'),
                // Issue #668: the title is the scene NUMBER — the summary
                // moved to the truncated excerpt line below.
                Flexible(child: Text(tileLabel(scene.sceneNumber ?? scene.id))),
              ],
            ),
            _ => Text(tileLabel(scene.sceneNumber ?? scene.id)),
          },
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Issue #668: truncated excerpt (first sentence + `…`),
              // omitted entirely for a null/empty summary. The full
              // summary stays visible in the scene detail screen.
              if (sceneSummaryExcerpt(scene.summary) case final excerpt?)
                Text(
                  excerpt,
                  key: Key('scene-excerpt-${scene.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              Text(
                [
                  if (scene.location case final location?)
                    l10n.sceneLoc(location),
                  if (scene.scriptDay case final day?) l10n.sceneDay(day),
                  scene.isScheduleSet
                      ? l10n.sceneScheduled
                      : l10n.sceneUnscheduled,
                  // Defensive dedup (issue #550): the tile counts must survive a
                  // read-model fan-out regression without inflating.
                  l10n.sceneCharacterCount(
                    '${scene.assignedCharacters.toSet().length}',
                  ),
                  l10n.sceneShootingDayCount(
                    '${scene.shootingDayIds.toSet().length}',
                  ),
                ].join(' · '),
              ),
              // Set-shorthand mood with its reinforcing icons (issue #721):
              // its own line so the icons sit next to the visible `I/T`
              // text instead of inside the joined metadata string.
              if (scene.mood case final mood?)
                SceneMoodLabel(
                  key: Key('scene-mood-${scene.id}'),
                  mood: mood,
                  label: l10n.sceneMood(mood),
                  textStyle: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
      OptimisticSceneRow(:final overlay) => ListTile(
        key: Key('overlay-${overlay.id}'),
        minTileHeight: 48,
        title: Text(
          overlay.summary?.isNotEmpty == true
              ? overlay.summary!
              : tileLabel(overlay.sceneNumber),
        ),
        subtitle: Text(
          overlay.status == OverlayStatus.stale
              ? (overlay.warning ?? l10n.scenesTileSyncingStale)
              : l10n.scenesTileSyncing,
        ),
        trailing: overlay.status == OverlayStatus.stale
            ? const Icon(Icons.cloud_off, key: Key('overlay-warning'))
            : const SizedBox(
                key: Key('overlay-spinner'),
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
      ),
    };
  }
}

class ScenesEmptyView extends StatelessWidget {
  const ScenesEmptyView({super.key, required this.canCreate, this.onCreate});

  final bool canCreate;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10nOf(context).scenesEmpty,
          key: const Key('scenes-empty'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (canCreate)
          FilledButton.tonal(
            key: const Key('scenes-empty-create'),
            onPressed: onCreate,
            child: Text(l10nOf(context).scenesCreateFirst),
          ),
      ],
    ),
  );
}

class ScenesNotFoundView extends StatelessWidget {
  const ScenesNotFoundView({super.key, required this.code, this.onBack});

  final String code;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      key: const Key('scenes-not-found'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.search_off, size: 48),
        const SizedBox(height: 8),
        Text(l10nOf(context).scenesNotFound(code), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const Key('scenes-not-found-back'),
          onPressed: onBack,
          child: Text(l10nOf(context).scenesBackToEpisodes),
        ),
      ],
    ),
  );
}
