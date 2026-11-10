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
  int? resumedFrom,
  AiImportStage stage = AiImportStage.extracting,
}) => AiImportProgress(
  (b) => b
    ..stage = stage
    ..chunk = chunk
    ..chunksTotal = chunksTotal
    ..doneBytes = doneBytes
    ..totalBytes = totalBytes
    ..startedAt = startedAt
    // Issue #871 (D-B5): the resume point this attempt continues from.
    ..resumedFrom = resumedFrom,
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
    test('the byte basis still needs two COMPLETED CHUNKS, not two bytes', () {
      // One chunk done already exceeds two bytes — the floor is about samples,
      // not about the unit the rate happens to be measured in.
      final oneChunk = estimateAiJobEta(
        progress: _progress(
          chunk: 1,
          chunksTotal: 8,
          doneBytes: 4096,
          totalBytes: 16384,
          startedAt: _started,
        ),
        now: _started.add(const Duration(minutes: 1)),
      );
      expect(oneChunk, isNull);

      // The same frame with a second completed chunk is a defensible estimate.
      final twoChunks = estimateAiJobEta(
        progress: _progress(
          chunk: 2,
          chunksTotal: 8,
          doneBytes: 4096,
          totalBytes: 16384,
          startedAt: _started,
        ),
        now: _started.add(const Duration(minutes: 1)),
      );
      expect(twoChunks, isNotNull);
      expect(twoChunks!.basis, AiJobEtaBasis.bytes);
    });

    test('a below-threshold spread is a figure, never a narrow range', () {
      // A tiny per-frame deviation must not render "5–6 min" where the data
      // only supports "6 min".
      final first = estimateAiJobEta(
        progress: _progress(chunk: 2, chunksTotal: 8, startedAt: _started),
        now: _started.add(const Duration(minutes: 1)),
      );
      expect(first, isNotNull);
      // 1.2 s/unit against a 1 s/unit baseline: a 17 % gap, below the 20 %
      // threshold.
      final second = estimateAiJobEta(
        progress: _progress(chunk: 3, chunksTotal: 8, startedAt: _started),
        now: _started.add(const Duration(minutes: 1, seconds: 12)),
        previous: first,
      );
      expect(second, isNotNull);
      expect(second!.spread, lessThan(aiJobEtaRangeThreshold));
      expect(second.isRange, isFalse);
      expect(
        second.lower,
        second.upper,
        reason: 'below the threshold both bounds ARE the point estimate',
      );
    });

    test(
      'the stall window follows the CHUNK cadence, not the per-byte cost',
      () {
        // Byte basis: 16 KiB over 2 chunks in 2 minutes. The per-byte cost is
        // ~7 ms, whose 3× is far below the floor — but one chunk took a minute,
        // which is what the watchdog must measure.
        final eta = estimateAiJobEta(
          progress: _progress(
            chunk: 2,
            chunksTotal: 40,
            doneBytes: 16384,
            totalBytes: 327680,
            startedAt: _started,
          ),
          now: _started.add(const Duration(minutes: 2)),
        );
        expect(eta, isNotNull);
        expect(eta!.basis, AiJobEtaBasis.bytes);
        expect(eta.perUnit.inMilliseconds, lessThan(10));
        expect(eta.chunkCadence, const Duration(minutes: 1));
        expect(aiJobEtaStallWindow(eta), const Duration(minutes: 3));

        // A healthy byte-basis job is NOT stalled after 2.5 minutes of silence:
        // its window is the 3-minute chunk cadence, whereas the per-byte cost
        // would have clamped to the 2-minute floor and reported "delayed" for a
        // job that is simply between two slow chunks.
        final lastFrame = _started.add(const Duration(minutes: 10));
        const silentFor = Duration(minutes: 2, seconds: 30);
        expect(silentFor, greaterThan(aiJobEtaStallFloor));
        expect(silentFor, lessThan(const Duration(minutes: 3)));
        expect(
          aiJobEtaStalled(
            eta: eta,
            lastFrameAt: lastFrame,
            now: lastFrame.add(silentFor),
          ),
          isFalse,
        );
      },
    );

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
        // ONE slow chunk is a single sample: it may lift the figure by at most
        // the documented step factor and must NOT flip it into a range — the
        // uncertainty is smoothed too, so the width cannot teleport from 0 to
        // full spread in one frame.
        expect(
          second.upper.inMicroseconds,
          lessThanOrEqualTo(
            (first.upper.inMicroseconds * aiJobEtaMaxStepFactor).round(),
          ),
          reason: 'a single slow chunk may raise the estimate only gradually',
        );
        expect(
          second.isRange,
          isFalse,
          reason: 'one slow chunk is not yet a corroborated slowdown',
        );
        expect(second.lower, second.upper);

        // The slowdown is corroborated by the NEXT slow chunk: now the honest
        // answer is a range, and it is disclosed.
        final third = estimateAiJobEta(
          progress: _progress(chunk: 4, chunksTotal: 10, startedAt: _started),
          now: _started.add(const Duration(minutes: 21)),
          previous: second,
        );
        expect(third, isNotNull);
        expect(third!.isRange, isTrue);
        expect(third.upper, greaterThan(third.lower));
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
        // `isRange` is threshold-driven: a hand-built envelope must declare the
        // spread it represents, not rely on `upper > lower`.
        spread: aiJobEtaRangeThreshold,
      );
      expect(aiJobEtaText(eta: range, stalled: false, copy: copy()), '2–4 min');
    });

    test('long estimates switch to whole hours, range included', () {
      final hours = AiJobEta(
        lower: const Duration(minutes: 100),
        upper: const Duration(minutes: 200),
        perUnit: const Duration(minutes: 5),
        basis: AiJobEtaBasis.chunks,
        spread: aiJobEtaRangeThreshold,
      );
      expect(aiJobEtaText(eta: hours, stalled: false, copy: copy()), '2–3 h');
      // A range that collapses to one displayed hour is a figure, not a
      // "2–2 h" non-range.
      final collapsed = AiJobEta(
        lower: const Duration(minutes: 100),
        upper: const Duration(minutes: 140),
        perUnit: const Duration(minutes: 5),
        basis: AiJobEtaBasis.chunks,
        spread: aiJobEtaRangeThreshold,
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

  // -------------------------------------------------------------------------
  // Issue #871 (D-B5): a resumed attempt measures from its own start, never
  // from the absolute counter.
  // -------------------------------------------------------------------------
  group('resumed attempts', () {
    test('the rate divides by what THIS attempt completed, not the counter', () {
      // 26 of 42 done, of which 25 were resumed: this attempt did ONE chunk in
      // two minutes. A naive rate would read "26 chunks in two minutes".
      final eta = estimateAiJobEta(
        progress: _progress(
          chunk: 26,
          chunksTotal: 42,
          resumedFrom: 25,
          startedAt: _started,
        ),
        now: _started.add(const Duration(minutes: 2)),
      );
      // One sample this attempt is below the two-sample floor: no number is
      // fabricated.
      expect(eta, isNull);
    });

    test('two samples this attempt produce a figure from the delta', () {
      // 27 done, 25 resumed → 2 chunks in 4 minutes → 2 min/chunk → 15 chunks
      // left → 30 minutes.
      final eta = estimateAiJobEta(
        progress: _progress(
          chunk: 27,
          chunksTotal: 42,
          resumedFrom: 25,
          startedAt: _started,
        ),
        now: _started.add(const Duration(minutes: 4)),
      );
      expect(eta, isNotNull);
      expect(eta!.basis, AiJobEtaBasis.chunks);
      expect(eta.lower.inMinutes, 30);
      // NOT the absurd 4-minute-derived figure a naive rate would produce
      // (27 chunks in 4 min → ~2 min left).
      expect(eta.lower.inMinutes, isNot(lessThan(10)));
    });

    test('the stall watchdog measures the cadence of this attempt', () {
      // 2 chunks in 4 minutes → 2 min/chunk → a 6-minute stall window, not the
      // 2-minute floor a 27-chunk rate would produce.
      final eta = estimateAiJobEta(
        progress: _progress(
          chunk: 27,
          chunksTotal: 42,
          resumedFrom: 25,
          startedAt: _started,
        ),
        now: _started.add(const Duration(minutes: 4)),
      );
      expect(eta!.chunkCadence, const Duration(minutes: 2));
    });

    test('the byte basis is refused on a resumed attempt', () {
      // The prefix's bytes are not separable from this attempt's, so the pair is
      // unusable — the chunk pair is the honest basis.
      final units = aiJobProgressUnits(
        _progress(
          chunk: 26,
          chunksTotal: 42,
          doneBytes: 900,
          totalBytes: 2000,
          resumedFrom: 25,
        ),
      );
      expect(units, isNotNull);
      expect(units!.basis, AiJobEtaBasis.chunks);
    });

    test('a non-resumed frame keeps the byte preference', () {
      final units = aiJobProgressUnits(
        _progress(chunk: 2, chunksTotal: 10, doneBytes: 500, totalBytes: 2000),
      );
      expect(units!.basis, AiJobEtaBasis.bytes);
    });
  });
}
