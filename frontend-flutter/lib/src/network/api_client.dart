// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show FlutterError, kReleaseMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_config.dart';
import '../../auth/auth_providers.dart';
import '../../auth/token_store.dart';
import '../../data/settings/api_base_override_store.dart';
import 'auth_token_interceptor.dart';

/// Pinned-CA [SecurityContext] loaded once at bootstrap and reused across
/// Dio rebuilds (task 6.3). Overridden at the composition root with the
/// context from [loadPinnedSecurityContext]; reading it before the override
/// is a programming error.
final pinnedSecurityContextProvider = Provider<SecurityContext>(
  (ref) => throw UnimplementedError(
    'pinnedSecurityContextProvider must be overridden at bootstrap',
  ),
);

/// Rebuildable API [Dio] (task 6.3): the effective base is the runtime
/// override when set, else the (possibly override-merged) `AppConfig.apiBase`
/// from bootstrap. Built over the reused pinned context with the
/// bearer-attaching interceptor; every dependent client/repository rebuilds
/// when the base changes.
final apiDioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  return buildPinnedDio(
    baseUrl: ref.watch(runtimeApiBaseProvider) ?? config.apiBase,
    context: ref.watch(pinnedSecurityContextProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  );
});

/// Builds a [SecurityContext] that trusts ONLY the supplied CA certificate
/// bytes. `withTrustedRoots: false` deliberately excludes the system trust
/// store, so a certificate that is system-trusted but not chained to the
/// pinned CA is rejected (ADR-024 / AGENTS.md §5 — pinned-CA stance; D4 —
/// platform roots excluded in BOTH flavors).
///
/// The returned context is consumed by [buildApiClient], which attaches it to
/// the Dio HTTP client. Never pair this with a `badCertificateCallback` that
/// accepts everything, nor with a verification-disabled `HttpClient` — that is
/// a hard `no_insecure_tls` error.
SecurityContext pinnedSecurityContext(List<int> caPemBytes) {
  final ctx = SecurityContext(withTrustedRoots: false);
  ctx.setTrustedCertificatesBytes(Uint8List.fromList(caPemBytes));
  return ctx;
}

/// A failure to load or validate the pinned-CA configuration. Fatal at
/// startup (D4 — fail-closed): the composition root renders a
/// "TLS configuration invalid" screen and never constructs an HTTP client.
class TlsConfigError implements Exception {
  const TlsConfigError(this.message);

  final String message;

  @override
  String toString() => 'TlsConfigError: $message';
}

/// Resolves and validates the per-flavor pinned CA PEM (D4 — exclusive,
/// fail-closed).
///
/// Source precedence:
/// 1. `--dart-define=PINNED_CA_PEM` (inline PEM; CI builds inject it from
///    secrets), when non-empty;
/// 2. otherwise the flavor's bundled asset `assets/certs/<flavor>/ca.pem`
///    (the dev CA set, including the dev IdP cert).
///
/// Validation is fail-closed: an empty/missing PEM, a non-PEM body, or a PEM
/// the TLS stack cannot parse throws [TlsConfigError] — BEFORE any
/// [HttpClient] is constructed. The resulting context never contains system
/// roots (`withTrustedRoots: false`), in either flavor.
Future<SecurityContext> loadPinnedSecurityContext(
  AppConfig config, {
  // Test seam: production callers omit this, and the `PINNED_CA_PEM`
  // dart-define is read instead. Tests inject the PEM directly.
  String? inlinePem,
}) async {
  final pem = inlinePem ?? const String.fromEnvironment('PINNED_CA_PEM');
  String caPem;
  if (pem.isNotEmpty) {
    caPem = pem;
  } else {
    try {
      caPem = await rootBundle.loadString(
        'assets/certs/${config.flavor.name}/ca.pem',
      );
    } on FlutterError catch (e) {
      throw TlsConfigError(
        'pinned CA asset assets/certs/${config.flavor.name}/ca.pem could not '
        'be loaded and no PINNED_CA_PEM define was supplied (${e.message})',
      );
    }
  }

  if (caPem.trim().isEmpty) {
    throw const TlsConfigError('pinned CA configuration is empty');
  }
  if (!caPem.contains('-----BEGIN CERTIFICATE-----')) {
    throw const TlsConfigError(
      'pinned CA configuration is not valid PEM (no CERTIFICATE block)',
    );
  }

  try {
    // Parsing validates the PEM; an unparseable cert throws [TlsException].
    return pinnedSecurityContext(utf8.encode(caPem));
  } on TlsException catch (e) {
    throw TlsConfigError('pinned CA failed to parse: ${e.message}');
  }
}

/// Builds a pinned-CA [Dio] over an already-resolved [SecurityContext]
/// (synchronous core shared by [buildApiClient] and the rebuildable
/// `apiDioProvider` — the context is loaded once at bootstrap and reused
/// across base-URL rebuilds, task 6.3).
///
/// Attaches [AuthTokenInterceptor] (bearer over HTTPS only, withheld on
/// cleartext) backed by [tokenStore].
Dio buildPinnedDio({
  required String baseUrl,
  required SecurityContext context,
  required TokenStore tokenStore,
}) {
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient(context: context),
  );
  dio.interceptors.add(AuthTokenInterceptor(tokenStore));
  return dio;
}

/// Builds the [Dio] HTTP client for the active flavor with per-flavor CA
/// pinning (delegates transport construction to [buildPinnedDio]).
///
/// The base URL is taken from [AppConfig.apiBase] (sourced from `--dart-define`
/// at build time). The trusted CA is resolved by [loadPinnedSecurityContext]
/// (inline `PINNED_CA_PEM` define, else the per-flavor bundle
/// `assets/certs/<flavor>/ca.pem`), so the dev build trusts the dev-pinned CA
/// set and the prod build the pinned prod CA set. The client never opts out
/// of verification.
///
/// Throws [TlsConfigError] (fail-closed, D4) when the pinned-CA source is
/// missing or invalid — call this from the composition root where the fatal
/// screen can be rendered.
Future<Dio> buildApiClient(
  AppConfig config, {
  String? inlinePem,
  TokenStore? tokenStore,
}) async {
  // Prod requires HTTPS: a clear-text http:// base URL would bypass the
  // pinned-CA TLS context entirely, defeating the TLS pinning. Enforce
  // this at the composition root so a misconfigured --dart-define
  // API_BASE is caught early (AGENTS.md §5 — REQUIRE_IN_TRANSIT_TLS).
  assert(
    config.flavor != Flavor.prod || config.apiBase.startsWith('https://'),
    'prod flavor requires an https:// base URL; '
    'clear-text http:// bypasses the pinned CA TLS context',
  );

  final ctx = await loadPinnedSecurityContext(config, inlinePem: inlinePem);
  return buildPinnedDio(
    baseUrl: config.apiBase,
    context: ctx,
    tokenStore: tokenStore ?? SecureTokenStore(),
  );
}

/// Builds the [Dio] client used for IdP (OIDC discovery / token endpoint)
/// traffic.
///
/// Default: the same pinned-CA client as the API (D1 primary transport —
/// HTTPS + dev CA). Only under the documented D1 exception
/// (`DEV_IDP_INSECURE=1`, dev flavor, non-release) is a plain verifying
/// `HttpClient` used for the HTTP port-forward IdP host — verification stays
/// ON (system roots), and the API host keeps the pinned context.
///
/// Throws [TlsConfigError] if the flag is compiled into a release build —
/// a release artifact can never relax IdP pinning (D1 guard).
Future<Dio> buildIdpDio(AppConfig config) async {
  if (kReleaseMode && config.devIdpInsecure == '1') {
    throw const TlsConfigError(
      'DEV_IDP_INSECURE=1 was compiled into a release build; the IdP must '
      'always be pinned in release artifacts',
    );
  }
  if (config.devIdpHttpAllowed) {
    final dio = Dio(BaseOptions(baseUrl: config.oidcIss));
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: HttpClient.new,
    );
    return dio;
  }
  return buildApiClient(config);
}
