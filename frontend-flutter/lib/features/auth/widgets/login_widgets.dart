// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter/material.dart';

import '../../../design/spacing.dart';

/// Pure presentation widgets for the login screen (spec `flutter-auth-shell`,
/// design.md §2.1).
///
/// Framework-only: NO Riverpod imports here — these widgets render what they
/// are given and dispatch through callbacks. All session branching lives in
/// [LoginScreen]. Scheme roles and [AppSpacing] tokens only; no hardcoded
/// colors, text styles, or spacing literals.
class DevAuthNotice extends StatelessWidget {
  const DevAuthNotice({super.key, required this.sub});

  /// The effective `DEV_AUTH_SUB` the Continue action signs in as.
  final String sub;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('login-dev-notice'),
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space16),
        child: Row(
          children: [
            Icon(Icons.construction, color: scheme.onTertiaryContainer),
            const SizedBox(width: AppSpacing.space12),
            Expanded(
              child: Text(
                'Dev authentication in effect — continuing as $sub.',
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// OIDC sign-in action. Disabled with an inline spinner while [inFlight];
/// 48×48 minimum touch target (spec `flutter-design-tokens` contrast/
/// accessibility baseline).
class SignInButton extends StatelessWidget {
  const SignInButton({
    super.key,
    required this.inFlight,
    required this.onPressed,
  });

  final bool inFlight;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      key: const Key('login-signin-button'),
      style: ElevatedButton.styleFrom(minimumSize: const Size(48, 48)),
      onPressed: inFlight ? null : onPressed,
      child: inFlight
          ? const SizedBox(
              key: Key('login-spinner'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Sign in'),
    );
  }
}

/// Dev-auth Continue action (same 48×48 touch-target contract).
class DevContinueButton extends StatelessWidget {
  const DevContinueButton({
    super.key,
    required this.sub,
    required this.inFlight,
    required this.onPressed,
  });

  final String sub;
  final bool inFlight;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      key: const Key('login-continue-button'),
      style: ElevatedButton.styleFrom(minimumSize: const Size(48, 48)),
      onPressed: inFlight ? null : onPressed,
      child: inFlight
          ? const SizedBox(
              key: Key('login-spinner'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text('Continue as $sub'),
    );
  }
}

/// Sign-in failure surface: localized copy (already keyed on `code` by the
/// caller) plus a retry affordance. Never renders server `detail` or raw
/// exception text — the caller passes only the safe [copy].
class LoginErrorBanner extends StatelessWidget {
  const LoginErrorBanner({
    super.key,
    required this.copy,
    required this.onRetry,
  });

  final String copy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('login-error-banner'),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                copy,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            const SizedBox(width: AppSpacing.space8),
            TextButton(
              key: const Key('login-error-retry'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
