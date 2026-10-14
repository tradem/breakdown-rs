// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_episode.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

String _$activeEpisodeHash() => r'466ee157ed9c5a48b33c10da1babeefd7fe8d26a';

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
