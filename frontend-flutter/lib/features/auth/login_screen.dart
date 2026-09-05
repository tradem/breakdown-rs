// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import '../../design/spacing.dart';
import 'login_errors.dart';
import 'widgets/login_widgets.dart';

/// Ephemeral sign-in failure from the last `signIn()` dispatch. Kept in a
/// provider (not widget state) so [LoginScreen] stays a `ConsumerWidget`;
/// cleared on every new dispatch. Sign-in never mints a session here — the
/// root gate recomposes when [authSessionControllerProvider] yields one.
class SignInError extends Notifier<ProblemError?> {
  @override
  ProblemError? build() => null;

  void set(ProblemError? error) => state = error;
}

final signInErrorProvider = NotifierProvider<SignInError, ProblemError?>(
  SignInError.new,
);

/// Tracks the in-flight `signIn()` dispatch (the controller holds no loading
/// state for the dispatch itself — success flips straight to
/// `AsyncData(session)`). While true the actions are disabled with a
/// spinner. Auto-disposing: a rebuilt gate never inherits a stale spinner.
class SignInInFlight extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool inFlight) => state = inFlight;
}

final signInInFlightProvider = NotifierProvider<SignInInFlight, bool>(
  SignInInFlight.new,
);

/// Login screen (spec `flutter-auth-shell`, design.md §2.1).
///
/// A `ConsumerWidget`: renders and dispatches only. OIDC sign-in is
/// delegated to the auth session controller; a restore failure handed down
/// by the gate ([restoreError]) renders the same localized error surface.
/// Copy is keyed on the stable problem `code` (never server `detail`, never
/// raw exceptions); every failure carries a retry affordance.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key, this.restoreError});

  /// Session-restore failure surfaced by the root gate (`AsyncError`
  /// normalized to a stable-code [ProblemError] before it reaches here).
  /// A fresh sign-in dispatch clears it via [signInErrorProvider].
  final ProblemError? restoreError;

  Future<void> _dispatchSignIn(WidgetRef ref) async {
    ref.read(signInInFlightProvider.notifier).set(true);
    ref.read(signInErrorProvider.notifier).set(null);
    try {
      await ref.read(authSessionControllerProvider.notifier).signIn();
    } on ProblemError catch (e) {
      ref.read(signInErrorProvider.notifier).set(e);
    } catch (_) {
      // Non-ProblemError failures (e.g. a discovery throw) are normalized
      // to the stable generic code — raw exception text is never rendered.
      ref
          .read(signInErrorProvider.notifier)
          .set(const ProblemError(code: 'auth.sign_in_failed'));
    } finally {
      ref.read(signInInFlightProvider.notifier).set(false);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final inFlight = ref.watch(signInInFlightProvider);
    final signInError = ref.watch(signInErrorProvider);
    final error = signInError ?? restoreError;

    return Scaffold(
      appBar: AppBar(title: const Text('Breakdown')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (config.devAuthMode) ...[
                DevAuthNotice(sub: config.devAuthSub),
                const SizedBox(height: AppSpacing.space16),
                DevContinueButton(
                  sub: config.devAuthSub,
                  inFlight: inFlight,
                  onPressed: () => _dispatchSignIn(ref),
                ),
              ] else
                SignInButton(
                  inFlight: inFlight,
                  onPressed: () => _dispatchSignIn(ref),
                ),
              if (error != null) ...[
                const SizedBox(height: AppSpacing.space16),
                LoginErrorBanner(
                  copy: loginErrorCopy(error),
                  // Disabled while a dispatch is in flight: a second tap
                  // must not start a concurrent OIDC flow.
                  onRetry: inFlight ? null : () => _dispatchSignIn(ref),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
