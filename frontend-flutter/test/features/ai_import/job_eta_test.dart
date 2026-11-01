// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-1 pure tests for the AI-import extraction ETA (issue #762).
//
// The estimator is a pure function with an explicit `now`, so every case here
// is deterministic — no sleeps, no widget pumping, no clock injection into a
// build method: first frame (no estimate), byte-vs-chunk preference, monotone
// smoothing, stall detection, and absurd/negative clamping.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/features/ai_import/import_jobs/job_eta.dart';

final DateTime _started = DateTime.utc(2026, 11, 2, 10);

AiImportProgress _progress({
  int? chunk,
  int? chunksTotal,
  int? doneBytes,
  int? totalBytes,
  DateTime? startedAt,
  AiImportStage stage = AiImportStage.extracting,
}) => AiImportProgress(
  (b) => b
    ..stage = stage
    ..chunk = chunk
    ..chunksTotal = chunksTotal
    ..doneBytes = doneBytes
    ..totalBytes = totalBytes
    ..startedAt = startedAt,
);

void main() {
  group('aiJobProgressUnits', () {
    test('prefers the byte pair when a positive budget was published', () {
      final units = aiJobProgressUnits(
        _progress(chunk: 2, chunksTotal: 10, doneBytes: 500, totalBytes: 2000),
      );
      expect(units, isNotNull);
      expect(units!.basis, AiJobEtaBasis.bytes);
      expect(units.done, 500);
      expect(units.total, 2000);
      expect(units.remaining, 1500);
    });

    test('falls back to the chunk counters without a byte budget', () {
      final units = aiJobProgressUnits(
        _progress(chunk: 3, chunksTotal: 12, totalBytes: 0, doneBytes: 0),
      );
      expect(units, isNotNull);
      expect(units!.basis, AiJobEtaBasis.chunks);
      expect(units.done, 3);
      expect(units.remaining, 9);
    });

    test('no counters at all yields null (pending, schedule, pre-#762)', () {
      expect(aiJobProgressUnits(null), isNull);
      expect(aiJobProgressUnits(_progress()), isNull);
      // A zero denominator can never be divided.
      expect(aiJobProgressUnits(_progress(chunk: 0, chunksTotal: 0)), isNull);
    });

    test('a numerator beyond the denominator is clamped — never negative', () {
      final units = aiJobProgressUnits(_progress(chunk: 99, chunksTotal: 10));
      expect(units!.done, 10);
      expect(units.remaining, 0);
    });
  });

  group('estimateAiJobEta', () {
    test('first frame: no estimate before two completed units', () {
      final progress = _progress(chunk: 1, chunksTotal: 8, startedAt: _started);
      expect(
        estimateAiJobEta(
          progress: progress,
          now: _started.add(const Duration(seconds: 30)),
        ),
        isNull,
      );
      // Zero completed units is even less informative.
      expect(
        estimateAiJobEta(
          progress: _progress(chunk: 0, chunksTotal: 8, startedAt: _started),
          now: _started.add(const Duration(seconds: 30)),
        ),
        isNull,
      );
    });

    test('no time anchor means no estimate (pre-#762 frames)', () {
      final progress = _progress(chunk: 4, chunksTotal: 8);
      expect(
        estimateAiJobEta(
          progress: progress,
          now: _started.add(const Duration(minutes: 2)),
        ),
        isNull,
      );
    });

    test('a non-positive elapsed time is refused, never divided', () {
      final progress = _progress(chunk: 2, chunksTotal: 8, startedAt: _started);
      expect(estimateAiJobEta(progress: progress, now: _started), isNull);
      expect(
        estimateAiJobEta(
          progress: progress,
          now: _started.subtract(const Duration(seconds: 5)),
        ),
        isNull,
      );
    });

    test('two units of 30 s each leave 3 min for 6 remaining units', () {
      final eta = estimateAiJobEta(
        progress: _progress(chunk: 2, chunksTotal: 8, startedAt: _started),
        now: _started.add(const Duration(minutes: 1)),
      );
      expect(eta, isNotNull);
      expect(eta!.perUnit, const Duration(seconds: 30));
      expect(eta.lower, const Duration(minutes: 3));
      expect(eta.upper, const Duration(minutes: 3));
      // First estimate is a point value: no second sample to measure spread.
      expect(eta.isRange, isFalse);
    });

    test('bytes drive the estimate when a budget exists', () {
      // 2 of 10 chunks done would say "80% left"; the byte pair says the
      // completed chunks were the big ones (9000 of 10000 bytes).
      final eta = estimateAiJobEta(
        progress: _progress(
          chunk: 2,
          chunksTotal: 10,
          doneBytes: 9000,
          totalBytes: 10000,
          startedAt: _started,
        ),
        now: _started.add(const Duration(minutes: 1)),
      );
      expect(eta, isNotNull);
      expect(eta!.basis, AiJobEtaBasis.bytes);
      // 4500 B/s over 1 min → the remaining 1000 bytes ≈ 13 s.
      expect(eta.upper, lessThan(const Duration(seconds: 30)));
    });

    test(
      'monotone smoothing: the countdown never climbs while units finish',
      () {
        var previous = estimateAiJobEta(
          progress: _progress(chunk: 2, chunksTotal: 10, startedAt: _started),
          now: _started.add(const Duration(minutes: 1)),
        );
        expect(previous, isNotNull);
        var now = _started.add(const Duration(minutes: 1));
        var lastUpper = previous!.upper;
        for (var done = 3; done <= 9; done++) {
          // A steady cadence keeps the point estimate shrinking.
          now = now.add(const Duration(seconds: 30));
          final next = estimateAiJobEta(
            progress: _progress(
              chunk: done,
              chunksTotal: 10,
              startedAt: _started,
            ),
            now: now,
            previous: previous,
          );
          expect(next, isNotNull, reason: 'unit $done must still estimate');
          expect(
            next!.upper,
            lessThanOrEqualTo(lastUpper),
            reason: 'a completed unit must never push the countdown up',
          );
          previous = next;
          lastUpper = next.upper;
        }
      },
    );

    test(
      'one pathological slow frame stretches the estimate only gradually',
      () {
        final first = estimateAiJobEta(
          progress: _progress(chunk: 2, chunksTotal: 10, startedAt: _started),
          now: _started.add(const Duration(minutes: 1)),
        );
        expect(first, isNotNull);
        // The next chunk took 10× as long: the raw per-unit cost explodes, but
        // the smoothed one may grow by at most `aiJobEtaMaxStepFactor`.
        final second = estimateAiJobEta(
          progress: _progress(chunk: 3, chunksTotal: 10, startedAt: _started),
          now: _started.add(const Duration(minutes: 11)),
          previous: first!,
        );
        expect(second, isNotNull);
        final rawPerUnit = const Duration(minutes: 11).inMicroseconds / 3;
        expect(second!.perUnit.inMicroseconds, lessThan(rawPerUnit));
        expect(
          second.perUnit.inMicroseconds,
          lessThanOrEqualTo(
            (first.perUnit.inMicroseconds * aiJobEtaMaxStepFactor).round(),
          ),
        );
        // The unsteady cadence is disclosed as a range instead of a figure.
        expect(second.isRange, isTrue);
        expect(second.upper, greaterThan(second.lower));
      },
    );

    test('an absurd horizon is refused instead of shown', () {
      // 1 unit took 0.5 s, 127 units left → under the horizon.
      final sane = estimateAiJobEta(
        progress: _progress(chunk: 1, chunksTotal: 2, startedAt: _started),
        now: _started.add(const Duration(milliseconds: 500)),
      );
      expect(sane, isNull, reason: 'one unit is still a single sample');

      final absurd = estimateAiJobEta(
        // Two units done over 30 days, 100 units still to go.
        progress: _progress(chunk: 2, chunksTotal: 102, startedAt: _started),
        now: _started.add(const Duration(days: 30)),
        previous: AiJobEta(
          lower: const Duration(days: 20),
          upper: const Duration(days: 20),
          perUnit: const Duration(days: 15),
          basis: AiJobEtaBasis.chunks,
        ),
      );
      expect(absurd, isNull);
    });

    test('a completed job clamps to zero instead of a negative remainder', () {
      final eta = estimateAiJobEta(
        progress: _progress(chunk: 10, chunksTotal: 10, startedAt: _started),
        now: _started.add(const Duration(minutes: 5)),
      );
      expect(eta, isNotNull);
      expect(eta!.lower, Duration.zero);
      expect(eta.upper, Duration.zero);
    });
  });

  group('aiJobEtaStalled', () {
    AiJobEta etaWith(Duration perUnit) => AiJobEta(
      lower: perUnit,
      upper: perUnit,
      perUnit: perUnit,
      basis: AiJobEtaBasis.chunks,
    );

    test('the window is 3× the cadence, floored at two minutes', () {
      expect(
        aiJobEtaStallWindow(etaWith(const Duration(seconds: 20))),
        aiJobEtaStallFloor,
      );
      expect(
        aiJobEtaStallWindow(etaWith(const Duration(minutes: 5))),
        const Duration(minutes: 15),
      );
      // Clamped from above: one chunk may take the provider timeout + retries.
      expect(
        aiJobEtaStallWindow(etaWith(const Duration(hours: 2))),
        aiJobEtaStallCeiling,
      );
    });

    test('a gap beyond the window is a stall; within it is not', () {
      final eta = etaWith(const Duration(minutes: 5));
      final lastFrame = _started;
      expect(
        aiJobEtaStalled(
          eta: eta,
          lastFrameAt: lastFrame,
          now: lastFrame.add(const Duration(minutes: 14)),
        ),
        isFalse,
      );
      expect(
        aiJobEtaStalled(
          eta: eta,
          lastFrameAt: lastFrame,
          now: lastFrame.add(const Duration(minutes: 16)),
        ),
        isTrue,
      );
      // A clock that moved backwards is never a stall.
      expect(
        aiJobEtaStalled(
          eta: eta,
          lastFrameAt: lastFrame,
          now: lastFrame.subtract(const Duration(minutes: 5)),
        ),
        isFalse,
      );
    });
  });

  group('aiJobEtaText', () {
    AiJobEtaCopy copy() => AiJobEtaCopy(
      calculating: 'calculating',
      delayed: 'delayed',
      imminent: 'imminent',
      minutes: (count) => '$count min',
      hours: (count) => '$count h',
      rangeMinutes: (lower, upper) => '$lower–$upper min',
      rangeHours: (lower, upper) => '$lower–$upper h',
    );

    final eta = AiJobEta(
      lower: const Duration(minutes: 3),
      upper: const Duration(minutes: 3),
      perUnit: const Duration(seconds: 30),
      basis: AiJobEtaBasis.chunks,
    );

    test('no estimate renders the estimating copy', () {
      expect(
        aiJobEtaText(eta: null, stalled: false, copy: copy()),
        'calculating',
      );
    });

    test('a stall wins over any estimate', () {
      expect(aiJobEtaText(eta: eta, stalled: true, copy: copy()), 'delayed');
    });

    test('coarse minutes, never a seconds-precision figure', () {
      expect(aiJobEtaText(eta: eta, stalled: false, copy: copy()), '3 min');
    });

    test('under a minute is "imminent", never "0 min"', () {
      final almost = AiJobEta(
        lower: Duration.zero,
        upper: const Duration(seconds: 20),
        perUnit: const Duration(seconds: 10),
        basis: AiJobEtaBasis.chunks,
      );
      expect(
        aiJobEtaText(eta: almost, stalled: false, copy: copy()),
        'imminent',
      );
    });

    test('a wide estimate renders as a range in one unit', () {
      final range = AiJobEta(
        lower: const Duration(minutes: 2),
        upper: const Duration(minutes: 4),
        perUnit: const Duration(seconds: 30),
        basis: AiJobEtaBasis.chunks,
      );
      expect(aiJobEtaText(eta: range, stalled: false, copy: copy()), '2–4 min');
    });

    test('long estimates switch to whole hours, range included', () {
      final hours = AiJobEta(
        lower: const Duration(minutes: 100),
        upper: const Duration(minutes: 200),
        perUnit: const Duration(minutes: 5),
        basis: AiJobEtaBasis.chunks,
      );
      expect(aiJobEtaText(eta: hours, stalled: false, copy: copy()), '2–3 h');
      // A range that collapses to one displayed hour is a figure, not a
      // "2–2 h" non-range.
      final collapsed = AiJobEta(
        lower: const Duration(minutes: 100),
        upper: const Duration(minutes: 140),
        perUnit: const Duration(minutes: 5),
        basis: AiJobEtaBasis.chunks,
      );
      expect(aiJobEtaText(eta: collapsed, stalled: false, copy: copy()), '2 h');
      final point = AiJobEta(
        lower: const Duration(minutes: 115),
        upper: const Duration(minutes: 115),
        perUnit: const Duration(minutes: 5),
        basis: AiJobEtaBasis.chunks,
      );
      expect(aiJobEtaText(eta: point, stalled: false, copy: copy()), '2 h');
    });
  });
}
