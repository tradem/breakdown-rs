// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

/// Host-side HTTP helpers for the Gherkin harness seeding steps
/// (issue #368).
///
/// The Gherkin RUNNER executes on the host while the instrumented app runs
/// on the device/emulator — two separate processes. Seeding steps that talk
/// to the dev backend therefore resolve the backend from the host's
/// perspective: the emulator-only loopback alias `10.0.2.2` is unreachable
/// from the host and is substituted with `localhost` (a caller-supplied
/// non-emulator `API_BASE` passes through unchanged).
///
/// All requests are bounded (connection + response timeouts), so a stalled
/// backend fails the seeding step deterministically instead of hanging the
/// run (deterministic-tests rule, AGENTS.md §6).
library;

import 'dart:convert';
import 'dart:io';

/// The dev series the harness seeds into (same series the season-setup
/// wizard and quick-create sheet target per `DEFAULT_SERIES_ID`).
const String kSeedSeriesId = '11111111-1111-1111-1111-111111111111';

/// `API_BASE` from the runner environment, host-resolved.
String hostApiBase() =>
    (Platform.environment['API_BASE'] ?? 'http://10.0.2.2:3000').replaceFirst(
      '10.0.2.2',
      'localhost',
    );

/// GET [path] (relative to the resolved host API base) and decode the JSON
/// body. Throws on transport failure or a non-2xx status.
Future<dynamic> getJson(String path) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client
        .getUrl(Uri.parse('${hostApiBase()}$path'))
        .timeout(const Duration(seconds: 10));
    final res = await req.close().timeout(const Duration(seconds: 10));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('seed GET $path failed (${res.statusCode}): $text');
    }
    return jsonDecode(text);
  } finally {
    client.close(force: true);
  }
}

/// POSTs [body] as JSON to [path] (relative to the resolved host API base)
/// with an optional `X-Active-Block` header and decodes the JSON response
/// (2xx accepted — the seed endpoints return 200 or 201). Throws on
/// transport failure or a non-2xx status.
Future<Map<String, dynamic>> postJson(
  String path,
  Map<String, Object?> body, {
  String? activeBlock,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client
        .postUrl(Uri.parse('${hostApiBase()}$path'))
        .timeout(const Duration(seconds: 10));
    req.headers.contentType = ContentType.json;
    if (activeBlock != null) req.headers.add('X-Active-Block', activeBlock);
    req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close().timeout(const Duration(seconds: 10));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('seed POST $path failed (${res.statusCode}): $text');
    }
    // 204 No Content (e.g. the membership invite accept) has no body.
    if (text.isEmpty) return const {};
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'value': decoded};
  } finally {
    client.close(force: true);
  }
}

/// Resolves the lowest free SERIES-scoped season number in the dev series
/// ([kSeedSeriesId]) from the REAL backend. The dev series accumulates
/// seasons across runs (the dispatch/seed POSTs 409 on a taken number), and
/// the season lists order by number — a huge epoch-based number would bury
/// the seeded row off-viewport. Returns 1 when the backend is unreachable
/// (the seed POST will then fail loudly, preserving the failure signal).
Future<int> resolveFreeSeasonNumber() async {
  try {
    final seasons =
        await getJson('/v1/seasons?limit=1000&offset=0') as List<dynamic>;
    final numbers = [
      for (final s in seasons)
        if (s is Map<String, dynamic> && s['series_id'] == kSeedSeriesId)
          (s['number'] as num).toInt(),
    ]..sort();
    var candidate = 1;
    for (final n in numbers) {
      if (n == candidate) candidate++;
    }
    return candidate;
  } on Object {
    return 1;
  }
}

/// Host-side, run-scoped seed cache: the hooks seed before the first app
/// launch, the Given steps copy from here into their scenario's
/// `AppWorld.seedIds` (opaque backend ids; the app boots AFTER the seed, so
/// its projections already include the seeded aggregates — no refresh race).
class SeedCache {
  SeedCache._();

  static Map<String, String>? costumeAssignmentIds;
}

/// Polls `GET /v1/seasons/{id}` until the season projection materializes
/// (the command 201 acks before the projector writes the read model). Bounded
/// retries with fixed delays (deterministic envelope, no wall-clock
/// assertions); throws when the projection never lands within the budget.
Future<void> awaitSeasonProjection(String seasonId) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    try {
      await getJson('/v1/seasons/$seasonId');
      return;
    } on Object {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
  throw Exception('season projection $seasonId never materialized');
}

/// Seeds the costume-assignment acceptance state against the REAL dev
/// backend (issue #368): season → block (auto-bootstraps the dev principal
/// as active costume-dept member in dev-auth mode) → two characters →
/// costume → server-side pre-assign c-7 → ch-9 (the season costume stream
/// scopes through the character join, so an unassigned costume never
/// renders there — a real-backend contract discovery of this run; the
/// scenario exercises its optimistic-update + reconciliation contract as a
/// REASSIGNMENT on device).
///
/// Returns the symbolic→real id map (`1`, `ch-3`, `ch-9`, `c-7`).
Future<Map<String, String>> seedCostumeAssignment() async {
  final seasonNumber = await resolveFreeSeasonNumber();
  final season = await postJson('/v1/seasons', {
    'series_id': kSeedSeriesId,
    'number': seasonNumber,
    'title': 'Gherkin seed',
  });
  final seasonId = season['id']! as String;
  // The command 201 acks before the projector writes the read model; the
  // season-scoped character create 404s on a missing projection.
  await awaitSeasonProjection(seasonId);
  final block = await postJson('/v1/blocks', {
    'season_id': seasonId,
    'series_id': kSeedSeriesId,
    'number': seasonNumber,
  });
  final blockId = block['id']! as String;
  final character3 = await postJson('/v1/characters', {
    'season_id': seasonId,
    'name': 'Gherkin Figur',
    'category': 'main_cast',
  }, activeBlock: blockId);
  final character9 = await postJson('/v1/characters', {
    'season_id': seasonId,
    'name': 'Gherkin Vorbefund',
    'category': 'guest',
  }, activeBlock: blockId);
  final costume = await postJson(
    '/v1/costumes',
    <String, Object?>{},
    activeBlock: blockId,
  );
  final costumeId = costume['id']! as String;
  await postJson('/v1/costumes/$costumeId/assign', {
    'character_id': character9['id']! as String,
    'version': 1,
  }, activeBlock: blockId);
  return {
    '1': seasonId,
    'ch-3': character3['id']! as String,
    'ch-9': character9['id']! as String,
    'c-7': costumeId,
  };
}
