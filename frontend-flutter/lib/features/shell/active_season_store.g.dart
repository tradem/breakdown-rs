// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_season_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The [ShellStateDao] seam (auto codegen so tests override with an
/// in-memory-Drift-backed instance via `overrideWith`).

@ProviderFor(shellStateDao)
final shellStateDaoProvider = ShellStateDaoProvider._();

/// The [ShellStateDao] seam (auto codegen so tests override with an
/// in-memory-Drift-backed instance via `overrideWith`).

final class ShellStateDaoProvider
    extends $FunctionalProvider<ShellStateDao, ShellStateDao, ShellStateDao>
    with $Provider<ShellStateDao> {
  /// The [ShellStateDao] seam (auto codegen so tests override with an
  /// in-memory-Drift-backed instance via `overrideWith`).
  ShellStateDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shellStateDaoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shellStateDaoHash();

  @$internal
  @override
  $ProviderElement<ShellStateDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ShellStateDao create(Ref ref) {
    return shellStateDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShellStateDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShellStateDao>(value),
    );
  }
}

String _$shellStateDaoHash() => r'c71e260464ed615de6899a158ea8d021f75b38a0';

/// The persisted active-season id, loaded once and kept alive.
///
/// A store failure degrades to `null` ("nothing persisted") right here —
/// failing the provider instead would arm the Riverpod auto-retry timers
/// (never settle under `pumpAndSettle` in widget tests) and buy nothing
/// in production.

@ProviderFor(activeSeasonPersisted)
final activeSeasonPersistedProvider = ActiveSeasonPersistedProvider._();

/// The persisted active-season id, loaded once and kept alive.
///
/// A store failure degrades to `null` ("nothing persisted") right here —
/// failing the provider instead would arm the Riverpod auto-retry timers
/// (never settle under `pumpAndSettle` in widget tests) and buy nothing
/// in production.

final class ActiveSeasonPersistedProvider
    extends $FunctionalProvider<AsyncValue<String?>, String?, FutureOr<String?>>
    with $FutureModifier<String?>, $FutureProvider<String?> {
  /// The persisted active-season id, loaded once and kept alive.
  ///
  /// A store failure degrades to `null` ("nothing persisted") right here —
  /// failing the provider instead would arm the Riverpod auto-retry timers
  /// (never settle under `pumpAndSettle` in widget tests) and buy nothing
  /// in production.
  ActiveSeasonPersistedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeSeasonPersistedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeSeasonPersistedHash();

  @$internal
  @override
  $FutureProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<String?> create(Ref ref) {
    return activeSeasonPersisted(ref);
  }
}

String _$activeSeasonPersistedHash() =>
    r'f2cfc99a65f1bfffb5ff75927ad695a9db8fb6b8';

/// Resolves the persisted active-season id against the seasons projection.
///
/// `null` when nothing is persisted or the id matches no row of the live
/// (TTL-governed) seasons view. Re-runs whenever either side changes, so
/// the resolution converges after a seasons refetch.

@ProviderFor(activeSeasonResolution)
final activeSeasonResolutionProvider = ActiveSeasonResolutionProvider._();

/// Resolves the persisted active-season id against the seasons projection.
///
/// `null` when nothing is persisted or the id matches no row of the live
/// (TTL-governed) seasons view. Re-runs whenever either side changes, so
/// the resolution converges after a seasons refetch.

final class ActiveSeasonResolutionProvider
    extends
        $FunctionalProvider<
          AsyncValue<SeasonView?>,
          SeasonView?,
          FutureOr<SeasonView?>
        >
    with $FutureModifier<SeasonView?>, $FutureProvider<SeasonView?> {
  /// Resolves the persisted active-season id against the seasons projection.
  ///
  /// `null` when nothing is persisted or the id matches no row of the live
  /// (TTL-governed) seasons view. Re-runs whenever either side changes, so
  /// the resolution converges after a seasons refetch.
  ActiveSeasonResolutionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeSeasonResolutionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeSeasonResolutionHash();

  @$internal
  @override
  $FutureProviderElement<SeasonView?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<SeasonView?> create(Ref ref) {
    return activeSeasonResolution(ref);
  }
}

String _$activeSeasonResolutionHash() =>
    r'c77cd0f5eefbc61aa9f3cf50927b5d1eef5eb585';
