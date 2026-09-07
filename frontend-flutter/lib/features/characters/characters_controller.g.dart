// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'characters_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Character repository: owns network + Drift cache writes.

@ProviderFor(characterRepository)
final characterRepositoryProvider = CharacterRepositoryProvider._();

/// Character repository: owns network + Drift cache writes.

final class CharacterRepositoryProvider
    extends
        $FunctionalProvider<
          CharacterRepository,
          CharacterRepository,
          CharacterRepository
        >
    with $Provider<CharacterRepository> {
  /// Character repository: owns network + Drift cache writes.
  CharacterRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'characterRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$characterRepositoryHash();

  @$internal
  @override
  $ProviderElement<CharacterRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CharacterRepository create(Ref ref) {
    return characterRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CharacterRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CharacterRepository>(value),
    );
  }
}

String _$characterRepositoryHash() =>
    r'cb13ca6cec105ffbce71970df456f39277b58190';

/// The injected season-scoped list-fetch seam
/// (`GET /v1/characters?season_id=…`). Tests override this provider with a
/// fake.

@ProviderFor(charactersListFetch)
final charactersListFetchProvider = CharactersListFetchFamily._();

/// The injected season-scoped list-fetch seam
/// (`GET /v1/characters?season_id=…`). Tests override this provider with a
/// fake.

final class CharactersListFetchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<List<CharacterView>>>,
          Result<List<CharacterView>>,
          FutureOr<Result<List<CharacterView>>>
        >
    with
        $FutureModifier<Result<List<CharacterView>>>,
        $FutureProvider<Result<List<CharacterView>>> {
  /// The injected season-scoped list-fetch seam
  /// (`GET /v1/characters?season_id=…`). Tests override this provider with a
  /// fake.
  CharactersListFetchProvider._({
    required CharactersListFetchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'charactersListFetchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$charactersListFetchHash();

  @override
  String toString() {
    return r'charactersListFetchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<List<CharacterView>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<List<CharacterView>>> create(Ref ref) {
    final argument = this.argument as String;
    return charactersListFetch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CharactersListFetchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$charactersListFetchHash() =>
    r'6ae69e32f3b8ac4134b2f2e7685ecca04f04707f';

/// The injected season-scoped list-fetch seam
/// (`GET /v1/characters?season_id=…`). Tests override this provider with a
/// fake.

final class CharactersListFetchFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Result<List<CharacterView>>>,
          String
        > {
  CharactersListFetchFamily._()
    : super(
        retry: null,
        name: r'charactersListFetchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The injected season-scoped list-fetch seam
  /// (`GET /v1/characters?season_id=…`). Tests override this provider with a
  /// fake.

  CharactersListFetchProvider call(String seasonId) =>
      CharactersListFetchProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'charactersListFetchProvider';
}

/// Retained last-good snapshot per season.

@ProviderFor(CharactersPrevRows)
final charactersPrevRowsProvider = CharactersPrevRowsFamily._();

/// Retained last-good snapshot per season.
final class CharactersPrevRowsProvider
    extends $NotifierProvider<CharactersPrevRows, List<CharacterView>> {
  /// Retained last-good snapshot per season.
  CharactersPrevRowsProvider._({
    required CharactersPrevRowsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'charactersPrevRowsProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$charactersPrevRowsHash();

  @override
  String toString() {
    return r'charactersPrevRowsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CharactersPrevRows create() => CharactersPrevRows();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<CharacterView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<CharacterView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CharactersPrevRowsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$charactersPrevRowsHash() =>
    r'c570601287967dd3ebf6111f8152cc1b5121580e';

/// Retained last-good snapshot per season.

final class CharactersPrevRowsFamily extends $Family
    with
        $ClassFamilyOverride<
          CharactersPrevRows,
          List<CharacterView>,
          List<CharacterView>,
          List<CharacterView>,
          String
        > {
  CharactersPrevRowsFamily._()
    : super(
        retry: null,
        name: r'charactersPrevRowsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Retained last-good snapshot per season.

  CharactersPrevRowsProvider call(String seasonId) =>
      CharactersPrevRowsProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'charactersPrevRowsProvider';
}

/// Retained last-good snapshot per season.

abstract class _$CharactersPrevRows extends $Notifier<List<CharacterView>> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  List<CharacterView> build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<CharacterView>, List<CharacterView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<CharacterView>, List<CharacterView>>,
              List<CharacterView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Read-projection controller (seeder watches repository + fetch only).

@ProviderFor(CharactersViewController)
final charactersViewControllerProvider = CharactersViewControllerFamily._();

/// Read-projection controller (seeder watches repository + fetch only).
final class CharactersViewControllerProvider
    extends
        $NotifierProvider<
          CharactersViewController,
          AsyncValue<CharactersView>
        > {
  /// Read-projection controller (seeder watches repository + fetch only).
  CharactersViewControllerProvider._({
    required CharactersViewControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'charactersViewControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$charactersViewControllerHash();

  @override
  String toString() {
    return r'charactersViewControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CharactersViewController create() => CharactersViewController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<CharactersView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<CharactersView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CharactersViewControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$charactersViewControllerHash() =>
    r'e4db6e8defcb09039076cd8c2ca1ad51f45dfb45';

/// Read-projection controller (seeder watches repository + fetch only).

final class CharactersViewControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          CharactersViewController,
          AsyncValue<CharactersView>,
          AsyncValue<CharactersView>,
          AsyncValue<CharactersView>,
          String
        > {
  CharactersViewControllerFamily._()
    : super(
        retry: null,
        name: r'charactersViewControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Read-projection controller (seeder watches repository + fetch only).

  CharactersViewControllerProvider call(String seasonId) =>
      CharactersViewControllerProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'charactersViewControllerProvider';
}

/// Read-projection controller (seeder watches repository + fetch only).

abstract class _$CharactersViewController
    extends $Notifier<AsyncValue<CharactersView>> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  AsyncValue<CharactersView> build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<CharactersView>, AsyncValue<CharactersView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<CharactersView>,
                AsyncValue<CharactersView>
              >,
              AsyncValue<CharactersView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// TTL-based cache staleness for one season's characters (issue #366).

@ProviderFor(charactersCacheStale)
final charactersCacheStaleProvider = CharactersCacheStaleFamily._();

/// TTL-based cache staleness for one season's characters (issue #366).

final class CharactersCacheStaleProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// TTL-based cache staleness for one season's characters (issue #366).
  CharactersCacheStaleProvider._({
    required CharactersCacheStaleFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'charactersCacheStaleProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$charactersCacheStaleHash();

  @override
  String toString() {
    return r'charactersCacheStaleProvider'
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
    return charactersCacheStale(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CharactersCacheStaleProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$charactersCacheStaleHash() =>
    r'dda50d17f8dbe5724ebd9febf20d9352e4477837';

/// TTL-based cache staleness for one season's characters (issue #366).

final class CharactersCacheStaleFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, String> {
  CharactersCacheStaleFamily._()
    : super(
        retry: null,
        name: r'charactersCacheStaleProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// TTL-based cache staleness for one season's characters (issue #366).

  CharactersCacheStaleProvider call(String seasonId) =>
      CharactersCacheStaleProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'charactersCacheStaleProvider';
}

/// The projection a screen reads (selector).

@ProviderFor(charactersView)
final charactersViewProvider = CharactersViewFamily._();

/// The projection a screen reads (selector).

final class CharactersViewProvider
    extends $FunctionalProvider<CharactersView, CharactersView, CharactersView>
    with $Provider<CharactersView> {
  /// The projection a screen reads (selector).
  CharactersViewProvider._({
    required CharactersViewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'charactersViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$charactersViewHash();

  @override
  String toString() {
    return r'charactersViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<CharactersView> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CharactersView create(Ref ref) {
    final argument = this.argument as String;
    return charactersView(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CharactersView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CharactersView>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CharactersViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$charactersViewHash() => r'a312eacd455cfb07c9b8d13c72eb780ad82e2b73';

/// The projection a screen reads (selector).

final class CharactersViewFamily extends $Family
    with $FunctionalFamilyOverride<CharactersView, String> {
  CharactersViewFamily._()
    : super(
        retry: null,
        name: r'charactersViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The projection a screen reads (selector).

  CharactersViewProvider call(String seasonId) =>
      CharactersViewProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'charactersViewProvider';
}

/// Ephemeral optimistic overlay store per season (controller state, NOT
/// Drift — no global overlay store).

@ProviderFor(CharactersOverlays)
final charactersOverlaysProvider = CharactersOverlaysFamily._();

/// Ephemeral optimistic overlay store per season (controller state, NOT
/// Drift — no global overlay store).
final class CharactersOverlaysProvider
    extends $NotifierProvider<CharactersOverlays, List<CharacterOverlay>> {
  /// Ephemeral optimistic overlay store per season (controller state, NOT
  /// Drift — no global overlay store).
  CharactersOverlaysProvider._({
    required CharactersOverlaysFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'charactersOverlaysProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$charactersOverlaysHash();

  @override
  String toString() {
    return r'charactersOverlaysProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CharactersOverlays create() => CharactersOverlays();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<CharacterOverlay> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<CharacterOverlay>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CharactersOverlaysProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$charactersOverlaysHash() =>
    r'f5fa781c65e269746ac932a94b645f2cd6480e7a';

/// Ephemeral optimistic overlay store per season (controller state, NOT
/// Drift — no global overlay store).

final class CharactersOverlaysFamily extends $Family
    with
        $ClassFamilyOverride<
          CharactersOverlays,
          List<CharacterOverlay>,
          List<CharacterOverlay>,
          List<CharacterOverlay>,
          String
        > {
  CharactersOverlaysFamily._()
    : super(
        retry: null,
        name: r'charactersOverlaysProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Ephemeral optimistic overlay store per season (controller state, NOT
  /// Drift — no global overlay store).

  CharactersOverlaysProvider call(String seasonId) =>
      CharactersOverlaysProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'charactersOverlaysProvider';
}

/// Ephemeral optimistic overlay store per season (controller state, NOT
/// Drift — no global overlay store).

abstract class _$CharactersOverlays extends $Notifier<List<CharacterOverlay>> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  List<CharacterOverlay> build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<List<CharacterOverlay>, List<CharacterOverlay>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<CharacterOverlay>, List<CharacterOverlay>>,
              List<CharacterOverlay>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Last command failure per season, surfaced to the screen keyed on `code`.

@ProviderFor(CharactersCommandError)
final charactersCommandErrorProvider = CharactersCommandErrorFamily._();

/// Last command failure per season, surfaced to the screen keyed on `code`.
final class CharactersCommandErrorProvider
    extends $NotifierProvider<CharactersCommandError, ProblemError?> {
  /// Last command failure per season, surfaced to the screen keyed on `code`.
  CharactersCommandErrorProvider._({
    required CharactersCommandErrorFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'charactersCommandErrorProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$charactersCommandErrorHash();

  @override
  String toString() {
    return r'charactersCommandErrorProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CharactersCommandError create() => CharactersCommandError();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProblemError? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProblemError?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CharactersCommandErrorProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$charactersCommandErrorHash() =>
    r'180c836b7ce275261879c0b148470c9d4a5b1c92';

/// Last command failure per season, surfaced to the screen keyed on `code`.

final class CharactersCommandErrorFamily extends $Family
    with
        $ClassFamilyOverride<
          CharactersCommandError,
          ProblemError?,
          ProblemError?,
          ProblemError?,
          String
        > {
  CharactersCommandErrorFamily._()
    : super(
        retry: null,
        name: r'charactersCommandErrorProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Last command failure per season, surfaced to the screen keyed on `code`.

  CharactersCommandErrorProvider call(String seasonId) =>
      CharactersCommandErrorProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'charactersCommandErrorProvider';
}

/// Last command failure per season, surfaced to the screen keyed on `code`.

abstract class _$CharactersCommandError extends $Notifier<ProblemError?> {
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

/// `CharactersController(seasonId)` on the shared reconciliation runner:
/// create follows the optimistic-overlay pattern; contact/measurements are
/// full-replacement PATCH editors (prefilled, version echo, 409 → keyed
/// copy, never auto-bump).

@ProviderFor(CharactersController)
final charactersControllerProvider = CharactersControllerFamily._();

/// `CharactersController(seasonId)` on the shared reconciliation runner:
/// create follows the optimistic-overlay pattern; contact/measurements are
/// full-replacement PATCH editors (prefilled, version echo, 409 → keyed
/// copy, never auto-bump).
final class CharactersControllerProvider
    extends $NotifierProvider<CharactersController, CharactersScreenState> {
  /// `CharactersController(seasonId)` on the shared reconciliation runner:
  /// create follows the optimistic-overlay pattern; contact/measurements are
  /// full-replacement PATCH editors (prefilled, version echo, 409 → keyed
  /// copy, never auto-bump).
  CharactersControllerProvider._({
    required CharactersControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'charactersControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$charactersControllerHash();

  @override
  String toString() {
    return r'charactersControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CharactersController create() => CharactersController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CharactersScreenState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CharactersScreenState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CharactersControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$charactersControllerHash() =>
    r'111f4352f6f7011283ba1abd91505e0695e99331';

/// `CharactersController(seasonId)` on the shared reconciliation runner:
/// create follows the optimistic-overlay pattern; contact/measurements are
/// full-replacement PATCH editors (prefilled, version echo, 409 → keyed
/// copy, never auto-bump).

final class CharactersControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          CharactersController,
          CharactersScreenState,
          CharactersScreenState,
          CharactersScreenState,
          String
        > {
  CharactersControllerFamily._()
    : super(
        retry: null,
        name: r'charactersControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// `CharactersController(seasonId)` on the shared reconciliation runner:
  /// create follows the optimistic-overlay pattern; contact/measurements are
  /// full-replacement PATCH editors (prefilled, version echo, 409 → keyed
  /// copy, never auto-bump).

  CharactersControllerProvider call(String seasonId) =>
      CharactersControllerProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'charactersControllerProvider';
}

/// `CharactersController(seasonId)` on the shared reconciliation runner:
/// create follows the optimistic-overlay pattern; contact/measurements are
/// full-replacement PATCH editors (prefilled, version echo, 409 → keyed
/// copy, never auto-bump).

abstract class _$CharactersController extends $Notifier<CharactersScreenState> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  CharactersScreenState build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<CharactersScreenState, CharactersScreenState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CharactersScreenState, CharactersScreenState>,
              CharactersScreenState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
