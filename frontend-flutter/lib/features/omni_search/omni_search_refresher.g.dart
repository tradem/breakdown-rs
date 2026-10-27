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
/// episodes, per-episode scenes AND days plus characters and pieces.
/// The seams are the six aggregate REPOSITORIES (the layer beneath the
/// read screens' list-fetch providers — those are thin wrappers over
/// `repo.listBy…` with clock + fence): calling the repositories directly
/// keeps the refresh pass FREE of autoDispose provider-future lifecycle
/// races (CodeRabbit review — a bare `ref.read(provider.future)` holds no
/// listener, so Riverpod may dispose the provider mid-load and complete
/// its pending future with an error; plain repository futures carry no
/// such lifecycle). The cache-write discipline travels with the repos: the
/// same [CacheWriteFence] over the cache generation the fetch providers
/// build, so a base switch / sign-out reset mid-pass discards its writes.
///
/// The QUERY path never goes through here (spec: "No network call SHALL be
/// issued by the search itself"): typing and matching run purely over the
/// cache. The pass exists so a temporarily-behind cache catches up while
/// the user looks at the surface — failures are honest degradation, never
/// the surface's error state (that one is reserved for storage failures,
/// spec "Storage failure" scenario).
///
/// Lifecycle: the refresher is KEEP-ALIVE — a pass started for a season
/// survives a screen close and finishes its cache writes. Single-flight
/// futures are keyed BY SEASON: a pass for season A never satisfies a
/// `prefresh('B')` call, and same-season callers still join exactly one
/// pass. Every ref touch is `mounted`-guarded so a pass stops cleanly once
/// the container is gone — never as an unhandled rejection.

@ProviderFor(omniSearchSourceRefresher)
final omniSearchSourceRefresherProvider = OmniSearchSourceRefresherProvider._();

/// The bounded source-refresh for the OmniSearch surface (tasks §3.4, spec
/// `flutter-omni-search` "Cached-data honesty").
///
/// On surface open and on user retry the surface runs ONE bounded pass
/// through the ESTABLISHED read seams for the active season — blocks, their
/// episodes, per-episode scenes AND days plus characters and pieces.
/// The seams are the six aggregate REPOSITORIES (the layer beneath the
/// read screens' list-fetch providers — those are thin wrappers over
/// `repo.listBy…` with clock + fence): calling the repositories directly
/// keeps the refresh pass FREE of autoDispose provider-future lifecycle
/// races (CodeRabbit review — a bare `ref.read(provider.future)` holds no
/// listener, so Riverpod may dispose the provider mid-load and complete
/// its pending future with an error; plain repository futures carry no
/// such lifecycle). The cache-write discipline travels with the repos: the
/// same [CacheWriteFence] over the cache generation the fetch providers
/// build, so a base switch / sign-out reset mid-pass discards its writes.
///
/// The QUERY path never goes through here (spec: "No network call SHALL be
/// issued by the search itself"): typing and matching run purely over the
/// cache. The pass exists so a temporarily-behind cache catches up while
/// the user looks at the surface — failures are honest degradation, never
/// the surface's error state (that one is reserved for storage failures,
/// spec "Storage failure" scenario).
///
/// Lifecycle: the refresher is KEEP-ALIVE — a pass started for a season
/// survives a screen close and finishes its cache writes. Single-flight
/// futures are keyed BY SEASON: a pass for season A never satisfies a
/// `prefresh('B')` call, and same-season callers still join exactly one
/// pass. Every ref touch is `mounted`-guarded so a pass stops cleanly once
/// the container is gone — never as an unhandled rejection.

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
  /// episodes, per-episode scenes AND days plus characters and pieces.
  /// The seams are the six aggregate REPOSITORIES (the layer beneath the
  /// read screens' list-fetch providers — those are thin wrappers over
  /// `repo.listBy…` with clock + fence): calling the repositories directly
  /// keeps the refresh pass FREE of autoDispose provider-future lifecycle
  /// races (CodeRabbit review — a bare `ref.read(provider.future)` holds no
  /// listener, so Riverpod may dispose the provider mid-load and complete
  /// its pending future with an error; plain repository futures carry no
  /// such lifecycle). The cache-write discipline travels with the repos: the
  /// same [CacheWriteFence] over the cache generation the fetch providers
  /// build, so a base switch / sign-out reset mid-pass discards its writes.
  ///
  /// The QUERY path never goes through here (spec: "No network call SHALL be
  /// issued by the search itself"): typing and matching run purely over the
  /// cache. The pass exists so a temporarily-behind cache catches up while
  /// the user looks at the surface — failures are honest degradation, never
  /// the surface's error state (that one is reserved for storage failures,
  /// spec "Storage failure" scenario).
  ///
  /// Lifecycle: the refresher is KEEP-ALIVE — a pass started for a season
  /// survives a screen close and finishes its cache writes. Single-flight
  /// futures are keyed BY SEASON: a pass for season A never satisfies a
  /// `prefresh('B')` call, and same-season callers still join exactly one
  /// pass. Every ref touch is `mounted`-guarded so a pass stops cleanly once
  /// the container is gone — never as an unhandled rejection.
  OmniSearchSourceRefresherProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'omniSearchSourceRefresherProvider',
        isAutoDispose: false,
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
    r'83e84a1ebf2986fc6e72e6db9a04f75f635ba714';

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
