// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-1 tests for the script-block scope (issue #827): the value type decides
// how every surface combines "what the script states" with "where the import
// lands". Getting this wrong is user-visible in both directions — a blank field
// where the target should be, or a warning where there is nothing to warn
// about — so the combination rules are pinned here rather than in each widget.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/script_block_scope.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';

AiImportProgress _progress({
  int? blockNumber,
  List<String> episodes = const [],
}) => AiImportProgress(
  (b) => b
    ..stage = AiImportStage.extracting
    ..blockNumber = blockNumber
    ..episodesSeen.replace(BuiltList<String>(episodes)),
);

void main() {
  final de = lookupAppLocalizations(const Locale('de'));
  final en = lookupAppLocalizations(const Locale('en'));

  group('ScriptBlockScope', () {
    test('both values equal is the agreement case — no mismatch', () {
      const scope = ScriptBlockScope(
        scriptBlockNumber: 2,
        targetBlockNumber: 2,
      );
      expect(scope.mismatch, isFalse);
      expect(scope.scriptStatesBlock, isTrue);
      expect(scope.associatedBlockNumber, 2);
    });

    test('different values are a mismatch — the script belongs elsewhere', () {
      const scope = ScriptBlockScope(
        scriptBlockNumber: 2,
        targetBlockNumber: 1,
      );
      expect(scope.mismatch, isTrue);
      expect(scope.associatedBlockNumber, 2);
    });

    test('a script WITHOUT a block is no mismatch, and the target is the '
        'association (never a blank field)', () {
      const scope = ScriptBlockScope(targetBlockNumber: 3);
      expect(scope.scriptStatesBlock, isFalse);
      expect(scope.mismatch, isFalse);
      expect(scope.associatedBlockNumber, 3);
    });

    test('two unknowns never contradict — no mismatch, no association', () {
      const scope = ScriptBlockScope();
      expect(scope.mismatch, isFalse);
      expect(scope.associatedBlockNumber, isNull);
    });

    test('a script block without a recorded target is no mismatch', () {
      const scope = ScriptBlockScope(scriptBlockNumber: 2);
      expect(scope.mismatch, isFalse);
      expect(scope.associatedBlockNumber, 2);
    });
  });

  group('aiJobsRowDetectedValues', () {
    test('names the block and the episodes on ONE line', () {
      final progress = _progress(
        blockNumber: 2,
        episodes: const ['Ep. 299', 'Ep. 300'],
      );
      expect(
        aiJobsRowDetectedValues(en, progress),
        'Block 2 · Episodes: Ep. 299, Ep. 300',
      );
    });

    test('names the block alone when no episode was discovered', () {
      final progress = _progress(blockNumber: 2);
      expect(
        aiJobsRowDetectedValues(en, progress),
        'Block stated by the script: Block 2',
      );
    });

    test('keeps the plain episode value for a job without a block', () {
      final progress = _progress(episodes: const ['Ep. 299']);
      expect(
        aiJobsRowDetectedValues(en, progress),
        'Episodes discovered: Ep. 299',
      );
    });

    test('localizes the German copy too (no hardcoded string)', () {
      final progress = _progress(blockNumber: 2, episodes: const ['Ep. 299']);
      expect(
        aiJobsRowDetectedValues(de, progress),
        'Block 2 · Episoden: Ep. 299',
      );
    });
  });
}
