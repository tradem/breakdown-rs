// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';

/// OIDC discovery metadata the client consumes (ADR-010 / ADR-018 contract).
///
/// The backend validates JWTs against `OIDC_ISS`, `OIDC_AUDIENCE`, and the
/// IdP's JWKS (`CachingJwksProvider`). The client never verifies signatures
/// itself (that is server-owned); it consumes the discovery document to learn
/// the authorization/token endpoints and to pin the expected issuer identity.
class OidcDiscovery {
  const OidcDiscovery({
    required this.issuer,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    this.jwksUri,
    this.revocationEndpoint,
  });

  /// The IdP's canonical issuer identifier. Must string-equal the configured
  /// `OIDC_ISS` (RFC 8414 §2 / ADR-018 — an issuer mismatch means the client
  /// is talking to the wrong IdP and the discovery result is rejected).
  final String issuer;

  final String authorizationEndpoint;
  final String tokenEndpoint;

  /// Server-owned: the backend fetches this (`OIDC_JWKS_URL`); the client
  /// surfaces it only for diagnostics. Never used to verify tokens client-side.
  final String? jwksUri;

  final String? revocationEndpoint;

  /// Parses a discovery document, validating the mandatory fields.
  /// Returns `Left` when required fields are missing.
  static Result<OidcDiscovery> fromJson(Map<String, dynamic> json) {
    final issuer = json['issuer'];
    final authorizationEndpoint = json['authorization_endpoint'];
    final tokenEndpoint = json['token_endpoint'];
    if (issuer is! String ||
        authorizationEndpoint is! String ||
        tokenEndpoint is! String) {
      return Left(
        const ProblemError(
          code: 'oidc.discovery_invalid',
          detail:
              'discovery document is missing issuer/authorization_endpoint/'
              'token_endpoint',
        ),
      );
    }
    final jwksUri = json['jwks_uri'];
    final revocationEndpoint = json['revocation_endpoint'];
    return Right(
      OidcDiscovery(
        issuer: issuer,
        authorizationEndpoint: authorizationEndpoint,
        tokenEndpoint: tokenEndpoint,
        jwksUri: jwksUri is String ? jwksUri : null,
        revocationEndpoint: revocationEndpoint is String
            ? revocationEndpoint
            : null,
      ),
    );
  }
}

/// Fetches and validates the OIDC discovery document for [issuer] from
/// `{issuer}/.well-known/openid-configuration` over the pinned Dio.
///
/// Fails closed: a wrong `iss` (issuer mismatch — the client is pointed at a
/// different IdP than configured), a malformed document, or a transport error
/// are all `Left` values (AGENTS.md §5 — fail-closed, errors are values).
Future<Result<OidcDiscovery>> discoverOidc(
  Dio dio,
  String issuer, {
  String? path = '/.well-known/openid-configuration',
}) async {
  final normalized = issuer.endsWith('/')
      ? issuer.substring(0, issuer.length - 1)
      : issuer;
  try {
    final response = await dio.get<Map<String, dynamic>>(
      '$normalized$path',
      options: Options(responseType: ResponseType.json),
    );
    final data = response.data;
    if (data == null) {
      return const Left(
        ProblemError(code: 'oidc.discovery_invalid', detail: 'empty document'),
      );
    }
    final parsed = OidcDiscovery.fromJson(data);
    // Issuer identity check (ADR-018): the document's `iss` must match the
    // configured issuer exactly.
    final Result<OidcDiscovery> verified = parsed.match(
      Left.new,
      (doc) => doc.issuer == issuer
          ? Right(doc)
          : Left(
              ProblemError(
                code: 'oidc.issuer_mismatch',
                detail:
                    'discovery issuer "${doc.issuer}" != configured "$issuer"',
              ),
            ),
    );
    return verified;
  } on DioException catch (e) {
    return Left(problemErrorFromDio(e));
  }
}
