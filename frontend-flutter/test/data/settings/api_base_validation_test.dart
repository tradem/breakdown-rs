// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/data/settings/api_base_validation.dart';
import 'package:test/test.dart';

/// Tier-1 unit tests (no Flutter imports): every validation rule and the
/// copy contract for the settings dialog's inline errors.
void main() {
  group('validateApiBase', () {
    test('accepts https anywhere, both flavors', () {
      for (final isDev in [true, false]) {
        final result = validateApiBase('https://api.example.com', isDev: isDev);
        expect(result.isRight(), isTrue);
        expect(result.getRight().toNullable(), 'https://api.example.com');
      }
    });

    test('accepts emulator/loopback http in dev', () {
      for (final host in ['10.0.2.2', '127.0.0.1', 'localhost']) {
        final result = validateApiBase('http://$host:3000', isDev: true);
        expect(result.isRight(), isTrue, reason: host);
      }
    });

    test('rejects non-loopback http in dev (CWE-319)', () {
      final result = validateApiBase('http://192.168.1.10:3000', isDev: true);
      expect(result.isLeft(), isTrue);
      expect(
        result.getLeft().toNullable()?.code,
        'settings.backend_uri_cleartext_rejected',
      );
    });

    test('rejects any http in prod', () {
      final result = validateApiBase('http://10.0.2.2:3000', isDev: false);
      expect(result.isLeft(), isTrue);
      expect(
        result.getLeft().toNullable()?.code,
        'settings.backend_uri_scheme_rejected',
      );
    });

    test('rejects empty, relative, and non-http(s) input', () {
      expect(
        validateApiBase('', isDev: true).getLeft().toNullable()?.code,
        'settings.backend_uri_empty',
      );
      expect(
        validateApiBase('not-a-uri', isDev: true).getLeft().toNullable()?.code,
        'settings.backend_uri_not_absolute',
      );
      expect(
        validateApiBase(
          '/relative/path',
          isDev: true,
        ).getLeft().toNullable()?.code,
        'settings.backend_uri_not_absolute',
      );
      expect(
        validateApiBase(
          'ftp://files.example.com',
          isDev: true,
        ).getLeft().toNullable()?.code,
        'settings.backend_uri_scheme_rejected',
      );
      expect(
        validateApiBase('https://', isDev: true).getLeft().toNullable()?.code,
        'settings.backend_uri_not_absolute',
      );
    });

    test('trims and strips trailing slashes', () {
      expect(
        validateApiBase(
          '  https://api.example.com///  ',
          isDev: true,
        ).getRight().toNullable(),
        'https://api.example.com',
      );
    });
  });

  group('apiBaseValidationCopy', () {
    test('keys copy on code, never renders input', () {
      expect(
        apiBaseValidationCopy(
          const ProblemError(code: 'settings.backend_uri_empty'),
        ),
        contains('Enter a backend address'),
      );
      expect(
        apiBaseValidationCopy(
          const ProblemError(code: 'settings.backend_uri_cleartext_rejected'),
        ),
        contains('loopback'),
      );
      final unknown = apiBaseValidationCopy(
        const ProblemError(code: 'settings.whatever'),
      );
      expect(unknown, contains('settings.whatever'));
    });
  });
}
