// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_flutter/testing/request_recorder.dart';

/// Tier-1 unit test for the on-device Gherkin request recorder (issue #380):
/// route scoping (photo pipeline vs. navigation traffic) and snapshot/reset
/// semantics. Pure logic — no driver, no app, no wall clock.
void main() {
  // Every test starts from a clean recorder.
  setUp(RequestRecorder.reset);

  void record(String rawPath) {
    // `onRequest` calls `handler.next` synchronously, so the counters are
    // settled as soon as it returns (no timers, no awaiting needed).
    RequestRecorderInterceptor().onRequest(
      RequestOptions(path: rawPath, baseUrl: 'http://10.0.2.2:3000'),
      RequestInterceptorHandler(),
    );
  }

  test('counts a photo upload against the photo pipeline and the total', () {
    record('/v1/pieces/c1/photos');
    expect(RequestRecorder.totalRequests, 1);
    expect(RequestRecorder.photoPipelineRequests, 1);
  });

  test('counts photo bytes and continuity link routes as photo pipeline', () {
    record('/v1/pieces/c1/photos/p1/bytes');
    record(
      '/v1/shooting-days/d1/scenes/s1/scene-shoots/ssh1/continuity-photos',
    );
    expect(RequestRecorder.totalRequests, 2);
    expect(RequestRecorder.photoPipelineRequests, 2);
  });

  test('counts piece assign/unassign commands against the piece counter', () {
    record('/v1/pieces/c1/assign');
    record('/v1/pieces/c1/unassign');
    expect(RequestRecorder.totalRequests, 2);
    expect(RequestRecorder.pieceCommandRequests, 2);
    // Read fetches under the same resource are NOT command traffic.
    record('/v1/pieces/c1');
    record('/v1/pieces/c1/details');
    expect(RequestRecorder.pieceCommandRequests, 2);
    expect(RequestRecorder.totalRequests, 4);
  });

  test('navigation read-model fetches count ONLY against the total', () {
    record('/v1/seasons');
    record('/v1/blocks');
    record('/v1/pieces/c1/details');
    expect(RequestRecorder.totalRequests, 3);
    // The client-side AUTHZ-GATE (D6) must prevent capture-pipeline
    // traffic — page loads are legitimate and must not trip the preflight
    // assertion.
    expect(RequestRecorder.photoPipelineRequests, 0);
  });

  test('counts a look command as outfit traffic, not as a read', () {
    RequestRecorderInterceptor().onRequest(
      RequestOptions(
        path: '/v1/outfits/o1/pieces',
        baseUrl: 'http://10.0.2.2:3000',
        method: 'POST',
      ),
      RequestInterceptorHandler(),
    );
    expect(RequestRecorder.outfitCommandRequests, 1);
    // A read of the same resource is legitimate navigation traffic.
    RequestRecorderInterceptor().onRequest(
      RequestOptions(
        path: '/v1/characters/c1/outfits',
        baseUrl: 'http://10.0.2.2:3000',
      ),
      RequestInterceptorHandler(),
    );
    expect(RequestRecorder.outfitCommandRequests, 1);
    expect(RequestRecorder.totalRequests, 2);
  });

  test('snapshot carries all counts and reset zeroes them', () {
    record('/v1/seasons');
    record('/v1/pieces/c1/photos');
    record('/v1/pieces/c1/assign');
    RequestRecorderInterceptor().onRequest(
      RequestOptions(
        path: '/v1/outfits/o1/name',
        baseUrl: 'http://10.0.2.2:3000',
        method: 'PATCH',
      ),
      RequestInterceptorHandler(),
    );
    expect(
      RequestRecorder.snapshot(),
      'total=4;photo=1;piece=1;outfit=1',
      reason:
          'the driver channel speaks String only — the steps parse '
          'this exact shape',
    );

    RequestRecorder.reset();
    expect(RequestRecorder.totalRequests, 0);
    expect(RequestRecorder.photoPipelineRequests, 0);
    expect(RequestRecorder.pieceCommandRequests, 0);
    expect(RequestRecorder.outfitCommandRequests, 0);
    expect(RequestRecorder.snapshot(), 'total=0;photo=0;piece=0;outfit=0');
  });

  test('interceptor lets the request through to the next handler', () {
    final options = RequestOptions(path: '/v1/seasons');
    final handler = RequestInterceptorHandler();
    RequestRecorderInterceptor().onRequest(options, handler);
    expect(handler.isCompleted, isTrue, reason: 'next(options) was called');
    expect(RequestRecorder.totalRequests, 1);
  });
}
