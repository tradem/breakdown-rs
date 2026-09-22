<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Proposal: ADR-031 follow-up — dev-flavor `DEFAULT_SERIES_ID` bootstrap guard + fault-injection problem-document `Path` extractor (issue #483)

## Problem

Two ADR-031 hardening items deferred from issue #467 (per the confirmed
scope decision there) resurface as a dedicated follow-up:

1. **Dev-build guard (was 'Optionally' in #467):** a `Flavor.dev` build shipped
   without `--dart-define=DEFAULT_SERIES_ID` is only caught at wizard dispatch
   time (the #484 fail-fast guard). A startup-side log would surface the
   misconfiguration even earlier — when the app boots — before any screen is
   reached.
2. **`fault_injection.rs` uses raw `axum::extract::Path<String>`:**
   `crates/api/src/fault_injection.rs` (`arm_fault`) is the only handler in the
   crate still using the raw axum extractor instead of the problem-document
   wrapper (`crate::problems::Path`). It is practically unrejectable (any
   string segment parses) and the fault-injection router is `test-support`-
   gated out of production builds, but strictly speaking it is a remaining
   avenue that could answer outside `application/problem+json` if axum's path
   extraction ever rejects — violating the ADR-031 "no avenue may answer
   outside application/problem+json" invariant.

## Current state (drift-checked)

- **Frontend:** `lib/app.dart` owns the startup seam: `bootstrap()` runs
  `resolveAppConfig` → `validateStartupConfig` (fail-closed fatal screen) →
  `checkRedirectConsistency` → pinned-CA client construction. The wizard
  already fail-fasts at dispatch with the stable `config.series-id-missing`
  code (#484). `DEFAULT_SERIES_ID` remains an optional form pre-fill
  (`AppConfig.defaultSeriesId`, may be empty).
- **Backend:** every production handler imports the problem-document wrapper
  extractors from `crate::problems::{Json, Path, Query, Bytes}` (ADR-031 /
  #230/#231); `crate::problems::Path<T>` maps extraction failure to
  `ApiError::BadPathParam` → registered code `http.bad-path-param` (400).
  `fault_injection.rs` is the single straggler still importing raw
  `axum::extract::Path`. `http.bad-path-param` is already registered in
  `crates/core/src/error_registry.rs#problem_codes!` — no new code needed.

## Decisions (user-confirmed)

- **Scope:** both parts, one PR — the Flutter bootstrap guard and the backend
  `fault_injection.rs` extractor switch.
- **Guard severity is log, not a fatal screen and not a crashing `assert`:**
  an empty `DEFAULT_SERIES_ID` is *not* a fail-closed condition — the field is
  an optional pre-fill and the wizard owns the user-facing graceful failure
  (#484). A `FatalConfigErrorApp` screen would break otherwise-fine local dev
  boot; a hard `assert(…, …)` would crash every dev debug build that merely
  omits the define. The guard is therefore a non-fatal boot log (visible in
  the console/DevTools), surfaced through a pure, testable predicate so a
  widget test can drive it.
- **Backend:** switch (not document) — the `problems::Path` wrapper exists and
  is the crate-wide convention; swapping the single straggler closes the
  ADR-031 avenue at zero behavioral cost (success-path behavior is identical).

## What changes

### Frontend — bootstrap log guard

- `lib/app.dart`:
  - `devMissingSeriesIdWarning(AppConfig) → String?` — pure predicate
    (`@visibleForTesting`); returns the actionable message when
    `config.flavor == Flavor.dev && config.defaultSeriesId.isEmpty`, else
    `null`. Sibling of `validateStartupConfig` / `redirectMismatchError`.
  - `logDevMissingSeriesIdWarning(AppConfig)` — `@visibleForTesting` emission
    seam: `debugPrint`s the message (no-op when the predicate is `null`).
  - `bootstrap()`/`resolveAppConfig` — calls the emission seam right after the
    config resolves, before the fatal `validateStartupConfig` check. No network
    or UI change.
- `test/dev_missing_series_id_test.dart` — new:
  - predicate `Ok`/`Err`-style branches: dev+empty → message contains
    `DEFAULT_SERIES_ID`; dev+set → `null`; prod+empty → `null`.
  - widget-testable log seam: `debugPrintOverride`-captured `testWidgets` proves
    the message is emitted for dev+empty and silent for dev+set and prod.

### Backend — fault-injection `Path` wrapper

- `backend/crates/api/src/fault_injection.rs`:
  - Drop `Path` from the raw `axum::extract::{Path, State}` import; import the
    wrapper `crate::problems::{ApiError, Path}` (merging with the existing
    `ApiError` import).
  - `arm_fault` keeps `Path(fault): Path<String>` (now the wrapper); on the
    never-in-practice rejection path it answers `ApiError::BadPathParam`
    (`http.bad-path-param`, RFC 9457) instead of axum's plain-text rejection.
  - Extend the module doc comment noting the wrapper and why no rejection test
    is added (`Path<String>` with a `String` segment cannot reject; the switch
    is defense-in-depth so a future segment-type change stays on the problem
    surface).

## Not in scope

- No new registered wire code (reuses `http.bad-path-param`).
- No change to the wizard dispatch guard (already shipped, #484) and no fatal
  error screen for the missing pre-fill.
- No fault-injection DSL or additional faults (single `block-conflict` latch
  stays).

## Validation

- `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test`
  (new `test/dev_missing_series_id_test.dart` must pass).
- `cargo check -p api --features api/test-support` and the `fault_injection`
  unit tests (`cargo test -p api --features api/test-support fault_injection`).
- No OpenAPI drift surface (no route/handler signature change, no `#[openapi]`
  impact — `fault_control_routes` stays out of the spec).

## Depends On

- Issue #467 (merged as PR #484 — the wizard fail-fast and the ADR-031 wrapper
  extractor tests the guard complements).
