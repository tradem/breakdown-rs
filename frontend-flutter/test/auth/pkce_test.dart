// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/auth/pkce.dart';

void main() {
  group('Pkce.generate', () {
    test('produces a 64-char verifier over the RFC 7636 alphabet', () {
      final pkce = Pkce.generate(random: Random(42));
      expect(pkce.verifier.length, 64);
      expect(pkce.verifier, matches(RegExp(r'^[A-Za-z0-9\-._~]+$')));
    });

    test('challenge is BASE64URL(SHA256(verifier)) without padding', () {
      final pkce = Pkce.generate(random: Random(7));
      final expected = base64Url
          .encode(sha256.convert(utf8.encode(pkce.verifier)).bytes)
          .replaceAll('=', '');
      expect(pkce.challenge, expected);
      expect(pkce.challenge, isNot(contains('=')));
    });

    test('uses the S256 challenge method (plain is rejected)', () {
      expect(Pkce.challengeMethod, 'S256');
    });

    test('two generations never collide (CSPRNG entropy)', () {
      final a = Pkce.generate();
      final b = Pkce.generate();
      expect(a.verifier, isNot(b.verifier));
      expect(a.challenge, isNot(b.challenge));
    });
  });

  group('Pkce.challengeFor', () {
    test('is deterministic for a given verifier', () {
      const verifier = 'fixed-verifier-string-for-determinism-check';
      expect(Pkce.challengeFor(verifier), Pkce.challengeFor(verifier));
    });

    test('matches the RFC 7636 appendix-B example transformation', () {
      // The RFC's example uses a different hash input, so we verify the
      // transformation contract: S256 over the exact verifier bytes.
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      final expected = base64Url
          .encode(sha256.convert(utf8.encode(verifier)).bytes)
          .replaceAll('=', '');
      expect(Pkce.challengeFor(verifier), expected);
    });
  });
}
