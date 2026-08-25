---
name: flutter-testing-recipes
description: Scaffold Flutter tests the breakdown-rs way — unit (no Flutter imports), widget (semantic finders + golden), integration_test on device, and flutter_gherkin for designated critical flows only. Use when writing or reviewing tests under frontend-flutter/.
license: AGPL-3.0
compatibility: Requires the Flutter SDK; `flutter_gherkin` only after the `add-gherkin-critical-scenarios` follow-up lands the `features-spec/` tree. Err-branch assertions and deterministic-time rules apply from day one.
metadata:
  author: breakdown-rs
  version: "1.0"
  provenance: |
    Portable subset described in upstream `flutter/agent-plugins` and
    `dart-lang/skills` (testing recipes), adapted to breakdown-rs conventions.
    This SKILL.md is the authoritative breakdown-rs version. Upstream tracks
    the portable-subset structure; every recipe below encodes a decision from
    design.md §6 (Test pyramid, Hybrid Gherkin, Mutation-testing gap,
    Deterministic tests) and the `flutter-test-pyramid` /
    `flutter-gherkin-hybrid` specs.
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

# Flutter Testing Recipes

> **Provenance:** Ported from the portable subset described in upstream
> `flutter/agent-plugins` and `dart-lang/skills` (testing recipes), adapted to
> breakdown-rs conventions. Authoritative source: `frontend-flutter/AGENTS.md`
> §6 and the `flutter-test-pyramid` + `flutter-gherkin-hybrid` delta specs.

## The four-tier pyramid (decision D4)

```
Tier 4 (CI, few)   integration_test on device   — full screen flows vs real/mock API
Tier 3 (CI, few)   Gherkin .feature             — designated critical acceptance only
Tier 2 (bulk)      widget tests + goldens       — per-screen, per-component
Tier 1 (fast)      unit tests                   — pure domain/data, no Flutter imports
```

Pick the tier by *what* you are proving, not by convenience. A pure function
belongs in Tier 1; a rendered tree in Tier 2; an end-to-end auth-gated flow in
Tier 3 only if it is a *designated* critical scope, else Tier 4.

## Tier 1 — Unit tests (pure logic)

- Cover mappers, use-cases, `Result`/`Either` pipelines, problem-code routing
  in `lib/core/`, `lib/data/`, `lib/domain/`.
- **No Flutter imports** (`package:flutter/*`). If you reach for
  `package:flutter/foundation.dart` you are writing a widget test in disguise
  — move it to `test/widgets/`.
- **Err-branch assertions are mandatory.** Every `Result`-returning test MUST
  assert both `Ok` and `Err` branches; an unmatched `Err` variant is a visible
  coverage hole (spec `flutter-test-pyramid`).

```dart
// test/data/season_repository_test.dart — Tier 1 shape
test('createSeason maps a conflict problem to Err(seasons.conflict)', () async {
  final repo = SeasonRepository(client: FakeConflictClient());
  final result = await repo.createSeason(cmd).run();
  expect(result.isLeft(), isTrue);
  result.fold(
    (err) => expect(err.code, 'seasons.conflict'),
    (_) => fail('expected Err'),
  );
});
```

## Tier 2 — Widget tests (the bulk)

- Built on **semantic finders**: `find.text`, `find.byKey`, `find.byType` —
  paired, never `find.byType` *alone* for layout. A tree-shuffled widget must
  still fail the test; pair `byType` with a `find.text` or a golden.
- Inject fakes via Riverpod overrides — never a global mutable singleton:

```dart
testWidgets('SeasonsScreen renders fetched rows', (tester) async {
  final container = ProviderContainer(overrides: [
    seasonsRepositoryProvider.overrideWithValue(FakeSeasonsRepo()),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: SeasonsScreen()),
  ));
  await tester.pumpAndSettle();
  expect(find.byType(SeasonTile), findsNWidgets(3));
  expect(find.text('S01'), findsOneWidget); // semantic pair — not byType alone
});
```

- **Golden tests are required for any non-trivial widget** (stateful, renders
  domain state). Leaf presentational widgets may skip the golden.
- Regenerate goldens with `flutter test --update-goldens`; commit the updated
  files. A golden diff in CI that wasn't regenerated is a failure.

## Tier 3 — Gherkin `.feature` (designated critical only — decision Q2 → c)

`.feature` files live under `frontend-flutter/features-spec/` and run on device
via `flutter_gherkin`. **Only** the designated critical scopes (minimum):

- **Soll-Ist report** — planned vs actual, moved/missing/skipped/reshot,
  `final` from `wrapped_at`.
- **Continuity photo capture** — AUTHZ-GATE → multipart upload → projector-lag
  reconciliation → thumb appears.
- **Costume assignment** — command → optimistic update → projection refresh;
  role denial on the costume stream.

Rules:
- A `.feature` for a non-critical screen is *challenged* at review; the default
  is a widget test.
- **Steps run on device.** A step whose body only calls a pure function belongs
  in the unit-test tier — move it. (spec `flutter-gherkin-hybrid`.)
- The `features-spec/` tree + `flutter_gherkin` wiring land with the
  `add-gherkin-critical-scenarios` follow-up; until then this tier is empty by
  design.

## Tier 4 — integration_test (a few, on device)

- `integration_test/` covers a few full screen-flow scenarios against a real or
  mocked API (dev backend, or a hermetic fake server).
- Device/emulator only; CI runs via `integration_test` driver `_test.yaml`.

## Deterministic tests (hard rule, ported from backend)

- **Never gate a test on wall-clock timing or sleep-with-jitter.** Compute the
  worst case analytically against the test budget.
- For projector-lag reconciliation tests, use a fake clock / controllable
  `StreamController`, not real `Future.delayed`:

```dart
// controlled time — no real delays
final fakeClock = FakeClock();
final controller = StreamController<SeasonDto>.broadcast();
final provider = seasonsControllerProvider(fakeClock, controller.stream);
```

- If a test needs "wait for projection to catch up," drive the fake clock's
  advance explicitly and assert on the resulting `AsyncValue` transition.

## Mutation-testing gap (decision D5 — honest, no gate)

No maintained Dart/Flutter mutator exists. Do **not** propose "run mutation
tests" in CI without naming a maintained tool wired in. The four compositional
substitutes are what's enforced:

1. `coverde` line+branch threshold on changed code (lands with
   `add-flutter-ci-tests` follow-up).
2. Golden tests for non-trivial widgets.
3. Explicit Err-branch assertions on every `Result`-returning repo/use-case.
4. Semantic-finder widget tests (never `find.byType` alone for layout).

If a maintained mutator emerges, scope it to `lib/domain/` + `lib/data/` only
— never widgets, never goldens.

## Review checklist (apply on every Flutter test PR)

- [ ] Tier chosen by *what is proven*, not convenience?
- [ ] Every `Result` test asserts **both** `Ok` and `Err`?
- [ ] Widget tests pair `byType` with `find.text`/golden (no lone-byType layout)?
- [ ] Non-trivial widget has a golden?
- [ ] No wall-clock / `Future.delayed` in deterministic tests?
- [ ] `.feature` only for a designated critical scope (reviewer-challenged if not)?
- [ ] Steps in `.feature` actually exercise the device/HTTP path (not a pure fn)?
