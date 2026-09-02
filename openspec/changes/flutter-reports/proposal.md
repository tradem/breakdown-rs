<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Proposal: Reports — Phase 4 (PARTIALLY BLOCKED)

## Why
Phase 4 delivers the reporting surface: on-screen Soll-Ist
(planned-vs-actual) review per shooting day and the three PDF day
reports (disposition, shoot-day, planned-vs-actual) viewable and
shareable from the day context. The roadmap's designated Gherkin
critical scope "Soll-Ist report" lands here.

**Two contract defects were found during grounding (documented
blockers, not worked around):**

1. **PDF path-parameter defect:** the three PDF routes declare the
   `{id}` path segment without defining it in the spec, so the
   generated Dart client methods (`dispoReportPdf`,
   `shootDayReportPdf`, `plannedVsActualReportPdf`) take **no path
   parameter and cannot address a specific day** — already faithfully
   wrapped in `data/scene_shoot_repository.dart` and tracked as a
   backend spec defect (AGENTS.md §7 note). No client workaround (no
   hand-built URLs bypassing the client) is permissible.
2. **Missing JSON report routes:** the backend router serves the
   source JSON reports (`/v1/shooting-days/{id}/report/dispo`,
   `shoot-day`, `soll-ist`) but the checked-in `backend/openapi.yaml`
   does not contain them — the on-screen Soll-Ist report data has no
   contract surface yet (same family of gap as the Phase 2b change).

This change is created now to spec the UX, dependency-light, with
every task gated on the two backend fixes (a single OpenAPI re-export
plus the PDF parameter definitions).

## What changes (when unblocked)
- `features/reports/` — day-context report screen:
  - **Soll-Ist on-screen report** rendered from the JSON report route
    (pure presentation of the read DTO — planned vs actual scene
    shoots, moved/missing/skipped/reshot flags, finality from
    `wrapped_at`; server owns all derivation).
  - **PDF actions** per day: fetch via the generated client over the
    pinned-CA transport (raw bytes, streamed; in-memory bounded
    buffering), in-app preview, and share/save via the platform share
    sheet; explicit progress indication (fetch ~100 ms+) with
    LinearProgressIndicator and no fabricated progress.
- Gherkin critical scenario: **Soll-Ist report** (produce the day
  report after shoot-day execution; verify the flags/finality render
  — depends on Phase 2b landing first).
- Integration smoke for the PDF happy path once the route is callable.

## Capabilities
- `flutter-reports-screen` (new)

## Dependencies
- **Depends on:** `flutter-costume-domains` (day context),
  `flutter-shoot-day-execution` (wrapped days / Ist data; Part 2b
  blocked as documented).
- **Blocked on (both tracked backend items):** the PDF `{id}` path
  parameter definitions in `backend/openapi.yaml`, and the export of
  the JSON report routes; then `scripts/regen-client.sh`.
- **New packages:** PDF in-app viewing via a FOSS renderer
  (e.g. `pdfrx`) + share via `share_plus` — both FOSS/store-compliant;
  selection and pinning are finalized in design.md when unblocked.

## Non-goals
- No new report types, no client-side PDF synthesis or annotation; no
  offline report caching beyond a single in-memory document; no
  emailing/report distribution automation (AI notice + data
  minimization apply — reports stay user-initiated).

## Design Decisions
- **D1 — No hand-built URLs.** Until the generated client can carry
  the day id, no PDF fetch ships — not even via manual `Dio.get`
  string interpolation. The drift-checked contract is the only
  sanctioned transport surface.
- **D2 — On-screen report is a read-model render.** All flag and
  finality semantics (`moved/missing/skipped/reshot`, `final` from
  `wrapped_at`) come from the report read DTO; the client renders
  chips/rows, never recomputing.
- **D3 — Streaming, bounded memory.** PDF bytes stream through the
  pinned-CA client with a bounded buffer; documents landing in the
  platform share/save flow go to the app's temporary/documents
  directory, never to Drift (blob-store rule from Phase 2's photo
  work).
