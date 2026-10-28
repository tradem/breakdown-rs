// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

/// Gherkin steps for the AI-import preview's Pass-2 surface (issue #748).
///
/// `features-spec/ai_import_continuity_gap.feature` drives the outfit
/// provenance badges and the wardrobe-gap candidate picker of the AI-import
/// preview (OpenSpec `ai-import-decision-outfit-continuity`, issue #745).
///
/// Two kinds of work happen here, and both run against real processes:
///
/// * **Arrange (host side):** the runner POSTs a stored preview payload to the
///   `test-support`-only fixture route
///   (`POST /v1/__fixtures/ai-import-preview`, issue #748) and receives the id
///   of a real, `succeeded` AI-import job. The step then READS that job's
///   preview back over `GET /v1/ai-import/jobs/{id}/preview` and asserts the
///   seeded facet — so a misconfigured fixture backend fails the arrange step
///   with its own message instead of surfacing as a mysterious missing widget.
///   The backend must be booted with `--features api/test-support` and durable
///   AI payload storage (see `tool/run_gherkin.sh`).
/// * **Act/assert (device side):** the steps drive the real app through the
///   Flutter Driver only — drawer → AI import jobs → job status → preview —
///   and assert on widget keys and rendered text. No step calls a pure
///   function to satisfy an assertion.
library;

import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter_gherkin/flutter_gherkin.dart';
import 'package:gherkin/gherkin.dart';

import '../world/app_world.dart';
import 'seed_http.dart';

/// The look the fixture's script supports for the gap figure, and the name the
/// apply card must state after the reviewer's pick.
const String _lookName = 'Zivil-Look';

/// The figure the gap belongs to (verbatim script spelling).
const String _gapCharacter = 'BEN';

/// The preview screen's scrollable list — the only surface the row/gap cards
/// live in.
const String _previewListKey = 'ai-preview-screen';

/// Upper bound on scroll gestures per target. The worst case is analytic, not a
/// sleep budget: each gesture moves up to 60% of a viewport, so eight gestures
/// cross a stored preview of five rows plus the apply card several times over.
const int kPreviewScrollAttempts = 8;

// --- Fixture payloads -------------------------------------------------------

Map<String, Object?> _scene(
  String draftRef,
  int number, {
  List<String> characters = const [],
  List<Map<String, Object?>> outfits = const [],
}) => {
  'draft_ref': draftRef,
  'scene_number': number,
  'summary': 'Handlung $draftRef',
  'characters': characters,
  'outfits': outfits,
};

Map<String, Object?> _outfit(
  String character,
  String name, {
  String quote = '',
  String? origin,
  Map<String, Object?>? provenance,
  List<Map<String, Object?>> pieces = const [],
}) => {
  'character_name': character,
  'name': name,
  'source_quote': quote,
  'origin': ?origin,
  'provenance': ?provenance,
  'pieces': pieces,
};

Map<String, Object?> _candidate(
  String origin,
  String name, {
  required String sourceDraftRef,
  required int sourceSceneNumber,
  required double confidence,
}) => {
  'origin': origin,
  'name': name,
  'source_draft_ref': sourceDraftRef,
  'source_scene_number': sourceSceneNumber,
  'confidence': confidence,
};

/// The stored Pass-2 preview of scenario 1: scene 4 continues BEN's look from
/// scene 3 (the provenance badge under test) and scene 5 names BEN without
/// dressing him — the wardrobe gap Pass 2 reports with the two looks the script
/// actually supports.
Map<String, Object?> _continuityGapPreview() => {
  'title': 'Fixture-Pilot',
  'scenes': [
    _scene(
      'row-3',
      3,
      characters: [_gapCharacter],
      outfits: [
        _outfit(
          _gapCharacter,
          _lookName,
          quote: 'trägt Zivil',
          origin: 'explicit_quote',
        ),
      ],
    ),
    _scene(
      'row-4',
      4,
      characters: [_gapCharacter, 'ANNA'],
      outfits: [
        // A Pass-2 continuation quotes NOTHING: the provenance carries the
        // source row instead (design D2/D3).
        _outfit(
          _gapCharacter,
          _lookName,
          origin: 'continued_from_scene',
          provenance: {
            'source_draft_ref': 'row-3',
            'source_scene_number': 3,
            'confidence': 0.82,
          },
        ),
      ],
    ),
    _scene('row-5', 5, characters: [_gapCharacter, 'ANNA']),
  ],
  'uncertainties': [
    {
      'scene_index': 2,
      'field': 'outfits',
      'kind': 'dropped_row',
      'note':
          'no certain wardrobe state for $_gapCharacter (confidence 0.60); '
          'pick a look or leave the scene empty',
      'candidates': [
        _candidate(
          'continued_from_scene',
          _lookName,
          sourceDraftRef: 'row-4',
          sourceSceneNumber: 4,
          confidence: 0.6,
        ),
        _candidate(
          'inferred_from_context',
          'Kontext-Look (OP-SAAL)',
          sourceDraftRef: 'row-5',
          sourceSceneNumber: 5,
          confidence: 0.55,
        ),
      ],
    },
  ],
};

/// The stored preview of scenario 2: CARLA is named in scene 5 and dressed
/// nowhere, and Pass 2 could derive NO look for her — so the preview must keep
/// the plain notice and never offer an invented pick.
Map<String, Object?> _gapWithoutCandidatesPreview() => {
  'title': 'Fixture-Pilot',
  'scenes': [
    _scene('row-1', 2, characters: ['ANNA']),
    _scene('row-2', 3, characters: ['ANNA']),
    _scene('row-3', 4, characters: ['CARLA']),
    _scene('row-4', 5, characters: ['CARLA']),
  ],
  'uncertainties': [
    {
      'scene_index': 3,
      'field': 'outfits',
      'kind': 'dropped_row',
      'note':
          'no certain wardrobe state for CARLA; the script supports no look '
          'for this scene',
    },
  ],
};

// --- Host-side seeding helpers ---------------------------------------------

/// Seeds [payload] through the fixture route and records the REAL job id under
/// [jobKey] (`AppWorld.seedIds`), so the navigation steps never guess an id.
Future<String> _seedPreview(
  AppWorld world,
  String jobKey,
  Map<String, Object?> payload,
) async {
  final seeded = await postJson('/v1/__fixtures/ai-import-preview', payload);
  final jobId = seeded['job_id'];
  if (jobId is! String || jobId.isEmpty) {
    throw Exception(
      'the AI-import preview fixture returned no job_id (is the backend booted '
      'with --features api/test-support and AI payload storage?): $seeded',
    );
  }
  world.seedIds[jobKey] = jobId;
  world.lastAiImportJobId = jobId;
  return jobId;
}

/// The stored script preview of [jobId], read back over the REAL preview route
/// (never the fixture's own echo).
Future<Map<String, dynamic>> _storedPreview(String jobId) async {
  final response = await getJson('/v1/ai-import/jobs/$jobId/preview');
  final preview = (response as Map<String, dynamic>)['preview'];
  if (preview is! Map<String, dynamic>) {
    throw Exception('the stored preview carries no typed payload: $response');
  }
  final data = preview['data'];
  if (preview['kind'] != 'script' || data is! Map<String, dynamic>) {
    throw Exception('the stored preview is not a script preview: $response');
  }
  return data;
}

List<Map<String, dynamic>> _scenesOf(Map<String, dynamic> script) => [
  for (final scene in (script['scenes'] as List<dynamic>? ?? const []))
    scene as Map<String, dynamic>,
];

Map<String, dynamic> _sceneWithNumber(Map<String, dynamic> script, int number) {
  for (final scene in _scenesOf(script)) {
    if (scene['scene_number'] == number) return scene;
  }
  throw Exception('the stored preview carries no scene number $number');
}

/// Reads the text a keyed widget RENDERS.
///
/// `FlutterDriver.getText` resolves a single `Text`; a composite widget (the
/// provenance badge, which renders one label next to its icon) has to be
/// searched for its descendant.
Future<String> _renderedTextOf(FlutterDriver driver, String key) async {
  try {
    return await driver.getText(find.byValueKey(key));
  } on DriverError {
    return driver.getText(
      find.descendant(of: find.byValueKey(key), matching: find.byType('Text')),
    );
  }
}

/// The list viewport as `(top, bottom)` in screen coordinates.
Future<(double, double)> _viewportOf(
  FlutterDriver driver,
  SerializableFinder list,
) async {
  final top = await driver.getTopLeft(list);
  final bottom = await driver.getBottomRight(list);
  return (top.dy, bottom.dy);
}

/// Moves the preview list until [key] is INSIDE the viewport, not merely built.
///
/// Presence is not enough to tap: `ListView` builds a cacheExtent of rows
/// around the viewport, and `driver.tap` taps the widget's CENTER, so a row
/// that is laid out just below the fold would be found and then missed.
/// `scrollUntilVisible` does not solve that on its own — it also stops as soon
/// as `waitFor` proves TREE presence — so this helper scrolls by the measured
/// distance between the target's center and the viewport center, in either
/// direction, and succeeds only once the center is actually on screen.
///
/// Bounded and analytic: at most [kPreviewScrollAttempts] gestures of the
/// viewport distance, never a sleep budget.
Future<void> _scrollPreviewTo(FlutterDriver driver, String key) async {
  final list = find.byValueKey(_previewListKey);
  final target = find.byValueKey(key);
  // A widget far outside the cacheExtent is not built at all: one bounded wait
  // for it to exist (no gesture) before measuring.
  await driver.waitFor(target, timeout: const Duration(seconds: 20));
  for (var attempt = 0; attempt < kPreviewScrollAttempts; attempt++) {
    final (top, bottom) = await _viewportOf(driver, list);
    final center = await driver.getCenter(target);
    if (center.dy > top && center.dy < bottom) return;
    // `scroll` moves the CONTENT: a negative dy reveals later rows. The step is
    // the measured distance, clamped to most of one viewport so an off-tree
    // estimate cannot overshoot into a jump.
    final height = bottom - top;
    final wanted = center.dy - (top + bottom) / 2;
    final step = wanted.clamp(-height * 0.6, height * 0.6);
    await driver.scroll(list, 0, step, const Duration(milliseconds: 200));
  }
  throw Exception(
    'the widget "$key" could not be scrolled into the preview viewport',
  );
}

// --- Steps ------------------------------------------------------------------

/// Seeds the Pass-2 continuity preview and proves the continuation look is on
/// the stored payload (real HTTP read of the preview route).
StepDefinitionGeneric givenContinuationLookPreview() =>
    given3<String, String, int, FlutterWorld>(
      'an AI-import preview for job {string} carries a continuation look for '
      '{string} in scene {int}',
      (String jobKey, String character, int sceneNumber, context) async {
        final world = context.world as AppWorld;
        final jobId = await _seedPreview(
          world,
          jobKey,
          _continuityGapPreview(),
        );
        final scene = _sceneWithNumber(
          await _storedPreview(jobId),
          sceneNumber,
        );
        final outfits = (scene['outfits'] as List<dynamic>? ?? const []);
        final continued = outfits.where(
          (outfit) =>
              (outfit as Map<String, dynamic>)['character_name'] == character &&
              outfit['origin'] == 'continued_from_scene',
        );
        if (continued.isEmpty) {
          throw Exception(
            'the stored preview of job "$jobId" carries no continuation look '
            'for $character in scene $sceneNumber: $scene',
          );
        }
      },
    );

/// Proves the SAME stored preview reports a candidate-carrying wardrobe gap.
StepDefinitionGeneric givenGapWithCandidates() =>
    given2<String, int, FlutterWorld>(
      'the same preview carries a wardrobe gap for {string} in scene {int} '
      'with candidates',
      (String character, int sceneNumber, context) async {
        final world = context.world as AppWorld;
        final jobId = world.lastAiImportJobId;
        if (jobId == null) {
          throw Exception('no AI-import preview was seeded for this scenario');
        }
        final script = await _storedPreview(jobId);
        final scene = _sceneWithNumber(script, sceneNumber);
        final sceneIndex = _scenesOf(script).indexOf(scene);
        final gaps = [
          for (final uncertainty
              in (script['uncertainties'] as List<dynamic>? ?? const []))
            if (uncertainty is Map<String, dynamic> &&
                uncertainty['scene_index'] == sceneIndex &&
                uncertainty['field'] == 'outfits' &&
                (uncertainty['candidates'] as List<dynamic>? ?? const [])
                    .isNotEmpty)
              uncertainty,
        ];
        if (gaps.isEmpty) {
          throw Exception(
            'the stored preview of job "$jobId" carries no candidate-carrying '
            'wardrobe gap for scene $sceneNumber: $script',
          );
        }
        // The gap figure itself is derived by the CLIENT from the payload
        // (continuity_gap.dart), so this step only pins what the wire carries:
        // the scene names [character] without dressing them.
        final dresses = [
          for (final outfit in (scene['outfits'] as List<dynamic>? ?? const []))
            (outfit as Map<String, dynamic>)['character_name'],
        ];
        if (dresses.contains(character)) {
          throw Exception(
            'scene $sceneNumber already dresses $character, so it is no gap: '
            '$scene',
          );
        }
      },
    );

/// Seeds the gap WITHOUT script-derivable candidates.
StepDefinitionGeneric givenGapWithoutCandidates() =>
    given3<String, String, int, FlutterWorld>(
      'an AI-import preview for job {string} carries a wardrobe gap for '
      '{string} in scene {int} without candidates',
      (String jobKey, String character, int sceneNumber, context) async {
        final world = context.world as AppWorld;
        final jobId = await _seedPreview(
          world,
          jobKey,
          _gapWithoutCandidatesPreview(),
        );
        final script = await _storedPreview(jobId);
        final scene = _sceneWithNumber(script, sceneNumber);
        final sceneIndex = _scenesOf(script).indexOf(scene);
        final gaps = [
          for (final uncertainty
              in (script['uncertainties'] as List<dynamic>? ?? const []))
            if (uncertainty is Map<String, dynamic> &&
                uncertainty['scene_index'] == sceneIndex &&
                uncertainty['field'] == 'outfits')
              uncertainty,
        ];
        if (gaps.length != 1) {
          throw Exception(
            'the stored preview of job "$jobId" carries no single wardrobe gap '
            'for scene $sceneNumber: $script',
          );
        }
        if ((gaps.single['candidates'] as List<dynamic>? ?? const [])
            .isNotEmpty) {
          throw Exception(
            'the no-candidate gap of job "$jobId" carries candidates: '
            '${gaps.single}',
          );
        }
      },
    );

/// Opens the preview of a seeded job through the REAL app: the account drawer's
/// AI-import entry → the jobs list → the job's status screen → its review
/// action. Nothing is pushed programmatically.
StepDefinitionGeneric whenOpenAiImportPreview() => when1<String, FlutterWorld>(
  'I open the preview for job {string}',
  (String jobKey, context) async {
    final world = context.world as AppWorld;
    final jobId = world.seedIds[jobKey] ?? jobKey;
    final driver = world.driver!;

    // The drawer entry is the season-independent route into the jobs list,
    // so the scenario needs no seeded hierarchy.
    await FlutterDriverUtils.tap(
      driver,
      find.byValueKey('profile-menu-button'),
    );
    await FlutterDriverUtils.tap(driver, find.byValueKey('profile-ai-imports'));

    // The freshly seeded job sorts first (the queue lists newest-first).
    final row = find.byValueKey('ai-jobs-row-$jobId');
    await driver.waitFor(row, timeout: const Duration(seconds: 30));
    await FlutterDriverUtils.tap(driver, row);

    // A succeeded job's status card carries the review affordance.
    final openPreview = find.byValueKey('ai-job-open-preview');
    await driver.waitFor(openPreview, timeout: const Duration(seconds: 30));
    await FlutterDriverUtils.tap(driver, openPreview);

    await driver.waitFor(
      find.byValueKey(_previewListKey),
      timeout: const Duration(seconds: 30),
    );
  },
);

/// Scrolls the preview list until the keyed widget is laid out (the rows and
/// gap cards sit below the apply card, so a plain presence assertion would
/// depend on the viewport height).
StepDefinitionGeneric thenScrollPreviewToWidget() =>
    then1<String, FlutterWorld>('I scroll the preview to the widget {string}', (
      String key,
      context,
    ) async {
      await _scrollPreviewTo(context.world.driver!, key);
    });

/// Picks the continuation candidate of a gap (`<sceneIndex>-<identity>`), the
/// one-tap resolution the issue is about.
StepDefinitionGeneric whenPickContinuationCandidate() =>
    when1<String, FlutterWorld>(
      'I pick the continuation candidate for the gap {string}',
      (String gapKey, context) async {
        final driver = context.world.driver!;
        final chipKey = 'ai-preview-gap-pick-$gapKey-continued';
        await _scrollPreviewTo(driver, chipKey);
        await FlutterDriverUtils.tap(driver, find.byValueKey(chipKey));
      },
    );

/// Asserts an ABSENT widget. The budget bounds the wait for a stale widget to
/// disappear; callers assert a positive anchor (the notice, the preview
/// screen) first, so absence is never asserted against an unloaded screen.
StepDefinitionGeneric thenNoWidgetWithin() => then2<String, int, FlutterWorld>(
  'I expect no widget {string} to be present within {int} seconds',
  (String key, int seconds, context) async {
    final driver = context.world.driver!;
    await FlutterDriverUtils.waitUntil(
      driver,
      () async => FlutterDriverUtils.isAbsent(driver, find.byValueKey(key)),
      timeout: Duration(seconds: seconds),
    );
  },
);

/// Asserts the RENDERED text of a keyed widget contains a fragment — the
/// reviewer-facing statement (which look the gap scene will wear) is read off
/// the device, not recomputed here.
StepDefinitionGeneric thenWidgetContainsText() =>
    then2<String, String, FlutterWorld>(
      'I expect the widget {string} to contain the text {string}',
      (String key, String fragment, context) async {
        final driver = context.world.driver!;
        final rendered = await _renderedTextOf(driver, key);
        if (!rendered.contains(fragment)) {
          throw Exception(
            'the widget "$key" reads "$rendered", which does not contain '
            '"$fragment"',
          );
        }
      },
    );

/// Asserts the plain uncertainty notice of the uncertainty at [index] (the
/// notice a candidate-less gap keeps instead of a picker).
StepDefinitionGeneric thenUncertaintyNotice() => then2<int, int, FlutterWorld>(
  'I expect the uncertainty notice at index {int} to be present within '
  '{int} seconds',
  (int index, int seconds, context) async {
    final driver = context.world.driver!;
    await driver.waitFor(
      find.byValueKey('ai-preview-notice-$index'),
      timeout: Duration(seconds: seconds),
    );
  },
);

/// Every step of this file, in registration order.
List<StepDefinitionGeneric> aiImportFixtureSteps() => [
  givenContinuationLookPreview(),
  givenGapWithCandidates(),
  givenGapWithoutCandidates(),
  whenOpenAiImportPreview(),
  thenScrollPreviewToWidget(),
  whenPickContinuationCandidate(),
  thenNoWidgetWithin(),
  thenWidgetContainsText(),
  thenUncertaintyNotice(),
];
