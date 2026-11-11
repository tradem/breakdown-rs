// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_episode.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// When the process last PICKED each season's episode (issue #879).
///
/// A pick is written *before* the server-side projector carries the new
/// episode and before `GET /v1/episodes` can serve it, so a successful
/// projection read inside that window is not yet evidence that the episode is
/// gone — the projector-lag window §4 of `frontend-flutter/AGENTS.md` models
/// optimistically. `activeEpisodeScopeRepairProvider` therefore refuses to
/// evict a pick younger than `kEpisodeScopeSettleWindow`.
///
/// Deliberately IN MEMORY and per season (bounded by the seasons the user
/// visited, overwritten on every pick): a persisted timestamp would be renewed
/// by the cold-start restore and could never expire, and a cold start must be
/// free to repair a scope the previous session picked.

@ProviderFor(EpisodePickTimes)
final episodePickTimesProvider = EpisodePickTimesProvider._();

/// When the process last PICKED each season's episode (issue #879).
///
/// A pick is written *before* the server-side projector carries the new
/// episode and before `GET /v1/episodes` can serve it, so a successful
/// projection read inside that window is not yet evidence that the episode is
/// gone — the projector-lag window §4 of `frontend-flutter/AGENTS.md` models
/// optimistically. `activeEpisodeScopeRepairProvider` therefore refuses to
/// evict a pick younger than `kEpisodeScopeSettleWindow`.
///
/// Deliberately IN MEMORY and per season (bounded by the seasons the user
/// visited, overwritten on every pick): a persisted timestamp would be renewed
/// by the cold-start restore and could never expire, and a cold start must be
/// free to repair a scope the previous session picked.
final class EpisodePickTimesProvider
    extends
        $NotifierProvider<
          EpisodePickTimes,
          Map<String, ({DateTime at, String episodeId})>
        > {
  /// When the process last PICKED each season's episode (issue #879).
  ///
  /// A pick is written *before* the server-side projector carries the new
  /// episode and before `GET /v1/episodes` can serve it, so a successful
  /// projection read inside that window is not yet evidence that the episode is
  /// gone — the projector-lag window §4 of `frontend-flutter/AGENTS.md` models
  /// optimistically. `activeEpisodeScopeRepairProvider` therefore refuses to
  /// evict a pick younger than `kEpisodeScopeSettleWindow`.
  ///
  /// Deliberately IN MEMORY and per season (bounded by the seasons the user
  /// visited, overwritten on every pick): a persisted timestamp would be renewed
  /// by the cold-start restore and could never expire, and a cold start must be
  /// free to repair a scope the previous session picked.
  EpisodePickTimesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'episodePickTimesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$episodePickTimesHash();

  @$internal
  @override
  EpisodePickTimes create() => EpisodePickTimes();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    Map<String, ({DateTime at, String episodeId})> value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<Map<String, ({DateTime at, String episodeId})>>(
            value,
          ),
    );
  }
}

String _$episodePickTimesHash() => r'cb97fd9360fb43b3ada6ecf63270af6080cef395';

/// When the process last PICKED each season's episode (issue #879).
///
/// A pick is written *before* the server-side projector carries the new
/// episode and before `GET /v1/episodes` can serve it, so a successful
/// projection read inside that window is not yet evidence that the episode is
/// gone — the projector-lag window §4 of `frontend-flutter/AGENTS.md` models
/// optimistically. `activeEpisodeScopeRepairProvider` therefore refuses to
/// evict a pick younger than `kEpisodeScopeSettleWindow`.
///
/// Deliberately IN MEMORY and per season (bounded by the seasons the user
/// visited, overwritten on every pick): a persisted timestamp would be renewed
/// by the cold-start restore and could never expire, and a cold start must be
/// free to repair a scope the previous session picked.

abstract class _$EpisodePickTimes
    extends $Notifier<Map<String, ({DateTime at, String episodeId})>> {
  Map<String, ({DateTime at, String episodeId})> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<String, ({DateTime at, String episodeId})>,
              Map<String, ({DateTime at, String episodeId})>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, ({DateTime at, String episodeId})>,
                Map<String, ({DateTime at, String episodeId})>
              >,
              Map<String, ({DateTime at, String episodeId})>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The sticky active-episode scope. `null` means no episode is in context
/// (fresh boot, signed out, or the scope was cleared) — the quick-create
/// sheet then offers only its context-free entries.
///
/// `keepAlive: true` so the scope survives screen pops; consumers set it on
/// navigation into episode context and clear it on sign-out.

@ProviderFor(ActiveEpisode)
final activeEpisodeProvider = ActiveEpisodeProvider._();

/// The sticky active-episode scope. `null` means no episode is in context
/// (fresh boot, signed out, or the scope was cleared) — the quick-create
/// sheet then offers only its context-free entries.
///
/// `keepAlive: true` so the scope survives screen pops; consumers set it on
/// navigation into episode context and clear it on sign-out.
final class ActiveEpisodeProvider
    extends $NotifierProvider<ActiveEpisode, ActiveEpisodeScope?> {
  /// The sticky active-episode scope. `null` means no episode is in context
  /// (fresh boot, signed out, or the scope was cleared) — the quick-create
  /// sheet then offers only its context-free entries.
  ///
  /// `keepAlive: true` so the scope survives screen pops; consumers set it on
  /// navigation into episode context and clear it on sign-out.
  ActiveEpisodeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeEpisodeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeEpisodeHash();

  @$internal
  @override
  ActiveEpisode create() => ActiveEpisode();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ActiveEpisodeScope? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ActiveEpisodeScope?>(value),
    );
  }
}

String _$activeEpisodeHash() => r'ac36b3b81c6fe1e2d452415da4bc4f1a88254444';

/// The sticky active-episode scope. `null` means no episode is in context
/// (fresh boot, signed out, or the scope was cleared) — the quick-create
/// sheet then offers only its context-free entries.
///
/// `keepAlive: true` so the scope survives screen pops; consumers set it on
/// navigation into episode context and clear it on sign-out.

abstract class _$ActiveEpisode extends $Notifier<ActiveEpisodeScope?> {
  ActiveEpisodeScope? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ActiveEpisodeScope?, ActiveEpisodeScope?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ActiveEpisodeScope?, ActiveEpisodeScope?>,
              ActiveEpisodeScope?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
