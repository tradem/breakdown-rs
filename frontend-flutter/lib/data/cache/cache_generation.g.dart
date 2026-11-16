// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_generation.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Cache-write generation (task 6.3): bumped by the session-reset
/// coordinator before every Drift clear (sign-out and backend switch), so
/// in-flight reads fence themselves out. `keepAlive` — the epoch must survive
/// screen disposal, or a reset generation would compare equal to a fresh zero
/// (`@Riverpod` defaults to auto-dispose, a plain `NotifierProvider` does not;
/// the lifetime is preserved deliberately, issue #905).

@ProviderFor(CacheGeneration)
final cacheGenerationProvider = CacheGenerationProvider._();

/// Cache-write generation (task 6.3): bumped by the session-reset
/// coordinator before every Drift clear (sign-out and backend switch), so
/// in-flight reads fence themselves out. `keepAlive` — the epoch must survive
/// screen disposal, or a reset generation would compare equal to a fresh zero
/// (`@Riverpod` defaults to auto-dispose, a plain `NotifierProvider` does not;
/// the lifetime is preserved deliberately, issue #905).
final class CacheGenerationProvider
    extends $NotifierProvider<CacheGeneration, int> {
  /// Cache-write generation (task 6.3): bumped by the session-reset
  /// coordinator before every Drift clear (sign-out and backend switch), so
  /// in-flight reads fence themselves out. `keepAlive` — the epoch must survive
  /// screen disposal, or a reset generation would compare equal to a fresh zero
  /// (`@Riverpod` defaults to auto-dispose, a plain `NotifierProvider` does not;
  /// the lifetime is preserved deliberately, issue #905).
  CacheGenerationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cacheGenerationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cacheGenerationHash();

  @$internal
  @override
  CacheGeneration create() => CacheGeneration();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$cacheGenerationHash() => r'5ed0dd50fd29fd1f6ebe72d4ab286248e6435983';

/// Cache-write generation (task 6.3): bumped by the session-reset
/// coordinator before every Drift clear (sign-out and backend switch), so
/// in-flight reads fence themselves out. `keepAlive` — the epoch must survive
/// screen disposal, or a reset generation would compare equal to a fresh zero
/// (`@Riverpod` defaults to auto-dispose, a plain `NotifierProvider` does not;
/// the lifetime is preserved deliberately, issue #905).

abstract class _$CacheGeneration extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
