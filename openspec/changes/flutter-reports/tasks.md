<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Tasks: Reports — PARTIALLY BLOCKED

## 0. Unblock gate
- [ ] 0.1 Backend: define the `{id}` path parameter on the three PDF
       routes in `backend/openapi.yaml` (GitHub issue #334, also
       referenced in `data/scene_shoot_repository.dart`)
- [ ] 0.2 Backend: OpenAPI re-export including the JSON report routes
       (`dispo`, `shoot-day`, `soll-ist`) — GitHub issue #333 (same
       re-export as the Phase 2b unblock gate)
- [ ] 0.3 `bash scripts/regen-client.sh`; commit the regenerated
       client; verify per-day PDF methods and report DTOs exist

## 1. Data layer
- [ ] 1.1 Extend `data/scene_shoot_repository.dart` — per-day PDF
       methods (B1 surface) + Soll-Ist report fetch; remove the
       no-parameter wrappers once the signature lands
- [ ] 1.2 `data/report_cache.dart` — bounded in-memory PDF buffer +
       temp-file hand-off for share; never Drift
- [ ] 1.3 Unit tests: report DTO strict-parse mappers (unknown
       status/flag → `Err`), PDF bytes bound, share-file naming,
       temp-cleanup on failure

## 2. Reports screen
- [ ] 2.1 `features/reports/reports_screen.dart` — day context entry
       ("Reports" action on the Phase 2 day screen); Soll-Ist rows,
       flag chips, finality banner (read-model render only)
- [ ] 2.2 PDF cards — fetch (user-initiated only) with progress,
       in-app preview (FOSS viewer), share/save via platform sheet
- [ ] 2.3 AUTHZ-GATE pre-checks before every report call
       (`// AUTHZ-GATE:` annotated, membership capability narrative)
- [ ] 2.4 Widget tests + goldens ({light,dark} × {android,macos}):
       idle/fetching/error/ready card states, flag chips, finality,
       denial narrative, strict-reject error state

## 3. Gherkin (designated critical scenario)
- [ ] 3.1 `features-spec/soll_ist_report.feature` — after day
       execution (Phase 2b), the report shows correct rows, flags,
       and finality; wire into the flutter_gherkin CI manifest

## 4. Integration + housekeeping
- [ ] 4.1 On-emulator smoke: fetch → preview → share with a faked
       share sheet; failure path leaves no partial artifacts
- [ ] 4.2 SPDX headers; lint/coverage/gitleaks gates clean
- [ ] 4.3 `openspec` coverage audit for `flutter-reports-screen`
