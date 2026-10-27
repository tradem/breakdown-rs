// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outfits_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Outfit repository: the character's composed looks (own network + Drift
/// slice). The scene-beat picker and the outfit screens both read here.

@ProviderFor(outfitRepository)
final outfitRepositoryProvider = OutfitRepositoryProvider._();

/// Outfit repository: the character's composed looks (own network + Drift
/// slice). The scene-beat picker and the outfit screens both read here.

final class OutfitRepositoryProvider
    extends
        $FunctionalProvider<
          OutfitRepository,
          OutfitRepository,
          OutfitRepository
        >
    with $Provider<OutfitRepository> {
  /// Outfit repository: the character's composed looks (own network + Drift
  /// slice). The scene-beat picker and the outfit screens both read here.
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

/// The outfits of one character (fetch + snapshot-replace). The scene-beat
/// picker watches this; a fetch failure surfaces as a `Result` error.

@ProviderFor(characterOutfits)
final characterOutfitsProvider = CharacterOutfitsFamily._();

/// The outfits of one character (fetch + snapshot-replace). The scene-beat
/// picker watches this; a fetch failure surfaces as a `Result` error.

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
  /// The outfits of one character (fetch + snapshot-replace). The scene-beat
  /// picker watches this; a fetch failure surfaces as a `Result` error.
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

/// The outfits of one character (fetch + snapshot-replace). The scene-beat
/// picker watches this; a fetch failure surfaces as a `Result` error.

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

  /// The outfits of one character (fetch + snapshot-replace). The scene-beat
  /// picker watches this; a fetch failure surfaces as a `Result` error.

  CharacterOutfitsProvider call(String characterId) =>
      CharacterOutfitsProvider._(argument: characterId, from: this);

  @override
  String toString() => r'characterOutfitsProvider';
}

/// Photo repository for fitting photos (upload / bytes / delete / watch).

@ProviderFor(outfitPhotoRepository)
final outfitPhotoRepositoryProvider = OutfitPhotoRepositoryProvider._();

/// Photo repository for fitting photos (upload / bytes / delete / watch).

final class OutfitPhotoRepositoryProvider
    extends
        $FunctionalProvider<PhotoRepository, PhotoRepository, PhotoRepository>
    with $Provider<PhotoRepository> {
  /// Photo repository for fitting photos (upload / bytes / delete / watch).
  OutfitPhotoRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'outfitPhotoRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$outfitPhotoRepositoryHash();

  @$internal
  @override
  $ProviderElement<PhotoRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PhotoRepository create(Ref ref) {
    return outfitPhotoRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PhotoRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PhotoRepository>(value),
    );
  }
}

String _$outfitPhotoRepositoryHash() =>
    r'26b4e88ce465c0c0f55163a6df67ffe0e048feaa';

/// One character's looks, fetched through the repository (network + Drift
/// snapshot-replace, character-scoped).
///
/// The injected seam: tests override this provider with a fake so neither the
/// network nor Drift is touched.

@ProviderFor(outfitsListFetch)
final outfitsListFetchProvider = OutfitsListFetchFamily._();

/// One character's looks, fetched through the repository (network + Drift
/// snapshot-replace, character-scoped).
///
/// The injected seam: tests override this provider with a fake so neither the
/// network nor Drift is touched.

final class OutfitsListFetchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<List<OutfitView>>>,
          Result<List<OutfitView>>,
          FutureOr<Result<List<OutfitView>>>
        >
    with
        $FutureModifier<Result<List<OutfitView>>>,
        $FutureProvider<Result<List<OutfitView>>> {
  /// One character's looks, fetched through the repository (network + Drift
  /// snapshot-replace, character-scoped).
  ///
  /// The injected seam: tests override this provider with a fake so neither the
  /// network nor Drift is touched.
  OutfitsListFetchProvider._({
    required OutfitsListFetchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'outfitsListFetchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$outfitsListFetchHash();

  @override
  String toString() {
    return r'outfitsListFetchProvider'
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
    return outfitsListFetch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is OutfitsListFetchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$outfitsListFetchHash() => r'9104ab2535491563bcecd6cc79d5ddd35aa6b522';

/// One character's looks, fetched through the repository (network + Drift
/// snapshot-replace, character-scoped).
///
/// The injected seam: tests override this provider with a fake so neither the
/// network nor Drift is touched.

final class OutfitsListFetchFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Result<List<OutfitView>>>, String> {
  OutfitsListFetchFamily._()
    : super(
        retry: null,
        name: r'outfitsListFetchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One character's looks, fetched through the repository (network + Drift
  /// snapshot-replace, character-scoped).
  ///
  /// The injected seam: tests override this provider with a fake so neither the
  /// network nor Drift is touched.

  OutfitsListFetchProvider call(String characterId) =>
      OutfitsListFetchProvider._(argument: characterId, from: this);

  @override
  String toString() => r'outfitsListFetchProvider';
}

/// Retained last-good snapshot per character (stale-on-error).

@ProviderFor(OutfitsPrevRows)
final outfitsPrevRowsProvider = OutfitsPrevRowsFamily._();

/// Retained last-good snapshot per character (stale-on-error).
final class OutfitsPrevRowsProvider
    extends $NotifierProvider<OutfitsPrevRows, List<OutfitView>> {
  /// Retained last-good snapshot per character (stale-on-error).
  OutfitsPrevRowsProvider._({
    required OutfitsPrevRowsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'outfitsPrevRowsProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$outfitsPrevRowsHash();

  @override
  String toString() {
    return r'outfitsPrevRowsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  OutfitsPrevRows create() => OutfitsPrevRows();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<OutfitView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<OutfitView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is OutfitsPrevRowsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$outfitsPrevRowsHash() => r'd100441672768a76e170734048924911ad7683ac';

/// Retained last-good snapshot per character (stale-on-error).

final class OutfitsPrevRowsFamily extends $Family
    with
        $ClassFamilyOverride<
          OutfitsPrevRows,
          List<OutfitView>,
          List<OutfitView>,
          List<OutfitView>,
          String
        > {
  OutfitsPrevRowsFamily._()
    : super(
        retry: null,
        name: r'outfitsPrevRowsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Retained last-good snapshot per character (stale-on-error).

  OutfitsPrevRowsProvider call(String characterId) =>
      OutfitsPrevRowsProvider._(argument: characterId, from: this);

  @override
  String toString() => r'outfitsPrevRowsProvider';
}

/// Retained last-good snapshot per character (stale-on-error).

abstract class _$OutfitsPrevRows extends $Notifier<List<OutfitView>> {
  late final _$args = ref.$arg as String;
  String get characterId => _$args;

  List<OutfitView> build(String characterId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<OutfitView>, List<OutfitView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<OutfitView>, List<OutfitView>>,
              List<OutfitView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Read-projection controller (mirror of the pieces/seasons pattern).

@ProviderFor(OutfitsViewController)
final outfitsViewControllerProvider = OutfitsViewControllerFamily._();

/// Read-projection controller (mirror of the pieces/seasons pattern).
final class OutfitsViewControllerProvider
    extends $NotifierProvider<OutfitsViewController, AsyncValue<OutfitsView>> {
  /// Read-projection controller (mirror of the pieces/seasons pattern).
  OutfitsViewControllerProvider._({
    required OutfitsViewControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'outfitsViewControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$outfitsViewControllerHash();

  @override
  String toString() {
    return r'outfitsViewControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  OutfitsViewController create() => OutfitsViewController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<OutfitsView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<OutfitsView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is OutfitsViewControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$outfitsViewControllerHash() =>
    r'66916f1b4678e1e4e5a58889926fc3ddadd837a9';

/// Read-projection controller (mirror of the pieces/seasons pattern).

final class OutfitsViewControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          OutfitsViewController,
          AsyncValue<OutfitsView>,
          AsyncValue<OutfitsView>,
          AsyncValue<OutfitsView>,
          String
        > {
  OutfitsViewControllerFamily._()
    : super(
        retry: null,
        name: r'outfitsViewControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Read-projection controller (mirror of the pieces/seasons pattern).

  OutfitsViewControllerProvider call(String characterId) =>
      OutfitsViewControllerProvider._(argument: characterId, from: this);

  @override
  String toString() => r'outfitsViewControllerProvider';
}

/// Read-projection controller (mirror of the pieces/seasons pattern).

abstract class _$OutfitsViewController
    extends $Notifier<AsyncValue<OutfitsView>> {
  late final _$args = ref.$arg as String;
  String get characterId => _$args;

  AsyncValue<OutfitsView> build(String characterId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<OutfitsView>, AsyncValue<OutfitsView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<OutfitsView>, AsyncValue<OutfitsView>>,
              AsyncValue<OutfitsView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// TTL-based cache staleness for one character's looks.

@ProviderFor(outfitsCacheStale)
final outfitsCacheStaleProvider = OutfitsCacheStaleFamily._();

/// TTL-based cache staleness for one character's looks.

final class OutfitsCacheStaleProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// TTL-based cache staleness for one character's looks.
  OutfitsCacheStaleProvider._({
    required OutfitsCacheStaleFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'outfitsCacheStaleProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$outfitsCacheStaleHash();

  @override
  String toString() {
    return r'outfitsCacheStaleProvider'
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
    return outfitsCacheStale(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is OutfitsCacheStaleProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$outfitsCacheStaleHash() => r'b5bf1585400b404b4f055479769bac844d19fa9b';

/// TTL-based cache staleness for one character's looks.

final class OutfitsCacheStaleFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, String> {
  OutfitsCacheStaleFamily._()
    : super(
        retry: null,
        name: r'outfitsCacheStaleProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// TTL-based cache staleness for one character's looks.

  OutfitsCacheStaleProvider call(String characterId) =>
      OutfitsCacheStaleProvider._(argument: characterId, from: this);

  @override
  String toString() => r'outfitsCacheStaleProvider';
}

/// The projection a screen reads (selector pattern).

@ProviderFor(outfitsView)
final outfitsViewProvider = OutfitsViewFamily._();

/// The projection a screen reads (selector pattern).

final class OutfitsViewProvider
    extends $FunctionalProvider<OutfitsView, OutfitsView, OutfitsView>
    with $Provider<OutfitsView> {
  /// The projection a screen reads (selector pattern).
  OutfitsViewProvider._({
    required OutfitsViewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'outfitsViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$outfitsViewHash();

  @override
  String toString() {
    return r'outfitsViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<OutfitsView> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  OutfitsView create(Ref ref) {
    final argument = this.argument as String;
    return outfitsView(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OutfitsView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OutfitsView>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is OutfitsViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$outfitsViewHash() => r'7fa433c39020f28a236f1076d67392cd8125bcc3';

/// The projection a screen reads (selector pattern).

final class OutfitsViewFamily extends $Family
    with $FunctionalFamilyOverride<OutfitsView, String> {
  OutfitsViewFamily._()
    : super(
        retry: null,
        name: r'outfitsViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The projection a screen reads (selector pattern).

  OutfitsViewProvider call(String characterId) =>
      OutfitsViewProvider._(argument: characterId, from: this);

  @override
  String toString() => r'outfitsViewProvider';
}

/// Ephemeral row-level overlays per character (controller state, NOT Drift).

@ProviderFor(OutfitsOverlays)
final outfitsOverlaysProvider = OutfitsOverlaysFamily._();

/// Ephemeral row-level overlays per character (controller state, NOT Drift).
final class OutfitsOverlaysProvider
    extends $NotifierProvider<OutfitsOverlays, List<OutfitRowOverlay>> {
  /// Ephemeral row-level overlays per character (controller state, NOT Drift).
  OutfitsOverlaysProvider._({
    required OutfitsOverlaysFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'outfitsOverlaysProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$outfitsOverlaysHash();

  @override
  String toString() {
    return r'outfitsOverlaysProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  OutfitsOverlays create() => OutfitsOverlays();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<OutfitRowOverlay> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<OutfitRowOverlay>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is OutfitsOverlaysProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$outfitsOverlaysHash() => r'763ab823164e55ed7e9df472b5a9e8b75052a4dc';

/// Ephemeral row-level overlays per character (controller state, NOT Drift).

final class OutfitsOverlaysFamily extends $Family
    with
        $ClassFamilyOverride<
          OutfitsOverlays,
          List<OutfitRowOverlay>,
          List<OutfitRowOverlay>,
          List<OutfitRowOverlay>,
          String
        > {
  OutfitsOverlaysFamily._()
    : super(
        retry: null,
        name: r'outfitsOverlaysProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Ephemeral row-level overlays per character (controller state, NOT Drift).

  OutfitsOverlaysProvider call(String characterId) =>
      OutfitsOverlaysProvider._(argument: characterId, from: this);

  @override
  String toString() => r'outfitsOverlaysProvider';
}

/// Ephemeral row-level overlays per character (controller state, NOT Drift).

abstract class _$OutfitsOverlays extends $Notifier<List<OutfitRowOverlay>> {
  late final _$args = ref.$arg as String;
  String get characterId => _$args;

  List<OutfitRowOverlay> build(String characterId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<List<OutfitRowOverlay>, List<OutfitRowOverlay>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<OutfitRowOverlay>, List<OutfitRowOverlay>>,
              List<OutfitRowOverlay>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Last command failure per character (surfaced keyed on the problem `code`).

@ProviderFor(OutfitsCommandError)
final outfitsCommandErrorProvider = OutfitsCommandErrorFamily._();

/// Last command failure per character (surfaced keyed on the problem `code`).
final class OutfitsCommandErrorProvider
    extends $NotifierProvider<OutfitsCommandError, OutfitCommandFailure?> {
  /// Last command failure per character (surfaced keyed on the problem `code`).
  OutfitsCommandErrorProvider._({
    required OutfitsCommandErrorFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'outfitsCommandErrorProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$outfitsCommandErrorHash();

  @override
  String toString() {
    return r'outfitsCommandErrorProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  OutfitsCommandError create() => OutfitsCommandError();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OutfitCommandFailure? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OutfitCommandFailure?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is OutfitsCommandErrorProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$outfitsCommandErrorHash() =>
    r'029470a1318de553d135091ba8556a1abcf4222b';

/// Last command failure per character (surfaced keyed on the problem `code`).

final class OutfitsCommandErrorFamily extends $Family
    with
        $ClassFamilyOverride<
          OutfitsCommandError,
          OutfitCommandFailure?,
          OutfitCommandFailure?,
          OutfitCommandFailure?,
          String
        > {
  OutfitsCommandErrorFamily._()
    : super(
        retry: null,
        name: r'outfitsCommandErrorProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Last command failure per character (surfaced keyed on the problem `code`).

  OutfitsCommandErrorProvider call(String characterId) =>
      OutfitsCommandErrorProvider._(argument: characterId, from: this);

  @override
  String toString() => r'outfitsCommandErrorProvider';
}

/// Last command failure per character (surfaced keyed on the problem `code`).

abstract class _$OutfitsCommandError extends $Notifier<OutfitCommandFailure?> {
  late final _$args = ref.$arg as String;
  String get characterId => _$args;

  OutfitCommandFailure? build(String characterId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<OutfitCommandFailure?, OutfitCommandFailure?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<OutfitCommandFailure?, OutfitCommandFailure?>,
              OutfitCommandFailure?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// `OutfitsController(characterId)`: one character's look commands with
/// optimistic-after-2xx + bounded-retry reconciliation (version fence).

@ProviderFor(OutfitsController)
final outfitsControllerProvider = OutfitsControllerFamily._();

/// `OutfitsController(characterId)`: one character's look commands with
/// optimistic-after-2xx + bounded-retry reconciliation (version fence).
final class OutfitsControllerProvider
    extends $NotifierProvider<OutfitsController, OutfitsScreenState> {
  /// `OutfitsController(characterId)`: one character's look commands with
  /// optimistic-after-2xx + bounded-retry reconciliation (version fence).
  OutfitsControllerProvider._({
    required OutfitsControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'outfitsControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$outfitsControllerHash();

  @override
  String toString() {
    return r'outfitsControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  OutfitsController create() => OutfitsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OutfitsScreenState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OutfitsScreenState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is OutfitsControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$outfitsControllerHash() => r'7a912c1a55e6d0c7ac11e4dc2c4c3fe6a7384ac2';

/// `OutfitsController(characterId)`: one character's look commands with
/// optimistic-after-2xx + bounded-retry reconciliation (version fence).

final class OutfitsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          OutfitsController,
          OutfitsScreenState,
          OutfitsScreenState,
          OutfitsScreenState,
          String
        > {
  OutfitsControllerFamily._()
    : super(
        retry: null,
        name: r'outfitsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// `OutfitsController(characterId)`: one character's look commands with
  /// optimistic-after-2xx + bounded-retry reconciliation (version fence).

  OutfitsControllerProvider call(String characterId) =>
      OutfitsControllerProvider._(argument: characterId, from: this);

  @override
  String toString() => r'outfitsControllerProvider';
}

/// `OutfitsController(characterId)`: one character's look commands with
/// optimistic-after-2xx + bounded-retry reconciliation (version fence).

abstract class _$OutfitsController extends $Notifier<OutfitsScreenState> {
  late final _$args = ref.$arg as String;
  String get characterId => _$args;

  OutfitsScreenState build(String characterId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<OutfitsScreenState, OutfitsScreenState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<OutfitsScreenState, OutfitsScreenState>,
              OutfitsScreenState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
