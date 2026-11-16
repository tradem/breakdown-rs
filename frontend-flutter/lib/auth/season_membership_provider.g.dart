// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'season_membership_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// TTL-scoped cache for the strict-parsed membership read (design.md §5).
/// `keepAlive` — the TTL window must survive screen disposal, or every child
/// navigation would refetch (issue #905).

@ProviderFor(SeasonMembershipCache)
final seasonMembershipCacheProvider = SeasonMembershipCacheProvider._();

/// TTL-scoped cache for the strict-parsed membership read (design.md §5).
/// `keepAlive` — the TTL window must survive screen disposal, or every child
/// navigation would refetch (issue #905).
final class SeasonMembershipCacheProvider
    extends
        $NotifierProvider<
          SeasonMembershipCache,
          Map<String, SeasonMembershipEntry>
        > {
  /// TTL-scoped cache for the strict-parsed membership read (design.md §5).
  /// `keepAlive` — the TTL window must survive screen disposal, or every child
  /// navigation would refetch (issue #905).
  SeasonMembershipCacheProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'seasonMembershipCacheProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$seasonMembershipCacheHash();

  @$internal
  @override
  SeasonMembershipCache create() => SeasonMembershipCache();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, SeasonMembershipEntry> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, SeasonMembershipEntry>>(
        value,
      ),
    );
  }
}

String _$seasonMembershipCacheHash() =>
    r'264ebbfee1bc079c1384c6fc92dc25883994a81b';

/// TTL-scoped cache for the strict-parsed membership read (design.md §5).
/// `keepAlive` — the TTL window must survive screen disposal, or every child
/// navigation would refetch (issue #905).

abstract class _$SeasonMembershipCache
    extends $Notifier<Map<String, SeasonMembershipEntry>> {
  Map<String, SeasonMembershipEntry> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<String, SeasonMembershipEntry>,
              Map<String, SeasonMembershipEntry>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, SeasonMembershipEntry>,
                Map<String, SeasonMembershipEntry>
              >,
              Map<String, SeasonMembershipEntry>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Season-scoped membership read with strict capability parsing
/// (`flutter-hierarchy-navigation` 3.1).
///
/// Family provider over `GET /v1/seasons/{id}/membership` (via the existing
/// [membershipFetchProvider], so dev-auth short-circuit and the CURRENT
/// session wiring are reused): an unknown capability string rejects the DTO
/// as `Err` ([strictParseMembership]); fresh cache entries (younger than
/// [kMembershipTtl] per the injectable [clockProvider]) are served without
/// a network call so child navigation never refetches. Not keepAlive — the
/// TTL cache alongside it is.
///
/// Phase 1 uses this read for display (capabilities chip) only; gated
/// capability actions beyond it are future-phase concerns (D6).

@ProviderFor(seasonMembership)
final seasonMembershipProvider = SeasonMembershipFamily._();

/// Season-scoped membership read with strict capability parsing
/// (`flutter-hierarchy-navigation` 3.1).
///
/// Family provider over `GET /v1/seasons/{id}/membership` (via the existing
/// [membershipFetchProvider], so dev-auth short-circuit and the CURRENT
/// session wiring are reused): an unknown capability string rejects the DTO
/// as `Err` ([strictParseMembership]); fresh cache entries (younger than
/// [kMembershipTtl] per the injectable [clockProvider]) are served without
/// a network call so child navigation never refetches. Not keepAlive — the
/// TTL cache alongside it is.
///
/// Phase 1 uses this read for display (capabilities chip) only; gated
/// capability actions beyond it are future-phase concerns (D6).

final class SeasonMembershipProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<SeasonMembershipDto>>,
          Result<SeasonMembershipDto>,
          FutureOr<Result<SeasonMembershipDto>>
        >
    with
        $FutureModifier<Result<SeasonMembershipDto>>,
        $FutureProvider<Result<SeasonMembershipDto>> {
  /// Season-scoped membership read with strict capability parsing
  /// (`flutter-hierarchy-navigation` 3.1).
  ///
  /// Family provider over `GET /v1/seasons/{id}/membership` (via the existing
  /// [membershipFetchProvider], so dev-auth short-circuit and the CURRENT
  /// session wiring are reused): an unknown capability string rejects the DTO
  /// as `Err` ([strictParseMembership]); fresh cache entries (younger than
  /// [kMembershipTtl] per the injectable [clockProvider]) are served without
  /// a network call so child navigation never refetches. Not keepAlive — the
  /// TTL cache alongside it is.
  ///
  /// Phase 1 uses this read for display (capabilities chip) only; gated
  /// capability actions beyond it are future-phase concerns (D6).
  SeasonMembershipProvider._({
    required SeasonMembershipFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'seasonMembershipProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$seasonMembershipHash();

  @override
  String toString() {
    return r'seasonMembershipProvider'
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
    return seasonMembership(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SeasonMembershipProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$seasonMembershipHash() => r'127bd78381cfaad853a30cb6bbbb088654a5d473';

/// Season-scoped membership read with strict capability parsing
/// (`flutter-hierarchy-navigation` 3.1).
///
/// Family provider over `GET /v1/seasons/{id}/membership` (via the existing
/// [membershipFetchProvider], so dev-auth short-circuit and the CURRENT
/// session wiring are reused): an unknown capability string rejects the DTO
/// as `Err` ([strictParseMembership]); fresh cache entries (younger than
/// [kMembershipTtl] per the injectable [clockProvider]) are served without
/// a network call so child navigation never refetches. Not keepAlive — the
/// TTL cache alongside it is.
///
/// Phase 1 uses this read for display (capabilities chip) only; gated
/// capability actions beyond it are future-phase concerns (D6).

final class SeasonMembershipFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Result<SeasonMembershipDto>>,
          String
        > {
  SeasonMembershipFamily._()
    : super(
        retry: null,
        name: r'seasonMembershipProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Season-scoped membership read with strict capability parsing
  /// (`flutter-hierarchy-navigation` 3.1).
  ///
  /// Family provider over `GET /v1/seasons/{id}/membership` (via the existing
  /// [membershipFetchProvider], so dev-auth short-circuit and the CURRENT
  /// session wiring are reused): an unknown capability string rejects the DTO
  /// as `Err` ([strictParseMembership]); fresh cache entries (younger than
  /// [kMembershipTtl] per the injectable [clockProvider]) are served without
  /// a network call so child navigation never refetches. Not keepAlive — the
  /// TTL cache alongside it is.
  ///
  /// Phase 1 uses this read for display (capabilities chip) only; gated
  /// capability actions beyond it are future-phase concerns (D6).

  SeasonMembershipProvider call(String seasonId) =>
      SeasonMembershipProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'seasonMembershipProvider';
}
