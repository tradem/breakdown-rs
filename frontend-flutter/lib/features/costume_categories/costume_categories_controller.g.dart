// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'costume_categories_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Costume-category repository: owns network + Drift cache writes.

@ProviderFor(costumeCategoryRepository)
final costumeCategoryRepositoryProvider = CostumeCategoryRepositoryProvider._();

/// Costume-category repository: owns network + Drift cache writes.

final class CostumeCategoryRepositoryProvider
    extends
        $FunctionalProvider<
          CostumeCategoryRepository,
          CostumeCategoryRepository,
          CostumeCategoryRepository
        >
    with $Provider<CostumeCategoryRepository> {
  /// Costume-category repository: owns network + Drift cache writes.
  CostumeCategoryRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'costumeCategoryRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$costumeCategoryRepositoryHash();

  @$internal
  @override
  $ProviderElement<CostumeCategoryRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CostumeCategoryRepository create(Ref ref) {
    return costumeCategoryRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CostumeCategoryRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CostumeCategoryRepository>(value),
    );
  }
}

String _$costumeCategoryRepositoryHash() =>
    r'6350515a858ce1be96fb1e222947891a1b04513d';

/// The injected season-scoped list-fetch seam
/// (`GET /v1/seasons/{season_id}/costume-categories`, server
/// `ORDER BY order_key ASC`). Tests override this provider with a fake.

@ProviderFor(costumeCategoriesListFetch)
final costumeCategoriesListFetchProvider = CostumeCategoriesListFetchFamily._();

/// The injected season-scoped list-fetch seam
/// (`GET /v1/seasons/{season_id}/costume-categories`, server
/// `ORDER BY order_key ASC`). Tests override this provider with a fake.

final class CostumeCategoriesListFetchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<List<CostumeCategoryView>>>,
          Result<List<CostumeCategoryView>>,
          FutureOr<Result<List<CostumeCategoryView>>>
        >
    with
        $FutureModifier<Result<List<CostumeCategoryView>>>,
        $FutureProvider<Result<List<CostumeCategoryView>>> {
  /// The injected season-scoped list-fetch seam
  /// (`GET /v1/seasons/{season_id}/costume-categories`, server
  /// `ORDER BY order_key ASC`). Tests override this provider with a fake.
  CostumeCategoriesListFetchProvider._({
    required CostumeCategoriesListFetchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'costumeCategoriesListFetchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$costumeCategoriesListFetchHash();

  @override
  String toString() {
    return r'costumeCategoriesListFetchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<List<CostumeCategoryView>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<List<CostumeCategoryView>>> create(Ref ref) {
    final argument = this.argument as String;
    return costumeCategoriesListFetch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CostumeCategoriesListFetchProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$costumeCategoriesListFetchHash() =>
    r'1a4d0cd0c4451cf0af9f66a9009dde1c7a01038a';

/// The injected season-scoped list-fetch seam
/// (`GET /v1/seasons/{season_id}/costume-categories`, server
/// `ORDER BY order_key ASC`). Tests override this provider with a fake.

final class CostumeCategoriesListFetchFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Result<List<CostumeCategoryView>>>,
          String
        > {
  CostumeCategoriesListFetchFamily._()
    : super(
        retry: null,
        name: r'costumeCategoriesListFetchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The injected season-scoped list-fetch seam
  /// (`GET /v1/seasons/{season_id}/costume-categories`, server
  /// `ORDER BY order_key ASC`). Tests override this provider with a fake.

  CostumeCategoriesListFetchProvider call(String seasonId) =>
      CostumeCategoriesListFetchProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'costumeCategoriesListFetchProvider';
}

/// Retained last-good snapshot per season (complete projection — archived
/// rows included, so order-key derivation never depends on the render
/// toggle).

@ProviderFor(CostumeCategoriesPrevRows)
final costumeCategoriesPrevRowsProvider = CostumeCategoriesPrevRowsFamily._();

/// Retained last-good snapshot per season (complete projection — archived
/// rows included, so order-key derivation never depends on the render
/// toggle).
final class CostumeCategoriesPrevRowsProvider
    extends
        $NotifierProvider<
          CostumeCategoriesPrevRows,
          List<CostumeCategoryView>
        > {
  /// Retained last-good snapshot per season (complete projection — archived
  /// rows included, so order-key derivation never depends on the render
  /// toggle).
  CostumeCategoriesPrevRowsProvider._({
    required CostumeCategoriesPrevRowsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'costumeCategoriesPrevRowsProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$costumeCategoriesPrevRowsHash();

  @override
  String toString() {
    return r'costumeCategoriesPrevRowsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CostumeCategoriesPrevRows create() => CostumeCategoriesPrevRows();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<CostumeCategoryView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<CostumeCategoryView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CostumeCategoriesPrevRowsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$costumeCategoriesPrevRowsHash() =>
    r'31d61eb5380a0c9a458f3c440e246bedf856a27d';

/// Retained last-good snapshot per season (complete projection — archived
/// rows included, so order-key derivation never depends on the render
/// toggle).

final class CostumeCategoriesPrevRowsFamily extends $Family
    with
        $ClassFamilyOverride<
          CostumeCategoriesPrevRows,
          List<CostumeCategoryView>,
          List<CostumeCategoryView>,
          List<CostumeCategoryView>,
          String
        > {
  CostumeCategoriesPrevRowsFamily._()
    : super(
        retry: null,
        name: r'costumeCategoriesPrevRowsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Retained last-good snapshot per season (complete projection — archived
  /// rows included, so order-key derivation never depends on the render
  /// toggle).

  CostumeCategoriesPrevRowsProvider call(String seasonId) =>
      CostumeCategoriesPrevRowsProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'costumeCategoriesPrevRowsProvider';
}

/// Retained last-good snapshot per season (complete projection — archived
/// rows included, so order-key derivation never depends on the render
/// toggle).

abstract class _$CostumeCategoriesPrevRows
    extends $Notifier<List<CostumeCategoryView>> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  List<CostumeCategoryView> build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<List<CostumeCategoryView>, List<CostumeCategoryView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<CostumeCategoryView>, List<CostumeCategoryView>>,
              List<CostumeCategoryView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Read-projection controller.
///
/// Maps the injected fetch `Result` into an
/// `AsyncValue<CostumeCategoriesView>` and seeds the retained snapshot from
/// the cache FIRST (offline cold start).
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [CostumeCategoriesPrevRows]. Consumers read
/// through [costumeCategoriesViewProvider].

@ProviderFor(CostumeCategoriesViewController)
final costumeCategoriesViewControllerProvider =
    CostumeCategoriesViewControllerFamily._();

/// Read-projection controller.
///
/// Maps the injected fetch `Result` into an
/// `AsyncValue<CostumeCategoriesView>` and seeds the retained snapshot from
/// the cache FIRST (offline cold start).
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [CostumeCategoriesPrevRows]. Consumers read
/// through [costumeCategoriesViewProvider].
final class CostumeCategoriesViewControllerProvider
    extends
        $NotifierProvider<
          CostumeCategoriesViewController,
          AsyncValue<CostumeCategoriesView>
        > {
  /// Read-projection controller.
  ///
  /// Maps the injected fetch `Result` into an
  /// `AsyncValue<CostumeCategoriesView>` and seeds the retained snapshot from
  /// the cache FIRST (offline cold start).
  ///
  /// Loop discipline (reference pattern): this seeder watches the repository
  /// and the fetch ONLY — never [CostumeCategoriesPrevRows]. Consumers read
  /// through [costumeCategoriesViewProvider].
  CostumeCategoriesViewControllerProvider._({
    required CostumeCategoriesViewControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'costumeCategoriesViewControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$costumeCategoriesViewControllerHash();

  @override
  String toString() {
    return r'costumeCategoriesViewControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CostumeCategoriesViewController create() => CostumeCategoriesViewController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<CostumeCategoriesView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<CostumeCategoriesView>>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CostumeCategoriesViewControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$costumeCategoriesViewControllerHash() =>
    r'03359de5fc991683a55a7b9ab722ce9909db561b';

/// Read-projection controller.
///
/// Maps the injected fetch `Result` into an
/// `AsyncValue<CostumeCategoriesView>` and seeds the retained snapshot from
/// the cache FIRST (offline cold start).
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [CostumeCategoriesPrevRows]. Consumers read
/// through [costumeCategoriesViewProvider].

final class CostumeCategoriesViewControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          CostumeCategoriesViewController,
          AsyncValue<CostumeCategoriesView>,
          AsyncValue<CostumeCategoriesView>,
          AsyncValue<CostumeCategoriesView>,
          String
        > {
  CostumeCategoriesViewControllerFamily._()
    : super(
        retry: null,
        name: r'costumeCategoriesViewControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Read-projection controller.
  ///
  /// Maps the injected fetch `Result` into an
  /// `AsyncValue<CostumeCategoriesView>` and seeds the retained snapshot from
  /// the cache FIRST (offline cold start).
  ///
  /// Loop discipline (reference pattern): this seeder watches the repository
  /// and the fetch ONLY — never [CostumeCategoriesPrevRows]. Consumers read
  /// through [costumeCategoriesViewProvider].

  CostumeCategoriesViewControllerProvider call(String seasonId) =>
      CostumeCategoriesViewControllerProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'costumeCategoriesViewControllerProvider';
}

/// Read-projection controller.
///
/// Maps the injected fetch `Result` into an
/// `AsyncValue<CostumeCategoriesView>` and seeds the retained snapshot from
/// the cache FIRST (offline cold start).
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [CostumeCategoriesPrevRows]. Consumers read
/// through [costumeCategoriesViewProvider].

abstract class _$CostumeCategoriesViewController
    extends $Notifier<AsyncValue<CostumeCategoriesView>> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  AsyncValue<CostumeCategoriesView> build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<CostumeCategoriesView>,
              AsyncValue<CostumeCategoriesView>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<CostumeCategoriesView>,
                AsyncValue<CostumeCategoriesView>
              >,
              AsyncValue<CostumeCategoriesView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// TTL-based cache staleness for one season's categories (issue #366).
///
/// Backed by [CostumeCategoryRepository.isCacheStale] (client-only
/// `cachedAt` + the injectable [clockProvider]); a check failure resolves
/// to `false` (fail-closed — the error path still banners a failed
/// refetch).

@ProviderFor(costumeCategoriesCacheStale)
final costumeCategoriesCacheStaleProvider =
    CostumeCategoriesCacheStaleFamily._();

/// TTL-based cache staleness for one season's categories (issue #366).
///
/// Backed by [CostumeCategoryRepository.isCacheStale] (client-only
/// `cachedAt` + the injectable [clockProvider]); a check failure resolves
/// to `false` (fail-closed — the error path still banners a failed
/// refetch).

final class CostumeCategoriesCacheStaleProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// TTL-based cache staleness for one season's categories (issue #366).
  ///
  /// Backed by [CostumeCategoryRepository.isCacheStale] (client-only
  /// `cachedAt` + the injectable [clockProvider]); a check failure resolves
  /// to `false` (fail-closed — the error path still banners a failed
  /// refetch).
  CostumeCategoriesCacheStaleProvider._({
    required CostumeCategoriesCacheStaleFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'costumeCategoriesCacheStaleProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$costumeCategoriesCacheStaleHash();

  @override
  String toString() {
    return r'costumeCategoriesCacheStaleProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    final argument = this.argument as String;
    return costumeCategoriesCacheStale(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CostumeCategoriesCacheStaleProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$costumeCategoriesCacheStaleHash() =>
    r'5cd9f0f11a6508d089c6b3d8cb175b478419822b';

/// TTL-based cache staleness for one season's categories (issue #366).
///
/// Backed by [CostumeCategoryRepository.isCacheStale] (client-only
/// `cachedAt` + the injectable [clockProvider]); a check failure resolves
/// to `false` (fail-closed — the error path still banners a failed
/// refetch).

final class CostumeCategoriesCacheStaleFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, String> {
  CostumeCategoriesCacheStaleFamily._()
    : super(
        retry: null,
        name: r'costumeCategoriesCacheStaleProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// TTL-based cache staleness for one season's categories (issue #366).
  ///
  /// Backed by [CostumeCategoryRepository.isCacheStale] (client-only
  /// `cachedAt` + the injectable [clockProvider]); a check failure resolves
  /// to `false` (fail-closed — the error path still banners a failed
  /// refetch).

  CostumeCategoriesCacheStaleProvider call(String seasonId) =>
      CostumeCategoriesCacheStaleProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'costumeCategoriesCacheStaleProvider';
}

/// The projection a screen reads (selector).

@ProviderFor(costumeCategoriesView)
final costumeCategoriesViewProvider = CostumeCategoriesViewFamily._();

/// The projection a screen reads (selector).

final class CostumeCategoriesViewProvider
    extends
        $FunctionalProvider<
          CostumeCategoriesView,
          CostumeCategoriesView,
          CostumeCategoriesView
        >
    with $Provider<CostumeCategoriesView> {
  /// The projection a screen reads (selector).
  CostumeCategoriesViewProvider._({
    required CostumeCategoriesViewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'costumeCategoriesViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$costumeCategoriesViewHash();

  @override
  String toString() {
    return r'costumeCategoriesViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<CostumeCategoriesView> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CostumeCategoriesView create(Ref ref) {
    final argument = this.argument as String;
    return costumeCategoriesView(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CostumeCategoriesView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CostumeCategoriesView>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CostumeCategoriesViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$costumeCategoriesViewHash() =>
    r'6a8925e2e44ade86e0a03e38d6fdc7a7fa5fad2c';

/// The projection a screen reads (selector).

final class CostumeCategoriesViewFamily extends $Family
    with $FunctionalFamilyOverride<CostumeCategoriesView, String> {
  CostumeCategoriesViewFamily._()
    : super(
        retry: null,
        name: r'costumeCategoriesViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The projection a screen reads (selector).

  CostumeCategoriesViewProvider call(String seasonId) =>
      CostumeCategoriesViewProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'costumeCategoriesViewProvider';
}

/// Ephemeral optimistic overlay store per season (controller state, NOT
/// Drift — no global overlay store).

@ProviderFor(CostumeCategoriesOverlays)
final costumeCategoriesOverlaysProvider = CostumeCategoriesOverlaysFamily._();

/// Ephemeral optimistic overlay store per season (controller state, NOT
/// Drift — no global overlay store).
final class CostumeCategoriesOverlaysProvider
    extends
        $NotifierProvider<
          CostumeCategoriesOverlays,
          List<CostumeCategoryOverlay>
        > {
  /// Ephemeral optimistic overlay store per season (controller state, NOT
  /// Drift — no global overlay store).
  CostumeCategoriesOverlaysProvider._({
    required CostumeCategoriesOverlaysFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'costumeCategoriesOverlaysProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$costumeCategoriesOverlaysHash();

  @override
  String toString() {
    return r'costumeCategoriesOverlaysProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CostumeCategoriesOverlays create() => CostumeCategoriesOverlays();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<CostumeCategoryOverlay> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<CostumeCategoryOverlay>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CostumeCategoriesOverlaysProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$costumeCategoriesOverlaysHash() =>
    r'677a7cb8fa2724bbce1e66f1fc659c7f53531cca';

/// Ephemeral optimistic overlay store per season (controller state, NOT
/// Drift — no global overlay store).

final class CostumeCategoriesOverlaysFamily extends $Family
    with
        $ClassFamilyOverride<
          CostumeCategoriesOverlays,
          List<CostumeCategoryOverlay>,
          List<CostumeCategoryOverlay>,
          List<CostumeCategoryOverlay>,
          String
        > {
  CostumeCategoriesOverlaysFamily._()
    : super(
        retry: null,
        name: r'costumeCategoriesOverlaysProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Ephemeral optimistic overlay store per season (controller state, NOT
  /// Drift — no global overlay store).

  CostumeCategoriesOverlaysProvider call(String seasonId) =>
      CostumeCategoriesOverlaysProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'costumeCategoriesOverlaysProvider';
}

/// Ephemeral optimistic overlay store per season (controller state, NOT
/// Drift — no global overlay store).

abstract class _$CostumeCategoriesOverlays
    extends $Notifier<List<CostumeCategoryOverlay>> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  List<CostumeCategoryOverlay> build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<List<CostumeCategoryOverlay>, List<CostumeCategoryOverlay>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                List<CostumeCategoryOverlay>,
                List<CostumeCategoryOverlay>
              >,
              List<CostumeCategoryOverlay>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Last command failure per season, surfaced to the screen keyed on `code`.

@ProviderFor(CostumeCategoriesCommandError)
final costumeCategoriesCommandErrorProvider =
    CostumeCategoriesCommandErrorFamily._();

/// Last command failure per season, surfaced to the screen keyed on `code`.
final class CostumeCategoriesCommandErrorProvider
    extends $NotifierProvider<CostumeCategoriesCommandError, ProblemError?> {
  /// Last command failure per season, surfaced to the screen keyed on `code`.
  CostumeCategoriesCommandErrorProvider._({
    required CostumeCategoriesCommandErrorFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'costumeCategoriesCommandErrorProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$costumeCategoriesCommandErrorHash();

  @override
  String toString() {
    return r'costumeCategoriesCommandErrorProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CostumeCategoriesCommandError create() => CostumeCategoriesCommandError();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProblemError? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProblemError?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CostumeCategoriesCommandErrorProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$costumeCategoriesCommandErrorHash() =>
    r'f1d5c5ac7019a0a8a540293f569f2bc2c43b7259';

/// Last command failure per season, surfaced to the screen keyed on `code`.

final class CostumeCategoriesCommandErrorFamily extends $Family
    with
        $ClassFamilyOverride<
          CostumeCategoriesCommandError,
          ProblemError?,
          ProblemError?,
          ProblemError?,
          String
        > {
  CostumeCategoriesCommandErrorFamily._()
    : super(
        retry: null,
        name: r'costumeCategoriesCommandErrorProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Last command failure per season, surfaced to the screen keyed on `code`.

  CostumeCategoriesCommandErrorProvider call(String seasonId) =>
      CostumeCategoriesCommandErrorProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'costumeCategoriesCommandErrorProvider';
}

/// Last command failure per season, surfaced to the screen keyed on `code`.

abstract class _$CostumeCategoriesCommandError
    extends $Notifier<ProblemError?> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  ProblemError? build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ProblemError?, ProblemError?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ProblemError?, ProblemError?>,
              ProblemError?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Render-only archived-visibility toggle per season (default off). Held in
/// its own notifier so toggling never triggers a projection refetch — the
/// toggle affects rendering only, never order-key derivation.

@ProviderFor(CostumeCategoriesShowArchived)
final costumeCategoriesShowArchivedProvider =
    CostumeCategoriesShowArchivedFamily._();

/// Render-only archived-visibility toggle per season (default off). Held in
/// its own notifier so toggling never triggers a projection refetch — the
/// toggle affects rendering only, never order-key derivation.
final class CostumeCategoriesShowArchivedProvider
    extends $NotifierProvider<CostumeCategoriesShowArchived, bool> {
  /// Render-only archived-visibility toggle per season (default off). Held in
  /// its own notifier so toggling never triggers a projection refetch — the
  /// toggle affects rendering only, never order-key derivation.
  CostumeCategoriesShowArchivedProvider._({
    required CostumeCategoriesShowArchivedFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'costumeCategoriesShowArchivedProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$costumeCategoriesShowArchivedHash();

  @override
  String toString() {
    return r'costumeCategoriesShowArchivedProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CostumeCategoriesShowArchived create() => CostumeCategoriesShowArchived();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CostumeCategoriesShowArchivedProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$costumeCategoriesShowArchivedHash() =>
    r'89a37f3ec50c51b6eefd96c67b5fba51d4853095';

/// Render-only archived-visibility toggle per season (default off). Held in
/// its own notifier so toggling never triggers a projection refetch — the
/// toggle affects rendering only, never order-key derivation.

final class CostumeCategoriesShowArchivedFamily extends $Family
    with
        $ClassFamilyOverride<
          CostumeCategoriesShowArchived,
          bool,
          bool,
          bool,
          String
        > {
  CostumeCategoriesShowArchivedFamily._()
    : super(
        retry: null,
        name: r'costumeCategoriesShowArchivedProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Render-only archived-visibility toggle per season (default off). Held in
  /// its own notifier so toggling never triggers a projection refetch — the
  /// toggle affects rendering only, never order-key derivation.

  CostumeCategoriesShowArchivedProvider call(String seasonId) =>
      CostumeCategoriesShowArchivedProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'costumeCategoriesShowArchivedProvider';
}

/// Render-only archived-visibility toggle per season (default off). Held in
/// its own notifier so toggling never triggers a projection refetch — the
/// toggle affects rendering only, never order-key derivation.

abstract class _$CostumeCategoriesShowArchived extends $Notifier<bool> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  bool build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// `CostumeCategoriesController(seasonId)` on the shared reconciliation
/// runner: create follows the optimistic-overlay pattern; rename echoes the
/// read row's `version` (409 → keyed copy, no silent overwrite); archive
/// reconciles via the bounded refetch.

@ProviderFor(CostumeCategoriesController)
final costumeCategoriesControllerProvider =
    CostumeCategoriesControllerFamily._();

/// `CostumeCategoriesController(seasonId)` on the shared reconciliation
/// runner: create follows the optimistic-overlay pattern; rename echoes the
/// read row's `version` (409 → keyed copy, no silent overwrite); archive
/// reconciles via the bounded refetch.
final class CostumeCategoriesControllerProvider
    extends
        $NotifierProvider<
          CostumeCategoriesController,
          CostumeCategoriesScreenState
        > {
  /// `CostumeCategoriesController(seasonId)` on the shared reconciliation
  /// runner: create follows the optimistic-overlay pattern; rename echoes the
  /// read row's `version` (409 → keyed copy, no silent overwrite); archive
  /// reconciles via the bounded refetch.
  CostumeCategoriesControllerProvider._({
    required CostumeCategoriesControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'costumeCategoriesControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$costumeCategoriesControllerHash();

  @override
  String toString() {
    return r'costumeCategoriesControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CostumeCategoriesController create() => CostumeCategoriesController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CostumeCategoriesScreenState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CostumeCategoriesScreenState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CostumeCategoriesControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$costumeCategoriesControllerHash() =>
    r'3a6dd62206ce48ee39dbc41d700d8efa32a0fccd';

/// `CostumeCategoriesController(seasonId)` on the shared reconciliation
/// runner: create follows the optimistic-overlay pattern; rename echoes the
/// read row's `version` (409 → keyed copy, no silent overwrite); archive
/// reconciles via the bounded refetch.

final class CostumeCategoriesControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          CostumeCategoriesController,
          CostumeCategoriesScreenState,
          CostumeCategoriesScreenState,
          CostumeCategoriesScreenState,
          String
        > {
  CostumeCategoriesControllerFamily._()
    : super(
        retry: null,
        name: r'costumeCategoriesControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// `CostumeCategoriesController(seasonId)` on the shared reconciliation
  /// runner: create follows the optimistic-overlay pattern; rename echoes the
  /// read row's `version` (409 → keyed copy, no silent overwrite); archive
  /// reconciles via the bounded refetch.

  CostumeCategoriesControllerProvider call(String seasonId) =>
      CostumeCategoriesControllerProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'costumeCategoriesControllerProvider';
}

/// `CostumeCategoriesController(seasonId)` on the shared reconciliation
/// runner: create follows the optimistic-overlay pattern; rename echoes the
/// read row's `version` (409 → keyed copy, no silent overwrite); archive
/// reconciles via the bounded refetch.

abstract class _$CostumeCategoriesController
    extends $Notifier<CostumeCategoriesScreenState> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  CostumeCategoriesScreenState build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<CostumeCategoriesScreenState, CostumeCategoriesScreenState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                CostumeCategoriesScreenState,
                CostumeCategoriesScreenState
              >,
              CostumeCategoriesScreenState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
