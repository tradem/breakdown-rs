// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';

import '../../app_config.dart';

/// Builds a [SecurityContext] that trusts ONLY the supplied CA certificate
/// bytes. `withTrustedRoots: false` deliberately excludes the system trust
/// store, so a certificate that is system-trusted but not chained to the
/// pinned CA is rejected (ADR-024 / AGENTS.md §5 — pinned-CA stance).
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

/// Builds the [Dio] HTTP client for the active flavor with per-flavor CA
/// pinning.
///
/// The base URL is taken from [AppConfig.apiBase] (sourced from `--dart-define`
/// at build time). The trusted CA is loaded from the per-flavor bundle
/// `assets/certs/<flavor>/ca.pem`, so the dev build trusts the dev-pinned CA
/// set and the prod build the pinned prod CA set. TLS is pinned per-flavor via
/// the framework's pinned-CA configuration; the client above never opts out of
/// verification.
Future<Dio> buildApiClient(AppConfig config) async {
  // Prod requires HTTPS: a clear-text http:// base URL would bypass the
  // pinned-CA TLS context entirely, defeating the TLS pinning. Enforce
  // this at the composition root so a misconfigured --dart-define
  // API_BASE is caught early (AGENTS.md §5 — REQUIRE_IN_TRANSIT_TLS).
  assert(
    config.flavor != Flavor.prod || config.apiBase.startsWith('https://'),
    'prod flavor requires an https:// base URL; '
    'clear-text http:// bypasses the pinned CA TLS context',
  );

  final caPem = await rootBundle.loadString(
    'assets/certs/${config.flavor.name}/ca.pem',
  );
  final ctx = pinnedSecurityContext(utf8.encode(caPem));

  final dio = Dio(BaseOptions(baseUrl: config.apiBase));
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient(context: ctx),
  );
  return dio;
}
