// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seasons_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The reconciliation backoff seam (overridden with a controllable fake in
/// tests).

@ProviderFor(reconciliationScheduler)
final reconciliationSchedulerProvider = ReconciliationSchedulerProvider._();

/// The reconciliation backoff seam (overridden with a controllable fake in
/// tests).

final class ReconciliationSchedulerProvider
    extends
        $FunctionalProvider<
          ReconciliationScheduler,
          ReconciliationScheduler,
          ReconciliationScheduler
        >
    with $Provider<ReconciliationScheduler> {
  /// The reconciliation backoff seam (overridden with a controllable fake in
  /// tests).
  ReconciliationSchedulerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reconciliationSchedulerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reconciliationSchedulerHash();

  @$internal
  @override
  $ProviderElement<ReconciliationScheduler> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReconciliationScheduler create(Ref ref) {
    return reconciliationScheduler(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReconciliationScheduler value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReconciliationScheduler>(value),
    );
  }
}

String _$reconciliationSchedulerHash() =>
    r'0f4a742ba7b53da9a2ecf4ecf5c28ef57acd38da';

/// The first screen's controller — the reference pattern for every
/// subsequent screen (AGENTS.md §9).
///
/// State shape per spec `flutter-first-screen` D2; the task text's
/// `AsyncValue<List<SeasonDto>>` is the `projected` field of
/// [SeasonsScreenState] (the spec's `SeasonDto` is the generated
/// `breakdown_api` `SeasonView`).
///
/// It composes the `add-drift-read-cache` projection (Drift is the single
/// authoritative read source, D1 there) with the ephemeral optimistic
/// overlay layer, and owns the bounded-retry reconciliation on
/// `POST /v1/seasons`.

@ProviderFor(SeasonsController)
final seasonsControllerProvider = SeasonsControllerProvider._();

/// The first screen's controller — the reference pattern for every
/// subsequent screen (AGENTS.md §9).
///
/// State shape per spec `flutter-first-screen` D2; the task text's
/// `AsyncValue<List<SeasonDto>>` is the `projected` field of
/// [SeasonsScreenState] (the spec's `SeasonDto` is the generated
/// `breakdown_api` `SeasonView`).
///
/// It composes the `add-drift-read-cache` projection (Drift is the single
/// authoritative read source, D1 there) with the ephemeral optimistic
/// overlay layer, and owns the bounded-retry reconciliation on
/// `POST /v1/seasons`.
final class SeasonsControllerProvider
    extends $NotifierProvider<SeasonsController, SeasonsScreenState> {
  /// The first screen's controller — the reference pattern for every
  /// subsequent screen (AGENTS.md §9).
  ///
  /// State shape per spec `flutter-first-screen` D2; the task text's
  /// `AsyncValue<List<SeasonDto>>` is the `projected` field of
  /// [SeasonsScreenState] (the spec's `SeasonDto` is the generated
  /// `breakdown_api` `SeasonView`).
  ///
  /// It composes the `add-drift-read-cache` projection (Drift is the single
  /// authoritative read source, D1 there) with the ephemeral optimistic
  /// overlay layer, and owns the bounded-retry reconciliation on
  /// `POST /v1/seasons`.
  SeasonsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'seasonsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$seasonsControllerHash();

  @$internal
  @override
  SeasonsController create() => SeasonsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SeasonsScreenState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SeasonsScreenState>(value),
    );
  }
}

String _$seasonsControllerHash() => r'e3f2d25417617900306365e335480ed8ccbb0545';

/// The first screen's controller — the reference pattern for every
/// subsequent screen (AGENTS.md §9).
///
/// State shape per spec `flutter-first-screen` D2; the task text's
/// `AsyncValue<List<SeasonDto>>` is the `projected` field of
/// [SeasonsScreenState] (the spec's `SeasonDto` is the generated
/// `breakdown_api` `SeasonView`).
///
/// It composes the `add-drift-read-cache` projection (Drift is the single
/// authoritative read source, D1 there) with the ephemeral optimistic
/// overlay layer, and owns the bounded-retry reconciliation on
/// `POST /v1/seasons`.

abstract class _$SeasonsController extends $Notifier<SeasonsScreenState> {
  SeasonsScreenState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SeasonsScreenState, SeasonsScreenState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SeasonsScreenState, SeasonsScreenState>,
              SeasonsScreenState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
