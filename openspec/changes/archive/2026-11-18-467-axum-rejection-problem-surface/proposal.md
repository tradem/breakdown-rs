<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Proposal: ADR-031 gap — axum extraction rejections (422) bypass the problem surface; wizard fail-fast for a missing DEFAULT_SERIES_ID (issue #467)

## Problem

HTTP requests with a malformed/invalid JSON body (axum `Json<T>` extraction
failure) were answered by axum's built-in rejection — plain-text 422 without an
RFC 9457 problem body — bypassing the central problem builder
(`crates/api/src/problems`, ADR-031). Clients fell back to generic codes, so a
real misconfiguration surfaced as an unexplainable `domain.validation`.

Live observation (2026-09-21): the Flutter setup wizard dispatches
`POST /v1/seasons` with a `series_id` sourced from the `DEFAULT_SERIES_ID`
dart-define. When that define is absent the build ships an empty `series_id`
(`series_id: String` ← `""`), the request fails JSON deserialization, and the
app displays the meaningless fallback `domain.validation` — the user could not
tell that a build configuration is missing.

## Current state (drift-checked)

The ADR-031 hardening described in this issue's first requirement is largely
**already shipped** (from issue #230/#231): `crates/api/src/problems/mod.rs`
defines problem-document wrapper extractors `Json<T>`, `Path<T>`, `Query<T>`
and `Bytes`, used by every handler (`crate::problems::{Json, Path, Query,
Bytes}`), with registered codes `http.bad-json-body` (400),
`http.bad-path-param` (400), `http.bad-query-param` (400),
`http.unsupported-media-type` (415) and `http.payload-too-large` (413) in
`crates/core/src/error_registry.rs#problem_codes!`; `route_not_found` +
`CatchPanicLayer` close the 404/500 leaks. **However** that mapping had **zero
regression tests** — the acceptance criterion "no avenue may answer outside
`application/problem+json`" was unproven. The frontend wizard fail-fast guard
was not implemented at all.

## Decisions (user-confirmed)

- **Scope:** (a) backend regression tests that pin the extraction-rejection →
  problem-document contract; (b) frontend wizard pre-dispatch empty-series-id
  fail-fast guard with an actionable "Build missing DEFAULT_SERIES_ID" message.
  No new backend wire codes, no change to resolver semantics, no
  `fault_injection.rs` change, no optional dev-flavor bootstrap guard (all
  deferred by decision).

## What changes

### Backend — `crates/api/src/problems/mod.rs` (tests only)

New router-`oneshot` regression tests (via `tower::ServiceExt`) proving every
extraction rejection answers with an RFC 9457 problem document:

- `json_extraction_rejections_are_problem_documents` — malformed body (400
  `http.bad-json-body`), empty body (same), missing content type (415
  `http.unsupported-media-type`), wrong content type (415), and the issue's
  exact `series_id:""` → 422 `domain.validation` case (still a problem doc,
  never plain text), plus a positive control (valid body still extracts).
- `query_extraction_rejection_is_problem_document` — `/?limit=not-a-number` →
  400 `http.bad-query-param` (+ valid query control).
- `path_extraction_rejection_is_problem_document` — `/not-a-uuid` →
  400 `http.bad-path-param` (+ valid UUID control).
- `json_body_limit_rejection_is_problem_document` — oversized body →
  413 `http.payload-too-large`.

### Frontend — fail-fast guard

- `lib/features/seasons/setup/setup_wizard_state.dart` — adds
  `missingSeriesIdProblem` (`ProblemError(code: 'config.series-id-missing', …)`),
  `isMissingSeriesIdFailure(...)`, and a `wizardErrorCopy` case with the
  actionable German rebuild message. No `@freezed` state change (no codegen).
- `lib/features/seasons/setup/setup_wizard_controller.dart` — `submit()` and
  `retryRemaining()` fail fast (pre-dispatch, zero network) when the
  env-sourced `seriesId` is empty/whitespace, via `_failPreDispatchConfig()`.
- `lib/features/seasons/setup/widgets/wizard_completion_view.dart` — the guard's
  failure renders the honest build-misconfiguration state ("Build-Konfiguration
  fehlt", the `DEFAULT_SERIES_ID` copy, only a close affordance): zero partial
  work happened, so no partial summary and no in-session retry.
- `test/…` — `seasons_test_fakes.dart` adds `devAuthConfigNoSeriesId`;
  `setup_wizard_controller_test.dart` proves `submit`/`retryRemaining` with
  empty/whitespace series id never reach the network (`createCalls == 0`) and
  settle with `config.series-id-missing`; `setup_wizard_screen_test.dart`
  asserts the actionable message, the absence of the retry affordance, and that
  no create command was issued.

## Not in scope

- A distinct registered code for valid-JSON-but-invalid-schema payloads
  (empty `series_id` still reads 422 `domain.validation` on the wire today —
  the actionable root cause is now solved client-side by the fail-fast guard).
- Dev-flavor bootstrap `assert`/log for an empty `DEFAULT_SERIES_ID` (the
  issue marked it optional).
- Switching `fault_injection.rs` from raw `axum::extract::Path<String>` (a
  non-production, practically-unrejectable extractor).
