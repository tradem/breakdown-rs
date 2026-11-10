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

/// The session-scoped shell-state key currently in force.
///
/// One source for the key space: the read ([activeSeasonPersistedProvider])
/// and the repair ([activeScopeRepairProvider], issue #817) derive the key
/// from the same provider, so an eviction can only ever target the document
/// the resolution actually read — identity B never deletes identity A's
/// reference.

@ProviderFor(activeSeasonStorageKey)
final activeSeasonStorageKeyProvider = ActiveSeasonStorageKeyProvider._();

/// The session-scoped shell-state key currently in force.
///
/// One source for the key space: the read ([activeSeasonPersistedProvider])
/// and the repair ([activeScopeRepairProvider], issue #817) derive the key
/// from the same provider, so an eviction can only ever target the document
/// the resolution actually read — identity B never deletes identity A's
/// reference.

final class ActiveSeasonStorageKeyProvider
    extends $FunctionalProvider<String, String, String>
    with $Provider<String> {
  /// The session-scoped shell-state key currently in force.
  ///
  /// One source for the key space: the read ([activeSeasonPersistedProvider])
  /// and the repair ([activeScopeRepairProvider], issue #817) derive the key
  /// from the same provider, so an eviction can only ever target the document
  /// the resolution actually read — identity B never deletes identity A's
  /// reference.
  ActiveSeasonStorageKeyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeSeasonStorageKeyProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeSeasonStorageKeyHash();

  @$internal
  @override
  $ProviderElement<String> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String create(Ref ref) {
    return activeSeasonStorageKey(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$activeSeasonStorageKeyHash() =>
    r'0a6f78228ef1bf0d8cc8a0f3360a1de39963e798';

/// The persisted active-season id FOR THE CURRENT SESSION, kept alive.
///
/// Session-scoped (CodeRabbit review fix): the key carries the
/// authenticated `sub`, so a cold start only ever hydrates the signed-in
/// identity's reference. A store failure degrades to `null` ("nothing
/// persisted") right here — failing the provider instead would arm the
/// Riverpod auto-retry timers (never settle under `pumpAndSettle` in
/// widget tests) and buy nothing in production.

@ProviderFor(activeSeasonPersisted)
final activeSeasonPersistedProvider = ActiveSeasonPersistedProvider._();

/// The persisted active-season id FOR THE CURRENT SESSION, kept alive.
///
/// Session-scoped (CodeRabbit review fix): the key carries the
/// authenticated `sub`, so a cold start only ever hydrates the signed-in
/// identity's reference. A store failure degrades to `null` ("nothing
/// persisted") right here — failing the provider instead would arm the
/// Riverpod auto-retry timers (never settle under `pumpAndSettle` in
/// widget tests) and buy nothing in production.

final class ActiveSeasonPersistedProvider
    extends $FunctionalProvider<AsyncValue<String?>, String?, FutureOr<String?>>
    with $FutureModifier<String?>, $FutureProvider<String?> {
  /// The persisted active-season id FOR THE CURRENT SESSION, kept alive.
  ///
  /// Session-scoped (CodeRabbit review fix): the key carries the
  /// authenticated `sub`, so a cold start only ever hydrates the signed-in
  /// identity's reference. A store failure degrades to `null` ("nothing
  /// persisted") right here — failing the provider instead would arm the
  /// Riverpod auto-retry timers (never settle under `pumpAndSettle` in
  /// widget tests) and buy nothing in production.
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
    r'80e7cb04855d71a0af80763e8fb5d5573a1d128a';

/// Resolves the persisted active-season id against the seasons projection.
///
/// `null` when nothing is persisted or the id matches no row of the live
/// (TTL-governed) seasons view. Re-runs whenever either side changes, so
/// the resolution converges after a seasons refetch.
///
/// A persisted id that a *loaded* view no longer contains is dead state (the
/// dev-data-reset case of #810 / #770): the resolution refuses to return it,
/// and [activeScopeRepairProvider] evicts it (issue #817, the repair half of
/// #809). The resolution itself stays a pure resolver — no eviction side
/// effect — so its `.future` remains a reliable single-build await for
/// callers and tests.

@ProviderFor(activeSeasonResolution)
final activeSeasonResolutionProvider = ActiveSeasonResolutionProvider._();

/// Resolves the persisted active-season id against the seasons projection.
///
/// `null` when nothing is persisted or the id matches no row of the live
/// (TTL-governed) seasons view. Re-runs whenever either side changes, so
/// the resolution converges after a seasons refetch.
///
/// A persisted id that a *loaded* view no longer contains is dead state (the
/// dev-data-reset case of #810 / #770): the resolution refuses to return it,
/// and [activeScopeRepairProvider] evicts it (issue #817, the repair half of
/// #809). The resolution itself stays a pure resolver — no eviction side
/// effect — so its `.future` remains a reliable single-build await for
/// callers and tests.

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
  ///
  /// A persisted id that a *loaded* view no longer contains is dead state (the
  /// dev-data-reset case of #810 / #770): the resolution refuses to return it,
  /// and [activeScopeRepairProvider] evicts it (issue #817, the repair half of
  /// #809). The resolution itself stays a pure resolver — no eviction side
  /// effect — so its `.future` remains a reliable single-build await for
  /// callers and tests.
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

/// Evicts persisted shell state whose season the projection no longer serves
/// (issue #817 — the repair half of #809).
///
/// #809 made the AI-configuration entry *tolerate* a dead anchor; this is the
/// half that repairs it, so a dev data reset (#810 / #770) stops degrading
/// scope-derived UI until the user clears app data by hand.
///
/// Watching this provider performs the repair (the shell watches it once); it
/// re-runs whenever the seasons projection, the persisted anchor or the
/// persisted per-season block scopes change. Two things are removed:
///
/// - the anchor (`shell_state.active_season_id@<sub>`) once the seasons view
///   has loaded and does not contain it — compare-and-remove on the value
///   that was read, so a fresh pick that landed after this read survives;
/// - every persisted per-season block scope whose season is gone.
///   `blockScopeResolution` evicts a scope only per *resolved* season, which
///   never happens for a season the projection no longer serves.
///
/// Nothing is evicted while the seasons fetch is loading or failed: a
/// live-but-unloaded season must never be dropped. The proof of absence is
/// [SeasonsView.isLoaded] — the view deliberately always exposes a usable row
/// list (cached while the fetch is in flight, retained after a failure), so
/// "has rows" alone would treat an unloaded projection as authoritative.

@ProviderFor(activeScopeRepair)
final activeScopeRepairProvider = ActiveScopeRepairProvider._();

/// Evicts persisted shell state whose season the projection no longer serves
/// (issue #817 — the repair half of #809).
///
/// #809 made the AI-configuration entry *tolerate* a dead anchor; this is the
/// half that repairs it, so a dev data reset (#810 / #770) stops degrading
/// scope-derived UI until the user clears app data by hand.
///
/// Watching this provider performs the repair (the shell watches it once); it
/// re-runs whenever the seasons projection, the persisted anchor or the
/// persisted per-season block scopes change. Two things are removed:
///
/// - the anchor (`shell_state.active_season_id@<sub>`) once the seasons view
///   has loaded and does not contain it — compare-and-remove on the value
///   that was read, so a fresh pick that landed after this read survives;
/// - every persisted per-season block scope whose season is gone.
///   `blockScopeResolution` evicts a scope only per *resolved* season, which
///   never happens for a season the projection no longer serves.
///
/// Nothing is evicted while the seasons fetch is loading or failed: a
/// live-but-unloaded season must never be dropped. The proof of absence is
/// [SeasonsView.isLoaded] — the view deliberately always exposes a usable row
/// list (cached while the fetch is in flight, retained after a failure), so
/// "has rows" alone would treat an unloaded projection as authoritative.

final class ActiveScopeRepairProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  /// Evicts persisted shell state whose season the projection no longer serves
  /// (issue #817 — the repair half of #809).
  ///
  /// #809 made the AI-configuration entry *tolerate* a dead anchor; this is the
  /// half that repairs it, so a dev data reset (#810 / #770) stops degrading
  /// scope-derived UI until the user clears app data by hand.
  ///
  /// Watching this provider performs the repair (the shell watches it once); it
  /// re-runs whenever the seasons projection, the persisted anchor or the
  /// persisted per-season block scopes change. Two things are removed:
  ///
  /// - the anchor (`shell_state.active_season_id@<sub>`) once the seasons view
  ///   has loaded and does not contain it — compare-and-remove on the value
  ///   that was read, so a fresh pick that landed after this read survives;
  /// - every persisted per-season block scope whose season is gone.
  ///   `blockScopeResolution` evicts a scope only per *resolved* season, which
  ///   never happens for a season the projection no longer serves.
  ///
  /// Nothing is evicted while the seasons fetch is loading or failed: a
  /// live-but-unloaded season must never be dropped. The proof of absence is
  /// [SeasonsView.isLoaded] — the view deliberately always exposes a usable row
  /// list (cached while the fetch is in flight, retained after a failure), so
  /// "has rows" alone would treat an unloaded projection as authoritative.
  ActiveScopeRepairProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeScopeRepairProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeScopeRepairHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return activeScopeRepair(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$activeScopeRepairHash() => r'3a3fdabe65f324a5c2f4f8a92e08933268a5f4e4';
