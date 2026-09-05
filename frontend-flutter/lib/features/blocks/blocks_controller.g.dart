// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'blocks_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Block repository: owns network + Drift cache writes.

@ProviderFor(blockRepository)
final blockRepositoryProvider = BlockRepositoryProvider._();

/// Block repository: owns network + Drift cache writes.

final class BlockRepositoryProvider
    extends
        $FunctionalProvider<BlockRepository, BlockRepository, BlockRepository>
    with $Provider<BlockRepository> {
  /// Block repository: owns network + Drift cache writes.
  BlockRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'blockRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$blockRepositoryHash();

  @$internal
  @override
  $ProviderElement<BlockRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BlockRepository create(Ref ref) {
    return blockRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BlockRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BlockRepository>(value),
    );
  }
}

String _$blockRepositoryHash() => r'2f5dd7b51561e0e0d5c4d5e85f2084952f166213';

/// The injected season-scoped list-fetch seam: `GET /v1/blocks?season_id=…`
/// (writes Drift on success, never on failure). Tests override this provider
/// with a fake.

@ProviderFor(blocksListFetch)
final blocksListFetchProvider = BlocksListFetchFamily._();

/// The injected season-scoped list-fetch seam: `GET /v1/blocks?season_id=…`
/// (writes Drift on success, never on failure). Tests override this provider
/// with a fake.

final class BlocksListFetchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<List<BlockView>>>,
          Result<List<BlockView>>,
          FutureOr<Result<List<BlockView>>>
        >
    with
        $FutureModifier<Result<List<BlockView>>>,
        $FutureProvider<Result<List<BlockView>>> {
  /// The injected season-scoped list-fetch seam: `GET /v1/blocks?season_id=…`
  /// (writes Drift on success, never on failure). Tests override this provider
  /// with a fake.
  BlocksListFetchProvider._({
    required BlocksListFetchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'blocksListFetchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$blocksListFetchHash();

  @override
  String toString() {
    return r'blocksListFetchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<List<BlockView>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<List<BlockView>>> create(Ref ref) {
    final argument = this.argument as String;
    return blocksListFetch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is BlocksListFetchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$blocksListFetchHash() => r'34eee74f9e7a4b8ddc0ee12ad207266e52fb896c';

/// The injected season-scoped list-fetch seam: `GET /v1/blocks?season_id=…`
/// (writes Drift on success, never on failure). Tests override this provider
/// with a fake.

final class BlocksListFetchFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Result<List<BlockView>>>, String> {
  BlocksListFetchFamily._()
    : super(
        retry: null,
        name: r'blocksListFetchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The injected season-scoped list-fetch seam: `GET /v1/blocks?season_id=…`
  /// (writes Drift on success, never on failure). Tests override this provider
  /// with a fake.

  BlocksListFetchProvider call(String seasonId) =>
      BlocksListFetchProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'blocksListFetchProvider';
}

/// Retained last-good snapshot per season, so the view selector can serve
/// cached rows while the fetch is loading or has failed.

@ProviderFor(BlocksPrevRows)
final blocksPrevRowsProvider = BlocksPrevRowsFamily._();

/// Retained last-good snapshot per season, so the view selector can serve
/// cached rows while the fetch is loading or has failed.
final class BlocksPrevRowsProvider
    extends $NotifierProvider<BlocksPrevRows, List<BlockView>> {
  /// Retained last-good snapshot per season, so the view selector can serve
  /// cached rows while the fetch is loading or has failed.
  BlocksPrevRowsProvider._({
    required BlocksPrevRowsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'blocksPrevRowsProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$blocksPrevRowsHash();

  @override
  String toString() {
    return r'blocksPrevRowsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  BlocksPrevRows create() => BlocksPrevRows();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<BlockView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<BlockView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BlocksPrevRowsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$blocksPrevRowsHash() => r'677da36561092ff38efe8c7c6997c3728ea4ef2a';

/// Retained last-good snapshot per season, so the view selector can serve
/// cached rows while the fetch is loading or has failed.

final class BlocksPrevRowsFamily extends $Family
    with
        $ClassFamilyOverride<
          BlocksPrevRows,
          List<BlockView>,
          List<BlockView>,
          List<BlockView>,
          String
        > {
  BlocksPrevRowsFamily._()
    : super(
        retry: null,
        name: r'blocksPrevRowsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Retained last-good snapshot per season, so the view selector can serve
  /// cached rows while the fetch is loading or has failed.

  BlocksPrevRowsProvider call(String seasonId) =>
      BlocksPrevRowsProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'blocksPrevRowsProvider';
}

/// Retained last-good snapshot per season, so the view selector can serve
/// cached rows while the fetch is loading or has failed.

abstract class _$BlocksPrevRows extends $Notifier<List<BlockView>> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  List<BlockView> build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<BlockView>, List<BlockView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<BlockView>, List<BlockView>>,
              List<BlockView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Read-projection controller.
///
/// Maps the injected [blocksListFetchProvider] `Result` into an
/// `AsyncValue<BlocksView>` and seeds the retained snapshot from the cache
/// FIRST (offline cold start). A sync `Notifier` (not an `AsyncNotifier`)
/// so a fetch `Err` surfaces as `AsyncError` rather than triggering
/// Riverpod's async-notifier retry loop.
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [BlocksPrevRows]. It writes the snapshot
/// store but never reads it back through a watch, so its own writes can
/// never invalidate it (no seed/rebuild loop). Consumers read through
/// [blocksViewProvider].

@ProviderFor(BlocksViewController)
final blocksViewControllerProvider = BlocksViewControllerFamily._();

/// Read-projection controller.
///
/// Maps the injected [blocksListFetchProvider] `Result` into an
/// `AsyncValue<BlocksView>` and seeds the retained snapshot from the cache
/// FIRST (offline cold start). A sync `Notifier` (not an `AsyncNotifier`)
/// so a fetch `Err` surfaces as `AsyncError` rather than triggering
/// Riverpod's async-notifier retry loop.
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [BlocksPrevRows]. It writes the snapshot
/// store but never reads it back through a watch, so its own writes can
/// never invalidate it (no seed/rebuild loop). Consumers read through
/// [blocksViewProvider].
final class BlocksViewControllerProvider
    extends $NotifierProvider<BlocksViewController, AsyncValue<BlocksView>> {
  /// Read-projection controller.
  ///
  /// Maps the injected [blocksListFetchProvider] `Result` into an
  /// `AsyncValue<BlocksView>` and seeds the retained snapshot from the cache
  /// FIRST (offline cold start). A sync `Notifier` (not an `AsyncNotifier`)
  /// so a fetch `Err` surfaces as `AsyncError` rather than triggering
  /// Riverpod's async-notifier retry loop.
  ///
  /// Loop discipline (reference pattern): this seeder watches the repository
  /// and the fetch ONLY — never [BlocksPrevRows]. It writes the snapshot
  /// store but never reads it back through a watch, so its own writes can
  /// never invalidate it (no seed/rebuild loop). Consumers read through
  /// [blocksViewProvider].
  BlocksViewControllerProvider._({
    required BlocksViewControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'blocksViewControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$blocksViewControllerHash();

  @override
  String toString() {
    return r'blocksViewControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  BlocksViewController create() => BlocksViewController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<BlocksView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<BlocksView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BlocksViewControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$blocksViewControllerHash() =>
    r'42c96b6d6125782060bba4ed56a0b8177a825380';

/// Read-projection controller.
///
/// Maps the injected [blocksListFetchProvider] `Result` into an
/// `AsyncValue<BlocksView>` and seeds the retained snapshot from the cache
/// FIRST (offline cold start). A sync `Notifier` (not an `AsyncNotifier`)
/// so a fetch `Err` surfaces as `AsyncError` rather than triggering
/// Riverpod's async-notifier retry loop.
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [BlocksPrevRows]. It writes the snapshot
/// store but never reads it back through a watch, so its own writes can
/// never invalidate it (no seed/rebuild loop). Consumers read through
/// [blocksViewProvider].

final class BlocksViewControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          BlocksViewController,
          AsyncValue<BlocksView>,
          AsyncValue<BlocksView>,
          AsyncValue<BlocksView>,
          String
        > {
  BlocksViewControllerFamily._()
    : super(
        retry: null,
        name: r'blocksViewControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Read-projection controller.
  ///
  /// Maps the injected [blocksListFetchProvider] `Result` into an
  /// `AsyncValue<BlocksView>` and seeds the retained snapshot from the cache
  /// FIRST (offline cold start). A sync `Notifier` (not an `AsyncNotifier`)
  /// so a fetch `Err` surfaces as `AsyncError` rather than triggering
  /// Riverpod's async-notifier retry loop.
  ///
  /// Loop discipline (reference pattern): this seeder watches the repository
  /// and the fetch ONLY — never [BlocksPrevRows]. It writes the snapshot
  /// store but never reads it back through a watch, so its own writes can
  /// never invalidate it (no seed/rebuild loop). Consumers read through
  /// [blocksViewProvider].

  BlocksViewControllerProvider call(String seasonId) =>
      BlocksViewControllerProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'blocksViewControllerProvider';
}

/// Read-projection controller.
///
/// Maps the injected [blocksListFetchProvider] `Result` into an
/// `AsyncValue<BlocksView>` and seeds the retained snapshot from the cache
/// FIRST (offline cold start). A sync `Notifier` (not an `AsyncNotifier`)
/// so a fetch `Err` surfaces as `AsyncError` rather than triggering
/// Riverpod's async-notifier retry loop.
///
/// Loop discipline (reference pattern): this seeder watches the repository
/// and the fetch ONLY — never [BlocksPrevRows]. It writes the snapshot
/// store but never reads it back through a watch, so its own writes can
/// never invalidate it (no seed/rebuild loop). Consumers read through
/// [blocksViewProvider].

abstract class _$BlocksViewController
    extends $Notifier<AsyncValue<BlocksView>> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  AsyncValue<BlocksView> build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<BlocksView>, AsyncValue<BlocksView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<BlocksView>, AsyncValue<BlocksView>>,
              AsyncValue<BlocksView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// The projection a screen reads (selector).
///
/// Always exposes a usable value: during loading it serves the seeded
/// cached rows; on error it serves the retained snapshot with a stale
/// marker and the error; on success it serves the fresh rows.

@ProviderFor(blocksView)
final blocksViewProvider = BlocksViewFamily._();

/// The projection a screen reads (selector).
///
/// Always exposes a usable value: during loading it serves the seeded
/// cached rows; on error it serves the retained snapshot with a stale
/// marker and the error; on success it serves the fresh rows.

final class BlocksViewProvider
    extends $FunctionalProvider<BlocksView, BlocksView, BlocksView>
    with $Provider<BlocksView> {
  /// The projection a screen reads (selector).
  ///
  /// Always exposes a usable value: during loading it serves the seeded
  /// cached rows; on error it serves the retained snapshot with a stale
  /// marker and the error; on success it serves the fresh rows.
  BlocksViewProvider._({
    required BlocksViewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'blocksViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$blocksViewHash();

  @override
  String toString() {
    return r'blocksViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<BlocksView> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BlocksView create(Ref ref) {
    final argument = this.argument as String;
    return blocksView(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BlocksView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BlocksView>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BlocksViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$blocksViewHash() => r'9045a1f26325b4c63a3d50767f75a9cebf65a83f';

/// The projection a screen reads (selector).
///
/// Always exposes a usable value: during loading it serves the seeded
/// cached rows; on error it serves the retained snapshot with a stale
/// marker and the error; on success it serves the fresh rows.

final class BlocksViewFamily extends $Family
    with $FunctionalFamilyOverride<BlocksView, String> {
  BlocksViewFamily._()
    : super(
        retry: null,
        name: r'blocksViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The projection a screen reads (selector).
  ///
  /// Always exposes a usable value: during loading it serves the seeded
  /// cached rows; on error it serves the retained snapshot with a stale
  /// marker and the error; on success it serves the fresh rows.

  BlocksViewProvider call(String seasonId) =>
      BlocksViewProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'blocksViewProvider';
}

/// Ephemeral optimistic overlay store for the season (controller state, NOT
/// Drift — no global overlay store).

@ProviderFor(BlocksOverlays)
final blocksOverlaysProvider = BlocksOverlaysFamily._();

/// Ephemeral optimistic overlay store for the season (controller state, NOT
/// Drift — no global overlay store).
final class BlocksOverlaysProvider
    extends $NotifierProvider<BlocksOverlays, List<BlockOverlay>> {
  /// Ephemeral optimistic overlay store for the season (controller state, NOT
  /// Drift — no global overlay store).
  BlocksOverlaysProvider._({
    required BlocksOverlaysFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'blocksOverlaysProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$blocksOverlaysHash();

  @override
  String toString() {
    return r'blocksOverlaysProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  BlocksOverlays create() => BlocksOverlays();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<BlockOverlay> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<BlockOverlay>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BlocksOverlaysProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$blocksOverlaysHash() => r'6e9f002bae2812072c0c604b6ab331181d4ae054';

/// Ephemeral optimistic overlay store for the season (controller state, NOT
/// Drift — no global overlay store).

final class BlocksOverlaysFamily extends $Family
    with
        $ClassFamilyOverride<
          BlocksOverlays,
          List<BlockOverlay>,
          List<BlockOverlay>,
          List<BlockOverlay>,
          String
        > {
  BlocksOverlaysFamily._()
    : super(
        retry: null,
        name: r'blocksOverlaysProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Ephemeral optimistic overlay store for the season (controller state, NOT
  /// Drift — no global overlay store).

  BlocksOverlaysProvider call(String seasonId) =>
      BlocksOverlaysProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'blocksOverlaysProvider';
}

/// Ephemeral optimistic overlay store for the season (controller state, NOT
/// Drift — no global overlay store).

abstract class _$BlocksOverlays extends $Notifier<List<BlockOverlay>> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  List<BlockOverlay> build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<BlockOverlay>, List<BlockOverlay>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<BlockOverlay>, List<BlockOverlay>>,
              List<BlockOverlay>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Last command failure per season, surfaced to the screen keyed on `code`.

@ProviderFor(BlocksCommandError)
final blocksCommandErrorProvider = BlocksCommandErrorFamily._();

/// Last command failure per season, surfaced to the screen keyed on `code`.
final class BlocksCommandErrorProvider
    extends $NotifierProvider<BlocksCommandError, ProblemError?> {
  /// Last command failure per season, surfaced to the screen keyed on `code`.
  BlocksCommandErrorProvider._({
    required BlocksCommandErrorFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'blocksCommandErrorProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$blocksCommandErrorHash();

  @override
  String toString() {
    return r'blocksCommandErrorProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  BlocksCommandError create() => BlocksCommandError();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProblemError? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProblemError?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BlocksCommandErrorProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$blocksCommandErrorHash() =>
    r'7dff4967b5c8da31121c6ab3377033d950ccc60c';

/// Last command failure per season, surfaced to the screen keyed on `code`.

final class BlocksCommandErrorFamily extends $Family
    with
        $ClassFamilyOverride<
          BlocksCommandError,
          ProblemError?,
          ProblemError?,
          ProblemError?,
          String
        > {
  BlocksCommandErrorFamily._()
    : super(
        retry: null,
        name: r'blocksCommandErrorProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Last command failure per season, surfaced to the screen keyed on `code`.

  BlocksCommandErrorProvider call(String seasonId) =>
      BlocksCommandErrorProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'blocksCommandErrorProvider';
}

/// Last command failure per season, surfaced to the screen keyed on `code`.

abstract class _$BlocksCommandError extends $Notifier<ProblemError?> {
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

/// Family `BlocksController(seasonId)` on the shared reconciliation runner
/// (seasons reference pattern): projected `AsyncValue` rows, cached rows,
/// staleness, optimistic overlays, dismissible command error.

@ProviderFor(BlocksController)
final blocksControllerProvider = BlocksControllerFamily._();

/// Family `BlocksController(seasonId)` on the shared reconciliation runner
/// (seasons reference pattern): projected `AsyncValue` rows, cached rows,
/// staleness, optimistic overlays, dismissible command error.
final class BlocksControllerProvider
    extends $NotifierProvider<BlocksController, BlocksScreenState> {
  /// Family `BlocksController(seasonId)` on the shared reconciliation runner
  /// (seasons reference pattern): projected `AsyncValue` rows, cached rows,
  /// staleness, optimistic overlays, dismissible command error.
  BlocksControllerProvider._({
    required BlocksControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'blocksControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$blocksControllerHash();

  @override
  String toString() {
    return r'blocksControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  BlocksController create() => BlocksController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BlocksScreenState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BlocksScreenState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BlocksControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$blocksControllerHash() => r'38afa58e2193260cadcce17d5907d6666ed1edb2';

/// Family `BlocksController(seasonId)` on the shared reconciliation runner
/// (seasons reference pattern): projected `AsyncValue` rows, cached rows,
/// staleness, optimistic overlays, dismissible command error.

final class BlocksControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          BlocksController,
          BlocksScreenState,
          BlocksScreenState,
          BlocksScreenState,
          String
        > {
  BlocksControllerFamily._()
    : super(
        retry: null,
        name: r'blocksControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Family `BlocksController(seasonId)` on the shared reconciliation runner
  /// (seasons reference pattern): projected `AsyncValue` rows, cached rows,
  /// staleness, optimistic overlays, dismissible command error.

  BlocksControllerProvider call(String seasonId) =>
      BlocksControllerProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'blocksControllerProvider';
}

/// Family `BlocksController(seasonId)` on the shared reconciliation runner
/// (seasons reference pattern): projected `AsyncValue` rows, cached rows,
/// staleness, optimistic overlays, dismissible command error.

abstract class _$BlocksController extends $Notifier<BlocksScreenState> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  BlocksScreenState build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<BlocksScreenState, BlocksScreenState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BlocksScreenState, BlocksScreenState>,
              BlocksScreenState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
