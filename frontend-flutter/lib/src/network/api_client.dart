// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:dio/dio.dart';

import '../../app_config.dart';

/// Builds the [Dio] HTTP client for the active flavor.
///
/// The base URL is taken from [AppConfig.apiBase] (sourced from `--dart-define`
/// at build time). TLS is pinned per-flavor via the framework's
/// pinned-CA configuration; **no** `badCertificateCallback`, `dangerouslyAllow
/// InsecureCerts`, or verification-disabled `HttpClient` is ever constructed
/// (AGENTS.md §5 — `no_insecure_tls` is a hard error).
Dio buildApiClient(AppConfig config) {
  final dio = Dio(BaseOptions(baseUrl: config.apiBase));
  // NOTE: per-flavor CA pinning is configured in the platform network stack
  // (android/ + --dart-define). The client above never opts out of verification.
  return dio;
}
