// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_block.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The sticky active-block scope. `null` means no scope is set (fresh boot
/// or signed out) — requests go out headerless, which is valid for the
/// `Authenticated`-only routes (seasons, `/blocks`, photos, reports).
///
/// `keepAlive: true` so the scope survives screen pops; consumers set it on
/// navigation into block context and clear it on sign-out.

@ProviderFor(ActiveBlock)
final activeBlockProvider = ActiveBlockProvider._();

/// The sticky active-block scope. `null` means no scope is set (fresh boot
/// or signed out) — requests go out headerless, which is valid for the
/// `Authenticated`-only routes (seasons, `/blocks`, photos, reports).
///
/// `keepAlive: true` so the scope survives screen pops; consumers set it on
/// navigation into block context and clear it on sign-out.
final class ActiveBlockProvider
    extends $NotifierProvider<ActiveBlock, ActiveScope?> {
  /// The sticky active-block scope. `null` means no scope is set (fresh boot
  /// or signed out) — requests go out headerless, which is valid for the
  /// `Authenticated`-only routes (seasons, `/blocks`, photos, reports).
  ///
  /// `keepAlive: true` so the scope survives screen pops; consumers set it on
  /// navigation into block context and clear it on sign-out.
  ActiveBlockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeBlockProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeBlockHash();

  @$internal
  @override
  ActiveBlock create() => ActiveBlock();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ActiveScope? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ActiveScope?>(value),
    );
  }
}

String _$activeBlockHash() => r'0dc1be46fa7b95d5e91a138a80cc414209118ee5';

/// The sticky active-block scope. `null` means no scope is set (fresh boot
/// or signed out) — requests go out headerless, which is valid for the
/// `Authenticated`-only routes (seasons, `/blocks`, photos, reports).
///
/// `keepAlive: true` so the scope survives screen pops; consumers set it on
/// navigation into block context and clear it on sign-out.

abstract class _$ActiveBlock extends $Notifier<ActiveScope?> {
  ActiveScope? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ActiveScope?, ActiveScope?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ActiveScope?, ActiveScope?>,
              ActiveScope?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
