<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# flutter-state-management Specification

## Purpose
TBD - created by archiving change add-flutter-app-foundation. Update Purpose after archive.
## Requirements
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

Notifier-backed providers SHALL be declared through codegen
(`@Riverpod(keepAlive: …)` on a class extending the generated `_$ClassName`),
not as a hand-written `Notifier` + `NotifierProvider` pair. A hand-written pair
SHALL carry a documented exception stating why codegen cannot express it, and
SHALL NOT be copied as a template for new providers (issue #905).

A migration to codegen SHALL preserve the provider's **existing lifetime**
(a hand-written `NotifierProvider` is keep-alive, whereas `@Riverpod` defaults
to auto-dispose), its public notifier methods and its provider name — a rename
visible at a call site is a separate, reviewed decision.

#### Scenario: A widget reads reactive state
- **WHEN** a `ConsumerWidget` calls `ref.watch` on an asynchronous provider
  (`Future`, `Stream`, or `AsyncNotifier`).
- **THEN** it receives an `AsyncValue<T>` and rebuilds on state transition
  (loading / data / error), with no `setState` boileplate in the widget.
  (A synchronous provider would expose `T` directly, not `AsyncValue<T>`.)

#### Scenario: A repository is injected into a test
- **WHEN** a widget test needs a fake repository.
- **THEN** the test constructs a `ProviderContainer(overrides:
[seasonsRepositoryProvider.overrideWithValue(fakeRepo)])` and passes it
via `UncontrolledProviderScope`, with no global mutable singleton and no
runtime lookup that could fail at build time.

#### Scenario: A hand-written `NotifierProvider` is found
- **WHEN** a review finds a `class X extends Notifier<T>` plus
  `final xProvider = NotifierProvider<X, T>(X.new)` under `lib/`.
- **THEN** it is migrated to `@Riverpod(keepAlive: true) class X extends _$X`
  with the existing provider name and public methods preserved, and every
  call site (including `xProvider.notifier`) keeps compiling unchanged — unless
  a documented exception explains why codegen cannot express it.

#### Scenario: A shared notifier base class needs a codegen subclass
- **WHEN** several providers share behaviour through a base type (e.g. the
  optimistic overlay stores) and one of them must become a codegen provider.
- **THEN** the shared base is expressed as a mixin over Riverpod's public
  notifier root (`mixin Base<E> on AnyNotifier<List<E>, List<E>>`) rather than
  an `abstract class … extends Notifier<…>`, because a generated notifier must
  extend its own generated base and Dart allows only one superclass.

#### Scenario: A family provider is seeded by a bootstrap override
- **WHEN** a `NotifierProvider.family` takes its family argument as a
  constructor field and is seeded through a subclass with `overrideWith`
  (today: `easterEggProvider` / `HydratedEasterEggs`).
- **THEN** it MAY stay hand-written, with the exception documented at the
  declaration and in the change that inventoried it; it is not proof that other
  hand-written providers are justified.

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
`fpdart`'s `Either`/`TaskEither` types — `Right` for success, `Left` for
failure (fpdart does not define `Result`/`Err`/`Ok`; use the `Either`
vocabulary explicitly), returning errors as values rather than throwing.
Widgets and providers translate `Left` into `AsyncError`. This is the
client-side analog of the backend's "no panics in production" hard rule
(`unwrap`/`expect`/`panic` denied).

#### Scenario: A repository call fails with a problem error
- **WHEN** a `POST /v1/seasons` returns RFC 9457 `application/problem+json`.
- **THEN** the repository returns `Left(ProblemError(code, ...))` (never
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

