<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: muse-spark-1.3-contributor (opencode-go) -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

# Changelog

All notable changes to the Breakdown Flutter client will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
per ADR-033: single source of truth is `version: X.Y.Z+N` in `pubspec.yaml`,
releases are cut as `flutter-vX.Y.Z` tags.

## [Unreleased]

### Added

- **AI-import usability:** Script is now the default import kind and schedules
  are file-only (CSV/PDF); configured AI-imports can change provider and model
  selections; empty stored prompts fall back to the backend defaults in an
  editable XML-highlighted editor (issues #508, #509, #520).
- **Version bump:** `0.3.0-alpha.21+31 → 0.3.0-alpha.22+32` (pre-release
  increment per merged-PR practice on the alpha line; `+N` stays strictly
  monotonic for the Play `versionCode`).
- **Version bump:** `0.3.0-alpha.20+30 → 0.3.0-alpha.21+31` (pre-release
  increment for the localization feature; `+N` stays strictly monotonic for
  the Play `versionCode`).

- **App icon:** the Flutter default launcher icon is replaced with the
  Breakdown-RS mark — the official Material Symbols `checkroom` hanger
  (identical to the app's costuming-tab glyph) above the `settings` gear,
  on the flat brand seed teal (`#009688`, `design/tokens/color.json`).
  Ships as a full adaptive icon (API 26+: vector foreground, color
  background, Android 13+ monochrome/themed layer), legacy rasters for
  pre-API-26 launchers, and a regeneration/drift pipeline
  (`scripts/gen-app-icon.sh`) over the sources in `design/app-icon/`
  (byte-stable, path-data sync check between SVG and VectorDrawable,
  pixel-analytic safe-zone verification: 31.02dp < 33dp).
- **Version bump:** `0.3.0-alpha.18+28 → 0.3.0-alpha.19+29` (pre-release
  increment per merged-PR practice on the alpha line; `+N` stays strictly
  monotonic for the Play `versionCode`).

- AI-config edit form renders the **stored prompt texts** (issue #490):
  `AiConfigView` now carries `prompts` (`{script, schedule}` → stored text)
  alongside `prompt_kinds`, and the configured/edit form seeds the
  script/schedule fields from the fetched config via the existing
  `_PromptFields._sync` mechanism — the fields are never empty at load.
  An untouched save echoes the stored prompt map (the update command
  replaces it wholesale), so prompts are no longer silently cleared; a
  cleared field stays a deliberate "remove prompt" intent (the key is
  omitted). Backend `breakdown_core`/`infra`/`api` MINOR-bumped; client
  regenerated.
- **Version bump:** `0.3.0-alpha.17+27 → 0.3.0-alpha.18+28` (pre-release
  increment per merged-PR practice on the alpha line; `+N` stays strictly
  monotonic for the Play `versionCode`).

- AI-config dialog first-run **prefill/preselect** (issue #471): the create
  flow no longer starts empty. The script/schedule prompt fields are seeded
  from `GET /v1/ai-import/defaults` (the deployment's single-source prompts,
  `AI_IMPORT_DEFAULT_PROMPTS_PATH` or the built-in
  `config/default_ai_prompts.toml`) and the provider + assistant model are
  preselected on first run — the first curated provider in display order and
  its `recommended` model (backend `ModelInfo.recommended`; falls back to the
  first model for backends that predate the flag). Both remain editable and
  user-overridable; a failed defaults fetch degrades to empty editable fields
  (never a blocking state) and the configured/edit path is untouched.
  Per-field touched guards (`scriptPromptTouched`/`schedulePromptTouched`)
  keep a user-cleared prompt field from being silently resurrected by the
  default AND keep the untouched field's prefill when only the other is
  edited (a real regression fixed in review).
- **Version bump:** `0.3.0-alpha.16+26 → 0.3.0-alpha.17+27` (pre-release
  increment per merged-PR practice on the alpha line; `+N` stays strictly
  monotonic for the Play `versionCode`).

### Changed

- AI-import error switches key on the wire codes the backend actually emits
  (issue #481): the non-forbidden arms of `aiUploadErrorCopy`,
  `jobWatchErrorCopy`, and `aiConfigErrorCopy` were keyed on client-invented
  codes the backend never emits, so real 415/404/409 errors fell through to
  the generic `(${code})` fallback. The backend now emits scoped codes
  (`ai-import.unsupported-media-type`, `ai-import.not-found`,
  `ai-config.version-mismatch`; core registry 81 → 84) and the client keys on
  them; `ai_import.unsupported_media_type` (the client script pre-gate) and
  `http.payload-too-large`/`ai-import.disabled` (aligned, extractor-owned /
  already-scoped) round out the surface. Copy stays keyed on the stable
  `code`.
- Same-class fix: every client switch that keyed a version conflict on
  `concurrency.conflict` / `*.version_conflict` (putative codes the backend
  never emits — its ONE version-conflict code is
  `concurrency.version-mismatch`) now keys on `concurrency.version-mismatch`:
  `costumeErrorCopy` (drops the dead `costume.version_conflict` alias),
  `characterErrorCopy`, `costumeCategoryErrorCopy`, `shootingDayErrorCopy`,
  `sceneShootErrorCopy`. A real 409 on those screens previously rendered the
  generic fallback instead of the "changed elsewhere" copy. The dead
  name-uniqueness keys `scene.conflict`/`scenes.conflict` and
  `costume_category.conflict`/`costume_categories.conflict` (no backend code
  exists for either) are removed.
- **Version bump:** `0.3.0-alpha.15+25 → 0.3.0-alpha.16+26` (pre-release
  increment per merged-PR practice on the alpha line — the alpha pre-release
  number and the Play `versionCode` both advance; `+N` stays strictly
  monotonic for the Play `versionCode`).

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

- AI import / settings credential-role denials carry scoped wire codes
  (issue #470): the backend now emits `ai-config.forbidden` (AI-config
  management + provider/model discovery), `settings.forbidden` (settings
  credential endpoints) and `ai-import.forbidden` (job upload/status/
  preview/apply) instead of the overloaded generic `domain.forbidden`, so
  the AI-config screens' "Administrator role required — ask your production
  admin." narrative is reachable again (previously the config screen only
  matched the never-emitted `ai_config.forbidden`/`settings.forbidden`, so
  a real 403 landed in the generic `domain.forbidden` fallback — observed
  live on `GET /v1/ai-import/config`). `aiConfigErrorCopy` keys on
  `ai-config.forbidden`/`settings.forbidden`; the import-job switches key
  on `ai-import.forbidden` (apply screen / upload server-side 403) while
  keeping the client pre-gate deny code `ai_import.forbidden`; the
  job-status banner gains an ownership/scope 403 arm. Copy stays keyed on
  `code`, never the server `detail`.
- **Version bump:** `0.3.0-alpha.15+24 → 0.3.0-alpha.15+25` (pre-release
  increment per merged-PR practice on the alpha line; `+N` stays strictly
  monotonic for the Play `versionCode`).
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
