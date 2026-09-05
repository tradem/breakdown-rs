// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seasons_cache_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Injectable clock for deterministic cache/TTL tests (D2).

@ProviderFor(clock)
final clockProvider = ClockProvider._();

/// Injectable clock for deterministic cache/TTL tests (D2).

final class ClockProvider extends $FunctionalProvider<Clock, Clock, Clock>
    with $Provider<Clock> {
  /// Injectable clock for deterministic cache/TTL tests (D2).
  ClockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clockProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clockHash();

  @$internal
  @override
  $ProviderElement<Clock> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Clock create(Ref ref) {
    return clock(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Clock value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Clock>(value),
    );
  }
}

String _$clockHash() => r'4dd5d715e870200c4891084601c954bf4bc8b51a';

/// Generated API client over the rebuildable pinned Dio (task 6.3 —
/// follows runtime base-URL switches; same pinned `SecurityContext`).

@ProviderFor(apiClient)
final apiClientProvider = ApiClientProvider._();

/// Generated API client over the rebuildable pinned Dio (task 6.3 —
/// follows runtime base-URL switches; same pinned `SecurityContext`).

final class ApiClientProvider
    extends $FunctionalProvider<BreakdownApi, BreakdownApi, BreakdownApi>
    with $Provider<BreakdownApi> {
  /// Generated API client over the rebuildable pinned Dio (task 6.3 —
  /// follows runtime base-URL switches; same pinned `SecurityContext`).
  ApiClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'apiClientProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$apiClientHash();

  @$internal
  @override
  $ProviderElement<BreakdownApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BreakdownApi create(Ref ref) {
    return apiClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BreakdownApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BreakdownApi>(value),
    );
  }
}

String _$apiClientHash() => r'015c019bab23df442be6b0161b331fcba9a7ebf0';

/// The read-projection cache database.
///
/// Defaults to an in-memory database so the cache layer is self-contained and
/// testable. Production wiring MUST override this with a file-backed executor
/// (deferred to `first-screen-seasons`, which owns the persistence path).

@ProviderFor(cacheDatabase)
final cacheDatabaseProvider = CacheDatabaseProvider._();

/// The read-projection cache database.
///
/// Defaults to an in-memory database so the cache layer is self-contained and
/// testable. Production wiring MUST override this with a file-backed executor
/// (deferred to `first-screen-seasons`, which owns the persistence path).

final class CacheDatabaseProvider
    extends $FunctionalProvider<CacheDatabase, CacheDatabase, CacheDatabase>
    with $Provider<CacheDatabase> {
  /// The read-projection cache database.
  ///
  /// Defaults to an in-memory database so the cache layer is self-contained and
  /// testable. Production wiring MUST override this with a file-backed executor
  /// (deferred to `first-screen-seasons`, which owns the persistence path).
  CacheDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cacheDatabaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cacheDatabaseHash();

  @$internal
  @override
  $ProviderElement<CacheDatabase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CacheDatabase create(Ref ref) {
    return cacheDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CacheDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CacheDatabase>(value),
    );
  }
}

String _$cacheDatabaseHash() => r'39c427657e261f4ea42d80a7a83744e22f2e88e0';

/// Season repository: owns network + Drift cache writes (D1).

@ProviderFor(seasonRepository)
final seasonRepositoryProvider = SeasonRepositoryProvider._();

/// Season repository: owns network + Drift cache writes (D1).

final class SeasonRepositoryProvider
    extends
        $FunctionalProvider<
          SeasonRepository,
          SeasonRepository,
          SeasonRepository
        >
    with $Provider<SeasonRepository> {
  /// Season repository: owns network + Drift cache writes (D1).
  SeasonRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'seasonRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$seasonRepositoryHash();

  @$internal
  @override
  $ProviderElement<SeasonRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SeasonRepository create(Ref ref) {
    return seasonRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SeasonRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SeasonRepository>(value),
    );
  }
}

String _$seasonRepositoryHash() => r'07c267b177eeccbb0d406f6af4f8d763d32bb362';

/// The injected list-fetch seam (Design Decision D3).
///
/// The generated client has no seasons list endpoint yet (tracked separately),
/// so the default surfaces a `not_implemented` error; production wiring
/// replaces the body with `repo.fetchAndCacheList(() => repo.fetchSeasonsList())`
/// once `GET /v1/seasons` lands. Tests override this provider with a fake that
/// writes the cache via `repo.fetchAndCacheList(...)`.

@ProviderFor(seasonsListFetch)
final seasonsListFetchProvider = SeasonsListFetchProvider._();

/// The injected list-fetch seam (Design Decision D3).
///
/// The generated client has no seasons list endpoint yet (tracked separately),
/// so the default surfaces a `not_implemented` error; production wiring
/// replaces the body with `repo.fetchAndCacheList(() => repo.fetchSeasonsList())`
/// once `GET /v1/seasons` lands. Tests override this provider with a fake that
/// writes the cache via `repo.fetchAndCacheList(...)`.

final class SeasonsListFetchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<List<SeasonView>>>,
          Result<List<SeasonView>>,
          FutureOr<Result<List<SeasonView>>>
        >
    with
        $FutureModifier<Result<List<SeasonView>>>,
        $FutureProvider<Result<List<SeasonView>>> {
  /// The injected list-fetch seam (Design Decision D3).
  ///
  /// The generated client has no seasons list endpoint yet (tracked separately),
  /// so the default surfaces a `not_implemented` error; production wiring
  /// replaces the body with `repo.fetchAndCacheList(() => repo.fetchSeasonsList())`
  /// once `GET /v1/seasons` lands. Tests override this provider with a fake that
  /// writes the cache via `repo.fetchAndCacheList(...)`.
  SeasonsListFetchProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'seasonsListFetchProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$seasonsListFetchHash();

  @$internal
  @override
  $FutureProviderElement<Result<List<SeasonView>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<List<SeasonView>>> create(Ref ref) {
    return seasonsListFetch(ref);
  }
}

String _$seasonsListFetchHash() => r'f3fd1c3dfda29cb0092af5ef2e415cfbe915f553';

/// Read-projection controller (Design Decisions D1–D4).
///
/// It maps the injected [seasonsListFetchProvider] `Result` into an
/// `AsyncValue<SeasonsView>`: on success it emits fresh rows; on fetch `Err`
/// it emits `AsyncError` (never silently discarded — Task 3.3) while the
/// derived `seasonsView` selector serves the retained snapshot. Reading the
/// cache FIRST (seeding `seasonsPrevRowsProvider`) makes offline cold start
/// render cached rows. The controller is a sync `Notifier` (not an
/// `AsyncNotifier`) so a fetch `Err` surfaces as `AsyncError` rather than
/// triggering Riverpod's async-notifier retry loop.

@ProviderFor(SeasonsViewController)
final seasonsViewControllerProvider = SeasonsViewControllerProvider._();

/// Read-projection controller (Design Decisions D1–D4).
///
/// It maps the injected [seasonsListFetchProvider] `Result` into an
/// `AsyncValue<SeasonsView>`: on success it emits fresh rows; on fetch `Err`
/// it emits `AsyncError` (never silently discarded — Task 3.3) while the
/// derived `seasonsView` selector serves the retained snapshot. Reading the
/// cache FIRST (seeding `seasonsPrevRowsProvider`) makes offline cold start
/// render cached rows. The controller is a sync `Notifier` (not an
/// `AsyncNotifier`) so a fetch `Err` surfaces as `AsyncError` rather than
/// triggering Riverpod's async-notifier retry loop.
final class SeasonsViewControllerProvider
    extends $NotifierProvider<SeasonsViewController, AsyncValue<SeasonsView>> {
  /// Read-projection controller (Design Decisions D1–D4).
  ///
  /// It maps the injected [seasonsListFetchProvider] `Result` into an
  /// `AsyncValue<SeasonsView>`: on success it emits fresh rows; on fetch `Err`
  /// it emits `AsyncError` (never silently discarded — Task 3.3) while the
  /// derived `seasonsView` selector serves the retained snapshot. Reading the
  /// cache FIRST (seeding `seasonsPrevRowsProvider`) makes offline cold start
  /// render cached rows. The controller is a sync `Notifier` (not an
  /// `AsyncNotifier`) so a fetch `Err` surfaces as `AsyncError` rather than
  /// triggering Riverpod's async-notifier retry loop.
  SeasonsViewControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'seasonsViewControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$seasonsViewControllerHash();

  @$internal
  @override
  SeasonsViewController create() => SeasonsViewController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<SeasonsView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<SeasonsView>>(value),
    );
  }
}

String _$seasonsViewControllerHash() =>
    r'42ae3fe3666c780bba17ce97db061e04f550a916';

/// Read-projection controller (Design Decisions D1–D4).
///
/// It maps the injected [seasonsListFetchProvider] `Result` into an
/// `AsyncValue<SeasonsView>`: on success it emits fresh rows; on fetch `Err`
/// it emits `AsyncError` (never silently discarded — Task 3.3) while the
/// derived `seasonsView` selector serves the retained snapshot. Reading the
/// cache FIRST (seeding `seasonsPrevRowsProvider`) makes offline cold start
/// render cached rows. The controller is a sync `Notifier` (not an
/// `AsyncNotifier`) so a fetch `Err` surfaces as `AsyncError` rather than
/// triggering Riverpod's async-notifier retry loop.

abstract class _$SeasonsViewController
    extends $Notifier<AsyncValue<SeasonsView>> {
  AsyncValue<SeasonsView> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<SeasonsView>, AsyncValue<SeasonsView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<SeasonsView>, AsyncValue<SeasonsView>>,
              AsyncValue<SeasonsView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// TTL-based cache staleness for the seasons projection (issue #366).
///
/// Backed by [SeasonRepository.isCacheStale] (client-only `cachedAt` + the
/// injectable [clockProvider]); a staleness-check failure resolves to
/// `false` (fail-closed: no banner when staleness itself is unknown — the
/// error path still banners a failed refetch serving retained rows).

@ProviderFor(seasonsCacheStale)
final seasonsCacheStaleProvider = SeasonsCacheStaleProvider._();

/// TTL-based cache staleness for the seasons projection (issue #366).
///
/// Backed by [SeasonRepository.isCacheStale] (client-only `cachedAt` + the
/// injectable [clockProvider]); a staleness-check failure resolves to
/// `false` (fail-closed: no banner when staleness itself is unknown — the
/// error path still banners a failed refetch serving retained rows).

final class SeasonsCacheStaleProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// TTL-based cache staleness for the seasons projection (issue #366).
  ///
  /// Backed by [SeasonRepository.isCacheStale] (client-only `cachedAt` + the
  /// injectable [clockProvider]); a staleness-check failure resolves to
  /// `false` (fail-closed: no banner when staleness itself is unknown — the
  /// error path still banners a failed refetch serving retained rows).
  SeasonsCacheStaleProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'seasonsCacheStaleProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$seasonsCacheStaleHash();

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    return seasonsCacheStale(ref);
  }
}

String _$seasonsCacheStaleHash() => r'54e042c33fe8fc3b44989886979db51a88364a34';
