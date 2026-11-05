// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'job_telemetry.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The job's content-free telemetry summary — `null` for a job that recorded
/// none (every pre-#609 row).
///
/// `null` means exactly one thing: **the wire carries no telemetry**, so the
/// app cannot name the model that produced the rows. The provider never
/// invents one, and it never falls back to the configured model — "configured"
/// and "used" are different facts, which is the whole point of issue #831.
///
/// A FAILED read re-throws into Riverpod's error channel. The naming card
/// renders that arm like "no telemetry known" rather than inventing a pair (see
/// [aiNamingComparison] callers): a header that cannot state which model ran
/// must not claim a comparison.

@ProviderFor(aiJobTelemetry)
final aiJobTelemetryProvider = AiJobTelemetryFamily._();

/// The job's content-free telemetry summary — `null` for a job that recorded
/// none (every pre-#609 row).
///
/// `null` means exactly one thing: **the wire carries no telemetry**, so the
/// app cannot name the model that produced the rows. The provider never
/// invents one, and it never falls back to the configured model — "configured"
/// and "used" are different facts, which is the whole point of issue #831.
///
/// A FAILED read re-throws into Riverpod's error channel. The naming card
/// renders that arm like "no telemetry known" rather than inventing a pair (see
/// [aiNamingComparison] callers): a header that cannot state which model ran
/// must not claim a comparison.

final class AiJobTelemetryProvider
    extends
        $FunctionalProvider<
          AsyncValue<JobTelemetrySummary?>,
          JobTelemetrySummary?,
          FutureOr<JobTelemetrySummary?>
        >
    with
        $FutureModifier<JobTelemetrySummary?>,
        $FutureProvider<JobTelemetrySummary?> {
  /// The job's content-free telemetry summary — `null` for a job that recorded
  /// none (every pre-#609 row).
  ///
  /// `null` means exactly one thing: **the wire carries no telemetry**, so the
  /// app cannot name the model that produced the rows. The provider never
  /// invents one, and it never falls back to the configured model — "configured"
  /// and "used" are different facts, which is the whole point of issue #831.
  ///
  /// A FAILED read re-throws into Riverpod's error channel. The naming card
  /// renders that arm like "no telemetry known" rather than inventing a pair (see
  /// [aiNamingComparison] callers): a header that cannot state which model ran
  /// must not claim a comparison.
  AiJobTelemetryProvider._({
    required AiJobTelemetryFamily super.from,
    required String super.argument,
  }) : super(
         retry: _noAutoRetry,
         name: r'aiJobTelemetryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aiJobTelemetryHash();

  @override
  String toString() {
    return r'aiJobTelemetryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<JobTelemetrySummary?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<JobTelemetrySummary?> create(Ref ref) {
    final argument = this.argument as String;
    return aiJobTelemetry(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AiJobTelemetryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aiJobTelemetryHash() => r'faa17063f14a6a667c7812df5c230b161c06c34f';

/// The job's content-free telemetry summary — `null` for a job that recorded
/// none (every pre-#609 row).
///
/// `null` means exactly one thing: **the wire carries no telemetry**, so the
/// app cannot name the model that produced the rows. The provider never
/// invents one, and it never falls back to the configured model — "configured"
/// and "used" are different facts, which is the whole point of issue #831.
///
/// A FAILED read re-throws into Riverpod's error channel. The naming card
/// renders that arm like "no telemetry known" rather than inventing a pair (see
/// [aiNamingComparison] callers): a header that cannot state which model ran
/// must not claim a comparison.

final class AiJobTelemetryFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<JobTelemetrySummary?>, String> {
  AiJobTelemetryFamily._()
    : super(
        retry: _noAutoRetry,
        name: r'aiJobTelemetryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The job's content-free telemetry summary — `null` for a job that recorded
  /// none (every pre-#609 row).
  ///
  /// `null` means exactly one thing: **the wire carries no telemetry**, so the
  /// app cannot name the model that produced the rows. The provider never
  /// invents one, and it never falls back to the configured model — "configured"
  /// and "used" are different facts, which is the whole point of issue #831.
  ///
  /// A FAILED read re-throws into Riverpod's error channel. The naming card
  /// renders that arm like "no telemetry known" rather than inventing a pair (see
  /// [aiNamingComparison] callers): a header that cannot state which model ran
  /// must not claim a comparison.

  AiJobTelemetryProvider call(String jobId) =>
      AiJobTelemetryProvider._(argument: jobId, from: this);

  @override
  String toString() => r'aiJobTelemetryProvider';
}
