// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'decision_outcome.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The job's recorded Decision Model outcome (issue #767).
///
/// `null` means exactly one thing: **the wire carries no outcome** — a job
/// recorded before the field existed. The provider never invents one, so
/// "nothing recorded" keeps rendering no line at all.
///
/// A FAILED read is not `null`: it is an [AsyncError] the caller must show
/// (AGENTS.md §4 — "a failed refetch is surfaced as `AsyncError`, never
/// swallowed"). Mapping the failure to `null` as well made a transient
/// snapshot fault indistinguishable from a pre-#767 job, and nothing
/// invalidated the provider, so the silent gap outlived every rebuild.
///
/// `getJobAndCache` (NOT the SSE watch) keeps this a single cheap snapshot: the
/// preview and the job screen read one authoritative fact, and the app's single
/// SSE consumer stays the job-status controller (battery contract D5).
///
/// No automatic retry: Riverpod 3's default re-runs a failed provider on an
/// exponential backoff timer, which is unbounded, wall-clock driven (AGENTS.md
/// §6 forbids timing-gated tests) and would flag the state `isLoading` while the
/// backoff is pending. The refetch here is user-driven —
/// [AiDecisionOutcomeLine]'s retry button invalidates the provider.

@ProviderFor(aiJobDecisionTelemetry)
final aiJobDecisionTelemetryProvider = AiJobDecisionTelemetryFamily._();

/// The job's recorded Decision Model outcome (issue #767).
///
/// `null` means exactly one thing: **the wire carries no outcome** — a job
/// recorded before the field existed. The provider never invents one, so
/// "nothing recorded" keeps rendering no line at all.
///
/// A FAILED read is not `null`: it is an [AsyncError] the caller must show
/// (AGENTS.md §4 — "a failed refetch is surfaced as `AsyncError`, never
/// swallowed"). Mapping the failure to `null` as well made a transient
/// snapshot fault indistinguishable from a pre-#767 job, and nothing
/// invalidated the provider, so the silent gap outlived every rebuild.
///
/// `getJobAndCache` (NOT the SSE watch) keeps this a single cheap snapshot: the
/// preview and the job screen read one authoritative fact, and the app's single
/// SSE consumer stays the job-status controller (battery contract D5).
///
/// No automatic retry: Riverpod 3's default re-runs a failed provider on an
/// exponential backoff timer, which is unbounded, wall-clock driven (AGENTS.md
/// §6 forbids timing-gated tests) and would flag the state `isLoading` while the
/// backoff is pending. The refetch here is user-driven —
/// [AiDecisionOutcomeLine]'s retry button invalidates the provider.

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
  /// `null` means exactly one thing: **the wire carries no outcome** — a job
  /// recorded before the field existed. The provider never invents one, so
  /// "nothing recorded" keeps rendering no line at all.
  ///
  /// A FAILED read is not `null`: it is an [AsyncError] the caller must show
  /// (AGENTS.md §4 — "a failed refetch is surfaced as `AsyncError`, never
  /// swallowed"). Mapping the failure to `null` as well made a transient
  /// snapshot fault indistinguishable from a pre-#767 job, and nothing
  /// invalidated the provider, so the silent gap outlived every rebuild.
  ///
  /// `getJobAndCache` (NOT the SSE watch) keeps this a single cheap snapshot: the
  /// preview and the job screen read one authoritative fact, and the app's single
  /// SSE consumer stays the job-status controller (battery contract D5).
  ///
  /// No automatic retry: Riverpod 3's default re-runs a failed provider on an
  /// exponential backoff timer, which is unbounded, wall-clock driven (AGENTS.md
  /// §6 forbids timing-gated tests) and would flag the state `isLoading` while the
  /// backoff is pending. The refetch here is user-driven —
  /// [AiDecisionOutcomeLine]'s retry button invalidates the provider.
  AiJobDecisionTelemetryProvider._({
    required AiJobDecisionTelemetryFamily super.from,
    required String super.argument,
  }) : super(
         retry: _noAutoRetry,
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
    r'814db56b81551fb1b8b8d235c539c0d779a374ee';

/// The job's recorded Decision Model outcome (issue #767).
///
/// `null` means exactly one thing: **the wire carries no outcome** — a job
/// recorded before the field existed. The provider never invents one, so
/// "nothing recorded" keeps rendering no line at all.
///
/// A FAILED read is not `null`: it is an [AsyncError] the caller must show
/// (AGENTS.md §4 — "a failed refetch is surfaced as `AsyncError`, never
/// swallowed"). Mapping the failure to `null` as well made a transient
/// snapshot fault indistinguishable from a pre-#767 job, and nothing
/// invalidated the provider, so the silent gap outlived every rebuild.
///
/// `getJobAndCache` (NOT the SSE watch) keeps this a single cheap snapshot: the
/// preview and the job screen read one authoritative fact, and the app's single
/// SSE consumer stays the job-status controller (battery contract D5).
///
/// No automatic retry: Riverpod 3's default re-runs a failed provider on an
/// exponential backoff timer, which is unbounded, wall-clock driven (AGENTS.md
/// §6 forbids timing-gated tests) and would flag the state `isLoading` while the
/// backoff is pending. The refetch here is user-driven —
/// [AiDecisionOutcomeLine]'s retry button invalidates the provider.

final class AiJobDecisionTelemetryFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<DecisionTelemetry?>, String> {
  AiJobDecisionTelemetryFamily._()
    : super(
        retry: _noAutoRetry,
        name: r'aiJobDecisionTelemetryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The job's recorded Decision Model outcome (issue #767).
  ///
  /// `null` means exactly one thing: **the wire carries no outcome** — a job
  /// recorded before the field existed. The provider never invents one, so
  /// "nothing recorded" keeps rendering no line at all.
  ///
  /// A FAILED read is not `null`: it is an [AsyncError] the caller must show
  /// (AGENTS.md §4 — "a failed refetch is surfaced as `AsyncError`, never
  /// swallowed"). Mapping the failure to `null` as well made a transient
  /// snapshot fault indistinguishable from a pre-#767 job, and nothing
  /// invalidated the provider, so the silent gap outlived every rebuild.
  ///
  /// `getJobAndCache` (NOT the SSE watch) keeps this a single cheap snapshot: the
  /// preview and the job screen read one authoritative fact, and the app's single
  /// SSE consumer stays the job-status controller (battery contract D5).
  ///
  /// No automatic retry: Riverpod 3's default re-runs a failed provider on an
  /// exponential backoff timer, which is unbounded, wall-clock driven (AGENTS.md
  /// §6 forbids timing-gated tests) and would flag the state `isLoading` while the
  /// backoff is pending. The refetch here is user-driven —
  /// [AiDecisionOutcomeLine]'s retry button invalidates the provider.

  AiJobDecisionTelemetryProvider call(String jobId) =>
      AiJobDecisionTelemetryProvider._(argument: jobId, from: this);

  @override
  String toString() => r'aiJobDecisionTelemetryProvider';
}
