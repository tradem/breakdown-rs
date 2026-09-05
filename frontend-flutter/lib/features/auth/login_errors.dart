// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import '../../core/problem_error.dart';

/// Localized client-side copy for a sign-in or session-restore failure,
/// keyed on the stable problem `code` (AGENTS.md §5 — never branch on or
/// show the server's localized `detail`, never render raw exception text).
/// Unknown codes fall back to a code-carrying generic so the copy is always
/// actionable and the `code` stays greppable in bug reports.
///
/// Pure Dart (no Flutter imports) so Tier-1 unit tests cover every branch.
String loginErrorCopy(ProblemError error) => switch (error.code) {
  'oidc.authorization_ui_not_configured' =>
    'Sign-in is not available in this build '
        '(oidc.authorization_ui_not_configured).',
  'auth.restore_failed' =>
    'Your previous session could not be restored. '
        'Please sign in again.',
  'auth.sign_in_failed' => 'Sign-in failed. Please try again.',
  _ when error.code.startsWith('oidc.') =>
    'Sign-in failed (${error.code}). Please try again.',
  _ when error.code.startsWith('transport.') =>
    'Network problem — sign-in did not complete. Try again.',
  _
      when error.code.startsWith('authz.') ||
          error.code == 'auth.session_required' =>
    'Please sign in to continue.',
  _ => 'Something went wrong (${error.code}). Please try again.',
};
