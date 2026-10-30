// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'decision_outcome.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The job's recorded Decision Model outcome (issue #767).
///
/// `null` means "the wire carries no outcome" — a job recorded before the field
/// existed, or a read that failed. The provider never invents one: an
/// unreadable job renders no line at all, which is the honest degradation for
/// data that does not exist.
///
/// `getJobAndCache` (NOT the SSE watch) keeps this a single cheap snapshot: the
/// preview and the job screen read one authoritative fact, and the app's single
/// SSE consumer stays the job-status controller (battery contract D5).

@ProviderFor(aiJobDecisionTelemetry)
final aiJobDecisionTelemetryProvider = AiJobDecisionTelemetryFamily._();

/// The job's recorded Decision Model outcome (issue #767).
///
/// `null` means "the wire carries no outcome" — a job recorded before the field
/// existed, or a read that failed. The provider never invents one: an
/// unreadable job renders no line at all, which is the honest degradation for
/// data that does not exist.
///
/// `getJobAndCache` (NOT the SSE watch) keeps this a single cheap snapshot: the
/// preview and the job screen read one authoritative fact, and the app's single
/// SSE consumer stays the job-status controller (battery contract D5).

final class AiJobDecisionTelemetryProvider
    extends
        $FunctionalProvider<
          AsyncValue<DecisionTelemetry?>,
          DecisionTelemetry?,
          FutureOr<DecisionTelemetry?>
        >
    with
        $FutureModifier<DecisionTelemetry?>,
        $FutureProvider<DecisionTelemetry?> {
  /// The job's recorded Decision Model outcome (issue #767).
  ///
  /// `null` means "the wire carries no outcome" — a job recorded before the field
  /// existed, or a read that failed. The provider never invents one: an
  /// unreadable job renders no line at all, which is the honest degradation for
  /// data that does not exist.
  ///
  /// `getJobAndCache` (NOT the SSE watch) keeps this a single cheap snapshot: the
  /// preview and the job screen read one authoritative fact, and the app's single
  /// SSE consumer stays the job-status controller (battery contract D5).
  AiJobDecisionTelemetryProvider._({
    required AiJobDecisionTelemetryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'aiJobDecisionTelemetryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aiJobDecisionTelemetryHash();

  @override
  String toString() {
    return r'aiJobDecisionTelemetryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<DecisionTelemetry?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<DecisionTelemetry?> create(Ref ref) {
    final argument = this.argument as String;
    return aiJobDecisionTelemetry(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AiJobDecisionTelemetryProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aiJobDecisionTelemetryHash() =>
    r'e163004cec51373258ac979672808b2577c0c934';

/// The job's recorded Decision Model outcome (issue #767).
///
/// `null` means "the wire carries no outcome" — a job recorded before the field
/// existed, or a read that failed. The provider never invents one: an
/// unreadable job renders no line at all, which is the honest degradation for
/// data that does not exist.
///
/// `getJobAndCache` (NOT the SSE watch) keeps this a single cheap snapshot: the
/// preview and the job screen read one authoritative fact, and the app's single
/// SSE consumer stays the job-status controller (battery contract D5).

final class AiJobDecisionTelemetryFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<DecisionTelemetry?>, String> {
  AiJobDecisionTelemetryFamily._()
    : super(
        retry: null,
        name: r'aiJobDecisionTelemetryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The job's recorded Decision Model outcome (issue #767).
  ///
  /// `null` means "the wire carries no outcome" — a job recorded before the field
  /// existed, or a read that failed. The provider never invents one: an
  /// unreadable job renders no line at all, which is the honest degradation for
  /// data that does not exist.
  ///
  /// `getJobAndCache` (NOT the SSE watch) keeps this a single cheap snapshot: the
  /// preview and the job screen read one authoritative fact, and the app's single
  /// SSE consumer stays the job-status controller (battery contract D5).

  AiJobDecisionTelemetryProvider call(String jobId) =>
      AiJobDecisionTelemetryProvider._(argument: jobId, from: this);

  @override
  String toString() => r'aiJobDecisionTelemetryProvider';
}
