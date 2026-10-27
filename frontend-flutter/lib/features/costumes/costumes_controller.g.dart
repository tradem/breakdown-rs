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
        $FunctionalProvider<PieceRepository, PieceRepository, PieceRepository>
    with $Provider<PieceRepository> {
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
  $ProviderElement<PieceRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PieceRepository create(Ref ref) {
    return costumeRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PieceRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PieceRepository>(value),
    );
  }
}

String _$costumeRepositoryHash() => r'9a0ae2884fc48a141f8e169b2e04e1cd894b9825';

/// Outfit repository: the character's composed looks (own network + Drift
/// cache slice). A scene beat casts an OUTFIT, so the beat picker reads here.

@ProviderFor(outfitRepository)
final outfitRepositoryProvider = OutfitRepositoryProvider._();

/// Outfit repository: the character's composed looks (own network + Drift
/// cache slice). A scene beat casts an OUTFIT, so the beat picker reads here.

final class OutfitRepositoryProvider
    extends
        $FunctionalProvider<
          OutfitRepository,
          OutfitRepository,
          OutfitRepository
        >
    with $Provider<OutfitRepository> {
  /// Outfit repository: the character's composed looks (own network + Drift
  /// cache slice). A scene beat casts an OUTFIT, so the beat picker reads here.
  OutfitRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'outfitRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$outfitRepositoryHash();

  @$internal
  @override
  $ProviderElement<OutfitRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  OutfitRepository create(Ref ref) {
    return outfitRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OutfitRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OutfitRepository>(value),
    );
  }
}

String _$outfitRepositoryHash() => r'cf39e06765dc6cda94f4e081ec5480e7609c9ab0';

/// The outfits of one character (fetch + snapshot-replace). The scene beat
/// picker watches this; a fetch failure surfaces as a `Result` error, never
/// a throw.

@ProviderFor(characterOutfits)
final characterOutfitsProvider = CharacterOutfitsFamily._();

/// The outfits of one character (fetch + snapshot-replace). The scene beat
/// picker watches this; a fetch failure surfaces as a `Result` error, never
/// a throw.

final class CharacterOutfitsProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<List<OutfitView>>>,
          Result<List<OutfitView>>,
          FutureOr<Result<List<OutfitView>>>
        >
    with
        $FutureModifier<Result<List<OutfitView>>>,
        $FutureProvider<Result<List<OutfitView>>> {
  /// The outfits of one character (fetch + snapshot-replace). The scene beat
  /// picker watches this; a fetch failure surfaces as a `Result` error, never
  /// a throw.
  CharacterOutfitsProvider._({
    required CharacterOutfitsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'characterOutfitsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$characterOutfitsHash();

  @override
  String toString() {
    return r'characterOutfitsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<List<OutfitView>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<List<OutfitView>>> create(Ref ref) {
    final argument = this.argument as String;
    return characterOutfits(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CharacterOutfitsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$characterOutfitsHash() => r'97e4c6976e9bea68e8c506e3648318386f18fe52';

/// The outfits of one character (fetch + snapshot-replace). The scene beat
/// picker watches this; a fetch failure surfaces as a `Result` error, never
/// a throw.

final class CharacterOutfitsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Result<List<OutfitView>>>, String> {
  CharacterOutfitsFamily._()
    : super(
        retry: null,
        name: r'characterOutfitsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The outfits of one character (fetch + snapshot-replace). The scene beat
  /// picker watches this; a fetch failure surfaces as a `Result` error, never
  /// a throw.

  CharacterOutfitsProvider call(String characterId) =>
      CharacterOutfitsProvider._(argument: characterId, from: this);

  @override
  String toString() => r'characterOutfitsProvider';
}

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
          AsyncValue<Result<List<PieceView>>>,
          Result<List<PieceView>>,
          FutureOr<Result<List<PieceView>>>
        >
    with
        $FutureModifier<Result<List<PieceView>>>,
        $FutureProvider<Result<List<PieceView>>> {
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
  $FutureProviderElement<Result<List<PieceView>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<List<PieceView>>> create(Ref ref) {
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

String _$costumesListFetchHash() => r'cc78b304b0e79d39864f78efc870f616f05cf7eb';

/// The injected season-scoped list-fetch seam
/// (`GET /v1/costumes?season_id=…`). Tests override this provider with a
/// fake.

final class CostumesListFetchFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Result<List<PieceView>>>, String> {
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
    extends $NotifierProvider<CostumesPrevRows, List<PieceView>> {
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
  Override overrideWithValue(List<PieceView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<PieceView>>(value),
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

String _$costumesPrevRowsHash() => r'70777e041fb24f24dd7e6b8f7d12b7093933ed12';

/// Retained last-good snapshot per season.

final class CostumesPrevRowsFamily extends $Family
    with
        $ClassFamilyOverride<
          CostumesPrevRows,
          List<PieceView>,
          List<PieceView>,
          List<PieceView>,
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

abstract class _$CostumesPrevRows extends $Notifier<List<PieceView>> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  List<PieceView> build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<PieceView>, List<PieceView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<PieceView>, List<PieceView>>,
              List<PieceView>,
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
    r'2d897bca8eae9d861200979407aad529dbbafd6a';

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

String _$costumesOverlaysHash() => r'a0b33914f6ff9690453f9045576d2e73c8d08e96';

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

/// Last command failure per season (with its originating surface so the
/// banner copies correctly), surfaced to the screen keyed on `code`.

@ProviderFor(CostumesCommandError)
final costumesCommandErrorProvider = CostumesCommandErrorFamily._();

/// Last command failure per season (with its originating surface so the
/// banner copies correctly), surfaced to the screen keyed on `code`.
final class CostumesCommandErrorProvider
    extends $NotifierProvider<CostumesCommandError, CostumeCommandFailure?> {
  /// Last command failure per season (with its originating surface so the
  /// banner copies correctly), surfaced to the screen keyed on `code`.
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
  Override overrideWithValue(CostumeCommandFailure? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CostumeCommandFailure?>(value),
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
    r'79b692abfa43f3cccfb781bb4b18e85d19b21620';

/// Last command failure per season (with its originating surface so the
/// banner copies correctly), surfaced to the screen keyed on `code`.

final class CostumesCommandErrorFamily extends $Family
    with
        $ClassFamilyOverride<
          CostumesCommandError,
          CostumeCommandFailure?,
          CostumeCommandFailure?,
          CostumeCommandFailure?,
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

  /// Last command failure per season (with its originating surface so the
  /// banner copies correctly), surfaced to the screen keyed on `code`.

  CostumesCommandErrorProvider call(String seasonId) =>
      CostumesCommandErrorProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'costumesCommandErrorProvider';
}

/// Last command failure per season (with its originating surface so the
/// banner copies correctly), surfaced to the screen keyed on `code`.

abstract class _$CostumesCommandError
    extends $Notifier<CostumeCommandFailure?> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  CostumeCommandFailure? build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<CostumeCommandFailure?, CostumeCommandFailure?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CostumeCommandFailure?, CostumeCommandFailure?>,
              CostumeCommandFailure?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// `PiecesController(seasonId)` on the shared reconciliation runner.

@ProviderFor(PiecesController)
final piecesControllerProvider = PiecesControllerFamily._();

/// `PiecesController(seasonId)` on the shared reconciliation runner.
final class PiecesControllerProvider
    extends $NotifierProvider<PiecesController, CostumesScreenState> {
  /// `PiecesController(seasonId)` on the shared reconciliation runner.
  PiecesControllerProvider._({
    required PiecesControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'piecesControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$piecesControllerHash();

  @override
  String toString() {
    return r'piecesControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  PiecesController create() => PiecesController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CostumesScreenState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CostumesScreenState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PiecesControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$piecesControllerHash() => r'638934d0cc6cac072c6561b2ff2f46dc67473702';

/// `PiecesController(seasonId)` on the shared reconciliation runner.

final class PiecesControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          PiecesController,
          CostumesScreenState,
          CostumesScreenState,
          CostumesScreenState,
          String
        > {
  PiecesControllerFamily._()
    : super(
        retry: null,
        name: r'piecesControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// `PiecesController(seasonId)` on the shared reconciliation runner.

  PiecesControllerProvider call(String seasonId) =>
      PiecesControllerProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'piecesControllerProvider';
}

/// `PiecesController(seasonId)` on the shared reconciliation runner.

abstract class _$PiecesController extends $Notifier<CostumesScreenState> {
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
