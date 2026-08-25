<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## ADDED Requirements

### Requirement: Riverpod as the Composition Mechanism
The Flutter app SHALL use Riverpod (`flutter_riverpod` +
`riverpod_generator`) as the sole state-management and dependency-injection
mechanism. Providers are declared via codegen (`@riverpod`); widgets consume
via `ref.watch`/`ref.read`. No competing state container (Bloc, GetIt,
MobX, scoped `InheritedWidget` graphs) SHALL be introduced.

> This is a deliberate departure from the backend's "no DI framework" ethos:
Riverpod is compile-safe and its `override` system is honest DI (not a hidden
service locator), which the AGENTS.md accepts as the cost of widget-test
velocity.

#### Scenario: A widget reads reactive state
- **WHEN** a `ConsumerWidget` calls `ref.watch(fooControllerProvider)`.
- **THEN** it receives an `AsyncValue<T>` and rebuilds on state transition
  (loading / data / error), with no `setState` boileplate in the widget.

#### Scenario: A repository is injected into a test
- **WHEN** a widget test needs a fake repository.
- **THEN** the test constructs a `ProviderContainer(overrides:
[seasonsRepositoryProvider.overrideWithValue(fakeRepo)])` and passes it
via `UncontrolledProviderScope`, with no global mutable singleton and no
runtime lookup that could fail at build time.

### Requirement: No Business Logic in Widgets
Widgets SHALL only render and dispatch; all domain/data orchestration
(domains: query, command dispatch, optimistic insert, projector-lag
reconciliation) lives in providers or repository adapters. This is the
client-side analog of the backend's hexagonal boundary (widgets =
presentation adapters).

#### Scenario: A widget contains an `if` that branches on domain semantics
- **WHEN** a review finds domain branching (e.g. "if the season is archived,
disable the FAB") authored inside `build()` instead of in the controller.
- **THEN** it is flagged and moved to a provider that exposes a
presentation-ready state object.

### Requirement: Result/Either Discipline (no throw in data/domain)
The `data/` and `domain/` layers SHALL model fallible operations with
`fpdart`'s `Result`/`Either` (or an equivalent `Result` type), returning
errors as values rather than throwing. Widgets and providers translate
`Err` into `AsyncError`. This is the client-side analog of the backend's
"no panics in production" hard rule (`unwrap`/`expect`/`panic` denied).

#### Scenario: A repository call fails with a problem error
- **WHEN** a `POST /seasons` returns RFC 9457 `application/problem+json`.
- **THEN** the repository returns `Err(ProblemError(code, ...))` (never
  throws); the calling provider surfaces it as `AsyncError` and the widget
  branches on the stable `code` (e.g. `seasons.conflict`), never on
  `detail` text.

#### Scenario: A future result is discarded
- **WHEN** production code writes the equivalent of `let _ = <fallible call>`
  (an un-awaited `Future` or a discarded `Result`).
- **THEN** the analyzer (custom lint) rejects it; the call must be
  propagated (`?`-style), `.match`-handled, or explicitly suppressed with a
  justification comment — the client-side analog of the backend
  `discard-result` rule.
