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
  final totalBytes = progress.totalBytes;
  final doneBytes = progress.doneBytes;
  if (totalBytes != null && totalBytes > 0 && doneBytes != null) {
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
  });

  /// Optimistic remaining time (never negative).
  final Duration lower;

  /// Pessimistic remaining time (at least [lower]).
  final Duration upper;

  /// Smoothed cost of one completed unit — the carrier that survives frames so
  /// the estimate can be smoothed without re-deriving history.
  final Duration perUnit;

  /// Which counter pair produced this estimate.
  final AiJobEtaBasis basis;

  /// True when the cadence was unsteady enough that only a range is honest.
  ///
  /// A single figure would claim a precision the data does not carry, so the
  /// client renders "2–4 min" instead of a point value.
  bool get isRange => upper > lower;

  @override
  bool operator ==(Object other) =>
      other is AiJobEta &&
      other.lower == lower &&
      other.upper == upper &&
      other.perUnit == perUnit &&
      other.basis == basis;

  @override
  int get hashCode => Object.hash(lower, upper, perUnit, basis);

  @override
  String toString() =>
      'AiJobEta(${lower.inSeconds}s..${upper.inSeconds}s/unit '
      '${perUnit.inMilliseconds}ms, ${basis.name})';
}

/// Minimum completed units before an estimate is defensible.
///
/// One completed unit says nothing about the cadence — it is a single sample —
/// so the client renders "estimating …" until a second one lands.
const int aiJobEtaMinUnits = 2;

/// EMA weight of the newest frame in the per-unit cost.
const double aiJobEtaSmoothingAlpha = 0.35;

/// Largest factor by which the smoothed per-unit cost may move between two
/// frames.
///
/// Prevents the countdown from jumping backwards on one slow chunk (or
/// collapsing on one fast one): a step is absorbed gradually, so a user sees a
/// stable number instead of a timer that bounces.
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
/// Smoothing is an EMA over the per-unit cost, and the newest sample is first
/// clamped to [aiJobEtaMaxStepFactor] of the previous value. Re-deriving
/// `remaining = perUnit × unitsRemaining` on every frame is what keeps the
/// countdown monotone while units complete: a countdown that jumps *up* would
/// be a lie, and the clamp bounds how far one slow chunk may stretch it.
AiJobEta? estimateAiJobEta({
  required AiImportProgress? progress,
  required DateTime now,
  AiJobEta? previous,
}) {
  final units = aiJobProgressUnits(progress);
  final startedAt = progress?.startedAt;
  if (units == null || startedAt == null) return null;
  if (units.done < aiJobEtaMinUnits) return null;
  final elapsedMicros = now.difference(startedAt).inMicroseconds;
  if (elapsedMicros <= 0) return null;

  final rawPerUnit = elapsedMicros / units.done;
  var perUnitMicros = rawPerUnit;
  var spread = 0.0;
  final base = previous?.perUnit.inMicroseconds.toDouble();
  if (base != null && base > 0) {
    final bounded = rawPerUnit.clamp(
      base / aiJobEtaMaxStepFactor,
      base * aiJobEtaMaxStepFactor,
    );
    perUnitMicros = base + (bounded - base) * aiJobEtaSmoothingAlpha;
    final larger = rawPerUnit > perUnitMicros ? rawPerUnit : perUnitMicros;
    if (larger > 0) {
      spread = ((rawPerUnit - perUnitMicros).abs() / larger).clamp(
        0.0,
        aiJobEtaMaxSpread,
      );
    }
  }

  final remainingMicros = perUnitMicros * units.remaining;
  if (remainingMicros > aiJobEtaMaxHorizon.inMicroseconds) return null;
  final lowerMicros = remainingMicros * (1 - spread);
  final upperMicros = remainingMicros * (1 + spread);
  final isRange = spread >= aiJobEtaRangeThreshold;
  return AiJobEta(
    lower: _nonNegative(lowerMicros),
    // A point estimate carries no width; a range must actually be wider.
    upper: isRange ? _nonNegative(upperMicros) : _nonNegative(remainingMicros),
    perUnit: _nonNegative(perUnitMicros),
    basis: units.basis,
  );
}

Duration _nonNegative(double micros) {
  if (micros.isNaN || micros <= 0) return Duration.zero;
  final rounded = micros.round();
  return rounded <= 0 ? Duration.zero : Duration(microseconds: rounded);
}

/// How long without a progress frame counts as "stalled" for [eta].
///
/// [aiJobEtaStallCadenceFactor] × the observed per-unit cost, clamped into
/// [aiJobEtaStallFloor]..[aiJobEtaStallCeiling].
Duration aiJobEtaStallWindow(AiJobEta eta) {
  final raw = eta.perUnit.inMicroseconds * aiJobEtaStallCadenceFactor;
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
