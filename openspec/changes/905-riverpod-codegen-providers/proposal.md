<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Migrate handwritten Flutter `NotifierProvider`s to Riverpod codegen

## Why

Issue #905 (review residue of PR #904). `frontend-flutter/AGENTS.md` §1 /
Decision D3 declares Riverpod codegen (`@riverpod`) as the **only** accepted
way to declare a provider, yet `lib/` still carried fourteen hand-written
`Notifier` + `NotifierProvider` pairs. They are behaviourally fine, so nothing
forced the issue — which is exactly why the rule eroded: a new provider is
copied from a neighbouring hand-written one, and the guidance silently
disagrees with the tree.

`pendingDocumentProvider`
(`lib/features/ai_import/import_jobs/import_submit_controller.dart`) is the one
named by the issue (it predates #904 and was left out of that PR). The sweep
found thirteen more.

## What

**Thirteen declarations migrate to codegen** — every one is a plain `Notifier`
subclass with no override sites and no constructor arguments, so the migration
is mechanical and behaviour-preserving:

| Provider | File | Note |
|---|---|---|
| `pendingDocumentProvider` | `features/ai_import/import_jobs/import_submit_controller.dart` | the issue's named target |
| `aiStampWarningProvider` | same file | private `_StampWarning` becomes public `AiStampWarning` (codegen derives the provider name from the class name) |
| `pendingEpisodeProvider` | same file | |
| `cacheGenerationProvider` | `data/cache/cache_generation.dart` | |
| `seasonsPrevRowsProvider` | `data/cache/seasons_cache_providers.dart` | private `_SeasonsPrevRows` becomes public `SeasonsPrevRows` |
| `runtimeApiBaseProvider` | `data/settings/api_base_override_store.dart` | |
| `seasonCommandErrorProvider` | `features/seasons/seasons_controller.dart` | |
| `sessionResetProvider` | `features/auth/sign_out.dart` | `Notifier<void>` state |
| `signInErrorProvider` | `features/auth/login_screen.dart` | |
| `signInInFlightProvider` | `features/auth/login_screen.dart` | |
| `aiConfigDraftsProvider` | `features/ai_import/ai_config/ai_config_controller.dart` | |
| `seasonMembershipCacheProvider` | `auth/season_membership_provider.dart` | |
| `seasonOverlaysProvider` | `features/seasons/seasons_controller.dart` | needs the shared base to become a mixin (below) |

**Lifetime is preserved, not re-decided.** A plain `NotifierProvider` is
keep-alive by default; `@Riverpod` defaults to auto-dispose. Every migrated
provider therefore states `@Riverpod(keepAlive: true)` explicitly, so each keeps
its current lifetime. `signInInFlightProvider`'s doc comment claimed
"auto-disposing" while its declaration was a plain keep-alive provider — the
migration preserves the *actual* behaviour and corrects the comment instead of
silently changing the lifetime under the guise of a refactor.

**The call-site contract is unchanged.** Codegen derives the provider variable
from the class name (`PendingDocument` → `pendingDocumentProvider`), so every
`ref.read(pendingDocumentProvider.notifier).set(...)`, `ref.watch(...)` and test
`container.read(...)` keeps compiling untouched. The `.notifier` getter exposes
the same class instance type, including the domain methods (`set`, `toggle`,
`bump`, `signOut`, `switchBackend`, `store`/`invalidate`/`clear`, `add`,
`markAllReconciling`, `dropProjectedRows`, `markAllStale`).

**`OverlayStore` becomes a mixin** (`lib/domain/reconciliation/overlay_store.dart`).
A codegen notifier must `extend _$ClassName`, and Dart has no multiple
inheritance, so the shared overlay base cannot stay an `abstract class ...
extends Notifier<List<E>>` if its single subclass (`SeasonOverlays`) is to be
generated. It becomes
`mixin OverlayStore<E extends ReconciliationOverlay> on AnyNotifier<List<E>, List<E>>`:
`AnyNotifier` is Riverpod's public notifier root (the supertype of both the
hand-written `Notifier` and the generated `$Notifier` base), it exposes `state`
and `ref`, and a mixin has no competing superclass. The behaviour-carrying
methods (`add`, `markAllReconciling`, `dropProjectedRows`, `markAllStale`) and
the pure `overlay*` helpers are unchanged; only the `build() => const []`
default moves to the concrete subclass, because a mixin cannot initialize the
notifier state it does not own. The constraint still guarantees a
`List<E>`-shaped notifier, so the base is not a looser contract than before.

**Generated files are regenerated, never edited**: the six affected `.g.dart`
files come from `build_runner`; `vendor/breakdown_api/` and the Drift schemas
are untouched (no wire, no schema change).

## One documented exception

`easterEggProvider` (`data/settings/easter_eggs_store.dart`) stays hand-written:

- It is a **`NotifierProvider.family`** whose family argument is a
  **constructor-injected field** (`EasterEggs(this.id)`), not a `build(id)`
  parameter.
- `bootstrap()` seeds it through **`HydratedEasterEggs extends EasterEggs`**
  (`lib/app.dart` plus five test files) — a subclass of the notifier that
  carries the value resolved from the store and the read-failure flag, applied
  with `overrideWith`. Codegen would make the family argument a `build`
  parameter and the generated base own the arg plumbing, so the seeding
  subclass would have to stop taking its own constructor argument and read
  `.arg` instead — a rewrite of the bootstrap seam, not a migration, and it
  would be the only place in the tree shaped that way.
- The family is also the one provider in the tree where the exception is
  *load-bearing*: the alternative would silently couple bootstrap hydration to
  a generated base class's internals.

It is recorded here and in `AGENTS.md`'s provider-guidance table so a reviewer
does not re-litigate it and a future author does not copy it by accident.

## Out of scope

- No behaviour, lifetime, wire, Drift or copy change; no provider is renamed at
  the call site; no override site is rewritten.
- No new tests are needed for the migrated bodies (`Notifier` → `$Notifier`
  only), but the existing suites are the acceptance gate: they exercise every
  migrated provider through its public surface.
- An `easterEggProvider` codegen migration, if ever wanted, is its own change.

## Tests

No new test file: the migration is a declaration-shape change. The gate is the
existing suite — `flutter analyze`, `dart format --set-exit-if-changed .` and
`flutter test` (unit + widget + the AI-import / seasons / auth suites that drive
the migrated providers), plus the regenerated `.g.dart` diff.
