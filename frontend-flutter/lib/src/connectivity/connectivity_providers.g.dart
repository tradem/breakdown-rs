// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connectivity_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(passiveConnectivitySource)
final passiveConnectivitySourceProvider = PassiveConnectivitySourceProvider._();

final class PassiveConnectivitySourceProvider
    extends
        $FunctionalProvider<
          PassiveConnectivitySource,
          PassiveConnectivitySource,
          PassiveConnectivitySource
        >
    with $Provider<PassiveConnectivitySource> {
  PassiveConnectivitySourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'passiveConnectivitySourceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$passiveConnectivitySourceHash();

  @$internal
  @override
  $ProviderElement<PassiveConnectivitySource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PassiveConnectivitySource create(Ref ref) {
    return passiveConnectivitySource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PassiveConnectivitySource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PassiveConnectivitySource>(value),
    );
  }
}

String _$passiveConnectivitySourceHash() =>
    r'1d723815943d039e08f59e8093c5db52d17dad69';

@ProviderFor(connectivityHttpProbe)
final connectivityHttpProbeProvider = ConnectivityHttpProbeProvider._();

final class ConnectivityHttpProbeProvider
    extends
        $FunctionalProvider<
          ConnectivityHttpProbe,
          ConnectivityHttpProbe,
          ConnectivityHttpProbe
        >
    with $Provider<ConnectivityHttpProbe> {
  ConnectivityHttpProbeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectivityHttpProbeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectivityHttpProbeHash();

  @$internal
  @override
  $ProviderElement<ConnectivityHttpProbe> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ConnectivityHttpProbe create(Ref ref) {
    return connectivityHttpProbe(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConnectivityHttpProbe value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConnectivityHttpProbe>(value),
    );
  }
}

String _$connectivityHttpProbeHash() =>
    r'9d08cd3c1d06f6a8fe0c6f90094ab2a56fa1edff';

@ProviderFor(connectivityDelay)
final connectivityDelayProvider = ConnectivityDelayProvider._();

final class ConnectivityDelayProvider
    extends
        $FunctionalProvider<
          ConnectivityDelay,
          ConnectivityDelay,
          ConnectivityDelay
        >
    with $Provider<ConnectivityDelay> {
  ConnectivityDelayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectivityDelayProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectivityDelayHash();

  @$internal
  @override
  $ProviderElement<ConnectivityDelay> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ConnectivityDelay create(Ref ref) {
    return connectivityDelay(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConnectivityDelay value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConnectivityDelay>(value),
    );
  }
}

String _$connectivityDelayHash() => r'd856b32dd9fa6a5d6e33d382812481403dabe220';

/// Connectivity controller (issue #654): passive-first detection with a
/// conservative HTTP confirmation probe.
///
/// Strategy (battery requirement of issue #654):
/// 1. Passive OS signals (`PassiveConnectivitySource`) are the primary
///    source — no polling loop. `none` → [ConnectivityStatus.offline]
///    immediately.
/// 2. The FIRST carrier event of a session — and every reconnection from
///    offline/degraded — runs ONE lightweight HTTP probe to confirm the
///    route (captive portals report carriers too). Success →
///    [ConnectivityStatus.online]; failure → [ConnectivityStatus.degraded]
///    and re-probes run on the [connectivityProbeBackoff] schedule.
/// 3. While confirmed-healthy (`online` after a successful probe) the
///    controller NEVER probes — passive signals only.
/// 4. A generation counter cancels pending probe chains: a new passive
///    event (e.g. carrier lost again) supersedes any in-flight retry, so
///    a flapping link cannot trigger request storms.
///
/// The initial state is optimistic [ConnectivityStatus.online]: no pill
/// before evidence of offline (a cold-start offline device receives its
/// `none` event within the first passive callbacks). Plugin errors (which
/// occur in widget tests where the method channel is unimplemented) are
/// swallowed by the `onError` handler: without a signal the controller
/// stays `online` — it never invents an offline state it cannot back.

@ProviderFor(ConnectivityController)
final connectivityControllerProvider = ConnectivityControllerProvider._();

/// Connectivity controller (issue #654): passive-first detection with a
/// conservative HTTP confirmation probe.
///
/// Strategy (battery requirement of issue #654):
/// 1. Passive OS signals (`PassiveConnectivitySource`) are the primary
///    source — no polling loop. `none` → [ConnectivityStatus.offline]
///    immediately.
/// 2. The FIRST carrier event of a session — and every reconnection from
///    offline/degraded — runs ONE lightweight HTTP probe to confirm the
///    route (captive portals report carriers too). Success →
///    [ConnectivityStatus.online]; failure → [ConnectivityStatus.degraded]
///    and re-probes run on the [connectivityProbeBackoff] schedule.
/// 3. While confirmed-healthy (`online` after a successful probe) the
///    controller NEVER probes — passive signals only.
/// 4. A generation counter cancels pending probe chains: a new passive
///    event (e.g. carrier lost again) supersedes any in-flight retry, so
///    a flapping link cannot trigger request storms.
///
/// The initial state is optimistic [ConnectivityStatus.online]: no pill
/// before evidence of offline (a cold-start offline device receives its
/// `none` event within the first passive callbacks). Plugin errors (which
/// occur in widget tests where the method channel is unimplemented) are
/// swallowed by the `onError` handler: without a signal the controller
/// stays `online` — it never invents an offline state it cannot back.
final class ConnectivityControllerProvider
    extends $NotifierProvider<ConnectivityController, ConnectivityStatus> {
  /// Connectivity controller (issue #654): passive-first detection with a
  /// conservative HTTP confirmation probe.
  ///
  /// Strategy (battery requirement of issue #654):
  /// 1. Passive OS signals (`PassiveConnectivitySource`) are the primary
  ///    source — no polling loop. `none` → [ConnectivityStatus.offline]
  ///    immediately.
  /// 2. The FIRST carrier event of a session — and every reconnection from
  ///    offline/degraded — runs ONE lightweight HTTP probe to confirm the
  ///    route (captive portals report carriers too). Success →
  ///    [ConnectivityStatus.online]; failure → [ConnectivityStatus.degraded]
  ///    and re-probes run on the [connectivityProbeBackoff] schedule.
  /// 3. While confirmed-healthy (`online` after a successful probe) the
  ///    controller NEVER probes — passive signals only.
  /// 4. A generation counter cancels pending probe chains: a new passive
  ///    event (e.g. carrier lost again) supersedes any in-flight retry, so
  ///    a flapping link cannot trigger request storms.
  ///
  /// The initial state is optimistic [ConnectivityStatus.online]: no pill
  /// before evidence of offline (a cold-start offline device receives its
  /// `none` event within the first passive callbacks). Plugin errors (which
  /// occur in widget tests where the method channel is unimplemented) are
  /// swallowed by the `onError` handler: without a signal the controller
  /// stays `online` — it never invents an offline state it cannot back.
  ConnectivityControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectivityControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectivityControllerHash();

  @$internal
  @override
  ConnectivityController create() => ConnectivityController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConnectivityStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConnectivityStatus>(value),
    );
  }
}

String _$connectivityControllerHash() =>
    r'771963244b7efccf1d2c07036ecea412f9bac966';

/// Connectivity controller (issue #654): passive-first detection with a
/// conservative HTTP confirmation probe.
///
/// Strategy (battery requirement of issue #654):
/// 1. Passive OS signals (`PassiveConnectivitySource`) are the primary
///    source — no polling loop. `none` → [ConnectivityStatus.offline]
///    immediately.
/// 2. The FIRST carrier event of a session — and every reconnection from
///    offline/degraded — runs ONE lightweight HTTP probe to confirm the
///    route (captive portals report carriers too). Success →
///    [ConnectivityStatus.online]; failure → [ConnectivityStatus.degraded]
///    and re-probes run on the [connectivityProbeBackoff] schedule.
/// 3. While confirmed-healthy (`online` after a successful probe) the
///    controller NEVER probes — passive signals only.
/// 4. A generation counter cancels pending probe chains: a new passive
///    event (e.g. carrier lost again) supersedes any in-flight retry, so
///    a flapping link cannot trigger request storms.
///
/// The initial state is optimistic [ConnectivityStatus.online]: no pill
/// before evidence of offline (a cold-start offline device receives its
/// `none` event within the first passive callbacks). Plugin errors (which
/// occur in widget tests where the method channel is unimplemented) are
/// swallowed by the `onError` handler: without a signal the controller
/// stays `online` — it never invents an offline state it cannot back.

abstract class _$ConnectivityController extends $Notifier<ConnectivityStatus> {
  ConnectivityStatus build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ConnectivityStatus, ConnectivityStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ConnectivityStatus, ConnectivityStatus>,
              ConnectivityStatus,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
