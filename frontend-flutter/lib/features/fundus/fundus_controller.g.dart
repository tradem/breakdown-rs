// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fundus_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Fundus repository: owns the project-scoped network fetch + Drift cache
/// writes (OpenSpec change `flutter-fundus-search`, tasks §2/§3).

@ProviderFor(fundusRepository)
final fundusRepositoryProvider = FundusRepositoryProvider._();

/// Fundus repository: owns the project-scoped network fetch + Drift cache
/// writes (OpenSpec change `flutter-fundus-search`, tasks §2/§3).

final class FundusRepositoryProvider
    extends
        $FunctionalProvider<
          FundusRepository,
          FundusRepository,
          FundusRepository
        >
    with $Provider<FundusRepository> {
  /// Fundus repository: owns the project-scoped network fetch + Drift cache
  /// writes (OpenSpec change `flutter-fundus-search`, tasks §2/§3).
  FundusRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'fundusRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$fundusRepositoryHash();

  @$internal
  @override
  $ProviderElement<FundusRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  FundusRepository create(Ref ref) {
    return fundusRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FundusRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FundusRepository>(value),
    );
  }
}

String _$fundusRepositoryHash() => r'625fb53de679921396b15ffffb7efa47d3b0a983';

/// The project's cached fundus inputs — THE QUERY PATH (design D3).
///
/// READ-ONLY cache composition; the search itself NEVER issues a network
/// call. Freshness arrives via the bounded prefetch pass
/// ([FundusController.refresh]), the only seam that may touch the network.
///
/// The project's seasons come from the seasons projection (a read-DTO join,
/// never a second projection lookup for a command).

@ProviderFor(fundusInputs)
final fundusInputsProvider = FundusInputsFamily._();

/// The project's cached fundus inputs — THE QUERY PATH (design D3).
///
/// READ-ONLY cache composition; the search itself NEVER issues a network
/// call. Freshness arrives via the bounded prefetch pass
/// ([FundusController.refresh]), the only seam that may touch the network.
///
/// The project's seasons come from the seasons projection (a read-DTO join,
/// never a second projection lookup for a command).

final class FundusInputsProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<FundusInputs>>,
          Result<FundusInputs>,
          FutureOr<Result<FundusInputs>>
        >
    with
        $FutureModifier<Result<FundusInputs>>,
        $FutureProvider<Result<FundusInputs>> {
  /// The project's cached fundus inputs — THE QUERY PATH (design D3).
  ///
  /// READ-ONLY cache composition; the search itself NEVER issues a network
  /// call. Freshness arrives via the bounded prefetch pass
  /// ([FundusController.refresh]), the only seam that may touch the network.
  ///
  /// The project's seasons come from the seasons projection (a read-DTO join,
  /// never a second projection lookup for a command).
  FundusInputsProvider._({
    required FundusInputsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'fundusInputsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fundusInputsHash();

  @override
  String toString() {
    return r'fundusInputsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<FundusInputs>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<FundusInputs>> create(Ref ref) {
    final argument = this.argument as String;
    return fundusInputs(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is FundusInputsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fundusInputsHash() => r'e059d285d96962cf883e0698046ebfe128ecbd5c';

/// The project's cached fundus inputs — THE QUERY PATH (design D3).
///
/// READ-ONLY cache composition; the search itself NEVER issues a network
/// call. Freshness arrives via the bounded prefetch pass
/// ([FundusController.refresh]), the only seam that may touch the network.
///
/// The project's seasons come from the seasons projection (a read-DTO join,
/// never a second projection lookup for a command).

final class FundusInputsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Result<FundusInputs>>, String> {
  FundusInputsFamily._()
    : super(
        retry: null,
        name: r'fundusInputsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The project's cached fundus inputs — THE QUERY PATH (design D3).
  ///
  /// READ-ONLY cache composition; the search itself NEVER issues a network
  /// call. Freshness arrives via the bounded prefetch pass
  /// ([FundusController.refresh]), the only seam that may touch the network.
  ///
  /// The project's seasons come from the seasons projection (a read-DTO join,
  /// never a second projection lookup for a command).

  FundusInputsProvider call(String projectId) =>
      FundusInputsProvider._(argument: projectId, from: this);

  @override
  String toString() => r'fundusInputsProvider';
}

/// Whether a bounded prefetch pass has completed for a project (empty vs.
/// not-yet-loaded honesty). Written by the refresher pass, read by the
/// controller.

@ProviderFor(FundusLoaded)
final fundusLoadedProvider = FundusLoadedFamily._();

/// Whether a bounded prefetch pass has completed for a project (empty vs.
/// not-yet-loaded honesty). Written by the refresher pass, read by the
/// controller.
final class FundusLoadedProvider extends $NotifierProvider<FundusLoaded, bool> {
  /// Whether a bounded prefetch pass has completed for a project (empty vs.
  /// not-yet-loaded honesty). Written by the refresher pass, read by the
  /// controller.
  FundusLoadedProvider._({
    required FundusLoadedFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'fundusLoadedProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fundusLoadedHash();

  @override
  String toString() {
    return r'fundusLoadedProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  FundusLoaded create() => FundusLoaded();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FundusLoadedProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fundusLoadedHash() => r'7450c404ea4452ac25e9473969ba6b0831ca0153';

/// Whether a bounded prefetch pass has completed for a project (empty vs.
/// not-yet-loaded honesty). Written by the refresher pass, read by the
/// controller.

final class FundusLoadedFamily extends $Family
    with $ClassFamilyOverride<FundusLoaded, bool, bool, bool, String> {
  FundusLoadedFamily._()
    : super(
        retry: null,
        name: r'fundusLoadedProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether a bounded prefetch pass has completed for a project (empty vs.
  /// not-yet-loaded honesty). Written by the refresher pass, read by the
  /// controller.

  FundusLoadedProvider call(String projectId) =>
      FundusLoadedProvider._(argument: projectId, from: this);

  @override
  String toString() => r'fundusLoadedProvider';
}

/// Whether a bounded prefetch pass has completed for a project (empty vs.
/// not-yet-loaded honesty). Written by the refresher pass, read by the
/// controller.

abstract class _$FundusLoaded extends $Notifier<bool> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  bool build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Query notifier family per project (the project switch recomputes over the
/// new project only — the family key IS the scope).

@ProviderFor(FundusQuery)
final fundusQueryProvider = FundusQueryFamily._();

/// Query notifier family per project (the project switch recomputes over the
/// new project only — the family key IS the scope).
final class FundusQueryProvider
    extends $NotifierProvider<FundusQuery, FundusQueryState> {
  /// Query notifier family per project (the project switch recomputes over the
  /// new project only — the family key IS the scope).
  FundusQueryProvider._({
    required FundusQueryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'fundusQueryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fundusQueryHash();

  @override
  String toString() {
    return r'fundusQueryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  FundusQuery create() => FundusQuery();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FundusQueryState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FundusQueryState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FundusQueryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fundusQueryHash() => r'a2a86886fa6cce0ce0a0210826df6f249a78dc62';

/// Query notifier family per project (the project switch recomputes over the
/// new project only — the family key IS the scope).

final class FundusQueryFamily extends $Family
    with
        $ClassFamilyOverride<
          FundusQuery,
          FundusQueryState,
          FundusQueryState,
          FundusQueryState,
          String
        > {
  FundusQueryFamily._()
    : super(
        retry: null,
        name: r'fundusQueryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Query notifier family per project (the project switch recomputes over the
  /// new project only — the family key IS the scope).

  FundusQueryProvider call(String projectId) =>
      FundusQueryProvider._(argument: projectId, from: this);

  @override
  String toString() => r'fundusQueryProvider';
}

/// Query notifier family per project (the project switch recomputes over the
/// new project only — the family key IS the scope).

abstract class _$FundusQuery extends $Notifier<FundusQueryState> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  FundusQueryState build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<FundusQueryState, FundusQueryState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<FundusQueryState, FundusQueryState>,
              FundusQueryState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// The fundus-surface controller (tasks §3.1): maps the inputs `Result` into
/// a [FundusViewState], never discarding an `Err` (storage failure SURFACES
/// as the error state with a retry — the client analog of `discard-result`).

@ProviderFor(FundusController)
final fundusControllerProvider = FundusControllerFamily._();

/// The fundus-surface controller (tasks §3.1): maps the inputs `Result` into
/// a [FundusViewState], never discarding an `Err` (storage failure SURFACES
/// as the error state with a retry — the client analog of `discard-result`).
final class FundusControllerProvider
    extends $NotifierProvider<FundusController, AsyncValue<FundusViewState>> {
  /// The fundus-surface controller (tasks §3.1): maps the inputs `Result` into
  /// a [FundusViewState], never discarding an `Err` (storage failure SURFACES
  /// as the error state with a retry — the client analog of `discard-result`).
  FundusControllerProvider._({
    required FundusControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'fundusControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fundusControllerHash();

  @override
  String toString() {
    return r'fundusControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  FundusController create() => FundusController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<FundusViewState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<FundusViewState>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FundusControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fundusControllerHash() => r'eb8b95046693451e02eac22a315e5b43672aa72e';

/// The fundus-surface controller (tasks §3.1): maps the inputs `Result` into
/// a [FundusViewState], never discarding an `Err` (storage failure SURFACES
/// as the error state with a retry — the client analog of `discard-result`).

final class FundusControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          FundusController,
          AsyncValue<FundusViewState>,
          AsyncValue<FundusViewState>,
          AsyncValue<FundusViewState>,
          String
        > {
  FundusControllerFamily._()
    : super(
        retry: null,
        name: r'fundusControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The fundus-surface controller (tasks §3.1): maps the inputs `Result` into
  /// a [FundusViewState], never discarding an `Err` (storage failure SURFACES
  /// as the error state with a retry — the client analog of `discard-result`).

  FundusControllerProvider call(String projectId) =>
      FundusControllerProvider._(argument: projectId, from: this);

  @override
  String toString() => r'fundusControllerProvider';
}

/// The fundus-surface controller (tasks §3.1): maps the inputs `Result` into
/// a [FundusViewState], never discarding an `Err` (storage failure SURFACES
/// as the error state with a retry — the client analog of `discard-result`).

abstract class _$FundusController
    extends $Notifier<AsyncValue<FundusViewState>> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  AsyncValue<FundusViewState> build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<FundusViewState>, AsyncValue<FundusViewState>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<FundusViewState>,
                AsyncValue<FundusViewState>
              >,
              AsyncValue<FundusViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
