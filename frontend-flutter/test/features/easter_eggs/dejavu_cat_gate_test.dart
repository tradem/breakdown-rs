// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

// Tier-1 (no Flutter imports): the pure October gate and the walk-cycle
// math (issue #615, spec `flutter-easter-eggs`).

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_flutter/features/easter_eggs/dejavu_cat_gate.dart';

void main() {
  group('dejaVuCatActive (October gate)', () {
    test('active in October when enabled', () {
      expect(
        dejaVuCatActive(enabled: true, now: DateTime(2026, 10, 1)),
        isTrue,
      );
      expect(
        dejaVuCatActive(enabled: true, now: DateTime(2026, 10, 31, 23, 59)),
        isTrue,
      );
    });

    test('dormant outside October even when enabled', () {
      expect(
        dejaVuCatActive(enabled: true, now: DateTime(2026, 9, 30, 23, 59)),
        isFalse,
      );
      expect(
        dejaVuCatActive(enabled: true, now: DateTime(2026, 11, 1)),
        isFalse,
      );
      expect(
        dejaVuCatActive(enabled: true, now: DateTime(2026, 6, 15)),
        isFalse,
      );
    });

    test('dormant when disabled even in October', () {
      expect(
        dejaVuCatActive(enabled: false, now: DateTime(2026, 10, 15)),
        isFalse,
      );
    });
  });

  group('dejaVuCatTravel (walk cycle)', () {
    test('starts off the left edge and ends off the right', () {
      expect(dejaVuCatTravel(0.0), 0.0);
      expect(dejaVuCatTravel(1.0), 1.0);
    });

    test('is monotonic non-decreasing across the cycle', () {
      var previous = -1.0;
      for (var i = 0; i <= 100; i++) {
        final t = dejaVuCatTravel(i / 100);
        expect(t, greaterThanOrEqualTo(previous));
        previous = t;
      }
    });

    test('pauses mid-track for the déjà-vu beat', () {
      expect(dejaVuCatTravel(dejaVuCatPauseStart), 0.5);
      expect(dejaVuCatTravel(0.60), 0.5);
      expect(dejaVuCatTravel(dejaVuCatPauseEnd), closeTo(0.5, 1e-9));
    });

    test('clamps out-of-range phases', () {
      expect(dejaVuCatTravel(-0.5), 0.0);
      expect(dejaVuCatTravel(1.5), 1.0);
    });
  });

  group('dejaVuCatGlance (déjà-vu beat)', () {
    test('is zero outside the pause window', () {
      expect(dejaVuCatGlance(0.0), 0.0);
      expect(dejaVuCatGlance(dejaVuCatPauseStart), 0.0);
      expect(dejaVuCatGlance(dejaVuCatPauseEnd), 0.0);
      expect(dejaVuCatGlance(1.0), 0.0);
    });

    test('peaks mid-pause', () {
      final mid = (dejaVuCatPauseStart + dejaVuCatPauseEnd) / 2;
      expect(dejaVuCatGlance(mid), closeTo(1.0, 1e-9));
    });
  });
}
