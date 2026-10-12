// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

/// Pure Deja-vu Cat logic (issue #615, Decisions D4/D5 of
/// `615-dejavu-cat-easter-egg`): the October gate and the walk-cycle math.
/// Deterministic — no wall clock, no randomness, no Flutter imports
/// (Tier-1 unit testable). The widget supplies the current time from an
/// injectable clock; the month check itself lives here, never buried in a
/// widget.
library;

import 'dart:math' as math;

/// Whether the Deja-vu Cat egg is active for [now] given its [enabled]
/// switch: enabled **and** the current month is October. Outside October
/// the egg is dormant even when switched on (and returns next October).
bool dejaVuCatActive({required bool enabled, required DateTime now}) =>
    enabled && now.month == DateTime.october;

/// Fractions of one walk cycle marking the pause — the "déjà vu" glance
/// beat (Decision D5).
const double dejaVuCatPauseStart = 0.55;
const double dejaVuCatPauseEnd = 0.65;

/// The horizontal travel fraction (`0..1`) of the cat for an animation
/// [phase] (`0..1`): the cat walks left→right, pauses mid-track for the
/// "déjà vu" glance beat, then continues off the right edge. Pure and
/// deterministic.
double dejaVuCatTravel(double phase) {
  final p = phase.clamp(0.0, 1.0);
  if (p <= dejaVuCatPauseStart) {
    return p / dejaVuCatPauseStart * 0.5;
  }
  if (p < dejaVuCatPauseEnd) return 0.5;
  return 0.5 + (p - dejaVuCatPauseEnd) / (1 - dejaVuCatPauseEnd) * 0.5;
}

/// The glance strength (`0..1`) for an animation [phase]: 0 outside the
/// pause, peaking mid-pause — the "déjà vu" look-back. Pure and
/// deterministic.
double dejaVuCatGlance(double phase) {
  if (phase <= dejaVuCatPauseStart || phase >= dejaVuCatPauseEnd) return 0;
  final t =
      (phase - dejaVuCatPauseStart) / (dejaVuCatPauseEnd - dejaVuCatPauseStart);
  return math.sin(t * math.pi);
}
