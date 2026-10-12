// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'omni_search_refresher.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The bounded source-refresh for the OmniSearch surface (tasks §3.4, spec
/// `flutter-omni-search` "Cached-data honesty").
///
/// On surface open and on user retry the surface runs ONE bounded pass
/// through the ESTABLISHED read seams for the active season — blocks, their
/// episodes, per-episode scenes AND days plus characters and costumes —
/// each via the same providers the read screens consume (which own the
/// Drift cache-write discipline, fence included). After the pass the search
/// inputs provider is invalidated so the surface re-reads the cache.
///
/// The QUERY path never goes through here (spec: "No network call SHALL be
/// issued by the search itself"): typing and matching run purely over the
/// cache. The pass exists so a temporarily-behind cache catches up while
/// the user looks at the surface — failures are honest degradation, never
/// the surface's error state (that one is reserved for storage failures,
/// spec "Storage failure" scenario).
///
/// Single-flight: a concurrent retry joins the in-flight pass (the same
/// rule the ReconciliationCoordinator applies to the read screens).

@ProviderFor(omniSearchSourceRefresher)
final omniSearchSourceRefresherProvider = OmniSearchSourceRefresherProvider._();

/// The bounded source-refresh for the OmniSearch surface (tasks §3.4, spec
/// `flutter-omni-search` "Cached-data honesty").
///
/// On surface open and on user retry the surface runs ONE bounded pass
/// through the ESTABLISHED read seams for the active season — blocks, their
/// episodes, per-episode scenes AND days plus characters and costumes —
/// each via the same providers the read screens consume (which own the
/// Drift cache-write discipline, fence included). After the pass the search
/// inputs provider is invalidated so the surface re-reads the cache.
///
/// The QUERY path never goes through here (spec: "No network call SHALL be
/// issued by the search itself"): typing and matching run purely over the
/// cache. The pass exists so a temporarily-behind cache catches up while
/// the user looks at the surface — failures are honest degradation, never
/// the surface's error state (that one is reserved for storage failures,
/// spec "Storage failure" scenario).
///
/// Single-flight: a concurrent retry joins the in-flight pass (the same
/// rule the ReconciliationCoordinator applies to the read screens).

final class OmniSearchSourceRefresherProvider
    extends
        $FunctionalProvider<
          OmniSearchSourceRefresher,
          OmniSearchSourceRefresher,
          OmniSearchSourceRefresher
        >
    with $Provider<OmniSearchSourceRefresher> {
  /// The bounded source-refresh for the OmniSearch surface (tasks §3.4, spec
  /// `flutter-omni-search` "Cached-data honesty").
  ///
  /// On surface open and on user retry the surface runs ONE bounded pass
  /// through the ESTABLISHED read seams for the active season — blocks, their
  /// episodes, per-episode scenes AND days plus characters and costumes —
  /// each via the same providers the read screens consume (which own the
  /// Drift cache-write discipline, fence included). After the pass the search
  /// inputs provider is invalidated so the surface re-reads the cache.
  ///
  /// The QUERY path never goes through here (spec: "No network call SHALL be
  /// issued by the search itself"): typing and matching run purely over the
  /// cache. The pass exists so a temporarily-behind cache catches up while
  /// the user looks at the surface — failures are honest degradation, never
  /// the surface's error state (that one is reserved for storage failures,
  /// spec "Storage failure" scenario).
  ///
  /// Single-flight: a concurrent retry joins the in-flight pass (the same
  /// rule the ReconciliationCoordinator applies to the read screens).
  OmniSearchSourceRefresherProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'omniSearchSourceRefresherProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$omniSearchSourceRefresherHash();

  @$internal
  @override
  $ProviderElement<OmniSearchSourceRefresher> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  OmniSearchSourceRefresher create(Ref ref) {
    return omniSearchSourceRefresher(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OmniSearchSourceRefresher value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OmniSearchSourceRefresher>(value),
    );
  }
}

String _$omniSearchSourceRefresherHash() =>
    r'dca3dfa42671ca2880aea03090dfbb6206e271fd';

/// Which facets have delivered a source snapshot (empty-but-successful
/// counts — the server answered, so a future zero-match is zero-match and
/// not the "not yet loaded" note). The refresher writes; the surface reads.

@ProviderFor(OmniSearchFacetLoads)
final omniSearchFacetLoadsProvider = OmniSearchFacetLoadsFamily._();

/// Which facets have delivered a source snapshot (empty-but-successful
/// counts — the server answered, so a future zero-match is zero-match and
/// not the "not yet loaded" note). The refresher writes; the surface reads.
final class OmniSearchFacetLoadsProvider
    extends $NotifierProvider<OmniSearchFacetLoads, Set<OmniSearchFacet>> {
  /// Which facets have delivered a source snapshot (empty-but-successful
  /// counts — the server answered, so a future zero-match is zero-match and
  /// not the "not yet loaded" note). The refresher writes; the surface reads.
  OmniSearchFacetLoadsProvider._({
    required OmniSearchFacetLoadsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'omniSearchFacetLoadsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$omniSearchFacetLoadsHash();

  @override
  String toString() {
    return r'omniSearchFacetLoadsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  OmniSearchFacetLoads create() => OmniSearchFacetLoads();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<OmniSearchFacet> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<OmniSearchFacet>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is OmniSearchFacetLoadsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$omniSearchFacetLoadsHash() =>
    r'94f437ac66e84b186945d23818ab7eb82abbf3d2';

/// Which facets have delivered a source snapshot (empty-but-successful
/// counts — the server answered, so a future zero-match is zero-match and
/// not the "not yet loaded" note). The refresher writes; the surface reads.

final class OmniSearchFacetLoadsFamily extends $Family
    with
        $ClassFamilyOverride<
          OmniSearchFacetLoads,
          Set<OmniSearchFacet>,
          Set<OmniSearchFacet>,
          Set<OmniSearchFacet>,
          String
        > {
  OmniSearchFacetLoadsFamily._()
    : super(
        retry: null,
        name: r'omniSearchFacetLoadsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Which facets have delivered a source snapshot (empty-but-successful
  /// counts — the server answered, so a future zero-match is zero-match and
  /// not the "not yet loaded" note). The refresher writes; the surface reads.

  OmniSearchFacetLoadsProvider call(String seasonId) =>
      OmniSearchFacetLoadsProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'omniSearchFacetLoadsProvider';
}

/// Which facets have delivered a source snapshot (empty-but-successful
/// counts — the server answered, so a future zero-match is zero-match and
/// not the "not yet loaded" note). The refresher writes; the surface reads.

abstract class _$OmniSearchFacetLoads extends $Notifier<Set<OmniSearchFacet>> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  Set<OmniSearchFacet> build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Set<OmniSearchFacet>, Set<OmniSearchFacet>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<OmniSearchFacet>, Set<OmniSearchFacet>>,
              Set<OmniSearchFacet>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
