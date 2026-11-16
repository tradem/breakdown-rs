// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'login_screen.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Ephemeral sign-in failure from the last `signIn()` dispatch. Kept in a
/// provider (not widget state) so [LoginScreen] stays a `ConsumerWidget`;
/// cleared on every new dispatch. Sign-in never mints a session here — the
/// root gate recomposes when [authSessionControllerProvider] yields one.

@ProviderFor(SignInError)
final signInErrorProvider = SignInErrorProvider._();

/// Ephemeral sign-in failure from the last `signIn()` dispatch. Kept in a
/// provider (not widget state) so [LoginScreen] stays a `ConsumerWidget`;
/// cleared on every new dispatch. Sign-in never mints a session here — the
/// root gate recomposes when [authSessionControllerProvider] yields one.
final class SignInErrorProvider
    extends $NotifierProvider<SignInError, ProblemError?> {
  /// Ephemeral sign-in failure from the last `signIn()` dispatch. Kept in a
  /// provider (not widget state) so [LoginScreen] stays a `ConsumerWidget`;
  /// cleared on every new dispatch. Sign-in never mints a session here — the
  /// root gate recomposes when [authSessionControllerProvider] yields one.
  SignInErrorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'signInErrorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$signInErrorHash();

  @$internal
  @override
  SignInError create() => SignInError();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProblemError? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProblemError?>(value),
    );
  }
}

String _$signInErrorHash() => r'cd8fbd9072067eafe816644877d5d30bd85b57e2';

/// Ephemeral sign-in failure from the last `signIn()` dispatch. Kept in a
/// provider (not widget state) so [LoginScreen] stays a `ConsumerWidget`;
/// cleared on every new dispatch. Sign-in never mints a session here — the
/// root gate recomposes when [authSessionControllerProvider] yields one.

abstract class _$SignInError extends $Notifier<ProblemError?> {
  ProblemError? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ProblemError?, ProblemError?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ProblemError?, ProblemError?>,
              ProblemError?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Tracks the in-flight `signIn()` dispatch (the controller holds no loading
/// state for the dispatch itself — success flips straight to
/// `AsyncData(session)`). While true the actions are disabled with a
/// spinner.
///
/// `keepAlive` preserves the lifetime the hand-written `NotifierProvider`
/// already had (issue #905) — this comment previously claimed it was
/// auto-disposing. The flag is therefore cleared explicitly: set at the start
/// of a dispatch and reset in its `finally`, so a rebuilt gate never inherits a
/// stale spinner.

@ProviderFor(SignInInFlight)
final signInInFlightProvider = SignInInFlightProvider._();

/// Tracks the in-flight `signIn()` dispatch (the controller holds no loading
/// state for the dispatch itself — success flips straight to
/// `AsyncData(session)`). While true the actions are disabled with a
/// spinner.
///
/// `keepAlive` preserves the lifetime the hand-written `NotifierProvider`
/// already had (issue #905) — this comment previously claimed it was
/// auto-disposing. The flag is therefore cleared explicitly: set at the start
/// of a dispatch and reset in its `finally`, so a rebuilt gate never inherits a
/// stale spinner.
final class SignInInFlightProvider
    extends $NotifierProvider<SignInInFlight, bool> {
  /// Tracks the in-flight `signIn()` dispatch (the controller holds no loading
  /// state for the dispatch itself — success flips straight to
  /// `AsyncData(session)`). While true the actions are disabled with a
  /// spinner.
  ///
  /// `keepAlive` preserves the lifetime the hand-written `NotifierProvider`
  /// already had (issue #905) — this comment previously claimed it was
  /// auto-disposing. The flag is therefore cleared explicitly: set at the start
  /// of a dispatch and reset in its `finally`, so a rebuilt gate never inherits a
  /// stale spinner.
  SignInInFlightProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'signInInFlightProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$signInInFlightHash();

  @$internal
  @override
  SignInInFlight create() => SignInInFlight();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$signInInFlightHash() => r'486e0364a428e4a5f739120e6300e3cca90a719d';

/// Tracks the in-flight `signIn()` dispatch (the controller holds no loading
/// state for the dispatch itself — success flips straight to
/// `AsyncData(session)`). While true the actions are disabled with a
/// spinner.
///
/// `keepAlive` preserves the lifetime the hand-written `NotifierProvider`
/// already had (issue #905) — this comment previously claimed it was
/// auto-disposing. The flag is therefore cleared explicitly: set at the start
/// of a dispatch and reset in its `finally`, so a rebuilt gate never inherits a
/// stale spinner.

abstract class _$SignInInFlight extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
