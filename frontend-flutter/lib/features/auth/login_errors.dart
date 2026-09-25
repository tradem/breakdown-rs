// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import '../../core/problem_error.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/generated/app_localizations_en.dart';

/// Localized client-side copy for a sign-in or session-restore failure,
/// keyed on the stable problem `code` (AGENTS.md §5 — never branch on or
/// show the server's localized `detail`, never render raw exception text).
/// Unknown codes fall back to a code-carrying generic so the copy is always
/// actionable and the `code` stays greppable in bug reports.
///
/// Pure Dart (no Flutter imports) so Tier-1 unit tests cover every branch.
String loginErrorCopy(ProblemError error, [AppLocalizations? catalog]) {
  final l10n = catalog ?? AppLocalizationsEn();
  return switch (error.code) {
    'oidc.authorization_ui_not_configured' => l10n.authErrorConfiguration,
    'auth.restore_failed' => l10n.authErrorRestore,
    'auth.sign_in_failed' => l10n.authErrorSignInFailed,
    _ when error.code.startsWith('transport.') => l10n.authErrorNetwork,
    _
        when error.code.startsWith('authz.') ||
            error.code == 'auth.session_required' =>
      l10n.problemAuthzSessionRequired,
    _ => l10n.authErrorGeneric,
  };
}
