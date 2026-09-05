// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scenes_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Scene repository: owns network + Drift cache writes.

@ProviderFor(sceneRepository)
final sceneRepositoryProvider = SceneRepositoryProvider._();

/// Scene repository: owns network + Drift cache writes.

final class SceneRepositoryProvider
    extends
        $FunctionalProvider<SceneRepository, SceneRepository, SceneRepository>
    with $Provider<SceneRepository> {
  /// Scene repository: owns network + Drift cache writes.
  SceneRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sceneRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sceneRepositoryHash();

  @$internal
  @override
  $ProviderElement<SceneRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SceneRepository create(Ref ref) {
    return sceneRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SceneRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SceneRepository>(value),
    );
  }
}

String _$sceneRepositoryHash() => r'8f547f0b5733fb1d7b162ec968f3c15e6025c211';

/// The injected episode-scoped list-fetch seam
/// (`GET /v1/scenes?episode_id=…`). Tests override this provider with a fake.

@ProviderFor(scenesListFetch)
final scenesListFetchProvider = ScenesListFetchFamily._();

/// The injected episode-scoped list-fetch seam
/// (`GET /v1/scenes?episode_id=…`). Tests override this provider with a fake.

final class ScenesListFetchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<List<SceneView>>>,
          Result<List<SceneView>>,
          FutureOr<Result<List<SceneView>>>
        >
    with
        $FutureModifier<Result<List<SceneView>>>,
        $FutureProvider<Result<List<SceneView>>> {
  /// The injected episode-scoped list-fetch seam
  /// (`GET /v1/scenes?episode_id=…`). Tests override this provider with a fake.
  ScenesListFetchProvider._({
    required ScenesListFetchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'scenesListFetchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$scenesListFetchHash();

  @override
  String toString() {
    return r'scenesListFetchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<List<SceneView>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<List<SceneView>>> create(Ref ref) {
    final argument = this.argument as String;
    return scenesListFetch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ScenesListFetchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$scenesListFetchHash() => r'a2b07008a943a6c55b86c69169cbd0de31648ef3';

/// The injected episode-scoped list-fetch seam
/// (`GET /v1/scenes?episode_id=…`). Tests override this provider with a fake.

final class ScenesListFetchFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Result<List<SceneView>>>, String> {
  ScenesListFetchFamily._()
    : super(
        retry: null,
        name: r'scenesListFetchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The injected episode-scoped list-fetch seam
  /// (`GET /v1/scenes?episode_id=…`). Tests override this provider with a fake.

  ScenesListFetchProvider call(String episodeId) =>
      ScenesListFetchProvider._(argument: episodeId, from: this);

  @override
  String toString() => r'scenesListFetchProvider';
}

/// Retained last-good snapshot per episode.

@ProviderFor(ScenesPrevRows)
final scenesPrevRowsProvider = ScenesPrevRowsFamily._();

/// Retained last-good snapshot per episode.
final class ScenesPrevRowsProvider
    extends $NotifierProvider<ScenesPrevRows, List<SceneView>> {
  /// Retained last-good snapshot per episode.
  ScenesPrevRowsProvider._({
    required ScenesPrevRowsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'scenesPrevRowsProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$scenesPrevRowsHash();

  @override
  String toString() {
    return r'scenesPrevRowsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ScenesPrevRows create() => ScenesPrevRows();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<SceneView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<SceneView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ScenesPrevRowsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$scenesPrevRowsHash() => r'ae5fabb7e7556761726c19bac9e7bfe11d79c4e4';

/// Retained last-good snapshot per episode.

final class ScenesPrevRowsFamily extends $Family
    with
        $ClassFamilyOverride<
          ScenesPrevRows,
          List<SceneView>,
          List<SceneView>,
          List<SceneView>,
          String
        > {
  ScenesPrevRowsFamily._()
    : super(
        retry: null,
        name: r'scenesPrevRowsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Retained last-good snapshot per episode.

  ScenesPrevRowsProvider call(String episodeId) =>
      ScenesPrevRowsProvider._(argument: episodeId, from: this);

  @override
  String toString() => r'scenesPrevRowsProvider';
}

/// Retained last-good snapshot per episode.

abstract class _$ScenesPrevRows extends $Notifier<List<SceneView>> {
  late final _$args = ref.$arg as String;
  String get episodeId => _$args;

  List<SceneView> build(String episodeId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<SceneView>, List<SceneView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<SceneView>, List<SceneView>>,
              List<SceneView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Read-projection controller.
///
/// Maps the injected fetch `Result` into an `AsyncValue<ScenesView>` and
/// seeds the retained snapshot from the cache FIRST (offline cold start).
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [ScenesPrevRows]. Consumers read through
/// [scenesViewProvider].

@ProviderFor(ScenesViewController)
final scenesViewControllerProvider = ScenesViewControllerFamily._();

/// Read-projection controller.
///
/// Maps the injected fetch `Result` into an `AsyncValue<ScenesView>` and
/// seeds the retained snapshot from the cache FIRST (offline cold start).
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [ScenesPrevRows]. Consumers read through
/// [scenesViewProvider].
final class ScenesViewControllerProvider
    extends $NotifierProvider<ScenesViewController, AsyncValue<ScenesView>> {
  /// Read-projection controller.
  ///
  /// Maps the injected fetch `Result` into an `AsyncValue<ScenesView>` and
  /// seeds the retained snapshot from the cache FIRST (offline cold start).
  ///
  /// Loop discipline (reference pattern): this seeder watches the repository
  /// and the fetch ONLY — never [ScenesPrevRows]. Consumers read through
  /// [scenesViewProvider].
  ScenesViewControllerProvider._({
    required ScenesViewControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'scenesViewControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$scenesViewControllerHash();

  @override
  String toString() {
    return r'scenesViewControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ScenesViewController create() => ScenesViewController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<ScenesView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<ScenesView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ScenesViewControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$scenesViewControllerHash() =>
    r'eb674370b999377c50ec57ef1fabce5704b98e1b';

/// Read-projection controller.
///
/// Maps the injected fetch `Result` into an `AsyncValue<ScenesView>` and
/// seeds the retained snapshot from the cache FIRST (offline cold start).
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [ScenesPrevRows]. Consumers read through
/// [scenesViewProvider].

final class ScenesViewControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ScenesViewController,
          AsyncValue<ScenesView>,
          AsyncValue<ScenesView>,
          AsyncValue<ScenesView>,
          String
        > {
  ScenesViewControllerFamily._()
    : super(
        retry: null,
        name: r'scenesViewControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Read-projection controller.
  ///
  /// Maps the injected fetch `Result` into an `AsyncValue<ScenesView>` and
  /// seeds the retained snapshot from the cache FIRST (offline cold start).
  ///
  /// Loop discipline (reference pattern): this seeder watches the repository
  /// and the fetch ONLY — never [ScenesPrevRows]. Consumers read through
  /// [scenesViewProvider].

  ScenesViewControllerProvider call(String episodeId) =>
      ScenesViewControllerProvider._(argument: episodeId, from: this);

  @override
  String toString() => r'scenesViewControllerProvider';
}

/// Read-projection controller.
///
/// Maps the injected fetch `Result` into an `AsyncValue<ScenesView>` and
/// seeds the retained snapshot from the cache FIRST (offline cold start).
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [ScenesPrevRows]. Consumers read through
/// [scenesViewProvider].

abstract class _$ScenesViewController
    extends $Notifier<AsyncValue<ScenesView>> {
  late final _$args = ref.$arg as String;
  String get episodeId => _$args;

  AsyncValue<ScenesView> build(String episodeId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<ScenesView>, AsyncValue<ScenesView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ScenesView>, AsyncValue<ScenesView>>,
              AsyncValue<ScenesView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// The projection a screen reads (selector).

@ProviderFor(scenesView)
final scenesViewProvider = ScenesViewFamily._();

/// The projection a screen reads (selector).

final class ScenesViewProvider
    extends $FunctionalProvider<ScenesView, ScenesView, ScenesView>
    with $Provider<ScenesView> {
  /// The projection a screen reads (selector).
  ScenesViewProvider._({
    required ScenesViewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'scenesViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$scenesViewHash();

  @override
  String toString() {
    return r'scenesViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<ScenesView> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ScenesView create(Ref ref) {
    final argument = this.argument as String;
    return scenesView(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ScenesView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ScenesView>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ScenesViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$scenesViewHash() => r'b1e33ffbdbce2501e6aec640866929c530a22d0e';

/// The projection a screen reads (selector).

final class ScenesViewFamily extends $Family
    with $FunctionalFamilyOverride<ScenesView, String> {
  ScenesViewFamily._()
    : super(
        retry: null,
        name: r'scenesViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The projection a screen reads (selector).

  ScenesViewProvider call(String episodeId) =>
      ScenesViewProvider._(argument: episodeId, from: this);

  @override
  String toString() => r'scenesViewProvider';
}

/// Ephemeral optimistic overlay store per episode (controller state, NOT
/// Drift — no global overlay store).

@ProviderFor(ScenesOverlays)
final scenesOverlaysProvider = ScenesOverlaysFamily._();

/// Ephemeral optimistic overlay store per episode (controller state, NOT
/// Drift — no global overlay store).
final class ScenesOverlaysProvider
    extends $NotifierProvider<ScenesOverlays, List<SceneOverlay>> {
  /// Ephemeral optimistic overlay store per episode (controller state, NOT
  /// Drift — no global overlay store).
  ScenesOverlaysProvider._({
    required ScenesOverlaysFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'scenesOverlaysProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$scenesOverlaysHash();

  @override
  String toString() {
    return r'scenesOverlaysProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ScenesOverlays create() => ScenesOverlays();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<SceneOverlay> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<SceneOverlay>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ScenesOverlaysProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$scenesOverlaysHash() => r'9e15f7c259db20395069882c519375f3d34fb1e8';

/// Ephemeral optimistic overlay store per episode (controller state, NOT
/// Drift — no global overlay store).

final class ScenesOverlaysFamily extends $Family
    with
        $ClassFamilyOverride<
          ScenesOverlays,
          List<SceneOverlay>,
          List<SceneOverlay>,
          List<SceneOverlay>,
          String
        > {
  ScenesOverlaysFamily._()
    : super(
        retry: null,
        name: r'scenesOverlaysProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Ephemeral optimistic overlay store per episode (controller state, NOT
  /// Drift — no global overlay store).

  ScenesOverlaysProvider call(String episodeId) =>
      ScenesOverlaysProvider._(argument: episodeId, from: this);

  @override
  String toString() => r'scenesOverlaysProvider';
}

/// Ephemeral optimistic overlay store per episode (controller state, NOT
/// Drift — no global overlay store).

abstract class _$ScenesOverlays extends $Notifier<List<SceneOverlay>> {
  late final _$args = ref.$arg as String;
  String get episodeId => _$args;

  List<SceneOverlay> build(String episodeId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<SceneOverlay>, List<SceneOverlay>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<SceneOverlay>, List<SceneOverlay>>,
              List<SceneOverlay>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Last command failure per episode, surfaced to the screen keyed on `code`.

@ProviderFor(ScenesCommandError)
final scenesCommandErrorProvider = ScenesCommandErrorFamily._();

/// Last command failure per episode, surfaced to the screen keyed on `code`.
final class ScenesCommandErrorProvider
    extends $NotifierProvider<ScenesCommandError, ProblemError?> {
  /// Last command failure per episode, surfaced to the screen keyed on `code`.
  ScenesCommandErrorProvider._({
    required ScenesCommandErrorFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'scenesCommandErrorProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$scenesCommandErrorHash();

  @override
  String toString() {
    return r'scenesCommandErrorProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ScenesCommandError create() => ScenesCommandError();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProblemError? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProblemError?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ScenesCommandErrorProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$scenesCommandErrorHash() =>
    r'cca78e6b31a078a921512f1bd52e2c3398723e07';

/// Last command failure per episode, surfaced to the screen keyed on `code`.

final class ScenesCommandErrorFamily extends $Family
    with
        $ClassFamilyOverride<
          ScenesCommandError,
          ProblemError?,
          ProblemError?,
          ProblemError?,
          String
        > {
  ScenesCommandErrorFamily._()
    : super(
        retry: null,
        name: r'scenesCommandErrorProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Last command failure per episode, surfaced to the screen keyed on `code`.

  ScenesCommandErrorProvider call(String episodeId) =>
      ScenesCommandErrorProvider._(argument: episodeId, from: this);

  @override
  String toString() => r'scenesCommandErrorProvider';
}

/// Last command failure per episode, surfaced to the screen keyed on `code`.

abstract class _$ScenesCommandError extends $Notifier<ProblemError?> {
  late final _$args = ref.$arg as String;
  String get episodeId => _$args;

  ProblemError? build(String episodeId);
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

/// `ScenesController(episodeId)` on the shared reconciliation runner.

@ProviderFor(ScenesController)
final scenesControllerProvider = ScenesControllerFamily._();

/// `ScenesController(episodeId)` on the shared reconciliation runner.
final class ScenesControllerProvider
    extends $NotifierProvider<ScenesController, ScenesScreenState> {
  /// `ScenesController(episodeId)` on the shared reconciliation runner.
  ScenesControllerProvider._({
    required ScenesControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'scenesControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$scenesControllerHash();

  @override
  String toString() {
    return r'scenesControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ScenesController create() => ScenesController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ScenesScreenState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ScenesScreenState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ScenesControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$scenesControllerHash() => r'b98322b99e6a3cf97308ec58c69b9a838a8a34fe';

/// `ScenesController(episodeId)` on the shared reconciliation runner.

final class ScenesControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ScenesController,
          ScenesScreenState,
          ScenesScreenState,
          ScenesScreenState,
          String
        > {
  ScenesControllerFamily._()
    : super(
        retry: null,
        name: r'scenesControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// `ScenesController(episodeId)` on the shared reconciliation runner.

  ScenesControllerProvider call(String episodeId) =>
      ScenesControllerProvider._(argument: episodeId, from: this);

  @override
  String toString() => r'scenesControllerProvider';
}

/// `ScenesController(episodeId)` on the shared reconciliation runner.

abstract class _$ScenesController extends $Notifier<ScenesScreenState> {
  late final _$args = ref.$arg as String;
  String get episodeId => _$args;

  ScenesScreenState build(String episodeId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ScenesScreenState, ScenesScreenState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ScenesScreenState, ScenesScreenState>,
              ScenesScreenState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
