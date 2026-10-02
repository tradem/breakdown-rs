// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reports_index_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// `ReportsIndexController(scope)` — a pure projection of the episode's
/// existing day-list controller state (`shootingDaysControllerProvider`),
/// plus the season-scoped membership gate.
///
/// The index issues ZERO HTTP requests of its own: it watches
/// `shootingDaysControllerProvider(episodeId)` and projects its
/// `ProjectedShootingDayRow`s into index rows — no new fetch, no new Drift
/// table, no new repository (design decision 2). It inherits the day list's
/// projection-lag semantics unchanged: cached rows stay visible and
/// stale-indicated on a failed refresh, `AsyncError` carries the problem
/// `code`, and pull-to-refresh reconciles through the same controller.
// AUTHZ-GATE: the gate is the SAME client-side check the day-scoped report
// screen runs (`currentMembershipProvider` → `canViewReports`), evaluated
// BEFORE pushing that screen; it is a pre-check for the destination — the
// index itself fetches no protected data and issues zero requests on
// denial.

@ProviderFor(ReportsIndexController)
final reportsIndexControllerProvider = ReportsIndexControllerFamily._();

/// `ReportsIndexController(scope)` — a pure projection of the episode's
/// existing day-list controller state (`shootingDaysControllerProvider`),
/// plus the season-scoped membership gate.
///
/// The index issues ZERO HTTP requests of its own: it watches
/// `shootingDaysControllerProvider(episodeId)` and projects its
/// `ProjectedShootingDayRow`s into index rows — no new fetch, no new Drift
/// table, no new repository (design decision 2). It inherits the day list's
/// projection-lag semantics unchanged: cached rows stay visible and
/// stale-indicated on a failed refresh, `AsyncError` carries the problem
/// `code`, and pull-to-refresh reconciles through the same controller.
// AUTHZ-GATE: the gate is the SAME client-side check the day-scoped report
// screen runs (`currentMembershipProvider` → `canViewReports`), evaluated
// BEFORE pushing that screen; it is a pre-check for the destination — the
// index itself fetches no protected data and issues zero requests on
// denial.
final class ReportsIndexControllerProvider
    extends $NotifierProvider<ReportsIndexController, ReportsIndexScreenState> {
  /// `ReportsIndexController(scope)` — a pure projection of the episode's
  /// existing day-list controller state (`shootingDaysControllerProvider`),
  /// plus the season-scoped membership gate.
  ///
  /// The index issues ZERO HTTP requests of its own: it watches
  /// `shootingDaysControllerProvider(episodeId)` and projects its
  /// `ProjectedShootingDayRow`s into index rows — no new fetch, no new Drift
  /// table, no new repository (design decision 2). It inherits the day list's
  /// projection-lag semantics unchanged: cached rows stay visible and
  /// stale-indicated on a failed refresh, `AsyncError` carries the problem
  /// `code`, and pull-to-refresh reconciles through the same controller.
  // AUTHZ-GATE: the gate is the SAME client-side check the day-scoped report
  // screen runs (`currentMembershipProvider` → `canViewReports`), evaluated
  // BEFORE pushing that screen; it is a pre-check for the destination — the
  // index itself fetches no protected data and issues zero requests on
  // denial.
  ReportsIndexControllerProvider._({
    required ReportsIndexControllerFamily super.from,
    required ReportIndexScope super.argument,
  }) : super(
         retry: null,
         name: r'reportsIndexControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$reportsIndexControllerHash();

  @override
  String toString() {
    return r'reportsIndexControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ReportsIndexController create() => ReportsIndexController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReportsIndexScreenState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReportsIndexScreenState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReportsIndexControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$reportsIndexControllerHash() =>
    r'bc0883b4b53f74b83c77840becfc770a5ed4294f';

/// `ReportsIndexController(scope)` — a pure projection of the episode's
/// existing day-list controller state (`shootingDaysControllerProvider`),
/// plus the season-scoped membership gate.
///
/// The index issues ZERO HTTP requests of its own: it watches
/// `shootingDaysControllerProvider(episodeId)` and projects its
/// `ProjectedShootingDayRow`s into index rows — no new fetch, no new Drift
/// table, no new repository (design decision 2). It inherits the day list's
/// projection-lag semantics unchanged: cached rows stay visible and
/// stale-indicated on a failed refresh, `AsyncError` carries the problem
/// `code`, and pull-to-refresh reconciles through the same controller.
// AUTHZ-GATE: the gate is the SAME client-side check the day-scoped report
// screen runs (`currentMembershipProvider` → `canViewReports`), evaluated
// BEFORE pushing that screen; it is a pre-check for the destination — the
// index itself fetches no protected data and issues zero requests on
// denial.

final class ReportsIndexControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ReportsIndexController,
          ReportsIndexScreenState,
          ReportsIndexScreenState,
          ReportsIndexScreenState,
          ReportIndexScope
        > {
  ReportsIndexControllerFamily._()
    : super(
        retry: null,
        name: r'reportsIndexControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// `ReportsIndexController(scope)` — a pure projection of the episode's
  /// existing day-list controller state (`shootingDaysControllerProvider`),
  /// plus the season-scoped membership gate.
  ///
  /// The index issues ZERO HTTP requests of its own: it watches
  /// `shootingDaysControllerProvider(episodeId)` and projects its
  /// `ProjectedShootingDayRow`s into index rows — no new fetch, no new Drift
  /// table, no new repository (design decision 2). It inherits the day list's
  /// projection-lag semantics unchanged: cached rows stay visible and
  /// stale-indicated on a failed refresh, `AsyncError` carries the problem
  /// `code`, and pull-to-refresh reconciles through the same controller.
  // AUTHZ-GATE: the gate is the SAME client-side check the day-scoped report
  // screen runs (`currentMembershipProvider` → `canViewReports`), evaluated
  // BEFORE pushing that screen; it is a pre-check for the destination — the
  // index itself fetches no protected data and issues zero requests on
  // denial.

  ReportsIndexControllerProvider call(ReportIndexScope scope) =>
      ReportsIndexControllerProvider._(argument: scope, from: this);

  @override
  String toString() => r'reportsIndexControllerProvider';
}

/// `ReportsIndexController(scope)` — a pure projection of the episode's
/// existing day-list controller state (`shootingDaysControllerProvider`),
/// plus the season-scoped membership gate.
///
/// The index issues ZERO HTTP requests of its own: it watches
/// `shootingDaysControllerProvider(episodeId)` and projects its
/// `ProjectedShootingDayRow`s into index rows — no new fetch, no new Drift
/// table, no new repository (design decision 2). It inherits the day list's
/// projection-lag semantics unchanged: cached rows stay visible and
/// stale-indicated on a failed refresh, `AsyncError` carries the problem
/// `code`, and pull-to-refresh reconciles through the same controller.
// AUTHZ-GATE: the gate is the SAME client-side check the day-scoped report
// screen runs (`currentMembershipProvider` → `canViewReports`), evaluated
// BEFORE pushing that screen; it is a pre-check for the destination — the
// index itself fetches no protected data and issues zero requests on
// denial.

abstract class _$ReportsIndexController
    extends $Notifier<ReportsIndexScreenState> {
  late final _$args = ref.$arg as ReportIndexScope;
  ReportIndexScope get scope => _$args;

  ReportsIndexScreenState build(ReportIndexScope scope);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<ReportsIndexScreenState, ReportsIndexScreenState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ReportsIndexScreenState, ReportsIndexScreenState>,
              ReportsIndexScreenState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
