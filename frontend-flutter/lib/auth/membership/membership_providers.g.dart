// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'membership_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Fetches the season-scoped membership projection (D2 — single endpoint,
/// single source of truth). Returns the `Result` unthrown so the controller
/// below can map it to `AsyncValue` without an async-notifier retry loop.
///
/// Dev-auth mode short-circuits to the permissive membership without any
/// network call (Task 5.1).

@ProviderFor(membershipFetch)
final membershipFetchProvider = MembershipFetchFamily._();

/// Fetches the season-scoped membership projection (D2 — single endpoint,
/// single source of truth). Returns the `Result` unthrown so the controller
/// below can map it to `AsyncValue` without an async-notifier retry loop.
///
/// Dev-auth mode short-circuits to the permissive membership without any
/// network call (Task 5.1).

final class MembershipFetchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<SeasonMembershipDto>>,
          Result<SeasonMembershipDto>,
          FutureOr<Result<SeasonMembershipDto>>
        >
    with
        $FutureModifier<Result<SeasonMembershipDto>>,
        $FutureProvider<Result<SeasonMembershipDto>> {
  /// Fetches the season-scoped membership projection (D2 — single endpoint,
  /// single source of truth). Returns the `Result` unthrown so the controller
  /// below can map it to `AsyncValue` without an async-notifier retry loop.
  ///
  /// Dev-auth mode short-circuits to the permissive membership without any
  /// network call (Task 5.1).
  MembershipFetchProvider._({
    required MembershipFetchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'membershipFetchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$membershipFetchHash();

  @override
  String toString() {
    return r'membershipFetchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<SeasonMembershipDto>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<SeasonMembershipDto>> create(Ref ref) {
    final argument = this.argument as String;
    return membershipFetch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MembershipFetchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$membershipFetchHash() => r'4e82cef44c968e8f1b4fc812ca6a17254b937018';

/// Fetches the season-scoped membership projection (D2 — single endpoint,
/// single source of truth). Returns the `Result` unthrown so the controller
/// below can map it to `AsyncValue` without an async-notifier retry loop.
///
/// Dev-auth mode short-circuits to the permissive membership without any
/// network call (Task 5.1).

final class MembershipFetchFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Result<SeasonMembershipDto>>,
          String
        > {
  MembershipFetchFamily._()
    : super(
        retry: null,
        name: r'membershipFetchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Fetches the season-scoped membership projection (D2 — single endpoint,
  /// single source of truth). Returns the `Result` unthrown so the controller
  /// below can map it to `AsyncValue` without an async-notifier retry loop.
  ///
  /// Dev-auth mode short-circuits to the permissive membership without any
  /// network call (Task 5.1).

  MembershipFetchProvider call(String seasonId) =>
      MembershipFetchProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'membershipFetchProvider';
}

/// The series-level membership fetch for a **costume** (issue #535 review):
/// the client-side AUTHZ-GATE source for the **series-scoped costume-photo
/// policy** (ADR-035 B2/S2), keyed by the costume itself — mirroring the
/// server's resolution (character-first, repertoire fallback, unassigned
/// costume → first repertoire season, no resolvable container → error),
/// NOT the currently open season: a carried-over costume opened through a
/// repertoire season of a different series must gate on the costume's own
/// series, or the client would deny callers the server permits (and vice
/// versa).
///
/// Resolution order (mirror of `series_id_for_costume_strict`, api edge):
/// 1. `characterId != null` → `GET /v1/characters/{id}` → the character's
///    season → the season's series (D1 read path).
/// 2. else `seasonIds` (repertoire, ordered by `season_id` server-side) →
///    first season → the season's series (same deterministic first-season
///    pick the server makes).
/// 3. else — no character, no repertoire — `Left('costume.container-unresolved')`:
///    the gate stays pending-disabled; the server would answer 422 with the
///    same code (the photo affordances never render as a 403 narrative).
///
/// Dev-auth mode short-circuits to the permissive (or overridden-denial)
/// series membership without any network call.

@ProviderFor(seriesMembershipForCostume)
final seriesMembershipForCostumeProvider = SeriesMembershipForCostumeFamily._();

/// The series-level membership fetch for a **costume** (issue #535 review):
/// the client-side AUTHZ-GATE source for the **series-scoped costume-photo
/// policy** (ADR-035 B2/S2), keyed by the costume itself — mirroring the
/// server's resolution (character-first, repertoire fallback, unassigned
/// costume → first repertoire season, no resolvable container → error),
/// NOT the currently open season: a carried-over costume opened through a
/// repertoire season of a different series must gate on the costume's own
/// series, or the client would deny callers the server permits (and vice
/// versa).
///
/// Resolution order (mirror of `series_id_for_costume_strict`, api edge):
/// 1. `characterId != null` → `GET /v1/characters/{id}` → the character's
///    season → the season's series (D1 read path).
/// 2. else `seasonIds` (repertoire, ordered by `season_id` server-side) →
///    first season → the season's series (same deterministic first-season
///    pick the server makes).
/// 3. else — no character, no repertoire — `Left('costume.container-unresolved')`:
///    the gate stays pending-disabled; the server would answer 422 with the
///    same code (the photo affordances never render as a 403 narrative).
///
/// Dev-auth mode short-circuits to the permissive (or overridden-denial)
/// series membership without any network call.

final class SeriesMembershipForCostumeProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<SeriesMembershipDto>>,
          Result<SeriesMembershipDto>,
          FutureOr<Result<SeriesMembershipDto>>
        >
    with
        $FutureModifier<Result<SeriesMembershipDto>>,
        $FutureProvider<Result<SeriesMembershipDto>> {
  /// The series-level membership fetch for a **costume** (issue #535 review):
  /// the client-side AUTHZ-GATE source for the **series-scoped costume-photo
  /// policy** (ADR-035 B2/S2), keyed by the costume itself — mirroring the
  /// server's resolution (character-first, repertoire fallback, unassigned
  /// costume → first repertoire season, no resolvable container → error),
  /// NOT the currently open season: a carried-over costume opened through a
  /// repertoire season of a different series must gate on the costume's own
  /// series, or the client would deny callers the server permits (and vice
  /// versa).
  ///
  /// Resolution order (mirror of `series_id_for_costume_strict`, api edge):
  /// 1. `characterId != null` → `GET /v1/characters/{id}` → the character's
  ///    season → the season's series (D1 read path).
  /// 2. else `seasonIds` (repertoire, ordered by `season_id` server-side) →
  ///    first season → the season's series (same deterministic first-season
  ///    pick the server makes).
  /// 3. else — no character, no repertoire — `Left('costume.container-unresolved')`:
  ///    the gate stays pending-disabled; the server would answer 422 with the
  ///    same code (the photo affordances never render as a 403 narrative).
  ///
  /// Dev-auth mode short-circuits to the permissive (or overridden-denial)
  /// series membership without any network call.
  SeriesMembershipForCostumeProvider._({
    required SeriesMembershipForCostumeFamily super.from,
    required CostumeView super.argument,
  }) : super(
         retry: null,
         name: r'seriesMembershipForCostumeProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$seriesMembershipForCostumeHash();

  @override
  String toString() {
    return r'seriesMembershipForCostumeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<SeriesMembershipDto>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<SeriesMembershipDto>> create(Ref ref) {
    final argument = this.argument as CostumeView;
    return seriesMembershipForCostume(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SeriesMembershipForCostumeProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$seriesMembershipForCostumeHash() =>
    r'475ccc6f434e7afbd4a4f80b6161b1000d6f4b50';

/// The series-level membership fetch for a **costume** (issue #535 review):
/// the client-side AUTHZ-GATE source for the **series-scoped costume-photo
/// policy** (ADR-035 B2/S2), keyed by the costume itself — mirroring the
/// server's resolution (character-first, repertoire fallback, unassigned
/// costume → first repertoire season, no resolvable container → error),
/// NOT the currently open season: a carried-over costume opened through a
/// repertoire season of a different series must gate on the costume's own
/// series, or the client would deny callers the server permits (and vice
/// versa).
///
/// Resolution order (mirror of `series_id_for_costume_strict`, api edge):
/// 1. `characterId != null` → `GET /v1/characters/{id}` → the character's
///    season → the season's series (D1 read path).
/// 2. else `seasonIds` (repertoire, ordered by `season_id` server-side) →
///    first season → the season's series (same deterministic first-season
///    pick the server makes).
/// 3. else — no character, no repertoire — `Left('costume.container-unresolved')`:
///    the gate stays pending-disabled; the server would answer 422 with the
///    same code (the photo affordances never render as a 403 narrative).
///
/// Dev-auth mode short-circuits to the permissive (or overridden-denial)
/// series membership without any network call.

final class SeriesMembershipForCostumeFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Result<SeriesMembershipDto>>,
          CostumeView
        > {
  SeriesMembershipForCostumeFamily._()
    : super(
        retry: null,
        name: r'seriesMembershipForCostumeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The series-level membership fetch for a **costume** (issue #535 review):
  /// the client-side AUTHZ-GATE source for the **series-scoped costume-photo
  /// policy** (ADR-035 B2/S2), keyed by the costume itself — mirroring the
  /// server's resolution (character-first, repertoire fallback, unassigned
  /// costume → first repertoire season, no resolvable container → error),
  /// NOT the currently open season: a carried-over costume opened through a
  /// repertoire season of a different series must gate on the costume's own
  /// series, or the client would deny callers the server permits (and vice
  /// versa).
  ///
  /// Resolution order (mirror of `series_id_for_costume_strict`, api edge):
  /// 1. `characterId != null` → `GET /v1/characters/{id}` → the character's
  ///    season → the season's series (D1 read path).
  /// 2. else `seasonIds` (repertoire, ordered by `season_id` server-side) →
  ///    first season → the season's series (same deterministic first-season
  ///    pick the server makes).
  /// 3. else — no character, no repertoire — `Left('costume.container-unresolved')`:
  ///    the gate stays pending-disabled; the server would answer 422 with the
  ///    same code (the photo affordances never render as a 403 narrative).
  ///
  /// Dev-auth mode short-circuits to the permissive (or overridden-denial)
  /// series membership without any network call.

  SeriesMembershipForCostumeProvider call(CostumeView costume) =>
      SeriesMembershipForCostumeProvider._(argument: costume, from: this);

  @override
  String toString() => r'seriesMembershipForCostumeProvider';
}

/// The client-side AUTHZ-GATE source (D2/D3).
///
/// `currentMembershipProvider(seasonId)` exposes an
/// `AsyncValue<SeasonMembershipDto>`:
/// - `AsyncLoading` — the gated action is disabled with a spinner, never
///   reported as forbidden (D3).
/// - `AsyncError` — disabled with a retry affordance (`ref.refresh`); a
///   transient error, not a 403 narrative (D3).
/// - `AsyncData` — the resolved membership. A *resolved denial* is
///   `canUploadContinuityPhotos == false` (or the matching capability):
///   gated actions short-circuit client-side with a localized 403 narrative
///   keyed on the backend problem `code`, and never issue the request. The
///   server remains authoritative — a client `true` is a gate only.

@ProviderFor(CurrentMembership)
final currentMembershipProvider = CurrentMembershipFamily._();

/// The client-side AUTHZ-GATE source (D2/D3).
///
/// `currentMembershipProvider(seasonId)` exposes an
/// `AsyncValue<SeasonMembershipDto>`:
/// - `AsyncLoading` — the gated action is disabled with a spinner, never
///   reported as forbidden (D3).
/// - `AsyncError` — disabled with a retry affordance (`ref.refresh`); a
///   transient error, not a 403 narrative (D3).
/// - `AsyncData` — the resolved membership. A *resolved denial* is
///   `canUploadContinuityPhotos == false` (or the matching capability):
///   gated actions short-circuit client-side with a localized 403 narrative
///   keyed on the backend problem `code`, and never issue the request. The
///   server remains authoritative — a client `true` is a gate only.
final class CurrentMembershipProvider
    extends
        $NotifierProvider<CurrentMembership, AsyncValue<SeasonMembershipDto>> {
  /// The client-side AUTHZ-GATE source (D2/D3).
  ///
  /// `currentMembershipProvider(seasonId)` exposes an
  /// `AsyncValue<SeasonMembershipDto>`:
  /// - `AsyncLoading` — the gated action is disabled with a spinner, never
  ///   reported as forbidden (D3).
  /// - `AsyncError` — disabled with a retry affordance (`ref.refresh`); a
  ///   transient error, not a 403 narrative (D3).
  /// - `AsyncData` — the resolved membership. A *resolved denial* is
  ///   `canUploadContinuityPhotos == false` (or the matching capability):
  ///   gated actions short-circuit client-side with a localized 403 narrative
  ///   keyed on the backend problem `code`, and never issue the request. The
  ///   server remains authoritative — a client `true` is a gate only.
  CurrentMembershipProvider._({
    required CurrentMembershipFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'currentMembershipProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$currentMembershipHash();

  @override
  String toString() {
    return r'currentMembershipProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CurrentMembership create() => CurrentMembership();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<SeasonMembershipDto> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<SeasonMembershipDto>>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CurrentMembershipProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$currentMembershipHash() => r'ec71a84b6b4ffbc6824461db0ed3616a3909fcf0';

/// The client-side AUTHZ-GATE source (D2/D3).
///
/// `currentMembershipProvider(seasonId)` exposes an
/// `AsyncValue<SeasonMembershipDto>`:
/// - `AsyncLoading` — the gated action is disabled with a spinner, never
///   reported as forbidden (D3).
/// - `AsyncError` — disabled with a retry affordance (`ref.refresh`); a
///   transient error, not a 403 narrative (D3).
/// - `AsyncData` — the resolved membership. A *resolved denial* is
///   `canUploadContinuityPhotos == false` (or the matching capability):
///   gated actions short-circuit client-side with a localized 403 narrative
///   keyed on the backend problem `code`, and never issue the request. The
///   server remains authoritative — a client `true` is a gate only.

final class CurrentMembershipFamily extends $Family
    with
        $ClassFamilyOverride<
          CurrentMembership,
          AsyncValue<SeasonMembershipDto>,
          AsyncValue<SeasonMembershipDto>,
          AsyncValue<SeasonMembershipDto>,
          String
        > {
  CurrentMembershipFamily._()
    : super(
        retry: null,
        name: r'currentMembershipProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The client-side AUTHZ-GATE source (D2/D3).
  ///
  /// `currentMembershipProvider(seasonId)` exposes an
  /// `AsyncValue<SeasonMembershipDto>`:
  /// - `AsyncLoading` — the gated action is disabled with a spinner, never
  ///   reported as forbidden (D3).
  /// - `AsyncError` — disabled with a retry affordance (`ref.refresh`); a
  ///   transient error, not a 403 narrative (D3).
  /// - `AsyncData` — the resolved membership. A *resolved denial* is
  ///   `canUploadContinuityPhotos == false` (or the matching capability):
  ///   gated actions short-circuit client-side with a localized 403 narrative
  ///   keyed on the backend problem `code`, and never issue the request. The
  ///   server remains authoritative — a client `true` is a gate only.

  CurrentMembershipProvider call(String seasonId) =>
      CurrentMembershipProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'currentMembershipProvider';
}

/// The client-side AUTHZ-GATE source (D2/D3).
///
/// `currentMembershipProvider(seasonId)` exposes an
/// `AsyncValue<SeasonMembershipDto>`:
/// - `AsyncLoading` — the gated action is disabled with a spinner, never
///   reported as forbidden (D3).
/// - `AsyncError` — disabled with a retry affordance (`ref.refresh`); a
///   transient error, not a 403 narrative (D3).
/// - `AsyncData` — the resolved membership. A *resolved denial* is
///   `canUploadContinuityPhotos == false` (or the matching capability):
///   gated actions short-circuit client-side with a localized 403 narrative
///   keyed on the backend problem `code`, and never issue the request. The
///   server remains authoritative — a client `true` is a gate only.

abstract class _$CurrentMembership
    extends $Notifier<AsyncValue<SeasonMembershipDto>> {
  late final _$args = ref.$arg as String;
  String get seasonId => _$args;

  AsyncValue<SeasonMembershipDto> build(String seasonId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<SeasonMembershipDto>,
              AsyncValue<SeasonMembershipDto>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<SeasonMembershipDto>,
                AsyncValue<SeasonMembershipDto>
              >,
              AsyncValue<SeasonMembershipDto>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
