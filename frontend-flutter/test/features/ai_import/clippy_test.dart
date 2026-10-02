// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

// Tier-1 unit tests for the pure Karl Klammer trigger logic (issue #516,
// Decision D4): state → tip/pose mapping, deterministic idle cycling.

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_flutter/features/ai_import/clippy/clippy_trigger.dart';

void main() {
  group('clippyTipFor (issue #516, D4)', () {
    test('noConfig → letter-allusion tip, neutral pose', () {
      final tip = clippyTipFor(ClippyFlowState.noConfig, triggerCount: 0);
      expect(tip.key, ClippyTipKey.noConfig);
      expect(tip.pose, ClippyPose.neutral);
    });

    test('running → eager tip, excited pose', () {
      final tip = clippyTipFor(ClippyFlowState.running, triggerCount: 0);
      expect(tip.key, ClippyTipKey.running);
      expect(tip.pose, ClippyPose.excited);
    });

    test('error → consolation tip, droop pose', () {
      final tip = clippyTipFor(ClippyFlowState.error, triggerCount: 0);
      expect(tip.key, ClippyTipKey.error);
      expect(tip.pose, ClippyPose.droop);
    });

    test('success → proud tip, proud pose', () {
      final tip = clippyTipFor(ClippyFlowState.success, triggerCount: 0);
      expect(tip.key, ClippyTipKey.success);
      expect(tip.pose, ClippyPose.proud);
    });

    test(
      'idle cycles the fixed joke set deterministically (no randomness)',
      () {
        final seq = [
          for (var i = 0; i < 6; i++)
            clippyTipFor(ClippyFlowState.idle, triggerCount: i),
        ];
        expect(seq.map((t) => t.key), [
          ClippyTipKey.idle1,
          ClippyTipKey.idle2,
          ClippyTipKey.idle3,
          ClippyTipKey.idle1,
          ClippyTipKey.idle2,
          ClippyTipKey.idle3,
        ]);
        // Idle is never a blocking pose.
        expect(seq.every((t) => t.pose == ClippyPose.neutral), isTrue);
      },
    );

    test('mapping is total: every flow state yields a tip', () {
      for (final state in ClippyFlowState.values) {
        expect(clippyTipFor(state, triggerCount: 0), isNotNull);
      }
    });
  });
}
