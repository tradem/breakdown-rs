<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Proposal: Reports — Phase 4 (READY — contract landed)

## Why
Phase 4 delivers the reporting surface: on-screen Soll-Ist
(planned-vs-actual) review per shooting day and the three PDF day
reports (disposition, shoot-day, planned-vs-actual) viewable and
shareable from the day context. The roadmap's designated Gherkin
critical scope "Soll-Ist report" lands here.

**Both contract defects landed (no workarounds needed):**

1. **PDF path-parameter defect fixed:** every path template variable is now defined in the spec (backend issue #334, PR #349 — route-coverage guard test), so the regenerated Dart client methods (`dispoReportPdf`, `shootDayReportPdf`, `plannedVsActualReportPdf`) take the day id and address a specific day.
2. **JSON report routes exported:** the source JSON reports (`/v1/shooting-days/{id}/report/dispo`, `shoot-day`, `soll-ist`) are in the checked-in `backend/openapi.yaml` (backend issue #333, PR #344) — the on-screen Soll-Ist report consumes the read DTOs via the generated client.

## What changes
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
  `flutter-shoot-day-execution` (wrapped days / Ist data — unblocked
  alongside this change).
- **Contract:** GitHub issues #333 (JSON report route export, PR #344)
  and #334 (PDF `{id}` definitions, PR #349) landed; followed by
  `scripts/regen-client.sh`.
- **New packages:** PDF in-app viewing via a FOSS renderer
  (e.g. `pdfrx`) + share via `share_plus` — both FOSS/store-compliant;
  selection and pinning are finalized in design.md when unblocked.

## Non-goals
- No new report types, no client-side PDF synthesis or annotation; no
  offline report caching beyond a single in-memory document; no
  emailing/report distribution automation (AI notice + data
  minimization apply — reports stay user-initiated).

## Design Decisions
- **D1 — No hand-built URLs.** All PDF fetches dispatch via the
  generated per-day client methods (day id as a real parameter since
  issues #333/#334 landed) — never via manual `Dio.get` string
  interpolation. The drift-checked contract is the only sanctioned
  transport surface.
- **D2 — On-screen report is a read-model render.** All flag and
  finality semantics (`moved/missing/skipped/reshot`, `final` from
  `wrapped_at`) come from the report read DTO; the client renders
  chips/rows, never recomputing.
- **D3 — Streaming, bounded memory.** PDF bytes stream through the
  pinned-CA client with a bounded buffer; documents handed to the
  platform share/save flow are written to a **cache/temporary
  directory** (not the persistent documents directory, which is
  reserved for an explicit user save), and are removed on every
  non-save exit — preview closed, share cancelled or failed, or app
  termination before an explicit save. Nothing is ever written to
  Drift (blob-store rule from Phase 2's photo work).
