// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backend_health_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Production probe over the app's generated client: `GET /v1/health` is
/// public (the auth middleware exempts it), so riding `apiClientProvider`
/// costs no token round-trip while inheriting the pinned-CA transport and
/// the runtime base-URL override. `validateStatus: (_) => true` lets the
/// 503 "unhealthy" answer deserialize into a `HealthReport` instead of
/// throwing like Dio's default predicate would.

@ProviderFor(backendHealthProbe)
final backendHealthProbeProvider = BackendHealthProbeProvider._();

/// Production probe over the app's generated client: `GET /v1/health` is
/// public (the auth middleware exempts it), so riding `apiClientProvider`
/// costs no token round-trip while inheriting the pinned-CA transport and
/// the runtime base-URL override. `validateStatus: (_) => true` lets the
/// 503 "unhealthy" answer deserialize into a `HealthReport` instead of
/// throwing like Dio's default predicate would.

final class BackendHealthProbeProvider
    extends
        $FunctionalProvider<
          BackendHealthProbe,
          BackendHealthProbe,
          BackendHealthProbe
        >
    with $Provider<BackendHealthProbe> {
  /// Production probe over the app's generated client: `GET /v1/health` is
  /// public (the auth middleware exempts it), so riding `apiClientProvider`
  /// costs no token round-trip while inheriting the pinned-CA transport and
  /// the runtime base-URL override. `validateStatus: (_) => true` lets the
  /// 503 "unhealthy" answer deserialize into a `HealthReport` instead of
  /// throwing like Dio's default predicate would.
  BackendHealthProbeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backendHealthProbeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backendHealthProbeHash();

  @$internal
  @override
  $ProviderElement<BackendHealthProbe> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BackendHealthProbe create(Ref ref) {
    return backendHealthProbe(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BackendHealthProbe value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BackendHealthProbe>(value),
    );
  }
}

String _$backendHealthProbeHash() =>
    r'0e51bf243705a07a4876b80a3229cbf922ace302';

@ProviderFor(backendHealthDelay)
final backendHealthDelayProvider = BackendHealthDelayProvider._();

final class BackendHealthDelayProvider
    extends
        $FunctionalProvider<
          BackendHealthDelay,
          BackendHealthDelay,
          BackendHealthDelay
        >
    with $Provider<BackendHealthDelay> {
  BackendHealthDelayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backendHealthDelayProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backendHealthDelayHash();

  @$internal
  @override
  $ProviderElement<BackendHealthDelay> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BackendHealthDelay create(Ref ref) {
    return backendHealthDelay(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BackendHealthDelay value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BackendHealthDelay>(value),
    );
  }
}

String _$backendHealthDelayHash() =>
    r'6712aa0fa180e868c54b303916809b589ceda5ad';

/// Backend health controller (issue #657): polls the public
/// `GET /v1/health` on a battery-friendly schedule and exposes the coarse
/// [BackendHealthTier] for the drawer's health pill.
///
/// Strategy:
/// 1. The initial state is `null` (no data yet): the pill slot stays EMPTY
///    until the first probe answers, so the drawer never flashes a wrong
///    tier. The drawer child builds lazily (DrawerController only builds the
///    content when opened), so the first poll starts when the user first
///    opens the drawer — no background traffic before that.
/// 2. After a HEALTHY answer the next poll waits
///    [backendHealthPollInterval] (60 s). Degraded/unhealthy/offline
///    outcomes re-probe on the [backendHealthRetryBackoff] schedule.
/// 3. While the passive connectivity signal (issue #654) reports the device
///    offline, NO health probes run: the tier maps to offline directly and
///    any in-flight chain is canceled (generation counter). When
///    connectivity returns, a fresh poll starts immediately.
/// 4. A generation counter cancels pending chains: a new passive event or a
///    controller rebuild supersedes every in-flight continuation, so a
///    flapping link cannot trigger request storms.

@ProviderFor(BackendHealthController)
final backendHealthControllerProvider = BackendHealthControllerProvider._();

/// Backend health controller (issue #657): polls the public
/// `GET /v1/health` on a battery-friendly schedule and exposes the coarse
/// [BackendHealthTier] for the drawer's health pill.
///
/// Strategy:
/// 1. The initial state is `null` (no data yet): the pill slot stays EMPTY
///    until the first probe answers, so the drawer never flashes a wrong
///    tier. The drawer child builds lazily (DrawerController only builds the
///    content when opened), so the first poll starts when the user first
///    opens the drawer — no background traffic before that.
/// 2. After a HEALTHY answer the next poll waits
///    [backendHealthPollInterval] (60 s). Degraded/unhealthy/offline
///    outcomes re-probe on the [backendHealthRetryBackoff] schedule.
/// 3. While the passive connectivity signal (issue #654) reports the device
///    offline, NO health probes run: the tier maps to offline directly and
///    any in-flight chain is canceled (generation counter). When
///    connectivity returns, a fresh poll starts immediately.
/// 4. A generation counter cancels pending chains: a new passive event or a
///    controller rebuild supersedes every in-flight continuation, so a
///    flapping link cannot trigger request storms.
final class BackendHealthControllerProvider
    extends $NotifierProvider<BackendHealthController, BackendHealthTier?> {
  /// Backend health controller (issue #657): polls the public
  /// `GET /v1/health` on a battery-friendly schedule and exposes the coarse
  /// [BackendHealthTier] for the drawer's health pill.
  ///
  /// Strategy:
  /// 1. The initial state is `null` (no data yet): the pill slot stays EMPTY
  ///    until the first probe answers, so the drawer never flashes a wrong
  ///    tier. The drawer child builds lazily (DrawerController only builds the
  ///    content when opened), so the first poll starts when the user first
  ///    opens the drawer — no background traffic before that.
  /// 2. After a HEALTHY answer the next poll waits
  ///    [backendHealthPollInterval] (60 s). Degraded/unhealthy/offline
  ///    outcomes re-probe on the [backendHealthRetryBackoff] schedule.
  /// 3. While the passive connectivity signal (issue #654) reports the device
  ///    offline, NO health probes run: the tier maps to offline directly and
  ///    any in-flight chain is canceled (generation counter). When
  ///    connectivity returns, a fresh poll starts immediately.
  /// 4. A generation counter cancels pending chains: a new passive event or a
  ///    controller rebuild supersedes every in-flight continuation, so a
  ///    flapping link cannot trigger request storms.
  BackendHealthControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backendHealthControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backendHealthControllerHash();

  @$internal
  @override
  BackendHealthController create() => BackendHealthController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BackendHealthTier? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BackendHealthTier?>(value),
    );
  }
}

String _$backendHealthControllerHash() =>
    r'548c0107c691a037f6e06ed5d847a9c0b34d5c23';

/// Backend health controller (issue #657): polls the public
/// `GET /v1/health` on a battery-friendly schedule and exposes the coarse
/// [BackendHealthTier] for the drawer's health pill.
///
/// Strategy:
/// 1. The initial state is `null` (no data yet): the pill slot stays EMPTY
///    until the first probe answers, so the drawer never flashes a wrong
///    tier. The drawer child builds lazily (DrawerController only builds the
///    content when opened), so the first poll starts when the user first
///    opens the drawer — no background traffic before that.
/// 2. After a HEALTHY answer the next poll waits
///    [backendHealthPollInterval] (60 s). Degraded/unhealthy/offline
///    outcomes re-probe on the [backendHealthRetryBackoff] schedule.
/// 3. While the passive connectivity signal (issue #654) reports the device
///    offline, NO health probes run: the tier maps to offline directly and
///    any in-flight chain is canceled (generation counter). When
///    connectivity returns, a fresh poll starts immediately.
/// 4. A generation counter cancels pending chains: a new passive event or a
///    controller rebuild supersedes every in-flight continuation, so a
///    flapping link cannot trigger request storms.

abstract class _$BackendHealthController extends $Notifier<BackendHealthTier?> {
  BackendHealthTier? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<BackendHealthTier?, BackendHealthTier?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BackendHealthTier?, BackendHealthTier?>,
              BackendHealthTier?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
