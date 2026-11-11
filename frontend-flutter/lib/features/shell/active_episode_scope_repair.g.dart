// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_episode_scope_repair.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Evicts persisted active-episode scopes whose episode (or season) the
/// projections no longer serve (issue #879 — C5 of #809).
///
/// The episode-level sibling of [activeScopeRepairProvider] (issue #817): the
/// per-season episode reference in [ActiveEpisodeStore] had the same shape of
/// staleness and was never evicted, so after a dev data reset (#810 / #770) the
/// restore in `AppShell._restoreEpisodeScope` resolved to nothing and the entry
/// stayed in secure storage forever — the operator had to clear app data or the
/// persisted scope by hand (runbook §13).
///
/// Watching this provider performs the repair (the shell watches it once). Two
/// things are removed, both against a **loaded** projection only:
///
/// - the scope of a season the loaded seasons projection no longer serves —
///   the dev-data-reset case, which needs no episode read at all;
/// - the remembered episode of the **active** season once that episode's own
///   block-scoped projection has loaded without it. An episode belongs to
///   exactly one block, and the persisted document names that block, so
///   absence from `(blockId, seasonId)` is absence, not a filter artifact.
///
/// Nothing is evicted while a fetch is loading or has failed: a live-but-
/// unloaded episode must never be dropped. The proofs of absence are the
/// views' `isLoaded` flags — `SeasonsView.isLoaded` (issue #817) and
/// `EpisodesView.isLoaded` (issue #879 adds it, same contract) — because both
/// views deliberately always serve a usable row list: cached rows while a
/// fetch is in flight, retained rows after a failure, so "has rows" says
/// nothing about authority.
///
/// Nor is a pick younger than [kEpisodeScopeSettleWindow] evicted: a read
/// inside the projector-lag window is not evidence of absence yet (the
/// AI-import apply → "open imported episode" case the review caught).
///
/// The provider is auto-dispose on purpose: the shell is its only watcher, so
/// the repair's lifetime IS the shell's. When `AuthGate` drops the shell on
/// sign-out the element is disposed, and an in-flight eviction's `ref.mounted`
/// fence keeps it from writing or discarding anything afterwards.

@ProviderFor(activeEpisodeScopeRepair)
final activeEpisodeScopeRepairProvider = ActiveEpisodeScopeRepairProvider._();

/// Evicts persisted active-episode scopes whose episode (or season) the
/// projections no longer serve (issue #879 — C5 of #809).
///
/// The episode-level sibling of [activeScopeRepairProvider] (issue #817): the
/// per-season episode reference in [ActiveEpisodeStore] had the same shape of
/// staleness and was never evicted, so after a dev data reset (#810 / #770) the
/// restore in `AppShell._restoreEpisodeScope` resolved to nothing and the entry
/// stayed in secure storage forever — the operator had to clear app data or the
/// persisted scope by hand (runbook §13).
///
/// Watching this provider performs the repair (the shell watches it once). Two
/// things are removed, both against a **loaded** projection only:
///
/// - the scope of a season the loaded seasons projection no longer serves —
///   the dev-data-reset case, which needs no episode read at all;
/// - the remembered episode of the **active** season once that episode's own
///   block-scoped projection has loaded without it. An episode belongs to
///   exactly one block, and the persisted document names that block, so
///   absence from `(blockId, seasonId)` is absence, not a filter artifact.
///
/// Nothing is evicted while a fetch is loading or has failed: a live-but-
/// unloaded episode must never be dropped. The proofs of absence are the
/// views' `isLoaded` flags — `SeasonsView.isLoaded` (issue #817) and
/// `EpisodesView.isLoaded` (issue #879 adds it, same contract) — because both
/// views deliberately always serve a usable row list: cached rows while a
/// fetch is in flight, retained rows after a failure, so "has rows" says
/// nothing about authority.
///
/// Nor is a pick younger than [kEpisodeScopeSettleWindow] evicted: a read
/// inside the projector-lag window is not evidence of absence yet (the
/// AI-import apply → "open imported episode" case the review caught).
///
/// The provider is auto-dispose on purpose: the shell is its only watcher, so
/// the repair's lifetime IS the shell's. When `AuthGate` drops the shell on
/// sign-out the element is disposed, and an in-flight eviction's `ref.mounted`
/// fence keeps it from writing or discarding anything afterwards.

final class ActiveEpisodeScopeRepairProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  /// Evicts persisted active-episode scopes whose episode (or season) the
  /// projections no longer serve (issue #879 — C5 of #809).
  ///
  /// The episode-level sibling of [activeScopeRepairProvider] (issue #817): the
  /// per-season episode reference in [ActiveEpisodeStore] had the same shape of
  /// staleness and was never evicted, so after a dev data reset (#810 / #770) the
  /// restore in `AppShell._restoreEpisodeScope` resolved to nothing and the entry
  /// stayed in secure storage forever — the operator had to clear app data or the
  /// persisted scope by hand (runbook §13).
  ///
  /// Watching this provider performs the repair (the shell watches it once). Two
  /// things are removed, both against a **loaded** projection only:
  ///
  /// - the scope of a season the loaded seasons projection no longer serves —
  ///   the dev-data-reset case, which needs no episode read at all;
  /// - the remembered episode of the **active** season once that episode's own
  ///   block-scoped projection has loaded without it. An episode belongs to
  ///   exactly one block, and the persisted document names that block, so
  ///   absence from `(blockId, seasonId)` is absence, not a filter artifact.
  ///
  /// Nothing is evicted while a fetch is loading or has failed: a live-but-
  /// unloaded episode must never be dropped. The proofs of absence are the
  /// views' `isLoaded` flags — `SeasonsView.isLoaded` (issue #817) and
  /// `EpisodesView.isLoaded` (issue #879 adds it, same contract) — because both
  /// views deliberately always serve a usable row list: cached rows while a
  /// fetch is in flight, retained rows after a failure, so "has rows" says
  /// nothing about authority.
  ///
  /// Nor is a pick younger than [kEpisodeScopeSettleWindow] evicted: a read
  /// inside the projector-lag window is not evidence of absence yet (the
  /// AI-import apply → "open imported episode" case the review caught).
  ///
  /// The provider is auto-dispose on purpose: the shell is its only watcher, so
  /// the repair's lifetime IS the shell's. When `AuthGate` drops the shell on
  /// sign-out the element is disposed, and an in-flight eviction's `ref.mounted`
  /// fence keeps it from writing or discarding anything afterwards.
  ActiveEpisodeScopeRepairProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeEpisodeScopeRepairProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeEpisodeScopeRepairHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return activeEpisodeScopeRepair(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$activeEpisodeScopeRepairHash() =>
    r'e771bdb76dabcf115a4d260035b6c38b26b04e39';
