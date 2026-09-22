<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: muse-spark-1.3-contributor (opencode-go) -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Changelog

All notable changes to the Breakdown Flutter client will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
per ADR-033: single source of truth is `version: X.Y.Z+N` in `pubspec.yaml`,
releases are cut as `flutter-vX.Y.Z` tags.

## [Unreleased]

### Changed

- Costume detail add sends a real UUIDv7 wire id (issue #472):
  `CostumesController.addDetail` no longer submits the optimistic-overlay
  placeholder `'pending'` as `detail.id` — the `uuid`-typed contract
  rejected it with `422 domain.validation` before the handler ran, so
  details could never save. The wire id is now a client-side UUIDv7
  (`generateUuidV7()`, `uuid ^4.6.0`); the optimistic overlay keeps its
  separate `pending-detail-<version>` transient placeholder and is
  reconciled from the projection. A server 422 still surfaces its problem
  `code` via the keyed copy, never a generic network error.
- **Version bump:** `0.3.0-alpha.13+22 → 0.3.0-alpha.14+23` (pre-release
  increment per merged-PR practice on the alpha line; `+N` stays strictly
  monotonic for the Play `versionCode`).
- **IA cleanup (PR #474):** the AI-import entry moves from the Mehr tab
  to the top of the Planen tab (the KI-assistant creates planning
  entities — season/block/episode/schedule — so its action lives where
  that structure is built; key `planen-ai-import` replaces
  `mehr-ai-import`). The bottom tab **Kleidung** is renamed to
  **Garderobe** and the Mehr entry **Kategorien** to
  **Kostüm-Kategorien** (semantically precise: the entry manages the
  season-scoped vocabulary, not the costumes themselves). Shell test
  keys (`kleidung-*`, `shell-destination-*`, `kKleidungTabIndex`) are
  deliberately kept — on-device Gherkin suites bind to them; goldens
  regenerated.
- **Version bump:** `0.3.0-alpha.12+21 → 0.3.0-alpha.13+22` (pre-release
  increment per merged-PR practice on the alpha line; `+N` stays strictly
  monotonic for the Play `versionCode`).
- Costume Reassign runs a client-side unassign→assign sequence (issue
  #454). `CostumesController.assign` no longer dispatches the plain
  `POST /v1/costumes/{id}/assign` command onto an already-assigned costume
  (which the backend rejects with 409 `costume.already-assigned`): a
  reassignment now runs `unassign` (echoing the acted-on row's version) then
  `assign` (echoing the unassign ACK version — fence-friendly version
  echoes). Re-picking the already-assigned character is a client-side no-op
  (the backend 422s it). An assign-leg failure after a successful unassign
  leaves the costume honestly UNASSIGNED and surfaces via the command-error
  provider. On-device `costume_assignment.feature` gains a promoted
  reassignment scenario (dedicated seed costume `c-r`; seed step
  generalized, optimistic step tolerates the reconcile race on a fast
  localhost backend).
- **Version bump:** `0.3.0-alpha.11+20 → 0.3.0-alpha.12+21` (pre-release
  increment per merged-PR practice on the alpha line; `+N` stays strictly
  monotonic for the Play `versionCode`).
- Gherkin costume-assignment seed uses the backend #453 repertoire
  binding: `POST /v1/costumes` now carries `season_id`, so the seeded
  costume is created UNASSIGNED yet visible in the season's Kleidung
  stream — the server-side pre-assign workaround from #368 is dropped
  and the optimistic-overlay scenario can exercise a genuine first
  assignment. Un-pending + on-device run of
  `costume_assignment.feature` remains a follow-up (emulator harness
  from #368 in place).
- **Version bump:** `0.3.0-alpha.10+19 → 0.3.0-alpha.11+20` (pre-release
  increment per merged-PR practice on the alpha line; `+N` stays
  strictly monotonic for the Play `versionCode`).

### Added

- AI document import (`flutter-ai-import`): the user-facing
  configure → submit → watch → preview → apply pipeline over
  `/v1/ai-import/*`. Provider/model discovery-driven configuration with
  the two-step credential hand-off (`POST /v1/settings/credentials` →
  vault key id — the LLM key never persists on the device), version-echo
  edits without automatic re-dispatch on 409, credential rollback with
  orphan cleanup; raw schedule/script submission (paste, CSV, PDF via
  `file_picker` — PDF bytes uploaded verbatim, no re-encoding), duplicate
  uploads surfaced honestly (200 → callout, never a fresh import);
  bounded job watch state machine with an honest no-cancel copy
  (cancellation is backend-owned); typed preview rendering with strict
  rejection of unknown future payload kinds; apply into an episode with
  verbatim `draft_ref`s, edit distances from real selections, and a
  missing-context picker requirement. Every dispatch is AUTHZ-gated
  client-side (denial issues zero requests); sign-out and backend-switch
  wipe the hand-off store and job cache.
- **Version bump:** `0.2.0+8 → 0.3.0+9` (MINOR per ADR-033 D2 — additive
  feature surface; `+N` monotonic for the Play `versionCode`; no
  `flutter-v*` tag cut).
- Reports screen (`flutter-reports`): day-context Soll-Ist on-screen report
  (planned/actual counts, moved/missing/skipped/reshot flag chips, finality
  banner — all verbatim from the JSON report read DTOs, no client-side
  recomputation) plus the three per-day PDF report cards (dispo, shoot-day,
  planned-vs-actual): user-initiated streamed fetch through the pinned-CA
  generated client (path-keyed interceptor, 25 MB byte cap with CancelToken
  abort and temp cleanup), in-app FOSS preview (pdfrx) and platform-sheet
  share under `<day>-<report>.pdf`; PDF bytes never persist into Drift.
  Local non-fetching AUTHZ-GATE (`canViewReports` via
  `currentMembershipProvider`) refuses with zero report requests.
- **Version bump:** `0.1.0+7 → 0.2.0+8` (MINOR per ADR-033 D2 — additive
  feature surface; `+N` monotonic for the Play `versionCode`; no
  `flutter-v*` tag cut).
- Pre-release version line: the client versions as `0.x+N` until the
  first store submission, which will cut `1.0.0` (the `1.0.0+1` in
  `pubspec.yaml` was the untouched `flutter create` scaffold default, not
  a maturity claim; backend components version 0.x likewise). Build
  number `+N` keeps increasing monotonically for the Play `versionCode`.
  MINOR bumps carry additive features per ADR-033 D2 even before the
  first tag (D3/D7: tags snapshot the pubspec surface at release time; no
  flutter tag exists yet).
- Login & app shell (`flutter-login-and-app-shell`): auth gate (splash →
  login → seasons), OIDC platform leg (Custom Tabs + deep-link capture),
  light/dark Material 3 design tokens, app-shell overflow menu (identity,
  About, Settings, sign-out with cache clear), About/Info dialog (version,
  AGPL-3.0 + source link, AI usage notice), and settings dialog with
  dev-only runtime backend-URI override (validated, pinned-CA rebuild,
  generation-fenced cache reset).
- `AuthTokenInterceptor`: attaches the session bearer token over HTTPS
  only, always withheld on cleartext (CWE-319).
- Android deep-link registration for `OIDC_REDIRECT_URI` (Gradle
  `manifestPlaceholder` derived from the same source; `compileSdk 37` for
  `flutter_secure_storage`).
- Versioning scheme per ADR-033 (`pubspec.yaml` as single source of truth,
  `flutter-vX.Y.Z` release tags, monotonically increasing `+N` build number
  for the Play Store `versionCode`).
- `AppConfig.appVersion`: CI-injected `--dart-define=APP_VERSION` for the
  About/Info dialog (spec `flutter-app-dialogs`), falling back to `'unknown'`
  for local builds without the define.
- `package_info_plus` dependency as the native `version`/`buildNumber` reader
  (validates the injected `APP_VERSION` in release builds).
- `version-drift` CI job: enforces the `X.Y.Z+N` pubspec format on every run
  and the tag == build-name agreement on `flutter-v*` tags.

### Fixed

- Wrapped-day finality copy on execution 409 (issue #376):
  `sceneShootErrorCopy` branches on the backend's new wire code
  `scene-shoot.shooting-day-wrapped` (409) with the same finality narrative
  as the wrapped-board banner ("This day is wrapped — execution is final and
  read-only."). The board already gates execution controls proactively when
  `wrapped_at` is set; this covers the 409 that slips past that gate when
  the day is wrapped concurrently (other device / projector lag) — copy
  keyed on `code`, never the server `detail`. Planning (Soll) stays enabled
  on a wrapped day, matching the contract's plan-201/execution-409 split.
- **Version bump:** `0.3.0-alpha.4+13 → 0.3.0-alpha.5+14` (pre-release
  increment per merged-PR practice on the alpha line; `+N` stays strictly
  monotonic for the Play `versionCode`).
- AI import disabled state is honest (issue #422): the AI configuration
  screen now branches on the backend's new wire code `ai-import.disabled`
  (status 404, emitted instead of the overloaded generic
  `domain.not-found` when `AI_IMPORT_ENABLED` is unset) and renders a
  dedicated "AI import is not enabled on this instance" card WITHOUT a
  retry affordance — retrying cannot flip a server feature flag. Genuine
  discovery/transport failures keep the retry card. Provider-picker
  degradation shows the disabled copy and hides the retry button on the
  same code (copy keyed on `code`, never the server `detail`).
- **Version bump:** `0.3.0-alpha.3+12 → 0.3.0-alpha.4+13` (pre-release
  increment per merged-PR practice on the alpha line; `+N` stays strictly
  monotonic for the Play `versionCode` — the `version-gate` ships the
  committed pubspec values, CI gates format/monotonicity but does not
  auto-bump).
- Seasons list fetch wired to the backend (issue #377): `seasonsListFetch`
  calls `GET /v1/seasons` via `SeasonRepository.fetchSeasonsList` (regenerated
  `vendor/breakdown_api`) instead of short-circuiting with
  `transport.seasons_list_unavailable`. The projection now confirms a created
  id, so the "Created — catching up" overlay clears and blocks → … → day
  board become reachable. The fetch is unscoped (no `series_id`), confirming
  ids from any series and keeping the full-snapshot cache write coherent.
- **Version bump:** `0.1.0+3 → 0.1.0+4` (monotonic Play `versionCode`; no
  release tag cut — the client stays on the `0.1.x+N` pre-release line).
