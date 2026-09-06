// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'costumes_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Costume repository: owns network + Drift cache writes.

@ProviderFor(costumeRepository)
final costumeRepositoryProvider = CostumeRepositoryProvider._();

/// Costume repository: owns network + Drift cache writes.

final class CostumeRepositoryProvider
    extends
        $FunctionalProvider<
          CostumeRepository,
          CostumeRepository,
          CostumeRepository
        >
    with $Provider<CostumeRepository> {
  /// Costume repository: owns network + Drift cache writes.
  CostumeRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'costumeRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$costumeRepositoryHash();

  @$internal
  @override
  $ProviderElement<CostumeRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CostumeRepository create(Ref ref) {
    return costumeRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CostumeRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CostumeRepository>(value),
    );
  }
}

String _$costumeRepositoryHash() => r'81a1f9252aff1390902bd2c23acb57a2197a0c07';

/// Photo repository (upload / bytes / delete / watch).

@ProviderFor(costumePhotoRepository)
final costumePhotoRepositoryProvider = CostumePhotoRepositoryProvider._();

/// Photo repository (upload / bytes / delete / watch).

final class CostumePhotoRepositoryProvider
    extends
        $FunctionalProvider<PhotoRepository, PhotoRepository, PhotoRepository>
    with $Provider<PhotoRepository> {
  /// Photo repository (upload / bytes / delete / watch).
  CostumePhotoRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'costumePhotoRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$costumePhotoRepositoryHash();

  @$internal
  @override
  $ProviderElement<PhotoRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PhotoRepository create(Ref ref) {
    return costumePhotoRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PhotoRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PhotoRepository>(value),
    );
  }
}

String _$costumePhotoRepositoryHash() =>
    r'5cab1fce1f98108eba3d9af4e1e82fd9a7710374';

/// The injected season-scoped list-fetch seam
/// (`GET /v1/costumes?season_id=…`). Tests override this provider with a
/// fake.

@ProviderFor(costumesListFetch)
final costumesListFetchProvider = CostumesListFetchFamily._();

/// The injected season-scoped list-fetch seam
/// (`GET /v1/costumes?season_id=…`). Tests override this provider with a
/// fake.

final class CostumesListFetchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<List<CostumeView>>>,
          Result<List<CostumeView>>,
          FutureOr<Result<List<CostumeView>>>
        >
    with
        $FutureModifier<Result<List<CostumeView>>>,
        $FutureProvider<Result<List<CostumeView>>> {
  /// The injected season-scoped list-fetch seam
  /// (`GET /v1/costumes?season_id=…`). Tests override this provider with a
  /// fake.
  CostumesListFetchProvider._({
    required CostumesListFetchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'costumesListFetchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$costumesListFetchHash();

  @override
  String toString() {
    return r'costumesListFetchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<List<CostumeView>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<List<CostumeView>>> create(Ref ref) {
    final argument = this.argument as String;
    return costumesListFetch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CostumesListFetchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$costumesListFetchHash() => r'1bcd1ed4245ae1b5f7ffd189cbadab4d73a05302';

/// The injected season-scoped list-fetch seam
/// (`GET /v1/costumes?season_id=…`). Tests override this provider with a
/// fake.

final class CostumesListFetchFamily extends $Family
    with
        $FunctionalFamilyOverride<FutureOr<Result<List<CostumeView>>>, String> {
  CostumesListFetchFamily._()
    : super(
        retry: null,
        name: r'costumesListFetchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The injected season-scoped list-fetch seam
  /// (`GET /v1/costumes?season_id=…`). Tests override this provider with a
  /// fake.

  CostumesListFetchProvider call(String seasonId) =>
      CostumesListFetchProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'costumesListFetchProvider';
}

/// Retained last-good snapshot per season.

@ProviderFor(CostumesPrevRows)
final costumesPrevRowsProvider = CostumesPrevRowsFamily._();

/// Retained last-good snapshot per season.
final class CostumesPrevRowsProvider
    extends $NotifierProvider<CostumesPrevRows, List<CostumeView>> {
  /// Retained last-good snapshot per season.
  CostumesPrevRowsProvider._({
    required CostumesPrevRowsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'costumesPrevRowsProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$costumesPrevRowsHash();

  @override
  String toString() {
    return r'costumesPrevRowsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CostumesPrevRows create() => CostumesPrevRows();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<CostumeView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<CostumeView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CostumesPrevRowsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$costumesPrevRowsHash() => r'a2e996fe7383aa892b140ef91506ea96eaf4134c';

/// Retained last-good snapshot per season.

final class CostumesPrevRowsFamily extends $Family
    with
        $ClassFamilyOverride<
          CostumesPrevRows,
          List<CostumeView>,
          List<CostumeView>,
          List<CostumeView>,
          String
        > {
  CostumesPrevRowsFamily._()
    : super(
        retry: null,
        name: r'costumesPrevRowsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Retained last-good snapshot per season.

  CostumesPrevRowsProvider call(String seasonId) =>
      CostumesPrevRowsProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'costumesPrevRowsProvider';
}

/// Retained last-good snapshot per season.

abstract class _$CostumesPrevRows extends $Notifier<List<CostumeView>> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  List<CostumeView> build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<CostumeView>, List<CostumeView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<CostumeView>, List<CostumeView>>,
              List<CostumeView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Read-projection controller (seeder watches repository + fetch only).

@ProviderFor(CostumesViewController)
final costumesViewControllerProvider = CostumesViewControllerFamily._();

/// Read-projection controller (seeder watches repository + fetch only).
final class CostumesViewControllerProvider
    extends
        $NotifierProvider<CostumesViewController, AsyncValue<CostumesView>> {
  /// Read-projection controller (seeder watches repository + fetch only).
  CostumesViewControllerProvider._({
    required CostumesViewControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'costumesViewControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$costumesViewControllerHash();

  @override
  String toString() {
    return r'costumesViewControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CostumesViewController create() => CostumesViewController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<CostumesView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<CostumesView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CostumesViewControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$costumesViewControllerHash() =>
    r'f8685372baf10686442734df9e8b0977d9f42ee8';

/// Read-projection controller (seeder watches repository + fetch only).

final class CostumesViewControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          CostumesViewController,
          AsyncValue<CostumesView>,
          AsyncValue<CostumesView>,
          AsyncValue<CostumesView>,
          String
        > {
  CostumesViewControllerFamily._()
    : super(
        retry: null,
        name: r'costumesViewControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Read-projection controller (seeder watches repository + fetch only).

  CostumesViewControllerProvider call(String seasonId) =>
      CostumesViewControllerProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'costumesViewControllerProvider';
}

/// Read-projection controller (seeder watches repository + fetch only).

abstract class _$CostumesViewController
    extends $Notifier<AsyncValue<CostumesView>> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  AsyncValue<CostumesView> build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<CostumesView>, AsyncValue<CostumesView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<CostumesView>, AsyncValue<CostumesView>>,
              AsyncValue<CostumesView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// TTL-based cache staleness for one season's costumes (issue #366).

@ProviderFor(costumesCacheStale)
final costumesCacheStaleProvider = CostumesCacheStaleFamily._();

/// TTL-based cache staleness for one season's costumes (issue #366).

final class CostumesCacheStaleProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// TTL-based cache staleness for one season's costumes (issue #366).
  CostumesCacheStaleProvider._({
    required CostumesCacheStaleFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'costumesCacheStaleProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$costumesCacheStaleHash();

  @override
  String toString() {
    return r'costumesCacheStaleProvider'
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
    return costumesCacheStale(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CostumesCacheStaleProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$costumesCacheStaleHash() =>
    r'90e6308aef67004f148f2d08b17b8cce171a536b';

/// TTL-based cache staleness for one season's costumes (issue #366).

final class CostumesCacheStaleFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, String> {
  CostumesCacheStaleFamily._()
    : super(
        retry: null,
        name: r'costumesCacheStaleProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// TTL-based cache staleness for one season's costumes (issue #366).

  CostumesCacheStaleProvider call(String seasonId) =>
      CostumesCacheStaleProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'costumesCacheStaleProvider';
}

/// The projection a screen reads (selector).

@ProviderFor(costumesView)
final costumesViewProvider = CostumesViewFamily._();

/// The projection a screen reads (selector).

final class CostumesViewProvider
    extends $FunctionalProvider<CostumesView, CostumesView, CostumesView>
    with $Provider<CostumesView> {
  /// The projection a screen reads (selector).
  CostumesViewProvider._({
    required CostumesViewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'costumesViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$costumesViewHash();

  @override
  String toString() {
    return r'costumesViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<CostumesView> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CostumesView create(Ref ref) {
    final argument = this.argument as String;
    return costumesView(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CostumesView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CostumesView>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CostumesViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$costumesViewHash() => r'513c299d9654fcd46df37de6bd6c36244ed1f6bf';

/// The projection a screen reads (selector).

final class CostumesViewFamily extends $Family
    with $FunctionalFamilyOverride<CostumesView, String> {
  CostumesViewFamily._()
    : super(
        retry: null,
        name: r'costumesViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The projection a screen reads (selector).

  CostumesViewProvider call(String seasonId) =>
      CostumesViewProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'costumesViewProvider';
}

/// Ephemeral row-level optimistic overlays per season (controller state,
/// NOT Drift). Entries clear by the version fence during the projection
/// refetch — never by projected id (a row-level edit keeps its id).

@ProviderFor(CostumesOverlays)
final costumesOverlaysProvider = CostumesOverlaysFamily._();

/// Ephemeral row-level optimistic overlays per season (controller state,
/// NOT Drift). Entries clear by the version fence during the projection
/// refetch — never by projected id (a row-level edit keeps its id).
final class CostumesOverlaysProvider
    extends $NotifierProvider<CostumesOverlays, List<CostumeRowOverlay>> {
  /// Ephemeral row-level optimistic overlays per season (controller state,
  /// NOT Drift). Entries clear by the version fence during the projection
  /// refetch — never by projected id (a row-level edit keeps its id).
  CostumesOverlaysProvider._({
    required CostumesOverlaysFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'costumesOverlaysProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$costumesOverlaysHash();

  @override
  String toString() {
    return r'costumesOverlaysProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CostumesOverlays create() => CostumesOverlays();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<CostumeRowOverlay> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<CostumeRowOverlay>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CostumesOverlaysProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$costumesOverlaysHash() => r'71ff5ddf50f074d5bd5b2e382479946d174fc56e';

/// Ephemeral row-level optimistic overlays per season (controller state,
/// NOT Drift). Entries clear by the version fence during the projection
/// refetch — never by projected id (a row-level edit keeps its id).

final class CostumesOverlaysFamily extends $Family
    with
        $ClassFamilyOverride<
          CostumesOverlays,
          List<CostumeRowOverlay>,
          List<CostumeRowOverlay>,
          List<CostumeRowOverlay>,
          String
        > {
  CostumesOverlaysFamily._()
    : super(
        retry: null,
        name: r'costumesOverlaysProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Ephemeral row-level optimistic overlays per season (controller state,
  /// NOT Drift). Entries clear by the version fence during the projection
  /// refetch — never by projected id (a row-level edit keeps its id).

  CostumesOverlaysProvider call(String seasonId) =>
      CostumesOverlaysProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'costumesOverlaysProvider';
}

/// Ephemeral row-level optimistic overlays per season (controller state,
/// NOT Drift). Entries clear by the version fence during the projection
/// refetch — never by projected id (a row-level edit keeps its id).

abstract class _$CostumesOverlays extends $Notifier<List<CostumeRowOverlay>> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  List<CostumeRowOverlay> build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<List<CostumeRowOverlay>, List<CostumeRowOverlay>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<CostumeRowOverlay>, List<CostumeRowOverlay>>,
              List<CostumeRowOverlay>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Last command failure per season, surfaced to the screen keyed on `code`.

@ProviderFor(CostumesCommandError)
final costumesCommandErrorProvider = CostumesCommandErrorFamily._();

/// Last command failure per season, surfaced to the screen keyed on `code`.
final class CostumesCommandErrorProvider
    extends $NotifierProvider<CostumesCommandError, ProblemError?> {
  /// Last command failure per season, surfaced to the screen keyed on `code`.
  CostumesCommandErrorProvider._({
    required CostumesCommandErrorFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'costumesCommandErrorProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$costumesCommandErrorHash();

  @override
  String toString() {
    return r'costumesCommandErrorProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CostumesCommandError create() => CostumesCommandError();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProblemError? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProblemError?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CostumesCommandErrorProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$costumesCommandErrorHash() =>
    r'c8a6c3bfc414bf8d7331d70fc222d2dc8a7a57c0';

/// Last command failure per season, surfaced to the screen keyed on `code`.

final class CostumesCommandErrorFamily extends $Family
    with
        $ClassFamilyOverride<
          CostumesCommandError,
          ProblemError?,
          ProblemError?,
          ProblemError?,
          String
        > {
  CostumesCommandErrorFamily._()
    : super(
        retry: null,
        name: r'costumesCommandErrorProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Last command failure per season, surfaced to the screen keyed on `code`.

  CostumesCommandErrorProvider call(String seasonId) =>
      CostumesCommandErrorProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'costumesCommandErrorProvider';
}

/// Last command failure per season, surfaced to the screen keyed on `code`.

abstract class _$CostumesCommandError extends $Notifier<ProblemError?> {
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

/// `CostumesController(seasonId)` on the shared reconciliation runner.

@ProviderFor(CostumesController)
final costumesControllerProvider = CostumesControllerFamily._();

/// `CostumesController(seasonId)` on the shared reconciliation runner.
final class CostumesControllerProvider
    extends $NotifierProvider<CostumesController, CostumesScreenState> {
  /// `CostumesController(seasonId)` on the shared reconciliation runner.
  CostumesControllerProvider._({
    required CostumesControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'costumesControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$costumesControllerHash();

  @override
  String toString() {
    return r'costumesControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CostumesController create() => CostumesController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CostumesScreenState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CostumesScreenState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CostumesControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$costumesControllerHash() =>
    r'9e649890634ec9bcc3616c43887104ddb5529470';

/// `CostumesController(seasonId)` on the shared reconciliation runner.

final class CostumesControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          CostumesController,
          CostumesScreenState,
          CostumesScreenState,
          CostumesScreenState,
          String
        > {
  CostumesControllerFamily._()
    : super(
        retry: null,
        name: r'costumesControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// `CostumesController(seasonId)` on the shared reconciliation runner.

  CostumesControllerProvider call(String seasonId) =>
      CostumesControllerProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'costumesControllerProvider';
}

/// `CostumesController(seasonId)` on the shared reconciliation runner.

abstract class _$CostumesController extends $Notifier<CostumesScreenState> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  CostumesScreenState build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<CostumesScreenState, CostumesScreenState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CostumesScreenState, CostumesScreenState>,
              CostumesScreenState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
