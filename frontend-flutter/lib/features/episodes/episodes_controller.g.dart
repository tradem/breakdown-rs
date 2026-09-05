// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'episodes_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Episode repository: owns network + Drift cache writes.

@ProviderFor(episodeRepository)
final episodeRepositoryProvider = EpisodeRepositoryProvider._();

/// Episode repository: owns network + Drift cache writes.

final class EpisodeRepositoryProvider
    extends
        $FunctionalProvider<
          EpisodeRepository,
          EpisodeRepository,
          EpisodeRepository
        >
    with $Provider<EpisodeRepository> {
  /// Episode repository: owns network + Drift cache writes.
  EpisodeRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'episodeRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$episodeRepositoryHash();

  @$internal
  @override
  $ProviderElement<EpisodeRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  EpisodeRepository create(Ref ref) {
    return episodeRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EpisodeRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EpisodeRepository>(value),
    );
  }
}

String _$episodeRepositoryHash() => r'c8650c4774f96d6df742cfda9a5bd50d7a2340a7';

/// The injected block-scoped list-fetch seam via the server-side filter
/// (`GET /v1/episodes?block_id=…`, backend issue #335, PR #355). Tests
/// override this provider with a fake.

@ProviderFor(episodesListFetch)
final episodesListFetchProvider = EpisodesListFetchFamily._();

/// The injected block-scoped list-fetch seam via the server-side filter
/// (`GET /v1/episodes?block_id=…`, backend issue #335, PR #355). Tests
/// override this provider with a fake.

final class EpisodesListFetchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<List<EpisodeView>>>,
          Result<List<EpisodeView>>,
          FutureOr<Result<List<EpisodeView>>>
        >
    with
        $FutureModifier<Result<List<EpisodeView>>>,
        $FutureProvider<Result<List<EpisodeView>>> {
  /// The injected block-scoped list-fetch seam via the server-side filter
  /// (`GET /v1/episodes?block_id=…`, backend issue #335, PR #355). Tests
  /// override this provider with a fake.
  EpisodesListFetchProvider._({
    required EpisodesListFetchFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'episodesListFetchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$episodesListFetchHash();

  @override
  String toString() {
    return r'episodesListFetchProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<Result<List<EpisodeView>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<List<EpisodeView>>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return episodesListFetch(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is EpisodesListFetchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$episodesListFetchHash() => r'68ba802c892d29a61e02226ab8a8dfd3da533445';

/// The injected block-scoped list-fetch seam via the server-side filter
/// (`GET /v1/episodes?block_id=…`, backend issue #335, PR #355). Tests
/// override this provider with a fake.

final class EpisodesListFetchFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Result<List<EpisodeView>>>,
          (String, String)
        > {
  EpisodesListFetchFamily._()
    : super(
        retry: null,
        name: r'episodesListFetchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The injected block-scoped list-fetch seam via the server-side filter
  /// (`GET /v1/episodes?block_id=…`, backend issue #335, PR #355). Tests
  /// override this provider with a fake.

  EpisodesListFetchProvider call(String blockId, String seasonId) =>
      EpisodesListFetchProvider._(argument: (blockId, seasonId), from: this);

  @override
  String toString() => r'episodesListFetchProvider';
}

/// Retained last-good snapshot per block.

@ProviderFor(EpisodesPrevRows)
final episodesPrevRowsProvider = EpisodesPrevRowsFamily._();

/// Retained last-good snapshot per block.
final class EpisodesPrevRowsProvider
    extends $NotifierProvider<EpisodesPrevRows, List<EpisodeView>> {
  /// Retained last-good snapshot per block.
  EpisodesPrevRowsProvider._({
    required EpisodesPrevRowsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'episodesPrevRowsProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$episodesPrevRowsHash();

  @override
  String toString() {
    return r'episodesPrevRowsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  EpisodesPrevRows create() => EpisodesPrevRows();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<EpisodeView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<EpisodeView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EpisodesPrevRowsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$episodesPrevRowsHash() => r'21cbf6f9ea530c42fc49e6222267cd186ad9c859';

/// Retained last-good snapshot per block.

final class EpisodesPrevRowsFamily extends $Family
    with
        $ClassFamilyOverride<
          EpisodesPrevRows,
          List<EpisodeView>,
          List<EpisodeView>,
          List<EpisodeView>,
          (String, String)
        > {
  EpisodesPrevRowsFamily._()
    : super(
        retry: null,
        name: r'episodesPrevRowsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Retained last-good snapshot per block.

  EpisodesPrevRowsProvider call(String blockId, String seasonId) =>
      EpisodesPrevRowsProvider._(argument: (blockId, seasonId), from: this);

  @override
  String toString() => r'episodesPrevRowsProvider';
}

/// Retained last-good snapshot per block.

abstract class _$EpisodesPrevRows extends $Notifier<List<EpisodeView>> {
  late final _$args = ref.$arg as (String, String);
  String get blockId => _$args.$1;
  String get seasonId => _$args.$2;

  List<EpisodeView> build(String blockId, String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<EpisodeView>, List<EpisodeView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<EpisodeView>, List<EpisodeView>>,
              List<EpisodeView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

/// Read-projection controller.
///
/// Maps the injected fetch `Result` into an `AsyncValue<EpisodesView>` and
/// seeds the retained snapshot from the cache FIRST (offline cold start).
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [EpisodesPrevRows]. Consumers read through
/// [episodesViewProvider].

@ProviderFor(EpisodesViewController)
final episodesViewControllerProvider = EpisodesViewControllerFamily._();

/// Read-projection controller.
///
/// Maps the injected fetch `Result` into an `AsyncValue<EpisodesView>` and
/// seeds the retained snapshot from the cache FIRST (offline cold start).
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [EpisodesPrevRows]. Consumers read through
/// [episodesViewProvider].
final class EpisodesViewControllerProvider
    extends
        $NotifierProvider<EpisodesViewController, AsyncValue<EpisodesView>> {
  /// Read-projection controller.
  ///
  /// Maps the injected fetch `Result` into an `AsyncValue<EpisodesView>` and
  /// seeds the retained snapshot from the cache FIRST (offline cold start).
  ///
  /// Loop discipline (reference pattern): this seeder watches the repository
  /// and the fetch ONLY — never [EpisodesPrevRows]. Consumers read through
  /// [episodesViewProvider].
  EpisodesViewControllerProvider._({
    required EpisodesViewControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'episodesViewControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$episodesViewControllerHash();

  @override
  String toString() {
    return r'episodesViewControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  EpisodesViewController create() => EpisodesViewController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<EpisodesView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<EpisodesView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EpisodesViewControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$episodesViewControllerHash() =>
    r'd35c708237f2b7261bb7f2b953df77d0c2c14815';

/// Read-projection controller.
///
/// Maps the injected fetch `Result` into an `AsyncValue<EpisodesView>` and
/// seeds the retained snapshot from the cache FIRST (offline cold start).
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [EpisodesPrevRows]. Consumers read through
/// [episodesViewProvider].

final class EpisodesViewControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          EpisodesViewController,
          AsyncValue<EpisodesView>,
          AsyncValue<EpisodesView>,
          AsyncValue<EpisodesView>,
          (String, String)
        > {
  EpisodesViewControllerFamily._()
    : super(
        retry: null,
        name: r'episodesViewControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Read-projection controller.
  ///
  /// Maps the injected fetch `Result` into an `AsyncValue<EpisodesView>` and
  /// seeds the retained snapshot from the cache FIRST (offline cold start).
  ///
  /// Loop discipline (reference pattern): this seeder watches the repository
  /// and the fetch ONLY — never [EpisodesPrevRows]. Consumers read through
  /// [episodesViewProvider].

  EpisodesViewControllerProvider call(String blockId, String seasonId) =>
      EpisodesViewControllerProvider._(
        argument: (blockId, seasonId),
        from: this,
      );

  @override
  String toString() => r'episodesViewControllerProvider';
}

/// Read-projection controller.
///
/// Maps the injected fetch `Result` into an `AsyncValue<EpisodesView>` and
/// seeds the retained snapshot from the cache FIRST (offline cold start).
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [EpisodesPrevRows]. Consumers read through
/// [episodesViewProvider].

abstract class _$EpisodesViewController
    extends $Notifier<AsyncValue<EpisodesView>> {
  late final _$args = ref.$arg as (String, String);
  String get blockId => _$args.$1;
  String get seasonId => _$args.$2;

  AsyncValue<EpisodesView> build(String blockId, String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<EpisodesView>, AsyncValue<EpisodesView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<EpisodesView>, AsyncValue<EpisodesView>>,
              AsyncValue<EpisodesView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

/// The projection a screen reads (selector).

@ProviderFor(episodesView)
final episodesViewProvider = EpisodesViewFamily._();

/// The projection a screen reads (selector).

final class EpisodesViewProvider
    extends $FunctionalProvider<EpisodesView, EpisodesView, EpisodesView>
    with $Provider<EpisodesView> {
  /// The projection a screen reads (selector).
  EpisodesViewProvider._({
    required EpisodesViewFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'episodesViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$episodesViewHash();

  @override
  String toString() {
    return r'episodesViewProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<EpisodesView> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  EpisodesView create(Ref ref) {
    final argument = this.argument as (String, String);
    return episodesView(ref, argument.$1, argument.$2);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EpisodesView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EpisodesView>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EpisodesViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$episodesViewHash() => r'03a69d6569f8d442a89c0fb3bc6965a7bcc407b4';

/// The projection a screen reads (selector).

final class EpisodesViewFamily extends $Family
    with $FunctionalFamilyOverride<EpisodesView, (String, String)> {
  EpisodesViewFamily._()
    : super(
        retry: null,
        name: r'episodesViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The projection a screen reads (selector).

  EpisodesViewProvider call(String blockId, String seasonId) =>
      EpisodesViewProvider._(argument: (blockId, seasonId), from: this);

  @override
  String toString() => r'episodesViewProvider';
}

/// Ephemeral optimistic overlay store per block (controller state, NOT
/// Drift — no global overlay store).

@ProviderFor(EpisodesOverlays)
final episodesOverlaysProvider = EpisodesOverlaysFamily._();

/// Ephemeral optimistic overlay store per block (controller state, NOT
/// Drift — no global overlay store).
final class EpisodesOverlaysProvider
    extends $NotifierProvider<EpisodesOverlays, List<EpisodeOverlay>> {
  /// Ephemeral optimistic overlay store per block (controller state, NOT
  /// Drift — no global overlay store).
  EpisodesOverlaysProvider._({
    required EpisodesOverlaysFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'episodesOverlaysProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$episodesOverlaysHash();

  @override
  String toString() {
    return r'episodesOverlaysProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  EpisodesOverlays create() => EpisodesOverlays();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<EpisodeOverlay> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<EpisodeOverlay>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EpisodesOverlaysProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$episodesOverlaysHash() => r'78f8b7c3be097147185a1a5d9237a7bbfc99762c';

/// Ephemeral optimistic overlay store per block (controller state, NOT
/// Drift — no global overlay store).

final class EpisodesOverlaysFamily extends $Family
    with
        $ClassFamilyOverride<
          EpisodesOverlays,
          List<EpisodeOverlay>,
          List<EpisodeOverlay>,
          List<EpisodeOverlay>,
          (String, String)
        > {
  EpisodesOverlaysFamily._()
    : super(
        retry: null,
        name: r'episodesOverlaysProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Ephemeral optimistic overlay store per block (controller state, NOT
  /// Drift — no global overlay store).

  EpisodesOverlaysProvider call(String blockId, String seasonId) =>
      EpisodesOverlaysProvider._(argument: (blockId, seasonId), from: this);

  @override
  String toString() => r'episodesOverlaysProvider';
}

/// Ephemeral optimistic overlay store per block (controller state, NOT
/// Drift — no global overlay store).

abstract class _$EpisodesOverlays extends $Notifier<List<EpisodeOverlay>> {
  late final _$args = ref.$arg as (String, String);
  String get blockId => _$args.$1;
  String get seasonId => _$args.$2;

  List<EpisodeOverlay> build(String blockId, String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<EpisodeOverlay>, List<EpisodeOverlay>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<EpisodeOverlay>, List<EpisodeOverlay>>,
              List<EpisodeOverlay>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

/// Last command failure per block, surfaced to the screen keyed on `code`.

@ProviderFor(EpisodesCommandError)
final episodesCommandErrorProvider = EpisodesCommandErrorFamily._();

/// Last command failure per block, surfaced to the screen keyed on `code`.
final class EpisodesCommandErrorProvider
    extends $NotifierProvider<EpisodesCommandError, ProblemError?> {
  /// Last command failure per block, surfaced to the screen keyed on `code`.
  EpisodesCommandErrorProvider._({
    required EpisodesCommandErrorFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'episodesCommandErrorProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$episodesCommandErrorHash();

  @override
  String toString() {
    return r'episodesCommandErrorProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  EpisodesCommandError create() => EpisodesCommandError();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProblemError? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProblemError?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EpisodesCommandErrorProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$episodesCommandErrorHash() =>
    r'93763dc174860d6ecc255ef3425ed7d2b1b64692';

/// Last command failure per block, surfaced to the screen keyed on `code`.

final class EpisodesCommandErrorFamily extends $Family
    with
        $ClassFamilyOverride<
          EpisodesCommandError,
          ProblemError?,
          ProblemError?,
          ProblemError?,
          (String, String)
        > {
  EpisodesCommandErrorFamily._()
    : super(
        retry: null,
        name: r'episodesCommandErrorProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Last command failure per block, surfaced to the screen keyed on `code`.

  EpisodesCommandErrorProvider call(String blockId, String seasonId) =>
      EpisodesCommandErrorProvider._(argument: (blockId, seasonId), from: this);

  @override
  String toString() => r'episodesCommandErrorProvider';
}

/// Last command failure per block, surfaced to the screen keyed on `code`.

abstract class _$EpisodesCommandError extends $Notifier<ProblemError?> {
  late final _$args = ref.$arg as (String, String);
  String get blockId => _$args.$1;
  String get seasonId => _$args.$2;

  ProblemError? build(String blockId, String seasonId);
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
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

/// `EpisodesController(blockId, seasonId)` on the shared reconciliation
/// runner: the `blockId` is the fetch scope (server-side `?block_id=`
/// filter, D3); the `seasonId` namespaces the family by season context.
/// `groupByBlock` stays available as a pure mapper for merged renders.

@ProviderFor(EpisodesController)
final episodesControllerProvider = EpisodesControllerFamily._();

/// `EpisodesController(blockId, seasonId)` on the shared reconciliation
/// runner: the `blockId` is the fetch scope (server-side `?block_id=`
/// filter, D3); the `seasonId` namespaces the family by season context.
/// `groupByBlock` stays available as a pure mapper for merged renders.
final class EpisodesControllerProvider
    extends $NotifierProvider<EpisodesController, EpisodesScreenState> {
  /// `EpisodesController(blockId, seasonId)` on the shared reconciliation
  /// runner: the `blockId` is the fetch scope (server-side `?block_id=`
  /// filter, D3); the `seasonId` namespaces the family by season context.
  /// `groupByBlock` stays available as a pure mapper for merged renders.
  EpisodesControllerProvider._({
    required EpisodesControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'episodesControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$episodesControllerHash();

  @override
  String toString() {
    return r'episodesControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  EpisodesController create() => EpisodesController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EpisodesScreenState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EpisodesScreenState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EpisodesControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$episodesControllerHash() =>
    r'ba015653f703a4cf9d5f2e258410495b396cd8ce';

/// `EpisodesController(blockId, seasonId)` on the shared reconciliation
/// runner: the `blockId` is the fetch scope (server-side `?block_id=`
/// filter, D3); the `seasonId` namespaces the family by season context.
/// `groupByBlock` stays available as a pure mapper for merged renders.

final class EpisodesControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          EpisodesController,
          EpisodesScreenState,
          EpisodesScreenState,
          EpisodesScreenState,
          (String, String)
        > {
  EpisodesControllerFamily._()
    : super(
        retry: null,
        name: r'episodesControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// `EpisodesController(blockId, seasonId)` on the shared reconciliation
  /// runner: the `blockId` is the fetch scope (server-side `?block_id=`
  /// filter, D3); the `seasonId` namespaces the family by season context.
  /// `groupByBlock` stays available as a pure mapper for merged renders.

  EpisodesControllerProvider call(String blockId, String seasonId) =>
      EpisodesControllerProvider._(argument: (blockId, seasonId), from: this);

  @override
  String toString() => r'episodesControllerProvider';
}

/// `EpisodesController(blockId, seasonId)` on the shared reconciliation
/// runner: the `blockId` is the fetch scope (server-side `?block_id=`
/// filter, D3); the `seasonId` namespaces the family by season context.
/// `groupByBlock` stays available as a pure mapper for merged renders.

abstract class _$EpisodesController extends $Notifier<EpisodesScreenState> {
  late final _$args = ref.$arg as (String, String);
  String get blockId => _$args.$1;
  String get seasonId => _$args.$2;

  EpisodesScreenState build(String blockId, String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<EpisodesScreenState, EpisodesScreenState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<EpisodesScreenState, EpisodesScreenState>,
              EpisodesScreenState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
