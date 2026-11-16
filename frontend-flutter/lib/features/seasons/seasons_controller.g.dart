// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seasons_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Ephemeral optimistic overlay store (D2: controller state, NOT Drift).
///
/// Kept in its own [Notifier] so the overlay survives projection rebuilds
/// (`SeasonsController.build()` re-runs whenever the projection changes;
/// inlining the list there would wipe it).

@ProviderFor(SeasonOverlays)
final seasonOverlaysProvider = SeasonOverlaysProvider._();

/// Ephemeral optimistic overlay store (D2: controller state, NOT Drift).
///
/// Kept in its own [Notifier] so the overlay survives projection rebuilds
/// (`SeasonsController.build()` re-runs whenever the projection changes;
/// inlining the list there would wipe it).
final class SeasonOverlaysProvider
    extends $NotifierProvider<SeasonOverlays, List<SeasonOverlay>> {
  /// Ephemeral optimistic overlay store (D2: controller state, NOT Drift).
  ///
  /// Kept in its own [Notifier] so the overlay survives projection rebuilds
  /// (`SeasonsController.build()` re-runs whenever the projection changes;
  /// inlining the list there would wipe it).
  SeasonOverlaysProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'seasonOverlaysProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$seasonOverlaysHash();

  @$internal
  @override
  SeasonOverlays create() => SeasonOverlays();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<SeasonOverlay> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<SeasonOverlay>>(value),
    );
  }
}

String _$seasonOverlaysHash() => r'668bae0ee811847a24fe338ae9842cf72663cf57';

/// Ephemeral optimistic overlay store (D2: controller state, NOT Drift).
///
/// Kept in its own [Notifier] so the overlay survives projection rebuilds
/// (`SeasonsController.build()` re-runs whenever the projection changes;
/// inlining the list there would wipe it).

abstract class _$SeasonOverlays extends $Notifier<List<SeasonOverlay>> {
  List<SeasonOverlay> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<SeasonOverlay>, List<SeasonOverlay>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<SeasonOverlay>, List<SeasonOverlay>>,
              List<SeasonOverlay>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Last command failure, surfaced to the screen (keyed on the stable
/// problem `code`, never the `detail` text).

@ProviderFor(SeasonCommandError)
final seasonCommandErrorProvider = SeasonCommandErrorProvider._();

/// Last command failure, surfaced to the screen (keyed on the stable
/// problem `code`, never the `detail` text).
final class SeasonCommandErrorProvider
    extends $NotifierProvider<SeasonCommandError, ProblemError?> {
  /// Last command failure, surfaced to the screen (keyed on the stable
  /// problem `code`, never the `detail` text).
  SeasonCommandErrorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'seasonCommandErrorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$seasonCommandErrorHash();

  @$internal
  @override
  SeasonCommandError create() => SeasonCommandError();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProblemError? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProblemError?>(value),
    );
  }
}

String _$seasonCommandErrorHash() =>
    r'3a9a356d542c1f363fc77a461abca5061ba1b54c';

/// Last command failure, surfaced to the screen (keyed on the stable
/// problem `code`, never the `detail` text).

abstract class _$SeasonCommandError extends $Notifier<ProblemError?> {
  ProblemError? build();
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
    return element.handleCreate(ref, build);
  }
}

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

String _$seasonsControllerHash() => r'178b6e996cb503035034ed25662ed5c57e1fe600';

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
