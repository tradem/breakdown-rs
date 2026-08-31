// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PKCE (RFC 7636) helpers for the OIDC authorization-code flow.
///
/// The client always uses the `S256` challenge method (plain is rejected by
/// hardening review). The verifier is generated with a CSPRNG
/// ([Random.secure]) and carries ≥ 256 bits of entropy, well above the
/// RFC's 43-character floor.
class Pkce {
  Pkce._(this.verifier, this.challenge);

  /// The `code_verifier`: high-entropy ASCII string, 64–128 chars per RFC.
  final String verifier;

  /// The `code_challenge`: BASE64URL(SHA256(verifier)) without padding
  /// (`S256` method).
  final String challenge;

  /// The fixed challenge method sent to the IdP.
  static const String challengeMethod = 'S256';

  /// Unreserved `code_verifier` alphabet per RFC 7636 §4.1.
  static const String _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  /// Generates a fresh verifier/challenge pair.
  ///
  /// [random] is injectable for deterministic tests; production uses the
  /// default CSPRNG.
  factory Pkce.generate({Random? random}) {
    final rng = random ?? Random.secure();
    final verifier = List.generate(
      64,
      (_) => _alphabet[rng.nextInt(_alphabet.length)],
    ).join();
    return Pkce._(verifier, challengeFor(verifier));
  }

  /// Computes the `S256` challenge for an existing verifier (used on token
  /// refresh-free re-authentication paths and in tests).
  static String challengeFor(String verifier) => base64Url
      .encode(sha256.convert(utf8.encode(verifier)).bytes)
      .replaceAll('=', '');
}
