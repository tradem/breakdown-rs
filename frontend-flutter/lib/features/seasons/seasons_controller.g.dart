// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seasons_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

String _$seasonsControllerHash() => r'7fb6085e0e646fb30f967e75165f306044ec6021';

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

/// One season row by id, CACHE-FIRST — the read DTO a detail screen needs to
/// dispatch a command that takes a `SeasonView` (the scene detail's cast route
/// to the character detail, issue #834 follow-up).
///
/// A cached hit is served without a network call. A miss fetches THROUGH
/// [SeasonRepository] (`getAndCache`), the single owner of network + cache
/// writes, so the resolved row is the same DTO the season list shows. `null`
/// means the row genuinely could not be read (a transport failure): the caller
/// reports that instead of opening a screen it cannot fill — never a
/// hand-rolled DTO with guessed ids (CQRS boundary).

@ProviderFor(seasonById)
final seasonByIdProvider = SeasonByIdFamily._();

/// One season row by id, CACHE-FIRST — the read DTO a detail screen needs to
/// dispatch a command that takes a `SeasonView` (the scene detail's cast route
/// to the character detail, issue #834 follow-up).
///
/// A cached hit is served without a network call. A miss fetches THROUGH
/// [SeasonRepository] (`getAndCache`), the single owner of network + cache
/// writes, so the resolved row is the same DTO the season list shows. `null`
/// means the row genuinely could not be read (a transport failure): the caller
/// reports that instead of opening a screen it cannot fill — never a
/// hand-rolled DTO with guessed ids (CQRS boundary).

final class SeasonByIdProvider
    extends
        $FunctionalProvider<
          AsyncValue<SeasonView?>,
          SeasonView?,
          FutureOr<SeasonView?>
        >
    with $FutureModifier<SeasonView?>, $FutureProvider<SeasonView?> {
  /// One season row by id, CACHE-FIRST — the read DTO a detail screen needs to
  /// dispatch a command that takes a `SeasonView` (the scene detail's cast route
  /// to the character detail, issue #834 follow-up).
  ///
  /// A cached hit is served without a network call. A miss fetches THROUGH
  /// [SeasonRepository] (`getAndCache`), the single owner of network + cache
  /// writes, so the resolved row is the same DTO the season list shows. `null`
  /// means the row genuinely could not be read (a transport failure): the caller
  /// reports that instead of opening a screen it cannot fill — never a
  /// hand-rolled DTO with guessed ids (CQRS boundary).
  SeasonByIdProvider._({
    required SeasonByIdFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'seasonByIdProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$seasonByIdHash();

  @override
  String toString() {
    return r'seasonByIdProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<SeasonView?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<SeasonView?> create(Ref ref) {
    final argument = this.argument as String;
    return seasonById(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SeasonByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$seasonByIdHash() => r'286e33fcfe78dea83eeb6d8e189e66b9e5cbe364';

/// One season row by id, CACHE-FIRST — the read DTO a detail screen needs to
/// dispatch a command that takes a `SeasonView` (the scene detail's cast route
/// to the character detail, issue #834 follow-up).
///
/// A cached hit is served without a network call. A miss fetches THROUGH
/// [SeasonRepository] (`getAndCache`), the single owner of network + cache
/// writes, so the resolved row is the same DTO the season list shows. `null`
/// means the row genuinely could not be read (a transport failure): the caller
/// reports that instead of opening a screen it cannot fill — never a
/// hand-rolled DTO with guessed ids (CQRS boundary).

final class SeasonByIdFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<SeasonView?>, String> {
  SeasonByIdFamily._()
    : super(
        retry: null,
        name: r'seasonByIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One season row by id, CACHE-FIRST — the read DTO a detail screen needs to
  /// dispatch a command that takes a `SeasonView` (the scene detail's cast route
  /// to the character detail, issue #834 follow-up).
  ///
  /// A cached hit is served without a network call. A miss fetches THROUGH
  /// [SeasonRepository] (`getAndCache`), the single owner of network + cache
  /// writes, so the resolved row is the same DTO the season list shows. `null`
  /// means the row genuinely could not be read (a transport failure): the caller
  /// reports that instead of opening a screen it cannot fill — never a
  /// hand-rolled DTO with guessed ids (CQRS boundary).

  SeasonByIdProvider call(String seasonId) =>
      SeasonByIdProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'seasonByIdProvider';
}
