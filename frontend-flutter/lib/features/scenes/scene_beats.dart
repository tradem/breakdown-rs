// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';

/// One render group of the scene-costume section: a character and its
/// ordered costume beats.
typedef SceneBeatGroup = ({
  String characterId,
  List<SceneCostumeBeatView> beats,
});

/// Groups scene costume beats per character in stable render order
/// (issue #546).
///
/// Pure read-model shaping — no Flutter, no network, no throw:
/// * Characters render in the scene's `assignedCharacters` order (the
///   order the user established), deduplicated defensively (issue #550);
///   a character WITHOUT beats keeps its (empty) group so the screen can
///   render the inline "kein Kostüm in dieser Szene" empty state.
/// * Characters carrying beats but NOT in `assignedCharacters` (a stale
///   projection between AssignCharacter and AddCostumeBeat) are appended
///   in first-appearance order of the beat list — never dropped.
/// * Beats within a character sort by their dense zero-based `order`.
List<SceneBeatGroup> groupSceneBeats({
  required Iterable<String> assignedCharacters,
  required Iterable<SceneCostumeBeatView> beats,
}) {
  final byCharacter = <String, List<SceneCostumeBeatView>>{};
  for (final beat in beats) {
    byCharacter.putIfAbsent(beat.characterId, () => []).add(beat);
  }
  for (final group in byCharacter.values) {
    group.sort((a, b) => a.order.compareTo(b.order));
  }
  final seen = <String>{};
  final ordered = <SceneBeatGroup>[];
  for (final id in assignedCharacters) {
    if (!seen.add(id)) continue;
    ordered.add((
      characterId: id,
      beats: byCharacter[id] ?? const <SceneCostumeBeatView>[],
    ));
  }
  for (final entry in byCharacter.entries) {
    if (seen.add(entry.key)) {
      ordered.add((characterId: entry.key, beats: entry.value));
    }
  }
  return ordered;
}
