// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// On-device network recorder for the instrumented Gherkin app target
/// (issue #380).
///
/// Registered ONLY by `integration_test/gherkin/app.dart` (via the
/// `debugDioInterceptors` seam in `lib/src/network/api_client.dart`) —
/// never by `main.dart`, so no production build can carry it
/// (`@visibleForTesting` flags any stray production use).
///
/// The recorder lives in the **app isolate**; the Gherkin runner executes in
/// a separate host process and reads/resets the counters through the
/// FlutterDriver data handler (`driver.requestData` → `snapshot`/`reset`),
/// not through shared memory.
abstract final class RequestRecorder {
  /// Requests that left the device through any Dio built by
  /// `buildPinnedDio` since app start (or the last [reset]). The app
  /// restarts per Gherkin scenario (`restartAppBetweenScenarios`), so the
  /// fresh isolate starts at zero.
  static int totalRequests = 0;

  /// Subset of [totalRequests] against the AUTHZ-GATED photo pipeline —
  /// paths containing `/photos` (upload, bytes, delete) or
  /// `/continuity-photos` (link/unlink). The client-side AUTHZ-GATE
  /// (AGENTS.md §5, D6) must issue ZERO of these when it refuses an action;
  /// navigation read-model fetches are legitimate traffic and stay out of
  /// this count.
  static int photoPipelineRequests = 0;

  /// Subset of [totalRequests] against the AUTHZ-GATED costume commands —
  /// paths ending `/assign` or `/unassign` (the costume-assignment command
  /// surface). The client-side AUTHZ-GATE (AGENTS.md §5, D6) must issue ZERO
  /// of these when it refuses the assignment action (issue #459); the same
  /// navigation read-model fetches stay out of this count.
  static int costumeCommandRequests = 0;

  /// Zeroes all counters (reachable via the driver `reset` command).
  static void reset() {
    totalRequests = 0;
    photoPipelineRequests = 0;
    costumeCommandRequests = 0;
  }

  /// Compact snapshot for the driver channel; parsed by the host-side steps
  /// (`total=N;photo=M;costume=K`). Kept string-based — `driver.requestData`
  /// speaks `String` only.
  static String snapshot() =>
      'total=$totalRequests;photo=$photoPipelineRequests;'
      'costume=$costumeCommandRequests';
}

/// Interceptor that records every outgoing request into [RequestRecorder].
/// Appended to each Dio by the `debugDioInterceptors` seam, so it also
/// observes requests issued through later `apiDioProvider` rebuilds
/// (runtime base override, active-block scope change).
@visibleForTesting
class RequestRecorderInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    RequestRecorder.totalRequests++;
    final path = options.uri.path;
    if (path.contains('/photos') || path.contains('/continuity-photos')) {
      RequestRecorder.photoPipelineRequests++;
    }
    // Costume assignment commands: the Gherkin viewer-denial scenario
    // asserts ZERO of these leave the device (client-side AUTHZ-GATE,
    // issue #459). A path suffix is exact (`/assign` / `/unassign`), so
    // read fetches under the same resource (e.g. `GET /costumes/{id}`) are
    // never miscounted.
    if (path.endsWith('/assign') || path.endsWith('/unassign')) {
      RequestRecorder.costumeCommandRequests++;
    }
    handler.next(options);
  }
}
