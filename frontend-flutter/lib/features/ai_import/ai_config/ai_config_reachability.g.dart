// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_config_reachability.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One-shot reachability probe for the AI-configuration entry points
/// (issue #809).
///
/// Why a probe at all: a configuration surface hidden by "unknown" is
/// indistinguishable from an absent one, and a failed read is NOT the same
/// fact as "no configuration exists". The Settings entry therefore asks the
/// existing health seam whether the backend answers before it renders any
/// configuration claim.
///
/// Reuse, not reinvention: [backendHealthProbeProvider] is the single
/// `GET /v1/health` seam (public route, never throws, maps every failure to
/// [BackendHealthUnreachable]). This provider performs exactly ONE probe per
/// (autoDispose) lifetime — no polling, no backoff schedule; the drawer's
/// health pill owns the periodic poll. A retry is an explicit user action
/// (`ref.invalidate(aiConfigReachabilityProvider)`), which re-runs the probe.
///
/// AutoDispose by design: leaving the Settings screen or the configuration
/// screen drops the state, so the next visit measures again instead of
/// serving a stale "reachable" verdict as if it were current.

@ProviderFor(aiConfigReachability)
final aiConfigReachabilityProvider = AiConfigReachabilityProvider._();

/// One-shot reachability probe for the AI-configuration entry points
/// (issue #809).
///
/// Why a probe at all: a configuration surface hidden by "unknown" is
/// indistinguishable from an absent one, and a failed read is NOT the same
/// fact as "no configuration exists". The Settings entry therefore asks the
/// existing health seam whether the backend answers before it renders any
/// configuration claim.
///
/// Reuse, not reinvention: [backendHealthProbeProvider] is the single
/// `GET /v1/health` seam (public route, never throws, maps every failure to
/// [BackendHealthUnreachable]). This provider performs exactly ONE probe per
/// (autoDispose) lifetime — no polling, no backoff schedule; the drawer's
/// health pill owns the periodic poll. A retry is an explicit user action
/// (`ref.invalidate(aiConfigReachabilityProvider)`), which re-runs the probe.
///
/// AutoDispose by design: leaving the Settings screen or the configuration
/// screen drops the state, so the next visit measures again instead of
/// serving a stale "reachable" verdict as if it were current.

final class AiConfigReachabilityProvider
    extends
        $FunctionalProvider<
          AsyncValue<AiConfigBackendReachability>,
          AiConfigBackendReachability,
          FutureOr<AiConfigBackendReachability>
        >
    with
        $FutureModifier<AiConfigBackendReachability>,
        $FutureProvider<AiConfigBackendReachability> {
  /// One-shot reachability probe for the AI-configuration entry points
  /// (issue #809).
  ///
  /// Why a probe at all: a configuration surface hidden by "unknown" is
  /// indistinguishable from an absent one, and a failed read is NOT the same
  /// fact as "no configuration exists". The Settings entry therefore asks the
  /// existing health seam whether the backend answers before it renders any
  /// configuration claim.
  ///
  /// Reuse, not reinvention: [backendHealthProbeProvider] is the single
  /// `GET /v1/health` seam (public route, never throws, maps every failure to
  /// [BackendHealthUnreachable]). This provider performs exactly ONE probe per
  /// (autoDispose) lifetime — no polling, no backoff schedule; the drawer's
  /// health pill owns the periodic poll. A retry is an explicit user action
  /// (`ref.invalidate(aiConfigReachabilityProvider)`), which re-runs the probe.
  ///
  /// AutoDispose by design: leaving the Settings screen or the configuration
  /// screen drops the state, so the next visit measures again instead of
  /// serving a stale "reachable" verdict as if it were current.
  AiConfigReachabilityProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiConfigReachabilityProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiConfigReachabilityHash();

  @$internal
  @override
  $FutureProviderElement<AiConfigBackendReachability> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AiConfigBackendReachability> create(Ref ref) {
    return aiConfigReachability(ref);
  }
}

String _$aiConfigReachabilityHash() =>
    r'e92f3b5e2f005e6a2bc70c87ea298179eceec99c';
