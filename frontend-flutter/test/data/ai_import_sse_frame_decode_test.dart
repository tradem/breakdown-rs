// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

import 'dart:convert';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for the app-side `ai_import.dto_invalid` on every live
/// job watch: the SSE `event: job` frames must decode through the
/// **standard** serializers (with `StandardJsonPlugin`) — the same instance
/// the generated client uses. The bare `serializers` instance lacks the
/// plugin and rejects every backend frame (its custom built_value
/// serializers expect the plugin's pair-list representation, not a raw
/// JSON map), which made `_decodeJobFrame` return `null` for every frame.
///
/// The fixture is a byte-for-byte live frame captured from
/// `GET /v1/ai-import/jobs/{id}/events` (2026-10-18, backend 0.36.0).
void main() {
  const liveFrame =
      '{"job":{"id":"01a14f76-74a8-72c6-a1a3-219586fe487a","user_id":"dev-user","document_kind":"schedule","source_format":"pdf","block_id":"01a0ddbb-f11a-7400-aec3-085b2e9d8395","dedup_key":"dev-user|schedule|pdf|4e212da27fd05c873c24df2f871ede394c3511a15a7e2d58c3738d9e43deffc9","document_digest":"4e212da27fd05c873c24df2f871ede394c3511a15a7e2d58c3738d9e43deffc9","source_handle":"ai-import/01a14f76-74a8-72c6-a1a3-219586fe487a/source","status":"dead_letter","preview_handle":null,"last_error":"validation failed: schedule extraction is not supported by this client","retries":1,"max_retries":5,"next_attempt_at":null,"created_at":"2026-10-18T14:42:05.615310Z","updated_at":"2026-10-18T14:42:07.085713Z","progress":{"stage":"extracting_text","chunk":0,"chunks_total":1,"episodes_seen":[]},"telemetry":null,"cost":null,"attempts":[{"attempt_no":1,"status":"dead_letter","error_summary":"validation failed: schedule extraction is not supported by this client","code":"domain.validation","retryable":false,"created_at":"2026-10-18T14:42:07.085713Z"}]}}';

  test('live SSE job frame decodes via standardSerializers', () {
    final decoded = jsonDecode(liveFrame);
    final response = standardSerializers.deserializeWith(
      AiImportJobResponse.serializer,
      decoded,
    );
    expect(response, isNotNull);
    expect(response!.job.id, '01a14f76-74a8-72c6-a1a3-219586fe487a');
    expect(response.job.status, JobStatus.deadLetter);
    expect(response.job.progress, isNotNull);
  });
}
