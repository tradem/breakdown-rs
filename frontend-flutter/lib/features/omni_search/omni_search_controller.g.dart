// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'omni_search_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The search input DAO (tasks §2.1): one read-only composition seam over
/// the existing cache tables, injectable in tests.

@ProviderFor(omniSearchDao)
final omniSearchDaoProvider = OmniSearchDaoProvider._();

/// The search input DAO (tasks §2.1): one read-only composition seam over
/// the existing cache tables, injectable in tests.

final class OmniSearchDaoProvider
    extends $FunctionalProvider<OmniSearchDao, OmniSearchDao, OmniSearchDao>
    with $Provider<OmniSearchDao> {
  /// The search input DAO (tasks §2.1): one read-only composition seam over
  /// the existing cache tables, injectable in tests.
  OmniSearchDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'omniSearchDaoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$omniSearchDaoHash();

  @$internal
  @override
  $ProviderElement<OmniSearchDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  OmniSearchDao create(Ref ref) {
    return omniSearchDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OmniSearchDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OmniSearchDao>(value),
    );
  }
}

String _$omniSearchDaoHash() => r'7f0a9b295ad12d842f800e8d8c70930eb582cfc5';

/// The seasonal search inputs — THE QUERY PATH (tasks §2.1, D1).
///
/// READ-ONLY cache composition; the search itself NEVER issues a network
/// call (spec: `flutter-omni-search` name-prefilter + offline scenarios).
/// Cache freshness arrives via the bounded prefresh pass
/// (`OmniSearchSourceRefresher`), which is the only seam that may touch the
/// network — on surface open or on explicit user retry.

@ProviderFor(omniSearchInputs)
final omniSearchInputsProvider = OmniSearchInputsFamily._();

/// The seasonal search inputs — THE QUERY PATH (tasks §2.1, D1).
///
/// READ-ONLY cache composition; the search itself NEVER issues a network
/// call (spec: `flutter-omni-search` name-prefilter + offline scenarios).
/// Cache freshness arrives via the bounded prefresh pass
/// (`OmniSearchSourceRefresher`), which is the only seam that may touch the
/// network — on surface open or on explicit user retry.

final class OmniSearchInputsProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<OmniSearchInputs>>,
          Result<OmniSearchInputs>,
          FutureOr<Result<OmniSearchInputs>>
        >
    with
        $FutureModifier<Result<OmniSearchInputs>>,
        $FutureProvider<Result<OmniSearchInputs>> {
  /// The seasonal search inputs — THE QUERY PATH (tasks §2.1, D1).
  ///
  /// READ-ONLY cache composition; the search itself NEVER issues a network
  /// call (spec: `flutter-omni-search` name-prefilter + offline scenarios).
  /// Cache freshness arrives via the bounded prefresh pass
  /// (`OmniSearchSourceRefresher`), which is the only seam that may touch the
  /// network — on surface open or on explicit user retry.
  OmniSearchInputsProvider._({
    required OmniSearchInputsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'omniSearchInputsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$omniSearchInputsHash();

  @override
  String toString() {
    return r'omniSearchInputsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<OmniSearchInputs>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<OmniSearchInputs>> create(Ref ref) {
    final argument = this.argument as String;
    return omniSearchInputs(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is OmniSearchInputsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$omniSearchInputsHash() => r'3eb9757216edf1069cc5627b6caff75da18d9a42';

/// The seasonal search inputs — THE QUERY PATH (tasks §2.1, D1).
///
/// READ-ONLY cache composition; the search itself NEVER issues a network
/// call (spec: `flutter-omni-search` name-prefilter + offline scenarios).
/// Cache freshness arrives via the bounded prefresh pass
/// (`OmniSearchSourceRefresher`), which is the only seam that may touch the
/// network — on surface open or on explicit user retry.

final class OmniSearchInputsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Result<OmniSearchInputs>>, String> {
  OmniSearchInputsFamily._()
    : super(
        retry: null,
        name: r'omniSearchInputsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The seasonal search inputs — THE QUERY PATH (tasks §2.1, D1).
  ///
  /// READ-ONLY cache composition; the search itself NEVER issues a network
  /// call (spec: `flutter-omni-search` name-prefilter + offline scenarios).
  /// Cache freshness arrives via the bounded prefresh pass
  /// (`OmniSearchSourceRefresher`), which is the only seam that may touch the
  /// network — on surface open or on explicit user retry.

  OmniSearchInputsProvider call(String seasonId) =>
      OmniSearchInputsProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'omniSearchInputsProvider';
}

/// Notifier family per active season (task 4.2): the season switch
/// re-computes over the new season only — the family key IS the scope.

@ProviderFor(OmniSearchQuery)
final omniSearchQueryProvider = OmniSearchQueryFamily._();

/// Notifier family per active season (task 4.2): the season switch
/// re-computes over the new season only — the family key IS the scope.
final class OmniSearchQueryProvider
    extends $NotifierProvider<OmniSearchQuery, OmniSearchQueryState> {
  /// Notifier family per active season (task 4.2): the season switch
  /// re-computes over the new season only — the family key IS the scope.
  OmniSearchQueryProvider._({
    required OmniSearchQueryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'omniSearchQueryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$omniSearchQueryHash();

  @override
  String toString() {
    return r'omniSearchQueryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  OmniSearchQuery create() => OmniSearchQuery();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OmniSearchQueryState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OmniSearchQueryState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is OmniSearchQueryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$omniSearchQueryHash() => r'2969da07d984e34a916a3a94efd9edf9367b26eb';

/// Notifier family per active season (task 4.2): the season switch
/// re-computes over the new season only — the family key IS the scope.

final class OmniSearchQueryFamily extends $Family
    with
        $ClassFamilyOverride<
          OmniSearchQuery,
          OmniSearchQueryState,
          OmniSearchQueryState,
          OmniSearchQueryState,
          String
        > {
  OmniSearchQueryFamily._()
    : super(
        retry: null,
        name: r'omniSearchQueryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Notifier family per active season (task 4.2): the season switch
  /// re-computes over the new season only — the family key IS the scope.

  OmniSearchQueryProvider call(String seasonId) =>
      OmniSearchQueryProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'omniSearchQueryProvider';
}

/// Notifier family per active season (task 4.2): the season switch
/// re-computes over the new season only — the family key IS the scope.

abstract class _$OmniSearchQuery extends $Notifier<OmniSearchQueryState> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  OmniSearchQueryState build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<OmniSearchQueryState, OmniSearchQueryState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<OmniSearchQueryState, OmniSearchQueryState>,
              OmniSearchQueryState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// The search-surface controller (task 3.3/3.4): maps the inputs `Result`
/// into [OmniSearchViewState], never discarding an `Err` (the client analog
/// of the backend `discard-result` rule — storage failure SURFACES as the
/// error state with a retry, never as silent empty ground truth).

@ProviderFor(OmniSearchController)
final omniSearchControllerProvider = OmniSearchControllerFamily._();

/// The search-surface controller (task 3.3/3.4): maps the inputs `Result`
/// into [OmniSearchViewState], never discarding an `Err` (the client analog
/// of the backend `discard-result` rule — storage failure SURFACES as the
/// error state with a retry, never as silent empty ground truth).
final class OmniSearchControllerProvider
    extends
        $NotifierProvider<
          OmniSearchController,
          AsyncValue<OmniSearchViewState>
        > {
  /// The search-surface controller (task 3.3/3.4): maps the inputs `Result`
  /// into [OmniSearchViewState], never discarding an `Err` (the client analog
  /// of the backend `discard-result` rule — storage failure SURFACES as the
  /// error state with a retry, never as silent empty ground truth).
  OmniSearchControllerProvider._({
    required OmniSearchControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'omniSearchControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$omniSearchControllerHash();

  @override
  String toString() {
    return r'omniSearchControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  OmniSearchController create() => OmniSearchController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<OmniSearchViewState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<OmniSearchViewState>>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is OmniSearchControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$omniSearchControllerHash() =>
    r'89f04a99d135fed494813fb4801043abe1bf569c';

/// The search-surface controller (task 3.3/3.4): maps the inputs `Result`
/// into [OmniSearchViewState], never discarding an `Err` (the client analog
/// of the backend `discard-result` rule — storage failure SURFACES as the
/// error state with a retry, never as silent empty ground truth).

final class OmniSearchControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          OmniSearchController,
          AsyncValue<OmniSearchViewState>,
          AsyncValue<OmniSearchViewState>,
          AsyncValue<OmniSearchViewState>,
          String
        > {
  OmniSearchControllerFamily._()
    : super(
        retry: null,
        name: r'omniSearchControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The search-surface controller (task 3.3/3.4): maps the inputs `Result`
  /// into [OmniSearchViewState], never discarding an `Err` (the client analog
  /// of the backend `discard-result` rule — storage failure SURFACES as the
  /// error state with a retry, never as silent empty ground truth).

  OmniSearchControllerProvider call(String seasonId) =>
      OmniSearchControllerProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'omniSearchControllerProvider';
}

/// The search-surface controller (task 3.3/3.4): maps the inputs `Result`
/// into [OmniSearchViewState], never discarding an `Err` (the client analog
/// of the backend `discard-result` rule — storage failure SURFACES as the
/// error state with a retry, never as silent empty ground truth).

abstract class _$OmniSearchController
    extends $Notifier<AsyncValue<OmniSearchViewState>> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  AsyncValue<OmniSearchViewState> build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<OmniSearchViewState>,
              AsyncValue<OmniSearchViewState>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<OmniSearchViewState>,
                AsyncValue<OmniSearchViewState>
              >,
              AsyncValue<OmniSearchViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
