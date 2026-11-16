// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sign_out.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Session-reset coordinator (tasks 4.2/6.3): the single ordered path for
/// sign-out AND runtime backend switches.
///
/// - Sign-out: ordered cleanup in [AuthSessionController.signOut] (clear
///   tokens → gate to `LoginScreen`, fail-closed) → empty the Drift read
///   cache → reset keepAlive UI/session state. The next session can never
///   render the previous user's projections.
/// - Backend switch ([switchBackend]): persist the override → bump the
///   cache-write generation (fences in-flight reads) → rebuild the Dio
///   (provider-driven, same pinned `SecurityContext`) → await the Drift
///   clear → invalidate read providers.
///
/// Reset steps run AFTER the gate swap (sign-out) on purpose: the old
/// subtree is unwatched then, so invalidating resets state without rebuild
/// storms or projection refetches (no post-signout network — asserted in
/// tests). Auto-dispose providers (list fetch, membership fetch, view
/// controller) die with the subtree on their own; session-agnostic keepAlive
/// transports (`dio`, repositories, `oidcClient`) intentionally survive
/// (design.md §7.1).
///
/// Lives here (features-side) rather than in `auth_providers.dart` because
/// that file cannot import `features/` providers without an import cycle.

@ProviderFor(SessionReset)
final sessionResetProvider = SessionResetProvider._();

/// Session-reset coordinator (tasks 4.2/6.3): the single ordered path for
/// sign-out AND runtime backend switches.
///
/// - Sign-out: ordered cleanup in [AuthSessionController.signOut] (clear
///   tokens → gate to `LoginScreen`, fail-closed) → empty the Drift read
///   cache → reset keepAlive UI/session state. The next session can never
///   render the previous user's projections.
/// - Backend switch ([switchBackend]): persist the override → bump the
///   cache-write generation (fences in-flight reads) → rebuild the Dio
///   (provider-driven, same pinned `SecurityContext`) → await the Drift
///   clear → invalidate read providers.
///
/// Reset steps run AFTER the gate swap (sign-out) on purpose: the old
/// subtree is unwatched then, so invalidating resets state without rebuild
/// storms or projection refetches (no post-signout network — asserted in
/// tests). Auto-dispose providers (list fetch, membership fetch, view
/// controller) die with the subtree on their own; session-agnostic keepAlive
/// transports (`dio`, repositories, `oidcClient`) intentionally survive
/// (design.md §7.1).
///
/// Lives here (features-side) rather than in `auth_providers.dart` because
/// that file cannot import `features/` providers without an import cycle.
final class SessionResetProvider extends $NotifierProvider<SessionReset, void> {
  /// Session-reset coordinator (tasks 4.2/6.3): the single ordered path for
  /// sign-out AND runtime backend switches.
  ///
  /// - Sign-out: ordered cleanup in [AuthSessionController.signOut] (clear
  ///   tokens → gate to `LoginScreen`, fail-closed) → empty the Drift read
  ///   cache → reset keepAlive UI/session state. The next session can never
  ///   render the previous user's projections.
  /// - Backend switch ([switchBackend]): persist the override → bump the
  ///   cache-write generation (fences in-flight reads) → rebuild the Dio
  ///   (provider-driven, same pinned `SecurityContext`) → await the Drift
  ///   clear → invalidate read providers.
  ///
  /// Reset steps run AFTER the gate swap (sign-out) on purpose: the old
  /// subtree is unwatched then, so invalidating resets state without rebuild
  /// storms or projection refetches (no post-signout network — asserted in
  /// tests). Auto-dispose providers (list fetch, membership fetch, view
  /// controller) die with the subtree on their own; session-agnostic keepAlive
  /// transports (`dio`, repositories, `oidcClient`) intentionally survive
  /// (design.md §7.1).
  ///
  /// Lives here (features-side) rather than in `auth_providers.dart` because
  /// that file cannot import `features/` providers without an import cycle.
  SessionResetProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionResetProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionResetHash();

  @$internal
  @override
  SessionReset create() => SessionReset();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$sessionResetHash() => r'70f7634ddfeb8e73a53a3a4a6ab0103762802447';

/// Session-reset coordinator (tasks 4.2/6.3): the single ordered path for
/// sign-out AND runtime backend switches.
///
/// - Sign-out: ordered cleanup in [AuthSessionController.signOut] (clear
///   tokens → gate to `LoginScreen`, fail-closed) → empty the Drift read
///   cache → reset keepAlive UI/session state. The next session can never
///   render the previous user's projections.
/// - Backend switch ([switchBackend]): persist the override → bump the
///   cache-write generation (fences in-flight reads) → rebuild the Dio
///   (provider-driven, same pinned `SecurityContext`) → await the Drift
///   clear → invalidate read providers.
///
/// Reset steps run AFTER the gate swap (sign-out) on purpose: the old
/// subtree is unwatched then, so invalidating resets state without rebuild
/// storms or projection refetches (no post-signout network — asserted in
/// tests). Auto-dispose providers (list fetch, membership fetch, view
/// controller) die with the subtree on their own; session-agnostic keepAlive
/// transports (`dio`, repositories, `oidcClient`) intentionally survive
/// (design.md §7.1).
///
/// Lives here (features-side) rather than in `auth_providers.dart` because
/// that file cannot import `features/` providers without an import cycle.

abstract class _$SessionReset extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
