// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart' show AiImportProgress;

/// Which counter pair an estimate is derived from (issue #762).
///
/// Bytes win whenever the backend published a positive budget: one chunk is
/// one scene and scene lengths differ by an order of magnitude, so a chunk
/// count is the cruder denominator. The chunk pair is the documented fallback
/// for a backend that has no byte budget (and for a single-unit job).
enum AiJobEtaBasis { bytes, chunks }

/// Completed/total work units of a running import, as the backend published
/// them.
class AiJobProgressUnits {
  const AiJobProgressUnits({
    required this.done,
    required this.total,
    required this.basis,
  });

  /// Units already completed (`0..=total`).
  final int done;

  /// Total units the job will process.
  final int total;

  /// Which counter pair [done]/[total] came from.
  final AiJobEtaBasis basis;

  /// Remaining units, never negative.
  int get remaining => total > done ? total - done : 0;

  @override
  bool operator ==(Object other) =>
      other is AiJobProgressUnits &&
      other.done == done &&
      other.total == total &&
      other.basis == basis;

  @override
  int get hashCode => Object.hash(done, total, basis);

  @override
  String toString() => 'AiJobProgressUnits($done/$total, ${basis.name})';
}

/// Pick the counter pair to estimate from (issue #762).
///
/// `null` when the job published no usable pair at all — a `pending` job (its
/// progress is cleared on every claim), a schedule/merge job (a single
/// extraction unit) and a pre-#762 frame all land here. An ETA is then simply
/// not shown; nothing is fabricated from a missing denominator.
AiJobProgressUnits? aiJobProgressUnits(AiImportProgress? progress) {
  if (progress == null) return null;
  // Issue #871: on a RESUMED attempt the byte pair mixes two populations —
  // `doneBytes` starts at the stored prefix's bytes while `startedAt` only
  // covers this attempt — and the prefix's byte count is not on the wire. The
  // chunk pair, whose delta is exact (`chunk - resumed_from`), is therefore the
  // only honest basis. Nothing is fabricated from the unusable pair.
  final resumed = progress.resumedFrom ?? 0;
  final totalBytes = progress.totalBytes;
  final doneBytes = progress.doneBytes;
  if (resumed == 0 &&
      totalBytes != null &&
      totalBytes > 0 &&
      doneBytes != null) {
    return AiJobProgressUnits(
      done: doneBytes.clamp(0, totalBytes),
      total: totalBytes,
      basis: AiJobEtaBasis.bytes,
    );
  }
  final total = progress.chunksTotal;
  final done = progress.chunk;
  if (total != null && total > 0 && done != null) {
    return AiJobProgressUnits(
      done: done.clamp(0, total),
      total: total,
      basis: AiJobEtaBasis.chunks,
    );
  }
  return null;
}

/// A defensible coarse remaining-time estimate (issue #762).
///
/// Deliberately a *range carrier*, not a countdown: [lower]/[upper] are the
/// honest envelope, and [isRange] says whether the observed cadence was steady
/// enough to render a single figure.
class AiJobEta {
  const AiJobEta({
    required this.lower,
    required this.upper,
    required this.perUnit,
    required this.basis,
    this.spread = 0,
    Duration? chunkCadence,
  }) : chunkCadence = chunkCadence ?? perUnit;

  /// Optimistic remaining time (never negative).
  final Duration lower;

  /// Pessimistic remaining time (at least [lower]); equal to [lower] for a
  /// point estimate.
  final Duration upper;

  /// Smoothed cost of one completed unit — the carrier that survives frames so
  /// the estimate can be smoothed without re-deriving history.
  final Duration perUnit;

  /// Which counter pair produced this estimate.
  final AiJobEtaBasis basis;

  /// Smoothed relative uncertainty of [perUnit], in `0..=`[aiJobEtaMaxSpread].
  ///
  /// Carried across frames like [perUnit]: the rendered width is derived from
  /// it, so it has to be smoothed too. An unsmoothed spread would turn a point
  /// estimate into a full-width range on the strength of one slow chunk.
  final double spread;

  /// How long one **completed chunk** took on average.
  ///
  /// The stall watchdog measures this cadence, not the cost of one *unit*: on
  /// the byte basis a unit is a single byte, so a per-byte cost multiplied by
  /// the stall factor stays inside the floor forever and a slow-but-healthy
  /// chunk cycle would be reported as "delayed". Equal to [perUnit] when the
  /// measured pair already is the chunk pair.
  final Duration chunkCadence;

  /// True when the cadence was unsteady enough that only a range is honest.
  ///
  /// Derived from [aiJobEtaRangeThreshold], never from `upper > lower` alone:
  /// that would report a range for any nonzero width, including one whose
  /// bounds round to neighbouring coarse figures ("5–6 min" where the data only
  /// supports "6 min").
  bool get isRange => spread >= aiJobEtaRangeThreshold && upper > lower;

  @override
  bool operator ==(Object other) =>
      other is AiJobEta &&
      other.lower == lower &&
      other.upper == upper &&
      other.perUnit == perUnit &&
      other.basis == basis &&
      other.spread == spread &&
      other.chunkCadence == chunkCadence;

  @override
  int get hashCode =>
      Object.hash(lower, upper, perUnit, basis, spread, chunkCadence);

  @override
  String toString() =>
      'AiJobEta(${lower.inSeconds}s..${upper.inSeconds}s, ${basis.name}, '
      'spread=${spread.toStringAsFixed(2)}, unit ${perUnit.inMilliseconds}ms, '
      'chunk ${chunkCadence.inMilliseconds}ms)';
}

/// Minimum completed units before an estimate is defensible.
///
/// One completed unit says nothing about the cadence — it is a single sample —
/// so the client renders "estimating …" until a second one lands.
const int aiJobEtaMinUnits = 2;

/// EMA weight of the newest frame in the per-unit cost.
const double aiJobEtaSmoothingAlpha = 0.35;

/// Largest factor by which the smoothed per-unit cost — and therefore the
/// rendered estimate — may move between two adjacent frames.
///
/// One slow chunk is absorbed gradually instead of yanking the figure, so a user
/// sees a stable number rather than a timer that bounces.
///
/// What it deliberately does **not** do is freeze the countdown: when the
/// slowdown is real (the following chunks are slow too), the estimate must rise
/// — suppressing that would be a lie. The clamp refuses only the *single-sample*
/// jump, and the range (see [aiJobEtaRangeThreshold]) is how sustained
/// uncertainty is disclosed instead of a false-precision figure.
const double aiJobEtaMaxStepFactor = 1.5;

/// Cap of the rendered range half-width.
const double aiJobEtaMaxSpread = 0.5;

/// Above this spread the estimate renders as a range instead of a figure.
const double aiJobEtaRangeThreshold = 0.2;

/// Remaining time beyond this horizon is refused as a broken anchor rather than
/// shown as an absurd number.
const Duration aiJobEtaMaxHorizon = Duration(hours: 24);

/// Multiples of the observed per-unit cadence before a job counts as stalled.
const int aiJobEtaStallCadenceFactor = 3;

/// Lower clamp of the stall window: frames are throttled (one per completed
/// chunk), so short cadences must not declare a stall in seconds.
const Duration aiJobEtaStallFloor = Duration(minutes: 2);

/// Upper clamp of the stall window: a single chunk may legitimately take the
/// provider request timeout plus retries.
const Duration aiJobEtaStallCeiling = Duration(minutes: 30);

/// Estimate the remaining time of a running import (issue #762).
///
/// Pure and deterministic: the caller supplies `now` and — to smooth across
/// frames — the previous estimate. Returns `null` whenever an estimate is not
/// defensible (no time anchor, no counter pair, fewer than
/// [aiJobEtaMinUnits] completed units, a non-positive elapsed time, or a
/// remaining time beyond [aiJobEtaMaxHorizon]); the caller then renders the
/// "estimating …" state instead of a number.
///
/// `now` should be the frame's own write stamp ([AiImportProgress.writtenAt])
/// whenever the backend publishes one: the measured interval is then extraction
/// time, not "wall-clock time since the attempt started", which would count
/// every second the screen was closed as work.
///
/// Smoothing is an EMA over the per-unit cost **and** over the relative
/// uncertainty, and each is step-bounded: between two adjacent frames the cost
/// moves by at most [aiJobEtaMaxStepFactor] and the width by one EMA step. A
/// corroborated slowdown still raises the estimate — that is the honest answer —
/// but a single slow chunk cannot yank the figure or teleport it into a
/// full-width range.
AiJobEta? estimateAiJobEta({
  required AiImportProgress? progress,
  required DateTime now,
  AiJobEta? previous,
}) {
  final units = aiJobProgressUnits(progress);
  final startedAt = progress?.startedAt;
  if (units == null || startedAt == null) return null;
  // Issue #871: `chunk` counts the last completed chunk OF THIS ATTEMPT, which on
  // a resumed attempt already includes the stored prefix. Every quantity derived
  // from "how much did this attempt do" must therefore subtract it — otherwise a
  // resumed attempt reads as "25 chunks in one second" and then declares a healthy
  // successor chunk stalled after two minutes.
  final resumed = progress?.resumedFrom ?? 0;
  final chunksDone = progress?.chunk;
  // The two-sample floor is about COMPLETED CHUNKS, independent of the basis the
  // rate uses: one chunk is one sample whatever its byte count, so a byte-basis
  // frame with a single chunk done must not produce a number.
  final samplesThisAttempt = chunksDone == null ? null : chunksDone - resumed;
  if (samplesThisAttempt != null && samplesThisAttempt < aiJobEtaMinUnits) {
    return null;
  }
  final elapsedMicros = now.difference(startedAt).inMicroseconds;
  if (elapsedMicros <= 0) return null;
  // The rate denominator is what THIS attempt completed, never the absolute
  // counter; the remaining count still comes from the absolute counter.
  final rateDone = units.done - resumed;
  if (rateDone < aiJobEtaMinUnits) return null;
  return estimateEtaFrom(
    startedAt: startedAt,
    done: units.done,
    total: units.total,
    rateDone: rateDone,
    basis: units.basis,
    now: now,
    previous: previous,
    // The stall watchdog measures the CHUNK cadence: on the byte basis a unit is
    // a byte, so its cost says nothing about when the next frame may arrive.
    chunkCadence:
        samplesThisAttempt != null && samplesThisAttempt >= aiJobEtaMinUnits
        ? Duration(microseconds: (elapsedMicros / samplesThisAttempt).round())
        : null,
  );
}

/// Estimate the remaining time from any counter pair (issue #762).
///
/// The extraction phase feeds it `AiImportProgress` through
/// [estimateAiJobEta]; the apply run feeds it its own `applied`/`total`. Same
/// policy for both — that is the point: one estimator, one honesty contract, so
/// the two phases cannot drift into different "is this defensible?" rules.
///
/// [chunkCadence] is the observed cost of one completed **chunk** when the
/// caller can express it (the extraction phase can; an apply run has no separate
/// chunk notion and its rows ARE the units, so it falls back to [perUnit]).
AiJobEta? estimateEtaFrom({
  required DateTime? startedAt,
  required int done,
  required int total,
  required DateTime now,
  AiJobEta? previous,
  AiJobEtaBasis basis = AiJobEtaBasis.chunks,
  Duration? chunkCadence,

  /// Units THIS attempt completed, when that differs from [done] (issue #871:
  /// a resumed attempt's counter includes the stored prefix). The rate divides
  /// the elapsed time by this; the remaining count still comes from [done].
  int? rateDone,
}) {
  if (startedAt == null) return null;
  final units = AiJobProgressUnits(done: done, total: total, basis: basis);
  if (units.total <= 0) return null;
  if (units.done < aiJobEtaMinUnits) return null;
  final rateUnits = rateDone ?? units.done;
  if (rateUnits < aiJobEtaMinUnits) return null;
  final elapsedMicros = now.difference(startedAt).inMicroseconds;
  if (elapsedMicros <= 0) return null;

  final rawPerUnit = elapsedMicros / rateUnits;
  final rawSpread = _relativeGap(rawPerUnit, previous?.perUnit);
  var perUnitMicros = rawPerUnit;
  var spread = rawSpread;
  final base = previous?.perUnit.inMicroseconds.toDouble();
  if (base != null && base > 0) {
    final bounded = rawPerUnit.clamp(
      base / aiJobEtaMaxStepFactor,
      base * aiJobEtaMaxStepFactor,
    );
    perUnitMicros = base + (bounded - base) * aiJobEtaSmoothingAlpha;
    // The uncertainty is smoothed like the cost: unsmoothed, one slow chunk
    // would take a point estimate straight to a full-width range.
    spread =
        previous!.spread +
        (rawSpread - previous.spread) * aiJobEtaSmoothingAlpha;
  }

  final remainingMicros = perUnitMicros * units.remaining;
  if (remainingMicros > aiJobEtaMaxHorizon.inMicroseconds) return null;
  final isRange = spread >= aiJobEtaRangeThreshold;
  // Below the threshold no width is reported at all: a range whose bounds round
  // to neighbouring coarse figures ("5–6 min") would claim an uncertainty the
  // data does not support, so both bounds ARE the point estimate.
  final lowerMicros = isRange
      ? remainingMicros * (1 - spread)
      : remainingMicros;
  final upperMicros = isRange
      ? remainingMicros * (1 + spread)
      : remainingMicros;
  return AiJobEta(
    lower: _nonNegative(lowerMicros),
    upper: _nonNegative(upperMicros),
    perUnit: _nonNegative(perUnitMicros),
    basis: units.basis,
    spread: spread,
    chunkCadence: chunkCadence ?? _nonNegative(perUnitMicros),
  );
}

/// Relative distance between the newest per-unit sample and the cost it is about
/// to be blended into, clamped to [aiJobEtaMaxSpread].
double _relativeGap(double rawPerUnit, Duration? previousPerUnit) {
  final base = previousPerUnit?.inMicroseconds.toDouble();
  if (base == null || base <= 0) return 0;
  final larger = rawPerUnit > base ? rawPerUnit : base;
  if (larger <= 0) return 0;
  return ((rawPerUnit - base).abs() / larger).clamp(0.0, aiJobEtaMaxSpread);
}

Duration _nonNegative(double micros) {
  if (micros.isNaN || micros <= 0) return Duration.zero;
  final rounded = micros.round();
  return rounded <= 0 ? Duration.zero : Duration(microseconds: rounded);
}

/// How long without a progress frame counts as "stalled" for [eta].
///
/// [aiJobEtaStallCadenceFactor] × the observed **chunk** cadence
/// ([AiJobEta.chunkCadence], not the per-byte cost), clamped into
/// [aiJobEtaStallFloor]..[aiJobEtaStallCeiling].
Duration aiJobEtaStallWindow(AiJobEta eta) {
  final raw = eta.chunkCadence.inMicroseconds * aiJobEtaStallCadenceFactor;
  final window = Duration(microseconds: raw.round());
  if (window < aiJobEtaStallFloor) return aiJobEtaStallFloor;
  if (window > aiJobEtaStallCeiling) return aiJobEtaStallCeiling;
  return window;
}

/// True when the job stopped publishing frames (issue #762).
///
/// A stalled job drops its estimate entirely rather than showing a countdown
/// that can only be wrong: the honest state is "delayed".
bool aiJobEtaStalled({
  required AiJobEta eta,
  required DateTime lastFrameAt,
  required DateTime now,
}) {
  final gap = now.difference(lastFrameAt);
  if (gap.isNegative) return false;
  return gap > aiJobEtaStallWindow(eta);
}

/// Localized copy for [aiJobEtaText] (ADR-034: no user-facing strings in this
/// file — the presentation layer supplies them from the ARB catalogs).
class AiJobEtaCopy {
  const AiJobEtaCopy({
    required this.calculating,
    required this.delayed,
    required this.imminent,
    required this.minutes,
    required this.hours,
    required this.rangeMinutes,
    required this.rangeHours,
  });

  /// Shown while no estimate is defensible yet (fewer than two units done).
  final String calculating;

  /// Shown when frames stopped arriving.
  final String delayed;

  /// Shown when less than a minute remains.
  final String imminent;

  /// Renders `<n> minutes` remaining.
  final String Function(int count) minutes;

  /// Renders `<n> hours` remaining.
  final String Function(int count) hours;

  /// Renders a `<lower>–<upper> minutes` range.
  final String Function(int lower, int upper) rangeMinutes;

  /// Renders a `<lower>–<upper> hours` range.
  final String Function(int lower, int upper) rangeHours;
}

/// Coarse-unit threshold above which the copy switches to hours.
const int aiJobEtaHourThresholdMinutes = 90;

/// Render [eta] for the UI (issue #762).
///
/// `stalled` always wins: a stalled job has no defensible estimate. `null`
/// renders the "estimating …" state. Units are coarse on purpose — minutes
/// ("about 3 min") or whole hours ("about 2 h"), never a seconds-precision
/// timer, and never `0 min`: anything under a minute is "almost done".
String aiJobEtaText({
  required AiJobEta? eta,
  required bool stalled,
  required AiJobEtaCopy copy,
}) {
  if (stalled) return copy.delayed;
  if (eta == null) return copy.calculating;
  if (eta.upper < const Duration(minutes: 1)) return copy.imminent;

  final useHours = eta.upper.inMinutes >= aiJobEtaHourThresholdMinutes;
  final upper = useHours ? _hours(eta.upper) : _minutes(eta.upper);
  final lower = useHours ? _hours(eta.lower) : _minutes(eta.lower);
  if (eta.isRange && lower < upper) {
    return useHours
        ? copy.rangeHours(lower, upper)
        : copy.rangeMinutes(lower, upper);
  }
  return useHours ? copy.hours(upper) : copy.minutes(upper);
}

int _minutes(Duration duration) {
  final minutes = (duration.inSeconds / 60).ceil();
  return minutes < 1 ? 1 : minutes;
}

int _hours(Duration duration) {
  final hours = (duration.inMinutes / 60).round();
  return hours < 1 ? 1 : hours;
}
