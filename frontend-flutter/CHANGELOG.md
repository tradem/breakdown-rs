<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash-flex (neuralwatt) -->
<!-- Co-authored-by: muse-spark-1.3-contributor (opencode-go) -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->
<!-- Co-authored-by: qwen3.8-flash (opencode-go) -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Changelog

All notable changes to the Breakdown Flutter client will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
per ADR-033: single source of truth is `version: X.Y.Z+N` in `pubspec.yaml`,
releases are cut as `vX.Y.Z` tags (`v<build-name>`, enforced by
`scripts/release/version-gate.sh`).

## [Unreleased]

- **The import cost card leads with the money and the model** (`0.4.0-beta.28+120
  → 0.4.0-beta.29+121`, issues #761/#768). The card of the job-status screen was
  a flat column of equally weighted `bodySmall` lines, so the two facts an
  operator actually wants — what the import cost and which model produced it —
  were buried between token counts, snapshot rates, energy figures and a price
  date; the provider was not rendered at all. Since #768 the snapshot also has
  more than one priced component and an explicit `CostTotal` that states whether
  a sum may be shown — and the client rendered neither.

  - **Hero figure.** `headlineMedium` under an always-visible label: the money
    the user pays (`cost.total` when `known`, the extraction token cost
    otherwise), or the energy figure (`effective_capped_nano`, the capped value)
    under `cost_display_preference = energy`. The label changes with the figure,
    so a component is never dressed up as the total. A total the server refuses
    (`incomplete` / `mixed_currency`) renders the priced component PLUS a note
    stating why — no rate substitution, no currency conversion (design D2). An
    absent total (every pre-#768 row) claims nothing and stays silent.
  - **Identity.** Model and provider as two labelled chips in a `Wrap`
    (`smart_toy_outlined` / `cloud_outlined`), two lines maximum, ellipsized,
    full value in a tooltip — no overflow at the compact width, and the first
    surface that renders `telemetry.provider` at all.
  - **The #768 split.** When `cost.decision` is present, its OWN
    `provider / model`, its own usage counts and its own priced figures (in the
    component's own currency) render as a subordinate group. An unpriced
    component keeps its counts and says "nicht bepreist" — never `0`, never the
    extraction rate. The image component (`image_cost`) renders its own row,
    because it is priced into the total.
  - **Nothing dropped.** Token counts, cached count, snapshot rates, energy
    consumption, the energy-cap note, `price_as_of` and the #767
    Decision-Model outcome all still render — now icon-prefixed, grouped by
    role (usage → component costs → rates → Decision component → price date) and
    visually subordinate to the hero.
  - **Unchanged honesty.** `unknown` keeps the localized "Unbekannt" as the HERO
    VALUE (never `0`), `not_applicable` still states that no AI model was billed,
    and all math stays the integer nano-currency formatting of
    `cost_format.dart`.
  - **The jobs list agrees.** The compact one-line cost line keeps its text and
    its zero-extra-request behaviour and gains only the metric glyph of the same
    preference (one shared resolution), so list and detail cannot claim
    different primary metrics.
  - Client-only: no wire change, no new request, no second SSE consumer. The
    published card is `AiJobCostCard` (`job_cost_card.dart`), extracted from the
    screen so the pure hero decision (`aiCostHero`) is unit-testable.

- **The generated API client is regenerated for the per-request energy cap**
  (`0.4.0-beta.27+119 → 0.4.0-beta.28+120`, issue #794). The backend now states
  the Neuralwatt surge-protection semantics per **request** in the cost
  snapshot's schema descriptions, so `vendor/breakdown_api/` is regenerated via
  `scripts/regen-client.sh` to keep the committed tree byte-identical to what
  the `openapi-client-drift` job produces.

  - **Documentation only.** Two models carry the new wording
    (`energy_cost_breakdown.dart`, `decision_cost_breakdown.dart`):
    `effective_capped_nano = Σ_calls min(raw_i, token_i)`,
    `capped_by_token_cost` = "any request was reduced", and the token figure is
    priced once over the summed tokens. No field, no wire name, no serializer
    and no Dart API surface changed, so no app code or widget is affected.
  - Version bumped because the client tree changes: a `pubspec.yaml` bump is the
    only honest signal that a client build differs from the previous one
    (ADR-033 D1).

- **The import preview now shows WHICH provider/model produced the rows — and
  says so when no Decision Model is configured** (`0.4.0-beta.25+117 →
  0.4.0-beta.26+118`, issue #760). Provider and model were one tiny `bodySmall`
  line between the app bar and the scene cards, so in a long preview the
  machinery behind the rows was invisible; and a configuration without a
  Decision Model ran silently, so the missing wardrobe continuity suggestions
  and the missing star ratings looked like a defect. Both are preview-header
  disclosures — no new endpoint, no extra call (the state comes from the
  already-cached configuration discovery).

  - **Header card.** `AiNamingCard` replaces the footnote: the model as the
    primary line (`titleSmall`, one line, ellipsized — a long curated id never
    pushes the rows off screen), the provider as the secondary line
    (`labelLarge`), and the unchanged EU AI Act Art. 50 sentence as the caption,
    so the visual promotion does not weaken the disclosure. The submit
    disclosure and the apply section keep their compact line; both surfaces now
    render the SAME shared sentence (`aiNamingSentence`), so the wording cannot
    drift.
  - **Honest degradation.** An unconfigured account or a failed discovery keeps
    the existing "no AI configuration" copy with no model/provider line (a name
    is never invented); a pending discovery keeps the loading note; a reload
    keeps the resolved naming instead of flickering.
  - **"No Decision Model" warning.** A non-blocking card states the two factual
    consequences — Pass-2 wardrobe continuity suggestions and the scene/synopsis
    ratings are skipped — plus that the import still runs, with a link into the
    AI configuration (new keys `aiPreviewDecisionModelWarningTitle`,
    `aiPreviewDecisionModelWarningBody`, `aiPreviewDecisionModelWarningAction`,
    `aiPreviewNamingProvider`). It renders only for a RESOLVED configuration
    with an empty Decision Model slot, never blocks the apply, and never claims
    "unset" from a read that merely failed.
  - Preview goldens re-cut for the new header.

- **A script import that lost scenes is no longer invisible in the app**
  (`0.4.0-beta.22+114 → 0.4.0-beta.23+115`, issue #758, client part of the
  backend fix): importing the 57-scene script 299 "Erlösung" produced an
  episode with 4 scenes, and nothing in the app said so. The server now
  reconciles every detected scene heading against the extracted preview rows
  and states how many rows it had to rebuild from the document headings; the
  client surfaces both.

  - **Preview header.** The script preview's subtitle states what the DOCUMENT
    had next to what the model produced — `57 Skript-Szene(n) · 57 erkannt ·
    4 extrahiert · 53 aus Dokument-Metadaten ergänzt`. A preview extracted
    before the counters existed renders the row count alone: `0`/absent means
    "not recorded", never a fabricated ratio (new keys
    `aiPreviewScriptReconciliation`, `aiPreviewScriptSynthesized`).
  - **Jobs list.** A job whose extraction had to rebuild rows names it on its
    row (`53 Szene(n) nur aus Dokument-Metadaten`, key
    `aiJobsRowScenesRebuilt`) instead of passing for a clean import. The count
    is read from `telemetry.scenes_synthesized`; the Drift cache persists no
    telemetry column, so the line appears with the authoritative list read —
    a cached-first paint omits it rather than guessing.
  - **Rebuilt rows stay appliable.** Each rebuilt row arrives with a
    non-blocking `dropped_row` uncertainty (`field = "extraction"`), so the
    existing uncertainty notice names the missing content row by row while the
    apply stays enabled.
  - The generated client was regenerated for the additive
    `scenes_detected`/`scenes_extracted`/`scenes_synthesized` counters on
    `ScriptContext` and `JobTelemetrySummary`; no hand edits, no breaking change.

- **A saved Decision Model is verified against the server before the app calls
  it configured** (`0.4.0-beta.21+113 → 0.4.0-beta.22+114`, issue #769): the
  reported user configured a Decision Model (`eurouter` / `clef-flash`) before
  importing episode 300, saw no star ratings, and the app had presented the
  configuration as saved — while the backend held no decision configuration at
  all (no `decision_*` payload in the aggregate, three NULL projection columns,
  so the worker resolved `decision: None` and never ran a scoring pass).

  - **Round-trip verification.** A 2xx `POST`/`PATCH` acknowledgement is no
    longer treated as proof of persistence: `create`/`edit` re-read
    `GET /v1/ai-import/config/{id}` — with a bounded-retry refetch, because a
    committed write reaches the read model asynchronously — and compare the
    **submitted** Decision Model triple (provider, model, vault binding) with
    the **stored** one. On a mismatch the save is reported as a failure and the
    draft is preserved; what is never claimed is that the submitted Decision
    Model was stored. The configuration itself is real in both paths (created,
    or PATCH-committed), so the authoritative read replaces the cached view —
    which on `edit` also drops the stale pre-PATCH version, so a retry is not
    rejected as a version conflict. The pickers keep re-seeding from that
    authoritative view.
  - **New localized error** `ai_config.decision_not_persisted` (de/en).
    Client-detected by design: no server problem carries it, because the whole
    point is that the save *looked* successful.
  - **Unconfirmable saves are not success.** A failed read-back surfaces its own
    error (the existing `transport.*` narrative) instead of silently reporting
    the submitted state — "unconfirmed" must never render as "saved".
  - **Clearing is verified too.** Disabling scoring submits explicit nulls (the
    tri-state PATCH) and the same read-back proves the clear landed; a swallowed
    clear is the same class of silent loss.
  - **Tests:** a Tier-1 matcher suite (match, NULL columns, wrong model, wrong
    binding, wrong provider, verified clear, rejected clear) plus two screen
    tests asserting the PATCH body carries all three parts and that a read-back
    without the triple renders the localized error instead of success. The
    repository test double now echoes the submitted body for `getConfig`, so the
    existing suite exercises the real round trip rather than a real network call.

- **The AI-import jobs list identifies each row and stops showing a stale
  stage** (`0.4.0-beta.20+112 → 0.4.0-beta.21+113`, issue #763): every finished
  job rendered „Vorschau wird gespeichert …" forever, and a row was titled only
  `Skript · 12. Okt. 2026`, so after a few imports the user could not tell which
  document it belonged to or which episode it produced.

  - **Stale stage gone.** The block renders only while the job is in progress
    (`pending`/`running`), never on `progress != null` — the fetched row could
    still carry the worker's last frame (`storing_preview`), and the Drift cache
    kept it alive across restarts. The paired label now renders **with its
    values** (`Gefundene Episoden: Ep. 299, Ep. 300`); the label-only line is
    gone. The backend clears the column on terminal transitions too (part 1).
  - **Row identity.** The title is the uploaded document's own file name (two
    lines, then ellipsized) with `kind · date` as secondary text; an unnamed row
    keeps today's `kind · date` title. The identity line names the import target
    once an apply ran — `Skript · 299 Erlösung · 57 angewendet`, `(+n)` for
    further episodes — and degrades to today's copy when nothing is known.
  - **The upload sends the name.** `AiImportDocument` carries the picked file's
    name; the repository sends it as a percent-encoded UTF-8
    `X-Document-Filename` header, leaving the raw-body `Content-Type` contract
    untouched. A pasted body sends no header (nothing invented).
  - **Cache.** Two additive, nullable Drift columns (`source_file_name`,
    `applied_episodes_json`) with the guarded v16 → v17 migration; a
    cached-first paint serves what it knows and never fabricates a name.
  - Copy/docs: six de/en ARB keys + `flutter gen-l10n`, and the
    `ai-import-jobs` screen spec (wireframe, component table, interactions,
    accessibility). Tests: mapper/identity/progress-gate units, the v16 → v17
    migration probe, upload-header + `encodeDocumentFileName` units, the
    submit-dispatch name forwarding, and four row widget tests (terminal row
    without stage, running row with episode values, named vs unnamed title,
    multi-episode identity line).

- **Dispo/Soll-Ist rows render `Szene {n}` / `Tag {day} · {location}`, not a
  model dump** (`0.4.0-beta.19+111 → 0.4.0-beta.20+112`, issue #766): the
  day-scoped report interpolated the ROW instead of its field
  (`'$row.sceneNumber'` — a dropped brace), so any row that actually carried a
  scene number or script day rendered
  `Szene SollIstDiffRow{location=…, sceneId=…, plannedOrder=…}.sceneNumber` —
  user-visible garbage that also leaked internal field names, ids and order
  keys. The aggregate surface was already correct, which is why only the
  day-scoped view was affected.

  - Both sites now pass the value (`row.sceneNumber ?? <short scene id>`,
    `row.scriptDay!`), mirroring `reports_aggregate_screen.dart`; the
    no-scene-number fallback to the short `sceneId` is unchanged.
  - Regression coverage: `test/features/reports/reports_screen_test.dart`
    renders a row with `sceneNumber`/`scriptDay`/`location` and asserts the
    exact strings (`Szene 2`, `Tag 1 · Tiefgarage / Klinikum
    (Stationscounter)`) plus the absence of `SollIstDiffRow`, braces,
    `sceneId=`/`plannedOrder=` and the raw UUID; the twelve report goldens were
    regenerated (their rows previously showed the dump).
  - Root-cause guardrail: new `breakdown_lints` rule
    `no_field_access_string_interpolation` flags an unbraced `$ident` followed
    by a literal `.identifier` when the interpolated value is not a `String`
    (`'goldens/x_$name.png'` stays legal). Registered in the analyzer plugin
    (`packages/breakdown_lints`), in `analysis_options.yaml` and in the CI
    runner (`tool/breakdown_lints_runner`), with 15 unit tests
    (`tool/breakdown_lints_runner/test/`, `dart test`) and a new CI step.
    `lib/` + `test/` carry zero violations after the fix.
  - Latent same-class hardening: the two `Object?` tile-label helpers
    (`SceneTile`, `EpisodeTile`) take the wire types instead
    (`int? number` + `String? fallbackId`, `int? number`), so a DTO can no
    longer be interpolated into a visible title.

- **Preview & apply: Pass-2 outfit provenance and the wardrobe-gap candidate
  picker** (`0.4.0-beta.18+110 → 0.4.0-beta.19+111`, issue #745, OpenSpec
  change `ai-import-decision-outfit-continuity`): the review surface now reads
  the contract the previous entry only modelled.

  - Each look renders ONE provenance badge — *wörtlich aus dem Skript* /
    *aus dem Skript abgeleitet* (Pass 1) or *übernommen aus Szene N* /
    *aus dem Szenenkontext abgeleitet* (Pass 2), the scene number taken from
    `DraftOutfit.provenance`. A Pass-2 look renders NO source-quote line: it
    has no chunk to quote, and an empty quote would read as a script
    statement. A preview stored before the field existed renders no badge.
  - A wardrobe gap (Pass-2 `dropped_row` uncertainty on `outfits`) whose
    candidates the script supports becomes a one-tap picker: one `ChoiceChip`
    per candidate (look name + the server's confidence) plus an explicit
    "leave the scene without a look". A gap without candidates keeps the
    plain notice — an invented option is never offered.
  - The pick rides `continuity_selections` on the apply request, carrying the
    preview-wide `character_identity` derived from the gap's own scene
    (`lib/features/ai_import/import_jobs/continuity_gap.dart`, pairing the
    uncertainty with the scene's undressed figure through the continuation
    candidate's source row — never by parsing server prose). A pick counts as
    a review edit, so `accept_as_is` stays truthful; leaving a gap unresolved
    applies the preview unchanged.
  - The apply card repeats each gap's resolution at the dispatch (EU AI Act
    review gate) and localizes a `409
    ai-import.apply-unknown-continuity-candidate` as "refresh the preview and
    re-apply".
  - `AiApplyState` gained `copyWith`; every reviewer-decision mutation now
    goes through it, which also stops `setCommandError` /
    `dismissCommandError` from silently dropping the #706 day decisions.
  - Coverage: `test/unit/continuity_gap_test.dart` (identity mirror + gap
    pairing), `test/features/ai_import/preview_continuity_test.dart` (badges,
    quote suppression, picker → wire, stale-pick 409, four goldens) and
    `features-spec/ai_import_continuity_gap.feature` (`@pending` until the
    on-device harness can seed a Pass-2 preview).

- **AI import Pass-2 contract in the generated client**
  (`0.4.0-beta.17+109 → 0.4.0-beta.18+110`, OpenSpec change
  `ai-import-decision-outfit-continuity`): `vendor/breakdown_api` regenerated
  from `backend/openapi.yaml`, so the client now models where an extracted look
  came from — `DraftOutfitOrigin` is a plain string enum (`explicit_quote` /
  `derived` / `continued_from_scene` / `inferred_from_context`) and the Pass-2
  payload travels in `DraftOutfit.provenance`; `DraftOutfitCandidate`,
  `Uncertainty.candidates`, `OutfitContinuitySelection` /
  `OutfitContinuityCandidate` and `ApplyAiImportRequest.continuitySelections`
  are available. A regression test (`test/unit/draft_outfit_origin_test.dart`)
  pins that all four origin values decode and re-encode — the PR #746 review
  found that a data-carrying origin made the generated client reject
  `"explicit_quote"` outright. **No UI change yet:** the review screen still renders the
  pre-Pass-2 surface, because the provenance badges and the wardrobe-gap
  candidate picker are issue #745. `flutter analyze` clean,
  `test/features/ai_import` green.

- **AI import review surface follows the outfit/piece split** (OpenSpec change
  `ai-import-outfit-and-pieces`; `0.4.0-beta.16+108 → 0.4.0-beta.17+109`):
  the regenerated client replaces `DraftCostume`/`CostumeDecision`/
  `UnappliedCostume` with `DraftOutfit`/`DraftPiece`/`OutfitDecision`/
  `UnappliedOutfit`, so the review UI now shows one entry per **look**
  (`{character}: {name}`) with its grounding quote and the garments the look
  decomposes into (`Kleidungsstücke: OP-Kasack (Oberteil), …`). The reviewer
  vetoes a look, not an individual garment; the apply sends
  `outfitDecisions` and the outcome card reports
  `Kleidungsstück(e)` + `Look(s)` plus the per-row `unappliedOutfits`
  reason (new `piece_rejected`). Copy keys renamed
  `aiPreviewOutfit*` / `aiApplyUnappliedOutfit*`; the glossary inventory
  follows.

- **Issue #739 follow-up — review round on the look surface:**
  `0.4.0-beta.15+107 → 0.4.0-beta.16+108`. The review edits below were still
  unstaged in the working tree when #741 was squash-merged, so `main` carried
  the pre-review shape; they land here (no new screen, no wire change):

  - **AUTHZ-GATE is tri-state:** an unresolved membership fetch (transport
    fault, empty projection scope, provider torn down mid-await) is
    `membership.pending` and never a denial; a resolved `false` is
    `domain.forbidden` — the code the server actually renders on every
    `/v1/outfits*` route (`authorize_outfit_scoped` → 403). The retired
    `outfit.forbidden` never existed server-side. A failed fetch result is
    dropped so the NEXT command re-fetches instead of replaying the pending
    verdict as permanent, a successful command clears the retained failure,
    and `photoErrorCopy` localizes `domain.forbidden` alongside the photo
    codes.
  - **Cross-identity safety:** `characterOutfits` writes through the
    `CacheWriteFence` generation captured at fetch start, and sign-out
    invalidates the six look families, so no previous identity's rows or
    command failure survive the reset (`OutfitsPrevRows` is keepAlive and the
    empty-cache branch preserves nonempty state).
  - **Optimistic removal:** `applyOutfitRemovePieceOptimistic` rebuilds
    `pieceIds` together with `pieces`, so a remove → re-add of the same
    garment inside one reconciliation window is no longer a silent no-op.
    `applyOutfitAddPieceOptimistic` appends to `pieceIds` too — the mirror
    direction of the same desync: `createVariant` builds its optimistic fork
    from `source.pieceIds`, so a row-only add forked a look that silently
    omitted a garment still on screen.
  - **Garment picker:** the look detail's add-picker awaits
    `piecesListFetchProvider(season)` instead of reading a projection no
    surface ever watched — entered from Character → Looks → detail it now
    lists the season's garments. A failed fetch reports
    `outfitPieceListFetchError` with a retry action instead of the picker's
    "no garments in this season" copy (a false claim about the repertoire),
    and the await is held by a manual subscription so the auto-dispose fetch
    provider cannot tear down mid-request and fail its cache-write fence.
  - **Copy:** the continuity dropdown uses `continuityPieceLabel` /
    `continuityPieceLabelWithNotes` (de/en) instead of interpolating
    `'Piece $id'` inline.
  - **Verified locally:** `flutter analyze` clean, `flutter test` 1895/1895
    green, `breakdown_lints` clean, `scripts/check-authz-gates.sh` passed,
    ARB de/en parity + glossary inventory clean.

- **Wardrobe port to the `Piece`/`Outfit` split (backend change
  `separate-piece-and-outfit-domain`):** `0.4.0-beta.13+105 →
  0.4.0-beta.14+106`. The backend retired the single `Costume` aggregate and
  replaced it with two — `Piece` (fundus garment: required `name`, one optional
  category, season repertoire, details, photos, **no character binding**) and
  `Outfit` (a character's composed look: mandatory character, `0..n` pieces
  with layering, `variant_of`, photos) — and re-pointed scene casting to
  `SceneOutfitBeat`. The client follows in one step:

  - **Generated client:** regenerated from `backend/openapi.yaml`
    (`/v1/pieces*`, `/v1/outfits*`, `/v1/characters/{id}/outfits`,
    `/v1/scenes/{id}/outfits*`; the `/v1/costumes*` routes are gone). The
    `costume-category` vocabulary routes are unchanged by design.
  - **Offline cache (schema v16):** `piece_cache_rows` /
    `fundus_piece_cache_rows` carry the required `name` and no `character_id`;
    a new `outfit_cache_rows` slice is keyed by character. The retired
    `costume_cache_rows` snapshots are dropped in the migration — they describe
    a DTO that no longer exists and could never be read again — and refill on
    the next TTL snapshot-replace (the one deliberate exception to the
    "no destructive cache migrations" rule, documented in the migration).
  - **Data layer:** `PieceRepository` (create-with-name, rename, notes,
    details, category, repertoire, photos) and the new `OutfitRepository`
    (list by character, create, variant fork, rename, notes, add/remove piece)
    with optimistic overlays; scene beats dispatch outfit ids; the photo
    bindings are `piece`/`outfit`.
  - **UI:** the wardrobe screens operate on **pieces**; the character
    assignment actions are removed (a garment no longer belongs to a
    character), and the scene beat picker lists the character's **outfits**,
    labelled by the look's own name. Tile identity uses the piece's required
    `name`, falling back to the detail subject and notes.
  - **Verified locally:** `flutter analyze` clean, `flutter test` 1853/1853
    green, client regeneration byte-identical (drift job), goldens
    regenerated for the tile/editor/detail/beat sections.

  The fuller wardrobe UX (dedicated outfit list/detail screens, piece↔outfit
  navigation, German copy) is tracked in follow-up issue #739.
- **Issue #739 — wardrobe frontend for the `Piece`/`Outfit` split:**
  `0.4.0-beta.14+106 → 0.4.0-beta.15+107`. The compile-level port above left
  the presentation layer on the retired vocabulary and the look (outfit)
  half without screens. This change finishes the client side:

  - **Presentation rename (no behaviour change):** `lib/features/costumes/`
    → `lib/features/pieces/` with `PieceRow`, `PiecesScreenState`,
    `PiecesViewController`, `PieceTileIdentity`, `pieceTileIdentity`,
    `pieceDisplayName` and the matching providers; ~80 copy keys
    `costume*` → `piece*` ("Kleidungsstück") and the scene-beat keys
    `sceneDetail*Costume*` → `sceneDetail*Outfit*` ("Look"). The
    `costume-category` vocabulary, the `assign_costumes` capability with its
    "Kostüm-Rolle" copy, the `hasActiveCostumeRole*` predicates and the
    AI-import draft vocabulary are deliberately untouched.
  - **Outfit feature (new):** `lib/features/outfits/` — a look list on the
    character detail (name, variant lineage marker, piece count, create) and
    an `OutfitDetailScreen` (rename, notes, ordered garment rows with
    add/remove, fitting photos, `Variante erstellen`). Commands run the
    awaited season-scoped AUTHZ-GATE mirror, apply the optimistic overlay and
    clear it on the version fence with a bounded-retry resync.
  - **Piece ↔ look navigation:** an outfit's garment row opens the piece
    detail of the look's season; the piece detail never derives a command
    payload from a second projection read.
  - **Photo bindings repaired:** the raw-bytes upload targets
    `/v1/pieces/{id}/photos` (the retired `/v1/costumes/{id}/photos` literal
    was a silent 404), the outfit photo trio is wired, and the bounded variant
    watch is one implementation generic over the enriched view.
  - **Dead code removed:** the retired `assign`/`reassign`/`unassign` copy and
    the `photo.requires_character` branch (the backend answers
    `piece.container-unresolved` for an unresolvable garment container).
  - **Gherkin:** `costume_assignment.feature` → `outfit_casting.feature`
    (cast a look, continuity by repeated `outfit_id`, deviation via variant
    fork, role denial on the look surface with a zero-command assertion); the
    dev seed creates garments, looks, a variant, an episode and a scene.
  - **Docs:** `docs/design/screens/{pieces,outfits}.md`, glossary terms
    (Kleidungsstück / Look), and the neighbouring screen specs re-termed.
  - **Verified locally:** `flutter analyze` clean, `flutter test` 1886/1886
    green with regenerated goldens, coverage 81.5 % (gate 80 %),
    `scripts/regen-client.sh` byte-identical, `breakdown_lints` clean,
    ARB parity + glossary inventory clean, design diagrams compile.
- **Issue #736 — Decision provider picker driven by the backend capability:**
  `0.4.0-beta.12+104 → 0.4.0-beta.13+105`. The Decision Model provider
  picker filtered its entries through the client-side allowlist
  `kDecisionCapableProviderKeys = {neuralwatt, eurouter, openrouter}`, so a
  provider the backend added stayed unreachable and a provider it de-listed
  stayed offered (an avoidable dead end: the decision-models route answers
  `422` for it). The constant is gone — every `GET /v1/ai-import/providers`
  row now carries the additive `decisionCapable` flag (backend `api 0.41.0`,
  regenerated `breakdown_api`), and the picker renders exactly the providers
  the backend reports as capable, plus the explicit "disabled" entry and the
  stale-configured-key fallback (a stored decision provider the route no
  longer reports capable — or a provider list still loading — still renders,
  so the Dropdown never asserts on an unknown `initialValue`). The flag is
  nullable on the wire (`decision_capable` is not a required property): a
  backend that predates it serves rows without the field, and the picker then
  reads "not capable" — never a failed provider discovery that would block
  AI-config setup entirely on the older-server skew case. Covered by a widget
  regression (a capable provider appears, a non-capable one does not, disabled
  + stale fallback still render), a Tier-1 route test proving the flag
  round-trips from the wire, and a Tier-1 absence test (an old backend's row
  deserializes with an unknown capability instead of throwing).

- **Issue #731 fix point 4 — Decision Model picker: honest 422 "provider
  unavailable" copy:** `0.4.0-beta.10+102 → 0.4.0-beta.11+103`. The
  decision-model picker collapsed EVERY catalog failure to the generic "The
  model catalog could not be loaded." copy, while the assistant and image
  pickers already distinguished a 422 (unknown / not decision-capable
  provider) into "Provider unavailable — the model catalog cannot be read.".
  The picker now renders that same discrimination (its doc comment already
  claimed the parity), so a provider the server rejects outright no longer
  looks like a transient catalog problem. Covered by two widget tests: the
  422 test fails on the pre-fix code (the regression pin) while the 503 test
  is the passing control that keeps the generic copy from being swallowed by
  a blanket 422 branch. Presentation-only — no generated-client/API surface
  touched.

- **Version bump / generated-client sync (backend issue #732):**
  `0.4.0-beta.9+101 → 0.4.0-beta.10+102`. The regenerated `breakdown_api`
  client picks up the backend's curated image-model catalog endpoint
  (`GET /v1/ai-import/providers/{provider}/image-models`, backend `api
  0.40.0`) — the new `listAiImageModels` client method. The Image Model
  picker consumes the dedicated image catalog now: an empty catalog (a
  text-only provider, e.g. eurorouter/neuralwatt) collapses the picker to
  a greyed-out "— none —" with a localized hint instead of listing the
  assistant/extraction LLMs (issue #732, mirroring the #731 decision-
  picker fix).
- **Version bump / generated-client sync (backend issue #722):**
  `0.4.0-beta.7+99 → 0.4.0-beta.8+100`. The regenerated `breakdown_api`
  client picks up the backend's Decision Model surface (issue #722) — the
  additive `AiConfig`/request decision fields (`decisionProvider`,
  `decisionModel`, `decisionVaultKeyId`; tri-state on the update request),
  the preview score fields (`DraftScene.sceneScore`/`synopsisScore`/
  `scoring`, `DraftShootingDay.score`,
  `ShootingScheduleRow.shootingDayScore`), the `DecisionRubric` model and
  the `GET /v1/ai-import/providers/{provider}/decision-models` catalog
  endpoint. Purely additive — no existing type changed shape; the star-
  rating UI consuming these fields lands with issue #723.
- **Issue #721 — set-shorthand mood reinforcement + `<Episode>.<Scene>` schedule rows:**
  `0.4.0-beta.6+98 → 0.4.0-beta.7+99`. The mood line (`I/T`, `A/N`, `I/A/T`, …)
  renders with its reinforcing Material icons (`home_outlined`/`park_outlined`/
  `sensor_door_outlined` + `wb_sunny_outlined`/`dark_mode_outlined`/
  `wb_twilight_outlined`/`bedtime_outlined`) on scene detail, script overview
  tiles and AI preview rows — icons reinforce the visible text, never replace
  it; a scene without a mood renders no line. The shared
  `BreakdownMaterialIcons.forSceneMood` resolver and the `SceneMoodLabel`
  widget live in `lib/design/` (icons are decorative, `ExcludeSemantics`);
  the glossary rows are updated in the same change. The regenerated client
  carries `ShootingScheduleRow.episodeNumber` for the backend's lossless
  `<Episode>.<Scene>` schedule parsing (issue #721). No new copy keys (the
  visible label reuses `sceneMood`).
- **Issue #706 frontend continuation — shooting-day decisions + planned→actual
  merge:** `0.4.0-beta.5+97 → 0.4.0-beta.6+98`. The script preview renders
  each scene row's extracted shooting day (`DraftShootingDay` verbatim
  marker, `Tag <n>` fallback); the apply card gains the per-day-group
  decision section (accept-all default, unchecking sends `accepted: false`,
  one decision per group on the wire so the backend's
  `ai-import.apply-missing-shooting-day-group` gate never trips) with its
  dispatch-point summary (EU AI Act review gate) and `skipped_day_groups`
  on the outcome card; a toggled day is an honest `edit_distance` edit.
  The shooting-days screen adds the planned→actual merge: an
  "In echten Drehtag überführen" action on AI-extracted, non-archived days
  opens a target picker (same episode, not self/wrapped/archived) over
  `POST /v1/shooting-days/{id}/link-into/{target_id}`, with keyed copy for
  `shooting-day.target-wrapped` and `shooting-day.episode-mismatch`.
  No wire-contract change: the client consumes the already-regenerated
  `breakdown_api` types.

- **Version bump / generated-client sync (backend issue #706):**
  `0.4.0-beta.4+96 → 0.4.0-beta.5+97`. The regenerated `breakdown_api`
  client picks up the backend's script-apply shooting-day surface — apply
  request `shooting_days` (per-day reviewer decisions), response
  `skipped_day_groups` + script-side `created_days`/`planned_scene_shoots`,
  `DraftScene.shooting_day`/`DraftShootingDay` preview metadata, and the
  new `POST /v1/shooting-days/{id}/link-into/{target_id}` route with
  `LinkShootingDayResponse`/`ApplyShootingDayRequest`. No client feature
  work in this PR: the planned→actual day assignment UI continues in a
  follow-up branch (documented on issue #706). The new generated types are
  additive, so the app compiles unchanged and the whole test suite stays
  green.

- **Version bump / pre-release phase switch:** `0.4.0-alpha.41+92 →
  0.4.0-beta.1+93` — alpha → beta, the pre-release counter restarts at
  1. Semver-monotonic by construction: the label comparison precedes the
  numeric one, so `beta.1` > `alpha.41` (ADR-033 unified release format;
  the version gate's regex accepts both labels). The build number
  (versionCode) deliberately does NOT restart — `+93` continues the
  strictly-monotonic counter the release gate enforces across all
  previous `v*` tags and Android upgrade installs require.

- **Version bump:** `0.4.0-alpha.40+91 → 0.4.0-alpha.41+92` — apply
  feedback (user report: "the button activates but nothing happens" — the
  applies HAD succeeded server-side, 59/72 scenes, but with zero visible
  progress the reviewer re-tapped and navigated away mid-apply, dropping
  the outcome with the autoDispose notifier):
  * The submit button shows a spinner and disables while the apply runs
    (widget-local busy flag — dozens of commands per apply take seconds).
  * The "Episode wählen…" picker tile no longer renders when the preview
    carries episode groups (the in-preview creation assigns automatically);
    it stays for the single-episode flow without markers.

- **Version bump:** `0.4.0-alpha.39+90 → 0.4.0-alpha.40+91` — block-aware
  episode resolution (the 403 apply loop, found on the second 294.pdf
  import from a different block scope):
  * The job is bound to its upload block; the apply's cross-block IDOR
    guard requires the context episode to live in THAT block. The resolve
    matched episodes by NUMBER across the whole project — a same-number
    episode in a DIFFERENT block got adopted, and every apply answered 403
    forever (no retry — definitive — but the error copy is access-neutral,
    so it read as "nothing happens").
  * `resolveGroupDefaults` and the in-preview creation now adopt only
    same-block episodes; a number taken by ANOTHER block's episode
    surfaces the honest refusal `ai_import.episode_number_other_block`
    ("Wechsle den Block und lade das Dokument dort erneut hoch") — the
    dedup then lands on the other block's job, where the number resolves.

- **Version bump:** `0.4.0-alpha.38+89 → 0.4.0-alpha.39+90` — the episode
  target area ("Ziel ändern") moves INTO the apply card, ABOVE the dispatch
  button, and apply activates only on a RESOLVED episode (user UX spec):
  * `Import anwenden` activates exactly when all blocking-uncertainty
    checkboxes are ticked AND every group's episode is settled — found in
    the project, created in-preview, or picked via "Ziel ändern". An
    unresolved create target keeps the button disabled (the create-kind
    wire shape is no longer dispatchable through the UI; the backend 409
    recovery stays as defense-in-depth).
  * The in-preview creation now works WITHOUT a remembered context: the
    block anchor comes from the cached job row (`aiJobBlockInfoProvider`),
    the project from the block when needed — the curl-uploaded 294.pdf job
    (no context) previously skipped creation entirely.
  * "Ziel ändern" → create now really creates the episode server-side and
    adopts it (before: it only set a client-side intent that never
    materialized); "→ existing" adopts the picked episode into the apply
    context so the cross-block IDOR guard always passes.

- **Version bump:** `0.4.0-alpha.37+88 → 0.4.0-alpha.38+89` — in-preview
  episode creation (the 294.pdf empty-picker flow):
  * Root cause of the stuck import: the job is bound to its upload block,
    the apply's cross-block IDOR guard requires the context episode to live
    in THAT block — and the block had zero episodes (the block-scoped picker
    was empty, create-at-apply needs a valid `episode_id`) → apply was
    unreachable no matter what the reviewer did.
  * The preview seeding now CREATES each group's missing episode right in
    the review step, in the job's block (number from the `Ep.:` marker, name
    from the document's title-page heading), flips the group target to
    assign-EXISTING and moves the apply context to the created episode —
    the reviewer sees the episode exist before apply, no manual creation,
    no 409 dance. Resolve/create-optional: any failure keeps the
    create-at-apply default; the backend 409 recovery stays the backstop.
  * `AiJobContext` carries the job's `blockId` (the creation anchor).

- **Version bump:** `0.4.0-alpha.36+87 → 0.4.0-alpha.37+88` — three
  dev-stack fixes (2026-10-19 user reports):
  * **Offline pill stuck red:** the #654 liveness probe built a bare Dio
    WITHOUT the pinned-CA `SecurityContext`, so on the pinned-HTTPS dev
    setup every probe failed TLS verification and the pill never left
    `degraded` — while the app itself (pinned context) talked to the
    backend fine. The probe now rides the same pinned context (lazy read:
    the provider stays constructible where bootstrap never ran).
  * **AI-import episode auto-assign (with the backend extraction fix):**
    the apply section resolves each episode group against the project's
    live episodes — an existing `Ep.:` number defaults to
    assign-EXISTING (no more 409 `number-already-exists` recovery dance
    for an episode the reviewer already created); a missing number keeps
    the create-new default, now titled from the document's title-page
    heading (backend `(294) "Freundschaft"` scan). Resolve-optional: any
    fetch failure keeps the create defaults.
  * Scene numbers / script-index dedup are BACKEND-side (`pdftotext
    -layout` + number merge + title scan) — no client change beyond the
    resolve call above.

- **Version bump:** `0.4.0-alpha.35+86 → 0.4.0-alpha.36+87` — AI-import
  SSE job frames decode again (app-side `ai_import.dto_invalid` on every
  live job watch, found in the dev stack 2026-10-18):
  * `_decodeJobFrame` used the bare `serializers` instance (no
    `StandardJsonPlugin`), but the generated custom built_value
    serializers expect the plugin's pair-list representation — every
    `event: job` frame failed the map cast, decoded to `null`, and
    surfaced as `ai_import.dto_invalid` while waiting for the import to
    process. The decoder now uses `standardSerializers` (the same
    instance `api_client.dart` defaults to).
  * Regression test decodes a byte-for-byte live SSE frame captured from
    `GET /v1/ai-import/jobs/{id}/events`
    (`test/data/ai_import_sse_frame_decode_test.dart`). No API surface,
    no command dispatch, no vendor regeneration.

- **Version bump:** `0.4.0-alpha.34+85 → 0.4.0-alpha.35+86` — issue #675,
  per-import AI cost transparency:
  * Regenerated `vendor/breakdown_api/` (`LlmProvider.gemini`, `ModelInfo.pricing`,
    `AiConfigView.costDisplayPreference`, `AiImportJob.cost` / `telemetry`, the
    `CostBreakdown` / `ModelPricing` / `JobTelemetrySummary` model family).
  * AI config screen (`flutter-ai-config`): model picker renders formatted
    token + energy price signals from `ModelInfo.pricing` (localized
    `"Unbekannt"` / `"Unknown"` when `pricing == null` — never `0`); the
    `cost_display_preference` (`token` vs `energy`) selector threads through
    create and PATCH.
  * Jobs list + job status screen (`flutter-ai-import-workflow`): compact
    cost line per row and the detailed `CostBreakdown` card (token + energy
    breakdowns, snapshot rates, `price_as_of`, Neuralwatt cap note), with
    the primary figure switching on the user's `cost_display_preference`;
    `unknown` renders localized Unknown copy, never `0`. The terminal
    `succeeded` SSE frame populates the card without a manual refresh.
  * New pure cost formatters (`cost_format.dart`): integer-string
    nano-currency + mJ→Wh rendering, zero floats.

- **Version bump:** `0.4.0-alpha.33+84 → 0.4.0-alpha.34+85` — issue #664,
  AI-import SSE progress:
  * Regenerated `vendor/breakdown_api/` (`AiImportProgress`, `progress`
    on `AiImportJob`, the `/events` SSE route).
  * Drift cache v15: the nullable `progress_json` column on the AI job
    cache (guarded ADD COLUMN migration) + `aiImportProgressFromWire`.
  * `AiImportRepository.watch(jobId)` now consumes the SSE stream
    (`ResponseType.stream` over the pinned-CA Dio client, 65 s read-idle
    watchdog, `Last-Event-ID` reconnects, success-only cache writes) —
    no periodic polling anymore.
  * `AiJobStatusController` enforces the battery contract: cancel on
    screen disposal or app backgrounding; on resume ONE snapshot GET and
    a re-subscribe only for non-terminal jobs.
  * Progress UI: localized stage copy, `chunk / chunks_total` with a
    determinate bar (only when the backend carries a positive total) and
    episode chips on the status screen; compact stage/episode subtitle
    on the jobs list (still zero SSE streams there).

- **Version bump:** `0.4.0-alpha.32+83 → 0.4.0-alpha.33+84` — issue #671,
  the jobs-list delete affordance:
  * `DELETE /v1/ai-import/jobs/{id}` (backend issue #671): dead-letter
    rows carry a delete affordance (delete icon in the row trailing,
    absent on every other status) with the localized confirm dialog
    naming the dedup-lock release — a stuck import no longer permanently
    blocks re-uploading the same document.
  * Optimistic removal + Drift cache eviction (`deleteById`) + reconcile
    refetch in `jobs_controller`; a failed delete rolls the optimistic
    removal back and surfaces a code-keyed SnackBar (`ai-import.
    job-not-deletable` gets its own narrative — the #665 class).
  * Generated Dart client rebuilt for the DELETE operation
    (`scripts/regen-client.sh`).

- **Version bump:** `0.4.0-alpha.31+82 → 0.4.0-alpha.32+83` — issue #678,
  the editable role type:
  * The Cast screen's read-only category chip becomes an `ActionChip`:
    tap opens the three-category picker sheet (current one pre-selected);
    the dispatch carries the acted-on row's version echo and reconciles
    through the shared refresh + command-error banner (stale version →
    the established refresh-retry UX).
  * Picking the current category is a client-side no-op. Manual
    correction path for #677's import classifications.
  * Generated Dart client rebuilt for `PATCH /v1/characters/{id}/category`.

- **Version bump:** `0.4.0-alpha.30+81 → 0.4.0-alpha.31+82` — issue #677,
  the extracted character categories:
  * Generated Dart client rebuilt for the widened preview wire shape
    (`DraftScene.characters`: plain name strings → typed
    `DraftCharacter { name, category }` objects, additive with serde
    defaults server-side). Test fixtures updated for the typed shape; no
    app code consumes the list today.
  * The apply flow now carries the extracted classification end-to-end;
    manual correction lands with #678.

- **Version bump:** `0.4.0-alpha.29+80 → 0.4.0-alpha.30+81` — issue #666,
  the scope-picker staleness fix:
  * The episode and block scope pickers wrap their list in a
    `RefreshIndicator` invalidating the shared cache-first seam
    (`episodesListFetchProvider` / `blocksListFetchProvider`) — a stale
    list is recoverable from the picker itself; the season chip already
    had pull-to-refresh (sibling audit: N/A).
  * A successful AI apply invalidates both fetch families in the
    apply-result handling, so the created episode is visible in the pill
    navigation without leaving the flow (the refetch rewrites the block's
    Drift cache rows).

- **Version bump:** `0.4.0-alpha.28+79 → 0.4.0-alpha.29+80` — issue #665,
  the apply create-or-assign recovery:
  * A refused apply (`409 episode.number-already-exists`) renders a
    one-tap "assign the existing episode instead" action in the error
    card: the affected group(s) — found by the requested create number —
    flip to existing with the id the 409 carried, and the retry lands in
    the existing episode (idempotent continuation, no duplicate episode).
  * Older backends without the S1 extensions degrade to the plain
    narrative; the create default from the draft's `Ep.:` marker
    (pre-existing) is now regression-covered by the recovery test.
  * Generated Dart client rebuilt for the response extensions.

- **Version bump:** `0.4.0-alpha.27+78 → 0.4.0-alpha.28+79` — issue #663,
  the AI-import apply-gate rework:
  * The apply card renders blocking `field_ambiguity` uncertainties with
    one-tap acknowledge checkboxes; apply stays disabled until every
    blocker is confirmed (the client-side mirror of the backend gate, so
    the button explains itself instead of producing a guaranteed 409).
  * An `ai-import.apply-blocked` refusal renders the server's remaining
    blocking items inline (localized per stable `code`, never the bare
    code): `ProblemError` now carries the problem `extensions`.
  * Generated Dart client rebuilt for the `uncertainty_acknowledgements`
    request field (rebuild-only via `scripts/regen-client.sh`).

- **Version bump:** `0.4.0-alpha.26+77 → 0.4.0-alpha.27+78` — issue #670,
  the Easter-egg redesign session outcome:
  * **Déja-vu cat restyled** to the approved Ghibli-inspired artwork
    (seated cat, big alert camera-facing eyes, tail around the front
    paws; near-black radial fur gradient + blue-grey rim light, readable
    in both themes). Hand-ported `CustomPainter` (decision D1 of
    `670-easter-egg-redesign-karl-kleiderbuegel`); walk/glance/October
    contracts unchanged. Cat + host-surface goldens regenerated.
  * **"Karl Klammer" → "Karl Kleiderbügel"** app-wide: classes, files,
    test keys, l10n strings (de/en) and the persisted prefs key
    `easter_eggs.karl_klammer` → `easter_eggs.karl_kleiderbuegel` with a
    one-time value migration. The figure is redrawn from the approved
    user-drawn hanger SVG (wire twist, inner strut, glint lines,
    expressive face); the SVG's `feDropShadow` is rebuilt Flutter-natively
    (`MaskFilter.blur`). Settings row icon → `Icons.checkroom`.
  * Historical references (archived OpenSpec change id
    `add-karl-klammer-easter-egg`, issue titles) keep the old name.

- **Version bump:** `0.4.0-alpha.25+76 → 0.4.0-alpha.26+77` — the
  2026-10-14 test-session fixes, four issues in one change chain:
  * issue #672: the "KI-Import-Aufträge" list gets its own account-drawer
    entry (`profile-ai-imports`) between Einstellungen and Abmelden,
    pushing the jobs screen via the destination-navigator seam under the
    named route `ai-import-jobs` (the apply outcome's `popUntil` target);
    the redundant Settings entry was REMOVED (the jobs list is
    operational, not a setting — Settings keeps the AI-configuration
    entry). New ARB key `commonAiImportJobs`; `settingsAiImports` /
    `settingsAiImportsSubtitle` removed; drawer + settings goldens
    regenerated.
  * issue #668 (L2): `SceneTile` renders the scene NUMBER as the title
    with a truncated excerpt below it (first sentence + `…`, no
    mid-sentence hard cut; `null`/empty summary → no excerpt row) — a
    long summary no longer renders as one giant ellipsized line. The full
    summary stays in the scene detail screen. Scenes goldens regenerated.
  * issue #669: the disabled "Auf Drehtag planen" button explains itself
    when the episode has no shooting days (fresh script imports create
    none by design): inline hint + "Drehtag anlegen" quick-create
    affordance opening the existing `CreateShootingDaySheet`, sourced
    from the parent `EpisodeView` the user navigated from (no second
    projection lookup). `SceneDetailScreen` carries the episode DTO at
    all three push sites. New ARB keys `sceneDetailNoDayCandidatesHint` /
    `sceneDetailCreateFirstDay`; scene-detail golden regenerated.
  * issue #667: scope pills split across TWO rows per the agreed #638
    design (row 1 profile + Season + Block, row 2 the Episode chip, which
    collapses with its chip); the offline pill's degraded path is now
    reachable at cold start — the first passive carrier event runs the
    single HTTP confirmation probe (previously only re-connections
    probed, so "Wi-Fi on, backend unreachable" stayed silently online).

- **Version bump:** `0.4.0-alpha.21+72 → 0.4.0-alpha.22+73` — backend
  crate versions on the About screen (issue #656): the backend's new
  `GET /v1/meta/versions` route is exposed
  through the regenerated Dart client (`MetaVersionsResponse`,
  `getMetaVersions`) and rendered by `AppInfoScreen` as a new
  `info-backend-versions` tile (`api x · core y · infra z`) — fetched via
  the new `MetaRepository` (`Result` discipline, no throw in `data/`) and
  the `metaVersions` riverpod provider; loading and error states degrade
  gracefully (riverpod 3 surfaces failed fetches as an `AsyncLoading`
  state carrying `hasError` — the tile shows the honest localized error
  copy, never a crash). New ARB keys `infoBackendVersions` /
  `infoBackendVersionsSubtitle` / `infoBackendVersionsError`; repository
  Ok/Err unit tests and widget tests for the data/error/loading states;
  About-screen goldens regenerated.

- **Version bump:** `0.4.0-alpha.19+70 → 0.4.0-alpha.20+71` — persistent
  AI-imports entry in the Settings AI section (issue #644): a dedicated,
  always-present "KI" section groups the AI-configuration entry (#643,
  role gate unchanged) with a new unconditional "KI-Import-Aufträge" tile
  that pushes the existing `AiImportJobsScreen` under the named route
  `ai-import-jobs` — the apply outcome's "back to imports" `popUntil`
  contract keeps resolving from any entry, and the jobs list is reachable
  even when zero jobs need attention (the production overview's
  conditional active-jobs row alone made it unreachable after every
  import succeeded). No new screen, no API surface, no command dispatch:
  the read-only route is ownership-scoped server-side and its fetch seam
  (`aiImportJobsFetch`) resolves the session before the call. New ARB
  keys `settingsAi` / `settingsAiImports` / `settingsAiImportsSubtitle`.
  Design docs updated first (glossary, `settings.md`,
  `ai-import-jobs.md`).

- **Version bump:** `0.4.0-alpha.18+69 → 0.4.0-alpha.19+70` — central
  AI-configuration entry on the Settings screen (issue #643): a role-gated
  tile in the general section pushes the existing `AiConfigScreen`, so the
  AI provider/model configuration is reachable without starting an import.
  The entry mirrors the backend's `has_active_credential_role` gate through
  the existing D2/D3 resolution chain (sticky active-block scope →
  `currentMembershipProvider` → `hasActiveCostumeRoleInSeason`); an
  unresolved role renders no tile (D3: hide, never deny), denial on the
  screen itself stays the localized 403 narrative (documented D4
  exception). New ARB keys `settingsAiConfig` /
  `settingsAiConfigSubtitle`. Design docs updated first (glossary,
  `settings.md`).
- **Version bump:** `0.4.0-alpha.17+68 → 0.4.0-alpha.18+69` — surface the
  Deja-vu Cat beyond the sub-second splash (issue #640): the cat now also
  crosses the Seasons home empty state (same overlay as the splash —
  October gate, per-egg switch and "remove animations" preserved), and a
  „Vorschau" gallery in Settings renders each egg's figure regardless of
  month (bypassing only the October gate, never the per-egg switch). New
  ARB keys `settingsEasterEggsPreview` / `settingsEasterEggsPreviewSubtitle`;
  déjà-vu cat subtitle updated. Design docs updated first (glossary,
  `settings.md`, `seasons-home.md`).
- **Version bump:** `0.4.0-alpha.15+66 → 0.4.0-alpha.16+67` — regenerate the
  vendored `breakdown_api` client for the backend contract change of issue
  #637 (backend PR #646): the new `GET /v1/health` (`HealthReport`,
  `HealthEntry`, `HealthStatus`) and the additive `AiImportJob.next_attempt_at`
  / `attempts` fields plus the `AiImportAttempt` model. Purely generated
  (`vendor/breakdown_api/**`, excluded from coverage); no hand-written Dart
  consumes the new types yet, so no UI change.

- **Version bump:** `0.4.0-alpha.14+65 → 0.4.0-alpha.15+66` — the shell's
  **sticky top bar** redesign (issue #638, OpenSpec change
  `638-shell-top-bar-redesign`). The bar is now a shell-owned two-row
  surface inset below the system status bar (`SafeArea`) in all three
  morphologies (compact bottom nav / medium rail / expanded drawer), so no
  content renders under the Android status bar any more. Row 1 carries the
  profile affordance (left-most) and the three scope pills; row 2 carries
  the active destination's title, the hierarchy breadcrumb and the search
  affordance — the destination roots no longer own app bars (the Cast
  view's costume-category and fundus actions moved into its own toolbar,
  keeping their navigator target). The Season/Block/Episode chips became
  fully rounded, prerequisite-aware pills (season always visible; block once
  a season is active; episode once a block is scoped) whose set levels are
  filled with their own M3 container color (primary/secondary/tertiary
  container), with a neutral "… wählen" arm that opens the level's picker.
  New de/en keys `scopeChipSeasonUnset`, `scopeChipBlockUnset`,
  `scopeChipBlockUnsetTooltip`, `episodeChipUnset`,
  `episodeChipUnsetTooltip`. No `backend/openapi.yaml` change and no
  vendor-client regeneration.

- **Version bump:** `0.4.0-alpha.13+64 → 0.4.0-alpha.14+65` — the
  cross-season costume **fundus** browse surface (issue #625, OpenSpec
  change `flutter-fundus-search`): a SEPARATE, project-scoped surface
  (deliberately NOT a fifth OmniSearch chip — the four-chip /
  active-season-scoped contract is untouched), fed by the existing
  `GET /v1/costumes?project_id=` route into a new project-scoped Drift
  slice (`fundus_costume_cache_rows`, schema **v14**, additive
  `createTable`; probe `test/data/cache/fundus_migration_test.dart`).
  Season filter chips + a dictionary-folded name prefilter over the pinned
  costume fields (notes + category name), rows annotated with their
  repertoire season names, and deep links into the existing costume detail
  screen scoped to a project-resident repertoire season. No
  `backend/openapi.yaml` change and no vendor-client regeneration (the
  project-scoped route was already generated). Play `versionCode` `+N`
  stays strictly monotonic.

- **Version bump:** `0.4.0-alpha.6+57 → 0.4.0-alpha.7+58` — the
  `SeriesId` → `ProjectId` rename completed its wire/storage layer
  (issue #599, ADR-035 D1/S1 layer 3, completing issue #591). The
  generated client's `seriesId` accessors become `projectId` (vendor
  tree regenerated from `backend/openapi.yaml` — no hand edits), and
  every call site, DAO, cache row and test follows: the Drift mirror
  columns `season_cache_rows`/`block_cache_rows`/`episode_cache_rows`/
  `ai_import_job_cache_rows` are now `project_id` (schema **v13**,
  additive `ADD COLUMN` — the cache policy forbids destructive
  migrations and the cache is snapshot-replace, so a v12 install keeps
  its orphaned `series_id` and gains `project_id`; probe
  `test/data/cache/project_id_migration_test.dart`). The build-time
  pre-fill define is now `DEFAULT_PROJECT_ID` (was `DEFAULT_SERIES_ID`,
  same value — an opaque UUID), updated in `app_config.dart`, the
  de/en ARB copy and `scripts/dev/build-test-apk.sh`. The
  build-misconfiguration notice keeps its localized key
  (`seasonsCreateSeriesIdMissing`) — a diagnostic string, not the
  container's wire spelling. No `/v2` path version was cut: nothing had
  been released against `/v1`, so the rename landed in place.

- **Version bump:** `0.4.0-alpha.4+55 → 0.4.0-alpha.5+56` — costume
  season-repertoire management on the costume detail panel (issue #534,
  PR #595): vendor client reload (`addCostumeToSeason`/
  `removeCostumeFromSeason`, `CostumeView.seasonIds`), repertoire
  section, Drift cache column `season_ids_json` (schema v12), ARB copy
  de/en, widget tests + regenerated detail golden. Play `versionCode`
  `+N` stays strictly monotonic.

- **Version bump:** `0.3.0+51 → 0.4.0-alpha.1+52` — opening of the
  0.4.0 alpha line for the multi-episode AI script import backend
  (issue #581 backend in PR #584). Same convention as the pre-0.3.x
  alphas: the pre-release suffix marks the channel, the Play
  `versionCode` `+N` stays strictly monotonic.

## [0.3.0] – Released 2026-10-04

Stable release of the 0.3.0 alpha line (`0.3.0-alpha.1` →
`0.3.0-alpha.40`). The entries below cover everything since the first
published alpha.

- **Version bump:** `0.3.0-alpha.40+50 → 0.3.0+51` (stable graduation of
  the alpha line; the Play `versionCode` `+N` stays strictly monotonic).

### Fixed

- **AI-import apply: the episode picker live-fetches the JOB'S BLOCK
  episodes** (found while testing issue #581 on device): the picker read
  ONLY the local Drift cache, so a fresh install (or any episode the user
  had not visited before) rendered an empty/unassignable list — the target
  episode could not be picked and apply stayed disabled. The picker now
  scopes a live `GET /v1/episodes?block_id=…` through the shared
  `episodesListFetchProvider` seam, keyed on the cached job row's
  `block_id` (the same identity-scoped read discipline as `aiJobContext`).
  Offline-first fallback chain: fetch failure + cached block rows → cached
  rows (never an empty list while stale rows exist); failure + empty cache
  → the error branch; job without a `block_id` → the previous cache-wide
  read. Copy de-"cached"-ed (en/de) and regenerated.
- **Apply outcome no longer abandons the import flow:** the
  `ai-apply-open-episode` button popped to the app start, stranding the
  user away from the import surface. It now pops to the named
  `ai-import-jobs` route when the jobs screen is on the stack (the
  standard entry — review the job or start the next import); only a
  preview reached without the jobs screen falls back to the app start.
- **Version bump:** `0.3.0-alpha.39+49 → 0.3.0-alpha.40+50` (pre-release
  increment per merged-PR practice on the alpha line; `+N` stays strictly
  monotonic for the Play `versionCode`).

### Added
- **AI-import jobs view (issue #547):** a started import job is no longer
  lost once the status screen is left — the previously-unused
  `GET /v1/ai-import/jobs` wiring finally gets its production call site.
  New `AiImportJobsViewController` + `aiImportJobsView` selector (the
  seasons/blocks seam shape: identity-scoped cache-first paint, then
  server-authoritative revalidation via `listJobsAndCache()`, retained
  snapshot on error, `Result`-typed, code-keyed copy — and NO watch: the
  single foreground job watch stays owned by `AiJobStatusScreen`, pinned
  by a watch-counter test). The new `AiImportJobsScreen` renders
  newest-first rows (kind + date + one of the six honest status copies
  including `dead_letter`/`payload_unavailable` — previously unreachable
  after leaving the status screen — plus the `failed` retry budget and a
  `last_error` presence indicator); tapping a row pushes the status
  screen; pull-to-refresh re-runs exactly the list route. The Planen tab
  gains an active-jobs summary row (visible while any known job needs
  attention) that opens the list without arming a watch. The #547 `jobIds`
  fast path is wired (user-approved decision): the submit controller
  remembers the acked job id via `rememberJob`, and the jobs controller
  prunes remembered ids the authoritative list no longer returns via
  `forgetJob` — both previously zero-caller seams, now with tests.
  New ARB keys (`aiJobs*`, `planningActiveJobRow`, de/en parity), screen
  spec `docs/design/screens/ai-import-jobs.md` + glossary rows, four new
  goldens ({light,dark}×{android,macos}), and the tier-1/tier-2 test set
  (cache-then-revalidate ordering, no-watch D5 assertion, seed merge,
  reconciliation, status matrix, navigation, empty/error/stale states).
- **Version bump:** `0.3.0-alpha.32+42 → 0.3.0-alpha.33+43` (pre-release
  increment per merged-PR practice on the alpha line; `+N` stays strictly
  monotonic for the Play `versionCode`).
- **Costume detail inline editor (issue #545):** the `＋ Detail
  hinzufügen` row and a per-row edit action open the SAME inline editor
  (`_DetailEditor`) expanded in the row — no `showDialog` form any more, so
  the keyboard cannot collide with a modal and the scroll context survives.
  One widget serves create and edit mode (`initial: CostumeDetailView?`);
  edit dispatches the #544 `updateDetail` with the existing detail id (no
  placeholder path, issue #472 cannot recur), and a per-row delete action
  asks through a confirmation dialog before dispatching `removeDetail`
  (destructive glossary rule `common.delete`: always with confirm dialog).
  Required-field affordances: `text` is marked with a `*` label suffix and
  a required-mark helper, `subject` carries the symmetric `(optional)`
  helper, validation runs on first user interaction
  (`AutovalidateMode.onUserInteraction`), and the save button stays
  disabled while `text.trim()` is empty (no submit-only error). Failed
  commands surface via the command-error banner (no silent discard);
  version fences come from the shared `_resolveVersion` ack chain. A new
  open-editor golden (`costume_detail_editor_open`) locks the layout;
  the 4 collapsed-state screen goldens render unchanged. The stale
  `_PhotosSection._detail` doc comment (list rows "carry no child
  collections") is corrected to the real contract: the batch-enriched
  list route carries details/photos since the #543/#544 backend tranche;
  the single-costume fetch exists to refresh the possibly-optimistic
  rendered row.
- **Version bump:** `0.3.0-alpha.31+41 → 0.3.0-alpha.32+42` (pre-release
  increment per merged-PR practice on the alpha line; `+N` stays strictly
  monotonic for the Play `versionCode`).

- **Costume detail edit + delete (issue #544):** a costume detail can finally
  be changed and removed — until now it was add-only, so a typo in the
  `Betreff` was permanent. New `CostumesController.updateDetail` /
  `removeDetail` (plus the matching `CostumeRepository` methods) dispatch
  `PATCH` / `DELETE /v1/costumes/{id}/details/{detail_id}`. Both check the
  `assign_costumes` capability BEFORE any network call (403, localized,
  zero requests — provable by the request counters), then echo the freshest
  aggregate version, swap the entry into the acknowledged overlay, and let
  the bounded reconcile confirm it against the projection. `updateDetail`
  sends the FULL detail so a cleared `subject` reaches the server as an
  explicit `null` rather than silently keeping the old value, and reuses
  the existing wire id — issue #472's `'pending'` placeholder has no path
  here. A 404 `costume-detail.not-found` (the detail was already gone
  server-side) gets its own localized narrative keyed on the stable problem
  code instead of the generic "costume could not be saved" fallback. The
  row actions and inline editor that drive these methods land in issue #545.
  A `costume-detail.not-found` 404 additionally triggers a bounded
  reconcile, so the "the list was refreshed" narrative in the banner is
  backed by an actual refetch; every other error is left alone so a 409
  or a transport failure still surfaces the real cause.
- **Costume category picker (issue #543):** one costume = one category on
  the client — the costume editor's identity section shows the costume's
  category (icon + always-visible text, "Ohne Kategorie" fallback); the
  bottom-sheet picker lists the season's non-archived projected vocabulary
  with an icon per option plus the deliberate "Ohne Kategorie" clear row.
  New `CostumesController.setCategory` dispatches the costume-level
  `POST /v1/costumes/{id}/category` command behind the `assign_costumes`
  AUTHZ-GATE (membership check before any network call, provable
  request-counter denial), echoes the freshest aggregate version
  (freshness fence), applies the optimistic-after-2xx overlay on the row,
  and reconciles bounded. New problem narratives for 409
  `costume-category.season-mismatch` and `costume-category.archived`
  (never backend `detail` text). Design docs carried along:
  `docs/design/screens/costumes.md` (category row + picker in the editor
  Salt layout, components, interactions, validation) and the glossary's
  `categories.icon` "every category display shows the icon next to the
  text" rule extended to the picker. Six new widget tests (set with
  version echo, archived hidden + clear row, authz denial with zero
  requests, cross-command version freshness, season-mismatch narrative,
  idempotent clear no-op); the 4 screen goldens re-verified unchanged.
- **Version bump:** `0.3.0-alpha.28+38 → 0.3.0-alpha.29+39` (pre-release
  increment per merged-PR practice on the alpha line; `+N` stays strictly
  monotonic for the Play `versionCode`).
- **Version bump:** `0.3.0-alpha.27+37 → 0.3.0-alpha.28+38` (pre-release
  increment per merged-PR practice on the alpha line; `+N` stays strictly
  monotonic for the Play `versionCode`).
- **Version bump:** `0.3.0-alpha.26+36 → 0.3.0-alpha.27+37` (pre-release
  increment per merged-PR practice on the alpha line; `+N` stays strictly
  monotonic for the Play `versionCode`).
- **AI-import usability:** Script is now the default import kind and schedules
  are file-only (CSV/PDF); configured AI-imports can change assistant and
  image-model selections while the configured provider remains available for
  safe replacement; empty stored prompts fall back to the backend defaults in an editable
  XML-highlighted editor (issues #508, #509, #520).
- **AI-import provider replacement:** configured imports can switch providers
  with a safe two-phase credential hand-off. Previously entered provider
  credentials are retained as opaque references, so switching back does not
  require re-entering the API key. The server refuses to persist a vault key
  that is not an active credential of the selected provider, and the mismatch
  is reported with its own localized copy (issue #528).
- **Version bump:** `0.3.0-alpha.22+32 → 0.3.0-alpha.23+33` (pre-release
  increment per merged-PR practice on the alpha line; `+N` stays strictly
  monotonic for the Play `versionCode`).
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

- **Scene detail could contradict itself on duplicated read-model ids
  (issue #550, defensive):** the backend scene queries fanned out over the
  character × shooting-day pivots, so `assignedCharacters` /
  `shootingDayIds` arrived with one duplicate element per multiplied row —
  the header counted “Drehtage (2)” for one day while the set-based picker
  filter found no candidate and kept the schedule button permanently
  disabled. The origin is fixed backend-side (correlated subqueries, PR
  #553); the client now additionally dedups both id lists where counts and
  rows render (scene detail sections + scene tile counts), so a future
  read-model regression degrades gracefully instead of producing a
  self-contradictory screen. Widget tests pin the invariant.
- **AI import unusable on device — quoted job id broke every follow-up
  call:** the upload acknowledgement (`POST /v1/ai-import/{scripts,schedules}`)
  is a JSON *string* literal, wire body `"<uuid>"`, and dio's default
  transformer hands that raw literal through for a `post<String>` call — the
  generic type is a static cast only and never drives the decode. The quotes
  therefore survived into the next path segment
  (`/v1/ai-import/jobs/%22<uuid>%22`), the backend's `Path<AiImportJobId>`
  extractor rejected it, and every status poll, preview and apply failed with
  `400 http.bad-path-param` — the import could be submitted but never
  advanced. `AiImportRepository._upload` now decodes the JSON literal
  explicitly (fail-closed: a body that starts a JSON string but does not parse
  as one reports `ai_import.dto_invalid` instead of sending a malformed id).
  The unit harness previously injected an *unquoted* id and thereby encoded
  the wrong assumption, which is why this survived the suite; the regression
  tests now use the real wire format for both upload routes.
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
