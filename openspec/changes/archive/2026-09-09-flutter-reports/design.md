<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Design: Reports

## 1. Contract status (landed)

- **B1 — PDF parameter defect fixed:** `{id}` (uuid) is defined on the three PDF routes (backend issue #334, PR #349); the generated methods accept the day id.
- **B2 — JSON report routes exported:** `/v1/shooting-days/{id}/report/{dispo|shoot-day|soll-ist}` are in the checked-in spec (backend issue #333, PR #344).

Both fixes are backend-landed; the client change runs
`scripts/regen-client.sh` + implementation. Error copy branches on the
stable problem `code` from the per-operation RFC 9457 responses
(backend issue #343, PR #356).

## 2. Intended UX

```text
Day context (Phase 2 shooting-days screen) ── "Reports" action
└── ReportsScreen (day)
    ├── Soll-Ist on-screen report (B2)
    │     ├── planned vs actual rows (scene number, Soll position,
    │     │   Ist position/status)
    │     ├── flag chips: moved / missing / skipped / reshot
    │     ├── day finality banner (wrapped_at → "final")
    │     └── failure/empty/loading = standard asyncValue.when
    └── PDF cards: dispo / shoot-day / planned-vs-actual (B1)
          ├── fetch via generated client (pinned-CA, streamed)
          ├── LinearProgressIndicator while fetching (~100 ms+ rule)
          ├── in-app FOSS PDF preview (zoom/pan, theming-aware chrome)
          └── share / save via the platform sheet
```

- The Soll-Ist rows/chips render exclusively from the report DTO (D2)
  — same CQRS-boundary posture as every read screen.
- PDF fetches never write to Drift (D3); the shared document lands in
  the app documents directory only through the platform save action,
  with user-visible naming (`<day>-<report>.pdf`).
- Copy rules unchanged: problem `code`-keyed, localized error states;
  404 day / 403 (report routes are role-gated `CostumeDesigner`/
  wardrobe per the backend — client pre-gates via the membership
  capability check before every report call, `// AUTHZ-GATE:`
  annotated).
- Accessibility: PDF viewer chrome supports dynamic type to 1.3,
  keyboard zoom controls on macOS; report rows carry semantic labels
  (scene + status), tested with `find.text`-paired assertions and
  goldens {light,dark} × {android,macos}.
- Battery/store: a fetch happens only on user action; no prefetching,
  no background updates.

## 3. Gherkin (designated critical scope — after Phase 2b)

`features-spec/soll_ist_report.feature`: after executing a day
(plan → start → finish/skip → wrap), the report screen shows the
correct Soll/Ist rows, flags, and finality. Runs via `flutter_gherkin`
on device against the dev-auth backend with deterministic clock/API
doubles (no wall-clock).

## 4. Test tiers

- **Unit:** report DTO → row-model mappers (strict-parse unknown
  statuses → `Err`); PDF bytes buffering bound; share-file naming.
- **Widget + golden:** all four variants of the report screen and the
  PDF card states (idle/fetching/error/ready); flag chips; finality
  banner; denial narrative.
- **Gherkin:** the feature above.
- **Integration:** on-emulator PDF happy path once callable
  (fetch → preview → share with a faked share sheet).
