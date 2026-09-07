// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shooting_days_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Shooting-day repository: owns network + Drift cache writes.

@ProviderFor(shootingDayRepository)
final shootingDayRepositoryProvider = ShootingDayRepositoryProvider._();

/// Shooting-day repository: owns network + Drift cache writes.

final class ShootingDayRepositoryProvider
    extends
        $FunctionalProvider<
          ShootingDayRepository,
          ShootingDayRepository,
          ShootingDayRepository
        >
    with $Provider<ShootingDayRepository> {
  /// Shooting-day repository: owns network + Drift cache writes.
  ShootingDayRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shootingDayRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shootingDayRepositoryHash();

  @$internal
  @override
  $ProviderElement<ShootingDayRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ShootingDayRepository create(Ref ref) {
    return shootingDayRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShootingDayRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShootingDayRepository>(value),
    );
  }
}

String _$shootingDayRepositoryHash() =>
    r'7105c2c016b62b1c37a8d2c43662047e9ebd63c4';

/// The injected episode-scoped list-fetch seam
/// (`GET /v1/episodes/{episode_id}/shooting-days`, server `order_key ASC`).
/// Tests override this provider with a fake.

@ProviderFor(shootingDaysListFetch)
final shootingDaysListFetchProvider = ShootingDaysListFetchFamily._();

/// The injected episode-scoped list-fetch seam
/// (`GET /v1/episodes/{episode_id}/shooting-days`, server `order_key ASC`).
/// Tests override this provider with a fake.

final class ShootingDaysListFetchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<List<ShootingDayView>>>,
          Result<List<ShootingDayView>>,
          FutureOr<Result<List<ShootingDayView>>>
        >
    with
        $FutureModifier<Result<List<ShootingDayView>>>,
        $FutureProvider<Result<List<ShootingDayView>>> {
  /// The injected episode-scoped list-fetch seam
  /// (`GET /v1/episodes/{episode_id}/shooting-days`, server `order_key ASC`).
  /// Tests override this provider with a fake.
  ShootingDaysListFetchProvider._({
    required ShootingDaysListFetchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'shootingDaysListFetchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$shootingDaysListFetchHash();

  @override
  String toString() {
    return r'shootingDaysListFetchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<List<ShootingDayView>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<List<ShootingDayView>>> create(Ref ref) {
    final argument = this.argument as String;
    return shootingDaysListFetch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ShootingDaysListFetchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shootingDaysListFetchHash() =>
    r'4bbef32bf66b0f0874f85a51cd645f8b3f3503f1';

/// The injected episode-scoped list-fetch seam
/// (`GET /v1/episodes/{episode_id}/shooting-days`, server `order_key ASC`).
/// Tests override this provider with a fake.

final class ShootingDaysListFetchFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Result<List<ShootingDayView>>>,
          String
        > {
  ShootingDaysListFetchFamily._()
    : super(
        retry: null,
        name: r'shootingDaysListFetchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The injected episode-scoped list-fetch seam
  /// (`GET /v1/episodes/{episode_id}/shooting-days`, server `order_key ASC`).
  /// Tests override this provider with a fake.

  ShootingDaysListFetchProvider call(String episodeId) =>
      ShootingDaysListFetchProvider._(argument: episodeId, from: this);

  @override
  String toString() => r'shootingDaysListFetchProvider';
}

/// Retained last-good snapshot per episode (server order).

@ProviderFor(ShootingDaysPrevRows)
final shootingDaysPrevRowsProvider = ShootingDaysPrevRowsFamily._();

/// Retained last-good snapshot per episode (server order).
final class ShootingDaysPrevRowsProvider
    extends $NotifierProvider<ShootingDaysPrevRows, List<ShootingDayView>> {
  /// Retained last-good snapshot per episode (server order).
  ShootingDaysPrevRowsProvider._({
    required ShootingDaysPrevRowsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'shootingDaysPrevRowsProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$shootingDaysPrevRowsHash();

  @override
  String toString() {
    return r'shootingDaysPrevRowsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ShootingDaysPrevRows create() => ShootingDaysPrevRows();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<ShootingDayView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<ShootingDayView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ShootingDaysPrevRowsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shootingDaysPrevRowsHash() =>
    r'29934880a2ee70ced93fda83065cc7047ab7901d';

/// Retained last-good snapshot per episode (server order).

final class ShootingDaysPrevRowsFamily extends $Family
    with
        $ClassFamilyOverride<
          ShootingDaysPrevRows,
          List<ShootingDayView>,
          List<ShootingDayView>,
          List<ShootingDayView>,
          String
        > {
  ShootingDaysPrevRowsFamily._()
    : super(
        retry: null,
        name: r'shootingDaysPrevRowsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Retained last-good snapshot per episode (server order).

  ShootingDaysPrevRowsProvider call(String episodeId) =>
      ShootingDaysPrevRowsProvider._(argument: episodeId, from: this);

  @override
  String toString() => r'shootingDaysPrevRowsProvider';
}

/// Retained last-good snapshot per episode (server order).

abstract class _$ShootingDaysPrevRows extends $Notifier<List<ShootingDayView>> {
  late final _$args = ref.$arg as String;
  String get episodeId => _$args;

  List<ShootingDayView> build(String episodeId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<ShootingDayView>, List<ShootingDayView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<ShootingDayView>, List<ShootingDayView>>,
              List<ShootingDayView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Read-projection controller (seeder watches repository + fetch only).

@ProviderFor(ShootingDaysViewController)
final shootingDaysViewControllerProvider = ShootingDaysViewControllerFamily._();

/// Read-projection controller (seeder watches repository + fetch only).
final class ShootingDaysViewControllerProvider
    extends
        $NotifierProvider<
          ShootingDaysViewController,
          AsyncValue<ShootingDaysView>
        > {
  /// Read-projection controller (seeder watches repository + fetch only).
  ShootingDaysViewControllerProvider._({
    required ShootingDaysViewControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'shootingDaysViewControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$shootingDaysViewControllerHash();

  @override
  String toString() {
    return r'shootingDaysViewControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ShootingDaysViewController create() => ShootingDaysViewController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<ShootingDaysView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<ShootingDaysView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ShootingDaysViewControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shootingDaysViewControllerHash() =>
    r'd667a223bf0be3b6db6bc3f4c8cb01523ea7e609';

/// Read-projection controller (seeder watches repository + fetch only).

final class ShootingDaysViewControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ShootingDaysViewController,
          AsyncValue<ShootingDaysView>,
          AsyncValue<ShootingDaysView>,
          AsyncValue<ShootingDaysView>,
          String
        > {
  ShootingDaysViewControllerFamily._()
    : super(
        retry: null,
        name: r'shootingDaysViewControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Read-projection controller (seeder watches repository + fetch only).

  ShootingDaysViewControllerProvider call(String episodeId) =>
      ShootingDaysViewControllerProvider._(argument: episodeId, from: this);

  @override
  String toString() => r'shootingDaysViewControllerProvider';
}

/// Read-projection controller (seeder watches repository + fetch only).

abstract class _$ShootingDaysViewController
    extends $Notifier<AsyncValue<ShootingDaysView>> {
  late final _$args = ref.$arg as String;
  String get episodeId => _$args;

  AsyncValue<ShootingDaysView> build(String episodeId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<ShootingDaysView>, AsyncValue<ShootingDaysView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<ShootingDaysView>,
                AsyncValue<ShootingDaysView>
              >,
              AsyncValue<ShootingDaysView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// TTL-based cache staleness for one episode's days (issue #366).

@ProviderFor(shootingDaysCacheStale)
final shootingDaysCacheStaleProvider = ShootingDaysCacheStaleFamily._();

/// TTL-based cache staleness for one episode's days (issue #366).

final class ShootingDaysCacheStaleProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// TTL-based cache staleness for one episode's days (issue #366).
  ShootingDaysCacheStaleProvider._({
    required ShootingDaysCacheStaleFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'shootingDaysCacheStaleProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$shootingDaysCacheStaleHash();

  @override
  String toString() {
    return r'shootingDaysCacheStaleProvider'
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
    return shootingDaysCacheStale(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ShootingDaysCacheStaleProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shootingDaysCacheStaleHash() =>
    r'f841eb78743209bf4d47f581e07f8ce182467731';

/// TTL-based cache staleness for one episode's days (issue #366).

final class ShootingDaysCacheStaleFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, String> {
  ShootingDaysCacheStaleFamily._()
    : super(
        retry: null,
        name: r'shootingDaysCacheStaleProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// TTL-based cache staleness for one episode's days (issue #366).

  ShootingDaysCacheStaleProvider call(String episodeId) =>
      ShootingDaysCacheStaleProvider._(argument: episodeId, from: this);

  @override
  String toString() => r'shootingDaysCacheStaleProvider';
}

/// The projection a screen reads (selector).

@ProviderFor(shootingDaysView)
final shootingDaysViewProvider = ShootingDaysViewFamily._();

/// The projection a screen reads (selector).

final class ShootingDaysViewProvider
    extends
        $FunctionalProvider<
          ShootingDaysView,
          ShootingDaysView,
          ShootingDaysView
        >
    with $Provider<ShootingDaysView> {
  /// The projection a screen reads (selector).
  ShootingDaysViewProvider._({
    required ShootingDaysViewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'shootingDaysViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$shootingDaysViewHash();

  @override
  String toString() {
    return r'shootingDaysViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<ShootingDaysView> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ShootingDaysView create(Ref ref) {
    final argument = this.argument as String;
    return shootingDaysView(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShootingDaysView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShootingDaysView>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ShootingDaysViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shootingDaysViewHash() => r'a8f7901b485be324ad554557a0a0fe7ca65b7886';

/// The projection a screen reads (selector).

final class ShootingDaysViewFamily extends $Family
    with $FunctionalFamilyOverride<ShootingDaysView, String> {
  ShootingDaysViewFamily._()
    : super(
        retry: null,
        name: r'shootingDaysViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The projection a screen reads (selector).

  ShootingDaysViewProvider call(String episodeId) =>
      ShootingDaysViewProvider._(argument: episodeId, from: this);

  @override
  String toString() => r'shootingDaysViewProvider';
}

/// Ephemeral optimistic overlay store per episode (controller state, NOT
/// Drift — no global overlay store).

@ProviderFor(ShootingDaysOverlays)
final shootingDaysOverlaysProvider = ShootingDaysOverlaysFamily._();

/// Ephemeral optimistic overlay store per episode (controller state, NOT
/// Drift — no global overlay store).
final class ShootingDaysOverlaysProvider
    extends $NotifierProvider<ShootingDaysOverlays, List<ShootingDayOverlay>> {
  /// Ephemeral optimistic overlay store per episode (controller state, NOT
  /// Drift — no global overlay store).
  ShootingDaysOverlaysProvider._({
    required ShootingDaysOverlaysFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'shootingDaysOverlaysProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$shootingDaysOverlaysHash();

  @override
  String toString() {
    return r'shootingDaysOverlaysProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ShootingDaysOverlays create() => ShootingDaysOverlays();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<ShootingDayOverlay> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<ShootingDayOverlay>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ShootingDaysOverlaysProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shootingDaysOverlaysHash() =>
    r'bc97efe757e774cef2f005775bdaef04acb42e8e';

/// Ephemeral optimistic overlay store per episode (controller state, NOT
/// Drift — no global overlay store).

final class ShootingDaysOverlaysFamily extends $Family
    with
        $ClassFamilyOverride<
          ShootingDaysOverlays,
          List<ShootingDayOverlay>,
          List<ShootingDayOverlay>,
          List<ShootingDayOverlay>,
          String
        > {
  ShootingDaysOverlaysFamily._()
    : super(
        retry: null,
        name: r'shootingDaysOverlaysProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Ephemeral optimistic overlay store per episode (controller state, NOT
  /// Drift — no global overlay store).

  ShootingDaysOverlaysProvider call(String episodeId) =>
      ShootingDaysOverlaysProvider._(argument: episodeId, from: this);

  @override
  String toString() => r'shootingDaysOverlaysProvider';
}

/// Ephemeral optimistic overlay store per episode (controller state, NOT
/// Drift — no global overlay store).

abstract class _$ShootingDaysOverlays
    extends $Notifier<List<ShootingDayOverlay>> {
  late final _$args = ref.$arg as String;
  String get episodeId => _$args;

  List<ShootingDayOverlay> build(String episodeId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<List<ShootingDayOverlay>, List<ShootingDayOverlay>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<ShootingDayOverlay>, List<ShootingDayOverlay>>,
              List<ShootingDayOverlay>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Last command failure per episode, surfaced to the screen keyed on `code`.

@ProviderFor(ShootingDaysCommandError)
final shootingDaysCommandErrorProvider = ShootingDaysCommandErrorFamily._();

/// Last command failure per episode, surfaced to the screen keyed on `code`.
final class ShootingDaysCommandErrorProvider
    extends $NotifierProvider<ShootingDaysCommandError, ProblemError?> {
  /// Last command failure per episode, surfaced to the screen keyed on `code`.
  ShootingDaysCommandErrorProvider._({
    required ShootingDaysCommandErrorFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'shootingDaysCommandErrorProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$shootingDaysCommandErrorHash();

  @override
  String toString() {
    return r'shootingDaysCommandErrorProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ShootingDaysCommandError create() => ShootingDaysCommandError();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProblemError? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProblemError?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ShootingDaysCommandErrorProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shootingDaysCommandErrorHash() =>
    r'041014a31b7459f0de0d1098fa392e72b2f42bae';

/// Last command failure per episode, surfaced to the screen keyed on `code`.

final class ShootingDaysCommandErrorFamily extends $Family
    with
        $ClassFamilyOverride<
          ShootingDaysCommandError,
          ProblemError?,
          ProblemError?,
          ProblemError?,
          String
        > {
  ShootingDaysCommandErrorFamily._()
    : super(
        retry: null,
        name: r'shootingDaysCommandErrorProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Last command failure per episode, surfaced to the screen keyed on `code`.

  ShootingDaysCommandErrorProvider call(String episodeId) =>
      ShootingDaysCommandErrorProvider._(argument: episodeId, from: this);

  @override
  String toString() => r'shootingDaysCommandErrorProvider';
}

/// Last command failure per episode, surfaced to the screen keyed on `code`.

abstract class _$ShootingDaysCommandError extends $Notifier<ProblemError?> {
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

/// `ShootingDaysController(episodeId)` on the shared reconciliation runner:
/// create derives the append `order_key` with the shared rule (`source:
/// Manual`); updates are single-intent (reorder / reschedule+unschedule /
/// rename — one PATCH per action); archive reconciles via the bounded
/// refetch.

@ProviderFor(ShootingDaysController)
final shootingDaysControllerProvider = ShootingDaysControllerFamily._();

/// `ShootingDaysController(episodeId)` on the shared reconciliation runner:
/// create derives the append `order_key` with the shared rule (`source:
/// Manual`); updates are single-intent (reorder / reschedule+unschedule /
/// rename — one PATCH per action); archive reconciles via the bounded
/// refetch.
final class ShootingDaysControllerProvider
    extends $NotifierProvider<ShootingDaysController, ShootingDaysScreenState> {
  /// `ShootingDaysController(episodeId)` on the shared reconciliation runner:
  /// create derives the append `order_key` with the shared rule (`source:
  /// Manual`); updates are single-intent (reorder / reschedule+unschedule /
  /// rename — one PATCH per action); archive reconciles via the bounded
  /// refetch.
  ShootingDaysControllerProvider._({
    required ShootingDaysControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'shootingDaysControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$shootingDaysControllerHash();

  @override
  String toString() {
    return r'shootingDaysControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ShootingDaysController create() => ShootingDaysController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShootingDaysScreenState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShootingDaysScreenState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ShootingDaysControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shootingDaysControllerHash() =>
    r'16ff57011535af373587bdf74fa621cd2c54d326';

/// `ShootingDaysController(episodeId)` on the shared reconciliation runner:
/// create derives the append `order_key` with the shared rule (`source:
/// Manual`); updates are single-intent (reorder / reschedule+unschedule /
/// rename — one PATCH per action); archive reconciles via the bounded
/// refetch.

final class ShootingDaysControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ShootingDaysController,
          ShootingDaysScreenState,
          ShootingDaysScreenState,
          ShootingDaysScreenState,
          String
        > {
  ShootingDaysControllerFamily._()
    : super(
        retry: null,
        name: r'shootingDaysControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// `ShootingDaysController(episodeId)` on the shared reconciliation runner:
  /// create derives the append `order_key` with the shared rule (`source:
  /// Manual`); updates are single-intent (reorder / reschedule+unschedule /
  /// rename — one PATCH per action); archive reconciles via the bounded
  /// refetch.

  ShootingDaysControllerProvider call(String episodeId) =>
      ShootingDaysControllerProvider._(argument: episodeId, from: this);

  @override
  String toString() => r'shootingDaysControllerProvider';
}

/// `ShootingDaysController(episodeId)` on the shared reconciliation runner:
/// create derives the append `order_key` with the shared rule (`source:
/// Manual`); updates are single-intent (reorder / reschedule+unschedule /
/// rename — one PATCH per action); archive reconciles via the bounded
/// refetch.

abstract class _$ShootingDaysController
    extends $Notifier<ShootingDaysScreenState> {
  late final _$args = ref.$arg as String;
  String get episodeId => _$args;

  ShootingDaysScreenState build(String episodeId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<ShootingDaysScreenState, ShootingDaysScreenState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ShootingDaysScreenState, ShootingDaysScreenState>,
              ShootingDaysScreenState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
