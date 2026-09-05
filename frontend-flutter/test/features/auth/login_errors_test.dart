// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/features/auth/login_errors.dart';
import 'package:test/test.dart';

/// Tier-1 unit tests (no Flutter imports): every `loginErrorCopy` branch,
/// Ok/Err-adjacent — the copy contract the login screen renders.
void main() {
  group('loginErrorCopy', () {
    test('names the fail-closed stand-in build', () {
      expect(
        loginErrorCopy(
          const ProblemError(code: 'oidc.authorization_ui_not_configured'),
        ),
        contains('oidc.authorization_ui_not_configured'),
      );
    });

    test('restore failure asks for a fresh sign-in', () {
      expect(
        loginErrorCopy(const ProblemError(code: 'auth.restore_failed')),
        contains('sign in again'),
      );
    });

    test('generic sign-in failure stays actionable', () {
      expect(
        loginErrorCopy(const ProblemError(code: 'auth.sign_in_failed')),
        contains('try again'),
      );
    });

    test('oidc.* failures carry the stable code', () {
      final copy = loginErrorCopy(const ProblemError(code: 'oidc.timeout'));
      expect(copy, contains('oidc.timeout'));
      expect(copy, contains('try again'));
    });

    test('transport.* failures read as network problems', () {
      expect(
        loginErrorCopy(const ProblemError(code: 'transport.connectionError')),
        contains('Network problem'),
      );
    });

    test('authz failures ask to sign in', () {
      expect(
        loginErrorCopy(const ProblemError(code: 'authz.denied')),
        contains('sign in'),
      );
    });

    test('unknown codes fall back to a code-carrying generic', () {
      final copy = loginErrorCopy(const ProblemError(code: 'weird.nope'));
      expect(copy, contains('weird.nope'));
    });

    test('never renders server detail or raw exception text', () {
      const error = ProblemError(
        code: 'transport.connectionError',
        detail: 'Serverseitige Detailnachricht mit Umlauten äöü',
      );
      final copy = loginErrorCopy(error);
      expect(copy, isNot(contains('Serverseitige')));
      expect(copy, isNot(contains('äöü')));
    });
  });
}
