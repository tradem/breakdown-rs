// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pieces_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Piece repository: owns network + Drift cache writes.

@ProviderFor(pieceRepository)
final pieceRepositoryProvider = PieceRepositoryProvider._();

/// Piece repository: owns network + Drift cache writes.

final class PieceRepositoryProvider
    extends
        $FunctionalProvider<PieceRepository, PieceRepository, PieceRepository>
    with $Provider<PieceRepository> {
  /// Piece repository: owns network + Drift cache writes.
  PieceRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pieceRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pieceRepositoryHash();

  @$internal
  @override
  $ProviderElement<PieceRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PieceRepository create(Ref ref) {
    return pieceRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PieceRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PieceRepository>(value),
    );
  }
}

String _$pieceRepositoryHash() => r'cdd166d7ce1fcdb52e979b1e017523989fc5d052';

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

@ProviderFor(piecePhotoRepository)
final piecePhotoRepositoryProvider = PiecePhotoRepositoryProvider._();

/// Photo repository (upload / bytes / delete / watch).

final class PiecePhotoRepositoryProvider
    extends
        $FunctionalProvider<PhotoRepository, PhotoRepository, PhotoRepository>
    with $Provider<PhotoRepository> {
  /// Photo repository (upload / bytes / delete / watch).
  PiecePhotoRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'piecePhotoRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$piecePhotoRepositoryHash();

  @$internal
  @override
  $ProviderElement<PhotoRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PhotoRepository create(Ref ref) {
    return piecePhotoRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PhotoRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PhotoRepository>(value),
    );
  }
}

String _$piecePhotoRepositoryHash() =>
    r'cf5c9c1c7ac190c154804e12c0581fa2ff92dbef';

/// The injected season-scoped list-fetch seam
/// (`GET /v1/pieces?season_id=…`). Tests override this provider with a
/// fake.

@ProviderFor(piecesListFetch)
final piecesListFetchProvider = PiecesListFetchFamily._();

/// The injected season-scoped list-fetch seam
/// (`GET /v1/pieces?season_id=…`). Tests override this provider with a
/// fake.

final class PiecesListFetchProvider
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
  /// (`GET /v1/pieces?season_id=…`). Tests override this provider with a
  /// fake.
  PiecesListFetchProvider._({
    required PiecesListFetchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'piecesListFetchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$piecesListFetchHash();

  @override
  String toString() {
    return r'piecesListFetchProvider'
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
    return piecesListFetch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is PiecesListFetchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$piecesListFetchHash() => r'6a65893f4cc0e77aef4d4be6e84a7be56347e848';

/// The injected season-scoped list-fetch seam
/// (`GET /v1/pieces?season_id=…`). Tests override this provider with a
/// fake.

final class PiecesListFetchFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Result<List<PieceView>>>, String> {
  PiecesListFetchFamily._()
    : super(
        retry: null,
        name: r'piecesListFetchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The injected season-scoped list-fetch seam
  /// (`GET /v1/pieces?season_id=…`). Tests override this provider with a
  /// fake.

  PiecesListFetchProvider call(String seasonId) =>
      PiecesListFetchProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'piecesListFetchProvider';
}

/// Retained last-good snapshot per season.

@ProviderFor(PiecesPrevRows)
final piecesPrevRowsProvider = PiecesPrevRowsFamily._();

/// Retained last-good snapshot per season.
final class PiecesPrevRowsProvider
    extends $NotifierProvider<PiecesPrevRows, List<PieceView>> {
  /// Retained last-good snapshot per season.
  PiecesPrevRowsProvider._({
    required PiecesPrevRowsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'piecesPrevRowsProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$piecesPrevRowsHash();

  @override
  String toString() {
    return r'piecesPrevRowsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  PiecesPrevRows create() => PiecesPrevRows();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<PieceView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<PieceView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PiecesPrevRowsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$piecesPrevRowsHash() => r'1687a0872045dc34cf1472707f0404d34b5c7e1f';

/// Retained last-good snapshot per season.

final class PiecesPrevRowsFamily extends $Family
    with
        $ClassFamilyOverride<
          PiecesPrevRows,
          List<PieceView>,
          List<PieceView>,
          List<PieceView>,
          String
        > {
  PiecesPrevRowsFamily._()
    : super(
        retry: null,
        name: r'piecesPrevRowsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Retained last-good snapshot per season.

  PiecesPrevRowsProvider call(String seasonId) =>
      PiecesPrevRowsProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'piecesPrevRowsProvider';
}

/// Retained last-good snapshot per season.

abstract class _$PiecesPrevRows extends $Notifier<List<PieceView>> {
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

@ProviderFor(PiecesViewController)
final piecesViewControllerProvider = PiecesViewControllerFamily._();

/// Read-projection controller (seeder watches repository + fetch only).
final class PiecesViewControllerProvider
    extends $NotifierProvider<PiecesViewController, AsyncValue<PiecesView>> {
  /// Read-projection controller (seeder watches repository + fetch only).
  PiecesViewControllerProvider._({
    required PiecesViewControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'piecesViewControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$piecesViewControllerHash();

  @override
  String toString() {
    return r'piecesViewControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  PiecesViewController create() => PiecesViewController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<PiecesView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<PiecesView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PiecesViewControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$piecesViewControllerHash() =>
    r'73fc964d78b3036384afab91c0e689bf5e363ce0';

/// Read-projection controller (seeder watches repository + fetch only).

final class PiecesViewControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          PiecesViewController,
          AsyncValue<PiecesView>,
          AsyncValue<PiecesView>,
          AsyncValue<PiecesView>,
          String
        > {
  PiecesViewControllerFamily._()
    : super(
        retry: null,
        name: r'piecesViewControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Read-projection controller (seeder watches repository + fetch only).

  PiecesViewControllerProvider call(String seasonId) =>
      PiecesViewControllerProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'piecesViewControllerProvider';
}

/// Read-projection controller (seeder watches repository + fetch only).

abstract class _$PiecesViewController
    extends $Notifier<AsyncValue<PiecesView>> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  AsyncValue<PiecesView> build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<PiecesView>, AsyncValue<PiecesView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<PiecesView>, AsyncValue<PiecesView>>,
              AsyncValue<PiecesView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// TTL-based cache staleness for one season's pieces (issue #366).

@ProviderFor(piecesCacheStale)
final piecesCacheStaleProvider = PiecesCacheStaleFamily._();

/// TTL-based cache staleness for one season's pieces (issue #366).

final class PiecesCacheStaleProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// TTL-based cache staleness for one season's pieces (issue #366).
  PiecesCacheStaleProvider._({
    required PiecesCacheStaleFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'piecesCacheStaleProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$piecesCacheStaleHash();

  @override
  String toString() {
    return r'piecesCacheStaleProvider'
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
    return piecesCacheStale(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is PiecesCacheStaleProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$piecesCacheStaleHash() => r'6000bd8466795eba00a7ccd2a1dca6d2b2bece89';

/// TTL-based cache staleness for one season's pieces (issue #366).

final class PiecesCacheStaleFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, String> {
  PiecesCacheStaleFamily._()
    : super(
        retry: null,
        name: r'piecesCacheStaleProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// TTL-based cache staleness for one season's pieces (issue #366).

  PiecesCacheStaleProvider call(String seasonId) =>
      PiecesCacheStaleProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'piecesCacheStaleProvider';
}

/// The projection a screen reads (selector).

@ProviderFor(piecesView)
final piecesViewProvider = PiecesViewFamily._();

/// The projection a screen reads (selector).

final class PiecesViewProvider
    extends $FunctionalProvider<PiecesView, PiecesView, PiecesView>
    with $Provider<PiecesView> {
  /// The projection a screen reads (selector).
  PiecesViewProvider._({
    required PiecesViewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'piecesViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$piecesViewHash();

  @override
  String toString() {
    return r'piecesViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<PiecesView> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PiecesView create(Ref ref) {
    final argument = this.argument as String;
    return piecesView(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PiecesView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PiecesView>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PiecesViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$piecesViewHash() => r'e94510c33149c35e27789ceb0a1ac2e65b878368';

/// The projection a screen reads (selector).

final class PiecesViewFamily extends $Family
    with $FunctionalFamilyOverride<PiecesView, String> {
  PiecesViewFamily._()
    : super(
        retry: null,
        name: r'piecesViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The projection a screen reads (selector).

  PiecesViewProvider call(String seasonId) =>
      PiecesViewProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'piecesViewProvider';
}

/// Ephemeral row-level optimistic overlays per season (controller state,
/// NOT Drift). Entries clear by the version fence during the projection
/// refetch — never by projected id (a row-level edit keeps its id).

@ProviderFor(PiecesOverlays)
final piecesOverlaysProvider = PiecesOverlaysFamily._();

/// Ephemeral row-level optimistic overlays per season (controller state,
/// NOT Drift). Entries clear by the version fence during the projection
/// refetch — never by projected id (a row-level edit keeps its id).
final class PiecesOverlaysProvider
    extends $NotifierProvider<PiecesOverlays, List<PieceRowOverlay>> {
  /// Ephemeral row-level optimistic overlays per season (controller state,
  /// NOT Drift). Entries clear by the version fence during the projection
  /// refetch — never by projected id (a row-level edit keeps its id).
  PiecesOverlaysProvider._({
    required PiecesOverlaysFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'piecesOverlaysProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$piecesOverlaysHash();

  @override
  String toString() {
    return r'piecesOverlaysProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  PiecesOverlays create() => PiecesOverlays();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<PieceRowOverlay> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<PieceRowOverlay>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PiecesOverlaysProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$piecesOverlaysHash() => r'2af9a23cca335630acab896ba71a9b3f464edbc7';

/// Ephemeral row-level optimistic overlays per season (controller state,
/// NOT Drift). Entries clear by the version fence during the projection
/// refetch — never by projected id (a row-level edit keeps its id).

final class PiecesOverlaysFamily extends $Family
    with
        $ClassFamilyOverride<
          PiecesOverlays,
          List<PieceRowOverlay>,
          List<PieceRowOverlay>,
          List<PieceRowOverlay>,
          String
        > {
  PiecesOverlaysFamily._()
    : super(
        retry: null,
        name: r'piecesOverlaysProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Ephemeral row-level optimistic overlays per season (controller state,
  /// NOT Drift). Entries clear by the version fence during the projection
  /// refetch — never by projected id (a row-level edit keeps its id).

  PiecesOverlaysProvider call(String seasonId) =>
      PiecesOverlaysProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'piecesOverlaysProvider';
}

/// Ephemeral row-level optimistic overlays per season (controller state,
/// NOT Drift). Entries clear by the version fence during the projection
/// refetch — never by projected id (a row-level edit keeps its id).

abstract class _$PiecesOverlays extends $Notifier<List<PieceRowOverlay>> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  List<PieceRowOverlay> build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<PieceRowOverlay>, List<PieceRowOverlay>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<PieceRowOverlay>, List<PieceRowOverlay>>,
              List<PieceRowOverlay>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Last command failure per season (with its originating surface so the
/// banner copies correctly), surfaced to the screen keyed on `code`.

@ProviderFor(PiecesCommandError)
final piecesCommandErrorProvider = PiecesCommandErrorFamily._();

/// Last command failure per season (with its originating surface so the
/// banner copies correctly), surfaced to the screen keyed on `code`.
final class PiecesCommandErrorProvider
    extends $NotifierProvider<PiecesCommandError, PieceCommandFailure?> {
  /// Last command failure per season (with its originating surface so the
  /// banner copies correctly), surfaced to the screen keyed on `code`.
  PiecesCommandErrorProvider._({
    required PiecesCommandErrorFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'piecesCommandErrorProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$piecesCommandErrorHash();

  @override
  String toString() {
    return r'piecesCommandErrorProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  PiecesCommandError create() => PiecesCommandError();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PieceCommandFailure? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PieceCommandFailure?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PiecesCommandErrorProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$piecesCommandErrorHash() =>
    r'ec4c10f0242de9364cc773a45e547e819f45989e';

/// Last command failure per season (with its originating surface so the
/// banner copies correctly), surfaced to the screen keyed on `code`.

final class PiecesCommandErrorFamily extends $Family
    with
        $ClassFamilyOverride<
          PiecesCommandError,
          PieceCommandFailure?,
          PieceCommandFailure?,
          PieceCommandFailure?,
          String
        > {
  PiecesCommandErrorFamily._()
    : super(
        retry: null,
        name: r'piecesCommandErrorProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Last command failure per season (with its originating surface so the
  /// banner copies correctly), surfaced to the screen keyed on `code`.

  PiecesCommandErrorProvider call(String seasonId) =>
      PiecesCommandErrorProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'piecesCommandErrorProvider';
}

/// Last command failure per season (with its originating surface so the
/// banner copies correctly), surfaced to the screen keyed on `code`.

abstract class _$PiecesCommandError extends $Notifier<PieceCommandFailure?> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  PieceCommandFailure? build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PieceCommandFailure?, PieceCommandFailure?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PieceCommandFailure?, PieceCommandFailure?>,
              PieceCommandFailure?,
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
    extends $NotifierProvider<PiecesController, PiecesScreenState> {
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
  Override overrideWithValue(PiecesScreenState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PiecesScreenState>(value),
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

String _$piecesControllerHash() => r'6691c10702195a1f04b3fa73187930c5ec4e1d80';

/// `PiecesController(seasonId)` on the shared reconciliation runner.

final class PiecesControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          PiecesController,
          PiecesScreenState,
          PiecesScreenState,
          PiecesScreenState,
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

abstract class _$PiecesController extends $Notifier<PiecesScreenState> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  PiecesScreenState build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PiecesScreenState, PiecesScreenState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PiecesScreenState, PiecesScreenState>,
              PiecesScreenState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
