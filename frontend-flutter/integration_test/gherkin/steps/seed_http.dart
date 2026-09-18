// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: glm-5.3 (neuralwatt)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

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

/// The dev series the harness seeds into — `DEFAULT_SERIES_ID` from the
/// runner environment (the same value `buildGherkinConfig()` passes to the
/// app so the wizard and quick-create sheet submit against it), falling
/// back to the fixed dev-series UUID when unset. Deriving BOTH sides from
/// one variable keeps seed payloads and the wizard's series in sync
/// (CodeRabbit review, #456: a fixed id diverges from an env override).
String get seedSeriesId =>
    Platform.environment['DEFAULT_SERIES_ID'] ?? kDefaultSeedSeriesId;

/// Fallback dev-series UUID (the seeded dev backend's fixed series;
/// also the value `buildGherkinConfig()` defaults `DEFAULT_SERIES_ID` to).
const String kDefaultSeedSeriesId = '11111111-1111-1111-1111-111111111111';

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
    final text = await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 10));
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
    final text = await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 10));
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
/// ([seedSeriesId]) from the REAL backend. The dev series accumulates
/// seasons across runs (the dispatch/seed POSTs 409 on a taken number), and
/// the season lists order by number — a huge epoch-based number would bury
/// the seeded row off-viewport. Throws when the backend is unreachable or
/// the response cannot be parsed — the caller surfaces the failure
/// deterministically instead of silently reusing a taken number (CodeRabbit
/// review, #456: a silent `1` fallback reproduces exactly the 409 this
/// resolver exists to prevent).
Future<int> resolveFreeSeasonNumber() async {
  final seasons =
      await getJson('/v1/seasons?limit=1000&offset=0') as List<dynamic>;
  final numbers = [
    for (final s in seasons)
      if (s is Map<String, dynamic> && s['series_id'] == seedSeriesId)
        (s['number'] as num).toInt(),
  ]..sort();
  var candidate = 1;
  for (final n in numbers) {
    if (n == candidate) candidate++;
  }
  return candidate;
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
/// costume created with the repertoire season binding (issue #453 backend
/// fix: `POST /v1/costumes` accepts `season_id`, the costume stays UNASSIGNED
/// and is still visible in the season stream — the stream's repertoire union
/// replaces the old character-join-only scoping that required the
/// server-side pre-assign workaround).
///
/// Returns the symbolic→real id map (`1`, `ch-3`, `ch-9`, `c-7`, and the
/// reassignment-dedicated `c-r`).
Future<Map<String, String>> seedCostumeAssignment() async {
  final seasonNumber = await resolveFreeSeasonNumber();
  final season = await postJson('/v1/seasons', {
    'series_id': seedSeriesId,
    'number': seasonNumber,
    'title': 'Gherkin seed',
  });
  final seasonId = season['id']! as String;
  // The command 201 acks before the projector writes the read model; the
  // season-scoped character create 404s on a missing projection.
  await awaitSeasonProjection(seasonId);
  final block = await postJson('/v1/blocks', {
    'season_id': seasonId,
    'series_id': seedSeriesId,
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
  final costume = await postJson('/v1/costumes', <String, Object?>{
    'season_id': seasonId, // #453: repertoire binding → visible unassigned
  }, activeBlock: blockId);
  final costumeId = costume['id']! as String;
  // Second, DISTINCT unassigned costume for the reassignment scenario
  // (issue #454): the suite's scenarios share ONE seed run, so scenario 1's
  // assign mutates `c-7` (leaves it at version 2 = assigned); a scenario that
  // needs to first-assign then reassign must operate on its OWN costume that
  // no other scenario touches. `c-r` stays unassigned until the reassign
  // scenario assigns it.
  final reassignCostume = await postJson('/v1/costumes', <String, Object?>{
    'season_id': seasonId,
  }, activeBlock: blockId);
  final reassignCostumeId = reassignCostume['id']! as String;
  return {
    '1': seasonId,
    'ch-3': character3['id']! as String,
    'ch-9': character9['id']! as String,
    'c-7': costumeId,
    'c-r': reassignCostumeId,
  };
}
