// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'capabilities.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Default seam: the real `GET /v1/me/capabilities` read.
///
/// `keepAlive` because this is a stable seam, not state: the same reasoning as
/// `backendHealthProbeProvider` (issue #657), and it keeps a widget test's
/// `overrideWithValue` in force across rebuilds.

@ProviderFor(myCapabilitiesFetch)
final myCapabilitiesFetchProvider = MyCapabilitiesFetchProvider._();

/// Default seam: the real `GET /v1/me/capabilities` read.
///
/// `keepAlive` because this is a stable seam, not state: the same reasoning as
/// `backendHealthProbeProvider` (issue #657), and it keeps a widget test's
/// `overrideWithValue` in force across rebuilds.

final class MyCapabilitiesFetchProvider
    extends
        $FunctionalProvider<
          MyCapabilitiesFetch,
          MyCapabilitiesFetch,
          MyCapabilitiesFetch
        >
    with $Provider<MyCapabilitiesFetch> {
  /// Default seam: the real `GET /v1/me/capabilities` read.
  ///
  /// `keepAlive` because this is a stable seam, not state: the same reasoning as
  /// `backendHealthProbeProvider` (issue #657), and it keeps a widget test's
  /// `overrideWithValue` in force across rebuilds.
  MyCapabilitiesFetchProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'myCapabilitiesFetchProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myCapabilitiesFetchHash();

  @$internal
  @override
  $ProviderElement<MyCapabilitiesFetch> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MyCapabilitiesFetch create(Ref ref) {
    return myCapabilitiesFetch(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MyCapabilitiesFetch value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MyCapabilitiesFetch>(value),
    );
  }
}

String _$myCapabilitiesFetchHash() =>
    r'4815610b02f16240f5376454eafe8161b033ce8f';

/// The caller's global capabilities — a ONE-SHOT probe, no polling.
///
/// * `AsyncData(true)`  → the credential gate is open;
/// * `AsyncData(false)` → a RESOLVED denial (the entry says "Keine
///   Berechtigung" and the AI-config discovery dispatch is suppressed);
/// * `AsyncLoading` / `AsyncError` → UNKNOWN. Never rendered as a denial: a
///   failed read must not put a permission problem in front of a user whose
///   role is intact, and the server stays authoritative on every gated call.
///
/// AutoDispose by design (same lifetime as #809's reachability probe): the
/// Settings tile keeps watching it while the configuration screen is pushed,
/// and a new Settings visit measures again.

@ProviderFor(myCapabilities)
final myCapabilitiesProvider = MyCapabilitiesProvider._();

/// The caller's global capabilities — a ONE-SHOT probe, no polling.
///
/// * `AsyncData(true)`  → the credential gate is open;
/// * `AsyncData(false)` → a RESOLVED denial (the entry says "Keine
///   Berechtigung" and the AI-config discovery dispatch is suppressed);
/// * `AsyncLoading` / `AsyncError` → UNKNOWN. Never rendered as a denial: a
///   failed read must not put a permission problem in front of a user whose
///   role is intact, and the server stays authoritative on every gated call.
///
/// AutoDispose by design (same lifetime as #809's reachability probe): the
/// Settings tile keeps watching it while the configuration screen is pushed,
/// and a new Settings visit measures again.

final class MyCapabilitiesProvider
    extends
        $FunctionalProvider<
          AsyncValue<MyCapabilities>,
          MyCapabilities,
          FutureOr<MyCapabilities>
        >
    with $FutureModifier<MyCapabilities>, $FutureProvider<MyCapabilities> {
  /// The caller's global capabilities — a ONE-SHOT probe, no polling.
  ///
  /// * `AsyncData(true)`  → the credential gate is open;
  /// * `AsyncData(false)` → a RESOLVED denial (the entry says "Keine
  ///   Berechtigung" and the AI-config discovery dispatch is suppressed);
  /// * `AsyncLoading` / `AsyncError` → UNKNOWN. Never rendered as a denial: a
  ///   failed read must not put a permission problem in front of a user whose
  ///   role is intact, and the server stays authoritative on every gated call.
  ///
  /// AutoDispose by design (same lifetime as #809's reachability probe): the
  /// Settings tile keeps watching it while the configuration screen is pushed,
  /// and a new Settings visit measures again.
  MyCapabilitiesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'myCapabilitiesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myCapabilitiesHash();

  @$internal
  @override
  $FutureProviderElement<MyCapabilities> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MyCapabilities> create(Ref ref) {
    return myCapabilities(ref);
  }
}

String _$myCapabilitiesHash() => r'2ebd5995ec8b825f6e92cb4a38b3d019c376962d';
