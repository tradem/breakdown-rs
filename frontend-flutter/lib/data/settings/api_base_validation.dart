// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:fpdart/fpdart.dart';

import '../../core/problem_error.dart';
import '../../core/result.dart';

/// Emulator/loopback hosts that may serve cleartext HTTP in the `dev` flavor
/// (spec `flutter-app-dialogs`: the dev default is `http://10.0.2.2:3000`).
const Set<String> kDevCleartextHosts = {'10.0.2.2', '127.0.0.1', 'localhost'};

/// Validates a backend-URI override for the settings dialog (spec
/// `flutter-app-dialogs`, task 6.4; bootstrap re-validates defensively).
///
/// Rules, per flavor:
/// - must be an absolute URI with a non-empty host;
/// - `https` is always accepted;
/// - `http` is accepted in `dev` ONLY for [kDevCleartextHosts]
///   (emulator/loopback) — any other cleartext host is rejected (CWE-319: no
///   session credential is ever transmitted in the clear to an arbitrary
///   host; the transport additionally withholds the bearer token on every
///   cleartext request);
/// - `http` is rejected in `prod` (defensive double-check — the prod dialog
///   has no editor at all).
///
/// Returns the canonical form (trimmed, no trailing slash) on success.
/// Pure Dart (no Flutter imports) so Tier-1 unit tests cover every rule.
Result<String> validateApiBase(String input, {required bool isDev}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return const Left(ProblemError(code: 'settings.backend_uri_empty'));
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.isAbsolute || uri.host.isEmpty) {
    return const Left(ProblemError(code: 'settings.backend_uri_not_absolute'));
  }
  switch (uri.scheme.toLowerCase()) {
    case 'https':
      break;
    case 'http':
      if (!isDev) {
        return const Left(
          ProblemError(code: 'settings.backend_uri_scheme_rejected'),
        );
      }
      if (!kDevCleartextHosts.contains(uri.host.toLowerCase())) {
        return const Left(
          ProblemError(code: 'settings.backend_uri_cleartext_rejected'),
        );
      }
    default:
      return const Left(
        ProblemError(code: 'settings.backend_uri_scheme_rejected'),
      );
  }
  var canonical = trimmed;
  while (canonical.endsWith('/')) {
    canonical = canonical.substring(0, canonical.length - 1);
  }
  return Right(canonical);
}

/// Localized client-side copy for a validation failure, keyed on the stable
/// problem `code` (never server text — this error never leaves the device).
/// Pure Dart, Tier-1 testable alongside [validateApiBase].
String apiBaseValidationCopy(ProblemError error) => switch (error.code) {
  'settings.backend_uri_empty' => 'Enter a backend address.',
  'settings.backend_uri_not_absolute' =>
    'Enter an absolute address, e.g. https://api.example.com.',
  'settings.backend_uri_scheme_rejected' =>
    'Use an https address (http is dev-only and never allowed here).',
  'settings.backend_uri_cleartext_rejected' =>
    'Plain http is only allowed for emulator and loopback hosts.',
  _ => 'This backend address is invalid (${error.code}).',
};
