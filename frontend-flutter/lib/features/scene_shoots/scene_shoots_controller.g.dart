// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scene_shoots_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Scene-shoot repository: owns network + Drift cache writes.

@ProviderFor(sceneShootRepository)
final sceneShootRepositoryProvider = SceneShootRepositoryProvider._();

/// Scene-shoot repository: owns network + Drift cache writes.

final class SceneShootRepositoryProvider
    extends
        $FunctionalProvider<
          SceneShootRepository,
          SceneShootRepository,
          SceneShootRepository
        >
    with $Provider<SceneShootRepository> {
  /// Scene-shoot repository: owns network + Drift cache writes.
  SceneShootRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sceneShootRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sceneShootRepositoryHash();

  @$internal
  @override
  $ProviderElement<SceneShootRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SceneShootRepository create(Ref ref) {
    return sceneShootRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SceneShootRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SceneShootRepository>(value),
    );
  }
}

String _$sceneShootRepositoryHash() =>
    r'6cc95feedbbcc0faa9cb880a75d4f44b8ebd702a';

/// The injected day-board list-fetch seam
/// (`GET /v1/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots`; the
/// backend lists by day in `COALESCE(actual_order, planned_order) ASC`).
/// Tests override this provider with a fake.

@ProviderFor(sceneShootsListFetch)
final sceneShootsListFetchProvider = SceneShootsListFetchFamily._();

/// The injected day-board list-fetch seam
/// (`GET /v1/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots`; the
/// backend lists by day in `COALESCE(actual_order, planned_order) ASC`).
/// Tests override this provider with a fake.

final class SceneShootsListFetchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<List<SceneShootView>>>,
          Result<List<SceneShootView>>,
          FutureOr<Result<List<SceneShootView>>>
        >
    with
        $FutureModifier<Result<List<SceneShootView>>>,
        $FutureProvider<Result<List<SceneShootView>>> {
  /// The injected day-board list-fetch seam
  /// (`GET /v1/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots`; the
  /// backend lists by day in `COALESCE(actual_order, planned_order) ASC`).
  /// Tests override this provider with a fake.
  SceneShootsListFetchProvider._({
    required SceneShootsListFetchFamily super.from,
    required SceneShootDayScope super.argument,
  }) : super(
         retry: null,
         name: r'sceneShootsListFetchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sceneShootsListFetchHash();

  @override
  String toString() {
    return r'sceneShootsListFetchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<List<SceneShootView>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<List<SceneShootView>>> create(Ref ref) {
    final argument = this.argument as SceneShootDayScope;
    return sceneShootsListFetch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SceneShootsListFetchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sceneShootsListFetchHash() =>
    r'23c446574ce1b33e3003758cf051aedc26d71033';

/// The injected day-board list-fetch seam
/// (`GET /v1/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots`; the
/// backend lists by day in `COALESCE(actual_order, planned_order) ASC`).
/// Tests override this provider with a fake.

final class SceneShootsListFetchFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Result<List<SceneShootView>>>,
          SceneShootDayScope
        > {
  SceneShootsListFetchFamily._()
    : super(
        retry: null,
        name: r'sceneShootsListFetchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The injected day-board list-fetch seam
  /// (`GET /v1/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots`; the
  /// backend lists by day in `COALESCE(actual_order, planned_order) ASC`).
  /// Tests override this provider with a fake.

  SceneShootsListFetchProvider call(SceneShootDayScope scope) =>
      SceneShootsListFetchProvider._(argument: scope, from: this);

  @override
  String toString() => r'sceneShootsListFetchProvider';
}

/// Retained last-good snapshot per day (server order).

@ProviderFor(SceneShootsPrevRows)
final sceneShootsPrevRowsProvider = SceneShootsPrevRowsFamily._();

/// Retained last-good snapshot per day (server order).
final class SceneShootsPrevRowsProvider
    extends $NotifierProvider<SceneShootsPrevRows, List<SceneShootView>> {
  /// Retained last-good snapshot per day (server order).
  SceneShootsPrevRowsProvider._({
    required SceneShootsPrevRowsFamily super.from,
    required SceneShootDayScope super.argument,
  }) : super(
         retry: null,
         name: r'sceneShootsPrevRowsProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sceneShootsPrevRowsHash();

  @override
  String toString() {
    return r'sceneShootsPrevRowsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SceneShootsPrevRows create() => SceneShootsPrevRows();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<SceneShootView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<SceneShootView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SceneShootsPrevRowsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sceneShootsPrevRowsHash() =>
    r'2f4e54372d079d5b1fe3b7326de36881d4514a35';

/// Retained last-good snapshot per day (server order).

final class SceneShootsPrevRowsFamily extends $Family
    with
        $ClassFamilyOverride<
          SceneShootsPrevRows,
          List<SceneShootView>,
          List<SceneShootView>,
          List<SceneShootView>,
          SceneShootDayScope
        > {
  SceneShootsPrevRowsFamily._()
    : super(
        retry: null,
        name: r'sceneShootsPrevRowsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Retained last-good snapshot per day (server order).

  SceneShootsPrevRowsProvider call(SceneShootDayScope scope) =>
      SceneShootsPrevRowsProvider._(argument: scope, from: this);

  @override
  String toString() => r'sceneShootsPrevRowsProvider';
}

/// Retained last-good snapshot per day (server order).

abstract class _$SceneShootsPrevRows extends $Notifier<List<SceneShootView>> {
  late final _$args = ref.$arg as SceneShootDayScope;
  SceneShootDayScope get scope => _$args;

  List<SceneShootView> build(SceneShootDayScope scope);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<SceneShootView>, List<SceneShootView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<SceneShootView>, List<SceneShootView>>,
              List<SceneShootView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Read-projection controller (seeder watches repository + fetch only).

@ProviderFor(SceneShootsViewController)
final sceneShootsViewControllerProvider = SceneShootsViewControllerFamily._();

/// Read-projection controller (seeder watches repository + fetch only).
final class SceneShootsViewControllerProvider
    extends
        $NotifierProvider<
          SceneShootsViewController,
          AsyncValue<SceneShootsView>
        > {
  /// Read-projection controller (seeder watches repository + fetch only).
  SceneShootsViewControllerProvider._({
    required SceneShootsViewControllerFamily super.from,
    required SceneShootDayScope super.argument,
  }) : super(
         retry: null,
         name: r'sceneShootsViewControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sceneShootsViewControllerHash();

  @override
  String toString() {
    return r'sceneShootsViewControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SceneShootsViewController create() => SceneShootsViewController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<SceneShootsView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<SceneShootsView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SceneShootsViewControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sceneShootsViewControllerHash() =>
    r'850fee4cbe77e05b2e6df17e69914db65eb251c3';

/// Read-projection controller (seeder watches repository + fetch only).

final class SceneShootsViewControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SceneShootsViewController,
          AsyncValue<SceneShootsView>,
          AsyncValue<SceneShootsView>,
          AsyncValue<SceneShootsView>,
          SceneShootDayScope
        > {
  SceneShootsViewControllerFamily._()
    : super(
        retry: null,
        name: r'sceneShootsViewControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Read-projection controller (seeder watches repository + fetch only).

  SceneShootsViewControllerProvider call(SceneShootDayScope scope) =>
      SceneShootsViewControllerProvider._(argument: scope, from: this);

  @override
  String toString() => r'sceneShootsViewControllerProvider';
}

/// Read-projection controller (seeder watches repository + fetch only).

abstract class _$SceneShootsViewController
    extends $Notifier<AsyncValue<SceneShootsView>> {
  late final _$args = ref.$arg as SceneShootDayScope;
  SceneShootDayScope get scope => _$args;

  AsyncValue<SceneShootsView> build(SceneShootDayScope scope);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<SceneShootsView>, AsyncValue<SceneShootsView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<SceneShootsView>,
                AsyncValue<SceneShootsView>
              >,
              AsyncValue<SceneShootsView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// TTL-based cache staleness for one day's shoots (issue #366).

@ProviderFor(sceneShootsCacheStale)
final sceneShootsCacheStaleProvider = SceneShootsCacheStaleFamily._();

/// TTL-based cache staleness for one day's shoots (issue #366).

final class SceneShootsCacheStaleProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// TTL-based cache staleness for one day's shoots (issue #366).
  SceneShootsCacheStaleProvider._({
    required SceneShootsCacheStaleFamily super.from,
    required SceneShootDayScope super.argument,
  }) : super(
         retry: null,
         name: r'sceneShootsCacheStaleProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sceneShootsCacheStaleHash();

  @override
  String toString() {
    return r'sceneShootsCacheStaleProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    final argument = this.argument as SceneShootDayScope;
    return sceneShootsCacheStale(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SceneShootsCacheStaleProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sceneShootsCacheStaleHash() =>
    r'c63c7a71bb161b0b944d9061001891d7d0fdc0ab';

/// TTL-based cache staleness for one day's shoots (issue #366).

final class SceneShootsCacheStaleFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, SceneShootDayScope> {
  SceneShootsCacheStaleFamily._()
    : super(
        retry: null,
        name: r'sceneShootsCacheStaleProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// TTL-based cache staleness for one day's shoots (issue #366).

  SceneShootsCacheStaleProvider call(SceneShootDayScope scope) =>
      SceneShootsCacheStaleProvider._(argument: scope, from: this);

  @override
  String toString() => r'sceneShootsCacheStaleProvider';
}

/// The projection a screen reads (selector).

@ProviderFor(sceneShootsView)
final sceneShootsViewProvider = SceneShootsViewFamily._();

/// The projection a screen reads (selector).

final class SceneShootsViewProvider
    extends
        $FunctionalProvider<SceneShootsView, SceneShootsView, SceneShootsView>
    with $Provider<SceneShootsView> {
  /// The projection a screen reads (selector).
  SceneShootsViewProvider._({
    required SceneShootsViewFamily super.from,
    required SceneShootDayScope super.argument,
  }) : super(
         retry: null,
         name: r'sceneShootsViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sceneShootsViewHash();

  @override
  String toString() {
    return r'sceneShootsViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<SceneShootsView> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SceneShootsView create(Ref ref) {
    final argument = this.argument as SceneShootDayScope;
    return sceneShootsView(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SceneShootsView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SceneShootsView>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SceneShootsViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sceneShootsViewHash() => r'751d9d58f0ad5b3f7573c0c0c27b80a2bc19f219';

/// The projection a screen reads (selector).

final class SceneShootsViewFamily extends $Family
    with $FunctionalFamilyOverride<SceneShootsView, SceneShootDayScope> {
  SceneShootsViewFamily._()
    : super(
        retry: null,
        name: r'sceneShootsViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The projection a screen reads (selector).

  SceneShootsViewProvider call(SceneShootDayScope scope) =>
      SceneShootsViewProvider._(argument: scope, from: this);

  @override
  String toString() => r'sceneShootsViewProvider';
}

/// Ephemeral row-level optimistic overlays per day (controller state,
/// NOT Drift). Entries clear by the version fence during the projection
/// refetch — never by projected id (a row-level edit keeps its id).

@ProviderFor(SceneShootsOverlays)
final sceneShootsOverlaysProvider = SceneShootsOverlaysFamily._();

/// Ephemeral row-level optimistic overlays per day (controller state,
/// NOT Drift). Entries clear by the version fence during the projection
/// refetch — never by projected id (a row-level edit keeps its id).
final class SceneShootsOverlaysProvider
    extends $NotifierProvider<SceneShootsOverlays, List<SceneShootRowOverlay>> {
  /// Ephemeral row-level optimistic overlays per day (controller state,
  /// NOT Drift). Entries clear by the version fence during the projection
  /// refetch — never by projected id (a row-level edit keeps its id).
  SceneShootsOverlaysProvider._({
    required SceneShootsOverlaysFamily super.from,
    required SceneShootDayScope super.argument,
  }) : super(
         retry: null,
         name: r'sceneShootsOverlaysProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sceneShootsOverlaysHash();

  @override
  String toString() {
    return r'sceneShootsOverlaysProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SceneShootsOverlays create() => SceneShootsOverlays();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<SceneShootRowOverlay> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<SceneShootRowOverlay>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SceneShootsOverlaysProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sceneShootsOverlaysHash() =>
    r'42bc017ee682b791e183a50e42f5a301a4966e1e';

/// Ephemeral row-level optimistic overlays per day (controller state,
/// NOT Drift). Entries clear by the version fence during the projection
/// refetch — never by projected id (a row-level edit keeps its id).

final class SceneShootsOverlaysFamily extends $Family
    with
        $ClassFamilyOverride<
          SceneShootsOverlays,
          List<SceneShootRowOverlay>,
          List<SceneShootRowOverlay>,
          List<SceneShootRowOverlay>,
          SceneShootDayScope
        > {
  SceneShootsOverlaysFamily._()
    : super(
        retry: null,
        name: r'sceneShootsOverlaysProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Ephemeral row-level optimistic overlays per day (controller state,
  /// NOT Drift). Entries clear by the version fence during the projection
  /// refetch — never by projected id (a row-level edit keeps its id).

  SceneShootsOverlaysProvider call(SceneShootDayScope scope) =>
      SceneShootsOverlaysProvider._(argument: scope, from: this);

  @override
  String toString() => r'sceneShootsOverlaysProvider';
}

/// Ephemeral row-level optimistic overlays per day (controller state,
/// NOT Drift). Entries clear by the version fence during the projection
/// refetch — never by projected id (a row-level edit keeps its id).

abstract class _$SceneShootsOverlays
    extends $Notifier<List<SceneShootRowOverlay>> {
  late final _$args = ref.$arg as SceneShootDayScope;
  SceneShootDayScope get scope => _$args;

  List<SceneShootRowOverlay> build(SceneShootDayScope scope);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<List<SceneShootRowOverlay>, List<SceneShootRowOverlay>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                List<SceneShootRowOverlay>,
                List<SceneShootRowOverlay>
              >,
              List<SceneShootRowOverlay>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Last command failure per day, surfaced to the screen keyed on `code`.

@ProviderFor(SceneShootsCommandError)
final sceneShootsCommandErrorProvider = SceneShootsCommandErrorFamily._();

/// Last command failure per day, surfaced to the screen keyed on `code`.
final class SceneShootsCommandErrorProvider
    extends $NotifierProvider<SceneShootsCommandError, ProblemError?> {
  /// Last command failure per day, surfaced to the screen keyed on `code`.
  SceneShootsCommandErrorProvider._({
    required SceneShootsCommandErrorFamily super.from,
    required SceneShootDayScope super.argument,
  }) : super(
         retry: null,
         name: r'sceneShootsCommandErrorProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sceneShootsCommandErrorHash();

  @override
  String toString() {
    return r'sceneShootsCommandErrorProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SceneShootsCommandError create() => SceneShootsCommandError();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProblemError? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProblemError?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SceneShootsCommandErrorProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sceneShootsCommandErrorHash() =>
    r'002483fcbe8eee519d752b6fab90711b8bc24eca';

/// Last command failure per day, surfaced to the screen keyed on `code`.

final class SceneShootsCommandErrorFamily extends $Family
    with
        $ClassFamilyOverride<
          SceneShootsCommandError,
          ProblemError?,
          ProblemError?,
          ProblemError?,
          SceneShootDayScope
        > {
  SceneShootsCommandErrorFamily._()
    : super(
        retry: null,
        name: r'sceneShootsCommandErrorProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Last command failure per day, surfaced to the screen keyed on `code`.

  SceneShootsCommandErrorProvider call(SceneShootDayScope scope) =>
      SceneShootsCommandErrorProvider._(argument: scope, from: this);

  @override
  String toString() => r'sceneShootsCommandErrorProvider';
}

/// Last command failure per day, surfaced to the screen keyed on `code`.

abstract class _$SceneShootsCommandError extends $Notifier<ProblemError?> {
  late final _$args = ref.$arg as SceneShootDayScope;
  SceneShootDayScope get scope => _$args;

  ProblemError? build(SceneShootDayScope scope);
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

/// `SceneShootsController(scope)` on the shared reconciliation runner:
/// plan derives no client ids (path-authoritative); execution commands
/// echo the acted-on row's `version`; continuity link/list/unlink run the
/// `upload_continuity_photos` capability gate first.

@ProviderFor(SceneShootsController)
final sceneShootsControllerProvider = SceneShootsControllerFamily._();

/// `SceneShootsController(scope)` on the shared reconciliation runner:
/// plan derives no client ids (path-authoritative); execution commands
/// echo the acted-on row's `version`; continuity link/list/unlink run the
/// `upload_continuity_photos` capability gate first.
final class SceneShootsControllerProvider
    extends $NotifierProvider<SceneShootsController, SceneShootsScreenState> {
  /// `SceneShootsController(scope)` on the shared reconciliation runner:
  /// plan derives no client ids (path-authoritative); execution commands
  /// echo the acted-on row's `version`; continuity link/list/unlink run the
  /// `upload_continuity_photos` capability gate first.
  SceneShootsControllerProvider._({
    required SceneShootsControllerFamily super.from,
    required SceneShootDayScope super.argument,
  }) : super(
         retry: null,
         name: r'sceneShootsControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sceneShootsControllerHash();

  @override
  String toString() {
    return r'sceneShootsControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SceneShootsController create() => SceneShootsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SceneShootsScreenState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SceneShootsScreenState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SceneShootsControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sceneShootsControllerHash() =>
    r'34a72627cea68674db2bb3c297abfd85a4d65f62';

/// `SceneShootsController(scope)` on the shared reconciliation runner:
/// plan derives no client ids (path-authoritative); execution commands
/// echo the acted-on row's `version`; continuity link/list/unlink run the
/// `upload_continuity_photos` capability gate first.

final class SceneShootsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SceneShootsController,
          SceneShootsScreenState,
          SceneShootsScreenState,
          SceneShootsScreenState,
          SceneShootDayScope
        > {
  SceneShootsControllerFamily._()
    : super(
        retry: null,
        name: r'sceneShootsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// `SceneShootsController(scope)` on the shared reconciliation runner:
  /// plan derives no client ids (path-authoritative); execution commands
  /// echo the acted-on row's `version`; continuity link/list/unlink run the
  /// `upload_continuity_photos` capability gate first.

  SceneShootsControllerProvider call(SceneShootDayScope scope) =>
      SceneShootsControllerProvider._(argument: scope, from: this);

  @override
  String toString() => r'sceneShootsControllerProvider';
}

/// `SceneShootsController(scope)` on the shared reconciliation runner:
/// plan derives no client ids (path-authoritative); execution commands
/// echo the acted-on row's `version`; continuity link/list/unlink run the
/// `upload_continuity_photos` capability gate first.

abstract class _$SceneShootsController
    extends $Notifier<SceneShootsScreenState> {
  late final _$args = ref.$arg as SceneShootDayScope;
  SceneShootDayScope get scope => _$args;

  SceneShootsScreenState build(SceneShootDayScope scope);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<SceneShootsScreenState, SceneShootsScreenState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SceneShootsScreenState, SceneShootsScreenState>,
              SceneShootsScreenState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
