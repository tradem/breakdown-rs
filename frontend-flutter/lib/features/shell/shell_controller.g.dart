// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shell_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The shell controller (task 2.1, design D2/D7): holds the selected tab
/// index and the active season; resets both on sign-out / a new session.
///
/// `keepAlive: true` so the tab position survives screen pops inside the
/// tabs. Tab switches are user "jump" actions — they mutate only this
/// controller, never a navigation history (no tab-hopping back stack).

@ProviderFor(ShellController)
final shellControllerProvider = ShellControllerProvider._();

/// The shell controller (task 2.1, design D2/D7): holds the selected tab
/// index and the active season; resets both on sign-out / a new session.
///
/// `keepAlive: true` so the tab position survives screen pops inside the
/// tabs. Tab switches are user "jump" actions — they mutate only this
/// controller, never a navigation history (no tab-hopping back stack).
final class ShellControllerProvider
    extends $NotifierProvider<ShellController, ShellState> {
  /// The shell controller (task 2.1, design D2/D7): holds the selected tab
  /// index and the active season; resets both on sign-out / a new session.
  ///
  /// `keepAlive: true` so the tab position survives screen pops inside the
  /// tabs. Tab switches are user "jump" actions — they mutate only this
  /// controller, never a navigation history (no tab-hopping back stack).
  ShellControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shellControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shellControllerHash();

  @$internal
  @override
  ShellController create() => ShellController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShellState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShellState>(value),
    );
  }
}

String _$shellControllerHash() => r'2f66b4202f60e6a46bd17f1709fc5372d6a15d6d';

/// The shell controller (task 2.1, design D2/D7): holds the selected tab
/// index and the active season; resets both on sign-out / a new session.
///
/// `keepAlive: true` so the tab position survives screen pops inside the
/// tabs. Tab switches are user "jump" actions — they mutate only this
/// controller, never a navigation history (no tab-hopping back stack).

abstract class _$ShellController extends $Notifier<ShellState> {
  ShellState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ShellState, ShellState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ShellState, ShellState>,
              ShellState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
