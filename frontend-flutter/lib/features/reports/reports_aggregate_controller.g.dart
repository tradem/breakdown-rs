// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reports_aggregate_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The injected aggregate fetch seam
/// (`GET /v1/seasons/{id}/report/soll-ist` or
/// `GET /v1/episodes/{id}/report/soll-ist`, per the scope kind). Tests
/// override this provider with a fake.

@ProviderFor(reportsAggregateFetch)
final reportsAggregateFetchProvider = ReportsAggregateFetchFamily._();

/// The injected aggregate fetch seam
/// (`GET /v1/seasons/{id}/report/soll-ist` or
/// `GET /v1/episodes/{id}/report/soll-ist`, per the scope kind). Tests
/// override this provider with a fake.

final class ReportsAggregateFetchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<AggregateSollIstReport>>,
          Result<AggregateSollIstReport>,
          FutureOr<Result<AggregateSollIstReport>>
        >
    with
        $FutureModifier<Result<AggregateSollIstReport>>,
        $FutureProvider<Result<AggregateSollIstReport>> {
  /// The injected aggregate fetch seam
  /// (`GET /v1/seasons/{id}/report/soll-ist` or
  /// `GET /v1/episodes/{id}/report/soll-ist`, per the scope kind). Tests
  /// override this provider with a fake.
  ReportsAggregateFetchProvider._({
    required ReportsAggregateFetchFamily super.from,
    required ReportsAggregateScope super.argument,
  }) : super(
         retry: null,
         name: r'reportsAggregateFetchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$reportsAggregateFetchHash();

  @override
  String toString() {
    return r'reportsAggregateFetchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<AggregateSollIstReport>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<AggregateSollIstReport>> create(Ref ref) {
    final argument = this.argument as ReportsAggregateScope;
    return reportsAggregateFetch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ReportsAggregateFetchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$reportsAggregateFetchHash() =>
    r'18fca4ead17c3cf67ac01eb3a99f2dfd952aa249';

/// The injected aggregate fetch seam
/// (`GET /v1/seasons/{id}/report/soll-ist` or
/// `GET /v1/episodes/{id}/report/soll-ist`, per the scope kind). Tests
/// override this provider with a fake.

final class ReportsAggregateFetchFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Result<AggregateSollIstReport>>,
          ReportsAggregateScope
        > {
  ReportsAggregateFetchFamily._()
    : super(
        retry: null,
        name: r'reportsAggregateFetchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The injected aggregate fetch seam
  /// (`GET /v1/seasons/{id}/report/soll-ist` or
  /// `GET /v1/episodes/{id}/report/soll-ist`, per the scope kind). Tests
  /// override this provider with a fake.

  ReportsAggregateFetchProvider call(ReportsAggregateScope scope) =>
      ReportsAggregateFetchProvider._(argument: scope, from: this);

  @override
  String toString() => r'reportsAggregateFetchProvider';
}

/// The single PDF card state for the scope's aggregate PDF (idle until the
/// user fetches — no prefetching).

@ProviderFor(AggregatePdfCard)
final aggregatePdfCardProvider = AggregatePdfCardFamily._();

/// The single PDF card state for the scope's aggregate PDF (idle until the
/// user fetches — no prefetching).
final class AggregatePdfCardProvider
    extends $NotifierProvider<AggregatePdfCard, PdfCardState> {
  /// The single PDF card state for the scope's aggregate PDF (idle until the
  /// user fetches — no prefetching).
  AggregatePdfCardProvider._({
    required AggregatePdfCardFamily super.from,
    required ReportsAggregateScope super.argument,
  }) : super(
         retry: null,
         name: r'aggregatePdfCardProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aggregatePdfCardHash();

  @override
  String toString() {
    return r'aggregatePdfCardProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AggregatePdfCard create() => AggregatePdfCard();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PdfCardState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PdfCardState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AggregatePdfCardProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aggregatePdfCardHash() => r'3fcf61aad6a366856a7d398f7940e8e65811e3da';

/// The single PDF card state for the scope's aggregate PDF (idle until the
/// user fetches — no prefetching).

final class AggregatePdfCardFamily extends $Family
    with
        $ClassFamilyOverride<
          AggregatePdfCard,
          PdfCardState,
          PdfCardState,
          PdfCardState,
          ReportsAggregateScope
        > {
  AggregatePdfCardFamily._()
    : super(
        retry: null,
        name: r'aggregatePdfCardProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// The single PDF card state for the scope's aggregate PDF (idle until the
  /// user fetches — no prefetching).

  AggregatePdfCardProvider call(ReportsAggregateScope scope) =>
      AggregatePdfCardProvider._(argument: scope, from: this);

  @override
  String toString() => r'aggregatePdfCardProvider';
}

/// The single PDF card state for the scope's aggregate PDF (idle until the
/// user fetches — no prefetching).

abstract class _$AggregatePdfCard extends $Notifier<PdfCardState> {
  late final _$args = ref.$arg as ReportsAggregateScope;
  ReportsAggregateScope get scope => _$args;

  PdfCardState build(ReportsAggregateScope scope);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PdfCardState, PdfCardState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PdfCardState, PdfCardState>,
              PdfCardState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Last aggregate command failure, surfaced keyed on `code`.

@ProviderFor(ReportsAggregateCommandError)
final reportsAggregateCommandErrorProvider =
    ReportsAggregateCommandErrorFamily._();

/// Last aggregate command failure, surfaced keyed on `code`.
final class ReportsAggregateCommandErrorProvider
    extends $NotifierProvider<ReportsAggregateCommandError, ProblemError?> {
  /// Last aggregate command failure, surfaced keyed on `code`.
  ReportsAggregateCommandErrorProvider._({
    required ReportsAggregateCommandErrorFamily super.from,
    required ReportsAggregateScope super.argument,
  }) : super(
         retry: null,
         name: r'reportsAggregateCommandErrorProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$reportsAggregateCommandErrorHash();

  @override
  String toString() {
    return r'reportsAggregateCommandErrorProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ReportsAggregateCommandError create() => ReportsAggregateCommandError();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProblemError? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProblemError?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReportsAggregateCommandErrorProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$reportsAggregateCommandErrorHash() =>
    r'48baefa52119f69f7384de9fc976f68e37289809';

/// Last aggregate command failure, surfaced keyed on `code`.

final class ReportsAggregateCommandErrorFamily extends $Family
    with
        $ClassFamilyOverride<
          ReportsAggregateCommandError,
          ProblemError?,
          ProblemError?,
          ProblemError?,
          ReportsAggregateScope
        > {
  ReportsAggregateCommandErrorFamily._()
    : super(
        retry: null,
        name: r'reportsAggregateCommandErrorProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Last aggregate command failure, surfaced keyed on `code`.

  ReportsAggregateCommandErrorProvider call(ReportsAggregateScope scope) =>
      ReportsAggregateCommandErrorProvider._(argument: scope, from: this);

  @override
  String toString() => r'reportsAggregateCommandErrorProvider';
}

/// Last aggregate command failure, surfaced keyed on `code`.

abstract class _$ReportsAggregateCommandError extends $Notifier<ProblemError?> {
  late final _$args = ref.$arg as ReportsAggregateScope;
  ReportsAggregateScope get scope => _$args;

  ProblemError? build(ReportsAggregateScope scope);
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

/// Aggregated Soll-Ist reports controller: the on-screen JSON aggregation
/// plus user-initiated aggregate-PDF fetch/preview/share. Finality and day
/// counts render verbatim from the DTO — the client never recomputes the
/// aggregate finality rule (issue #571 decision 2).

@ProviderFor(ReportsAggregateController)
final reportsAggregateControllerProvider = ReportsAggregateControllerFamily._();

/// Aggregated Soll-Ist reports controller: the on-screen JSON aggregation
/// plus user-initiated aggregate-PDF fetch/preview/share. Finality and day
/// counts render verbatim from the DTO — the client never recomputes the
/// aggregate finality rule (issue #571 decision 2).
final class ReportsAggregateControllerProvider
    extends
        $NotifierProvider<
          ReportsAggregateController,
          ReportsAggregateScreenState
        > {
  /// Aggregated Soll-Ist reports controller: the on-screen JSON aggregation
  /// plus user-initiated aggregate-PDF fetch/preview/share. Finality and day
  /// counts render verbatim from the DTO — the client never recomputes the
  /// aggregate finality rule (issue #571 decision 2).
  ReportsAggregateControllerProvider._({
    required ReportsAggregateControllerFamily super.from,
    required ReportsAggregateScope super.argument,
  }) : super(
         retry: null,
         name: r'reportsAggregateControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$reportsAggregateControllerHash();

  @override
  String toString() {
    return r'reportsAggregateControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ReportsAggregateController create() => ReportsAggregateController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReportsAggregateScreenState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReportsAggregateScreenState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReportsAggregateControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$reportsAggregateControllerHash() =>
    r'60458a8db3d471396a9704a54c7fbb063924b401';

/// Aggregated Soll-Ist reports controller: the on-screen JSON aggregation
/// plus user-initiated aggregate-PDF fetch/preview/share. Finality and day
/// counts render verbatim from the DTO — the client never recomputes the
/// aggregate finality rule (issue #571 decision 2).

final class ReportsAggregateControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ReportsAggregateController,
          ReportsAggregateScreenState,
          ReportsAggregateScreenState,
          ReportsAggregateScreenState,
          ReportsAggregateScope
        > {
  ReportsAggregateControllerFamily._()
    : super(
        retry: null,
        name: r'reportsAggregateControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Aggregated Soll-Ist reports controller: the on-screen JSON aggregation
  /// plus user-initiated aggregate-PDF fetch/preview/share. Finality and day
  /// counts render verbatim from the DTO — the client never recomputes the
  /// aggregate finality rule (issue #571 decision 2).

  ReportsAggregateControllerProvider call(ReportsAggregateScope scope) =>
      ReportsAggregateControllerProvider._(argument: scope, from: this);

  @override
  String toString() => r'reportsAggregateControllerProvider';
}

/// Aggregated Soll-Ist reports controller: the on-screen JSON aggregation
/// plus user-initiated aggregate-PDF fetch/preview/share. Finality and day
/// counts render verbatim from the DTO — the client never recomputes the
/// aggregate finality rule (issue #571 decision 2).

abstract class _$ReportsAggregateController
    extends $Notifier<ReportsAggregateScreenState> {
  late final _$args = ref.$arg as ReportsAggregateScope;
  ReportsAggregateScope get scope => _$args;

  ReportsAggregateScreenState build(ReportsAggregateScope scope);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<ReportsAggregateScreenState, ReportsAggregateScreenState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                ReportsAggregateScreenState,
                ReportsAggregateScreenState
              >,
              ReportsAggregateScreenState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
