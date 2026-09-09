<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Tasks: Reports — READY

**Unblock gate landed:** 0.1–0.3 below are satisfied by backend PRs #344 (issue #333) + #349 (issue #334); remaining work is regen + implementation (still no hand-built URLs, no retyped DTOs).

## 0. Unblock gate (landed)
- [x] 0.1 Backend: define the `{id}` path parameter on the three PDF
       routes in `backend/openapi.yaml` (GitHub issue #334, PR #349)
- [x] 0.2 Backend: OpenAPI re-export including the JSON report routes
       (`dispo`, `shoot-day`, `soll-ist`) — GitHub issue #333 (PR #344)
- [x] 0.3 `bash scripts/regen-client.sh`; commit the regenerated
       client; verify per-day PDF methods and report DTOs exist
       (verified 2026-09-09: `dispoReportPdf`/`shootDayReportPdf`/
       `plannedVsActualReportPdf` all take `required String id`, plus
       `dispoReport`/`shootDayReport`/`sollIstReport` JSON routes;
       `DispoRow`/`ShootDayRow`/`SollIstDiffRow`/`SollIstReport` DTOs
       present; `vendor/` tree git-clean — regen is a no-op)

## 1. Data layer
- [x] 1.1 Extend `data/scene_shoot_repository.dart` — per-day PDF
       methods (B1 surface, day id as a real parameter since issues
       #333/#334 landed) + Soll-Ist report fetch; the old no-parameter
       wrappers are removed as part of this task
       (done: `fetchDispoReport`/`fetchShootDayReport`/`fetchSollIstReport`
       JSON fetches added; PDF methods now stream to `Result<File>`;
       old `Result<void>` wrappers removed)
- [x] 1.2 `data/report_cache.dart` — **stream-to-temp-file, not an
       in-memory buffer**: path-keyed interceptor sets
       `ResponseType.stream` for the PDF routes (the generated methods
       take no `Options`), the repository writes each chunk to the
       cache/temporary file (never the persistent documents directory,
       never Drift) while counting bytes, and cancels via
       `CancelToken` the moment `PDF_MAX_BYTES` is exceeded (partial
       file deleted); `Result<File>` on success
       (done: `PdfStreamingInterceptor` wired into `buildPinnedDio`;
       `writePdfStreamToTemp`/`writePdfResponseDataToTemp` with
       `kPdfMaxBytes` cap + `deleteReportTemp` cleanup)
- [x] 1.3 Unit tests: report DTO strict-parse mappers (unknown
       status/flag → `Err` with `report.unknown_status` /
       `report.unknown_shape`), transport/error-code normalization
       (`transport.*`, `http.<status>`), PDF byte cap abort, share-file
       naming, temp-cleanup on every non-save exit
       (done: `test/unit/reports_test.dart`, 14 tests green)
- [x] 1.4 Regression test for the PDF transport wiring: the pinned-CA
       `Dio` from `dioProvider` reaches the generated
       `HandlersApi` PDF calls through `SceneShootRepository`
       (pinning verified end-to-end, not only in isolation — added
       after client regeneration)
       (done: same `buildPinnedDio` interceptor order proven end-to-end
       through the generated client into a temp file in
       `test/unit/reports_test.dart`)

## 2. Reports screen
- [x] 2.1 `features/reports/reports_screen.dart` — day context entry
       ("Reports" action on the Phase 2 day screen); Soll-Ist rows,
       flag chips, finality banner (read-model render only)
       (done: `reports-open` action on `SceneShootsScreen`;
       `soll-ist-planned`/`soll-ist-actual` count keys for the Gherkin
       contract; `soll-ist-flag-*` chips; `soll-ist-final` banner)
- [x] 2.2 PDF cards — fetch (user-initiated only) with progress,
       in-app preview (FOSS viewer), share/save via platform sheet
       (done: `pdfrx` (FOSS) in-app preview, `share_plus` platform sheet,
       `path_provider` temp staging; cancel + cleanup on every non-save exit)
- [x] 2.3 AUTHZ-GATE pre-checks before every report call
       (`// AUTHZ-GATE:` annotated, membership capability narrative);
       the check is local and non-fetching — `AsyncLoading`,
       `AsyncError`, and unknown capability strings all deny locally
       with zero report requests
       (done: gate in the three fetch seams + `fetchPdf`; denial copy
       keyed `membership.pending`/`membership.unavailable`/
       `report.forbidden`; zero-request asserted per state)
- [x] 2.4 Widget tests + goldens ({light,dark} × {android,macOS}):
       idle/fetching/error/ready card states, flag chips, finality,
       denial narrative, strict-reject error state, and ALL locally
       denied membership states — `AsyncLoading`, `AsyncError`, and
       unknown capability string — each asserting zero report requests
       (done: `test/features/reports/reports_screen_test.dart`,
       14 tests + 4 goldens green)

## 3. Gherkin (designated critical scenario)
- [x] 3.1 `features-spec/soll_ist_report.feature` — after day
       execution (Phase 2b), the report shows correct rows, flags,
       and finality; wire into the flutter_gherkin CI manifest
       (done: scenarios now drive the landed day-context entry
       (`reports-open`), `whenOpenReports` registered in
       `configuration.dart`; `tool/check_gherkin.sh` green. Scenarios stay
       @pending until the Phase 2b seeded on-device flow lands — promotion
       is a separate step per the feature-file contract)

## 4. Integration + housekeeping
- [x] 4.1 On-emulator smoke: fetch → preview → share with a faked
       share sheet; failure path leaves no partial artifacts
       (done: `integration_test/reports_smoke_test.dart`, run on
       emulator-5554 — both scenarios green)
- [x] 4.2 SPDX headers; lint/coverage/gitleaks gates clean
       (done: SPDX + Co-authored-by on every new file; `dart analyze`
       clean; `dart format --set-exit-if-changed` clean;
       `breakdown_lints_runner` no violations; full-suite coverage
       (filtered, generated/test excluded) pooled 83.78% ≥ 80
       (`coverde check 80`); gitleaks frontend config clean. NOTE: the 4
       `SceneShootsScreen` goldens were regenerated — the board AppBar
       gained the `reports-open` action (2.1). The pre-existing
       `check-authz-gates.sh` false positive on `sign_out.dart`
       (heuristic matches the `photos/` import path) exists on HEAD and is
       tracked separately)
- [x] 4.3 `openspec` coverage audit for `flutter-reports-screen`
       (done: every delta requirement/scenario maps to implementation +
       tests —
       * Contract-Gated Reporting Surface → generated per-day methods only
         (`dispoReportPdf`/`shootDayReportPdf`/`plannedVsActualReportPdf`,
         no Dio string interpolation in prod; JSON routes via
         `dispoReport`/`shootDayReport`/`sollIstReport`; generated DTOs
         only) — verified 0.3 + transport-wiring unit test;
       * Soll-Ist On-Screen Report From the Read Model → DTO-verbatim rows/
         chips/finality (`_SollIstSection`), strict-reject
         `report.unknown_status`/`report.unknown_shape`, code-keyed copy —
         "Wrapped day report" + "Unknown status strict-rejects" scenarios
         covered by widget tests;
       * PDF Fetch, Preview, Share → user-initiated fetch with progress,
         pdfrx preview, platform-sheet share under `<day>-<report>.pdf`,
         byte cap + temp cleanup, no Drift persistence; AUTHZ-GATE local
         non-fetching with zero-request assertions per state — "Fetch and
         share" + "Fetch failure" covered by widget tests + emulator
         smoke). `openspec validate flutter-reports` valid.
