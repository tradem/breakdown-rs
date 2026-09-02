<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Design: Hierarchy Navigation

## 1. Grounding

Backend contract facts (from the checked-in `backend/openapi.yaml` and
`backend/crates/api/src/handlers/mod.rs`, which win on server-owned
concerns):

- `GET /v1/blocks?season_id=…` → `List<BlockView>`; `POST /v1/blocks`
  (`CreateBlockRequest`, required `series_id` + `season_id` + `number`)
  → 201 `IdVersionResponse`.
- `GET /v1/episodes?season_id=…` → `List<EpisodeView>` — **no
  `block_id` filter exists** (D3, backend issue #335);
  `EpisodeView.block_id` carries the
  grouping key. `POST /v1/episodes` requires `series_id` + `block_id` +
  `number`.
- `GET /v1/scenes?episode_id=…` → `List<SceneView>`; `POST /v1/scenes`
  requires `episode_id` + `details` (`SceneDetails`); the read model
  carries `mood`, `location`, `summary`, `script_day`,
  `is_schedule_set`, `assigned_characters`, `shooting_day_ids`.
- `GET /v1/seasons/{season_id}/costume-categories` → `List<CostumeCategoryView>`
  (id, name, `order_key`, archived, version, updated_at);
  `POST …/costume-categories` (`CreateCostumeCategoryRequest`:
  `season_id`, `name`, `order_key`) → 201 `IdVersionResponse`;
  `PATCH /v1/costume-categories/{id}` (`UpdateCostumeCategoryRequest`:
  `version` + optional name/order_key) → `AggregateVersion`;
  `POST /v1/costume-categories/{id}/archive` → 204/409.
- `GET /v1/seasons/{id}/membership` → `SeasonMembershipDto`
  (`season_id`, `has_active_costume_role_in_season`, `capabilities` —
  v1 values derived server-side: `upload_continuity_photos`,
  `assign_costumes`).
- Create handlers are `CurrentUser`-gated (auth-only), mirroring
  `create_season`.
- Every create/patch takes ids and `series_id` from caller-supplied
  payload; the client sources them from the read DTO the user navigated
  from (CQRS-boundary rule: no second projection lookup to "fill in"
  command context).

## 2. Screen architecture (per the seasons reference)

One feature folder per aggregate boundary; inside each:

```
features/<aggregate>/
├── <aggregate>s_screen.dart      # ConsumerWidget container; asyncValue.when
├── <aggregate>s_controller.dart  # @riverpod family (keyed by parent id)
├── <aggregate>s_state.dart       # projected AsyncValue + overlays + error
└── widgets/                      # pure presentation, no Riverpod imports
```

- **Controllers:** `blocksControllerProvider(seasonId)`,
  `episodesControllerProvider(blockId)` (with the season id for the
  fetch scope, see D3), `scenesControllerProvider(episodeId)`,
  `costumeCategoriesControllerProvider(seasonId)`. State mirrors
  `SeasonsScreenState`: `projected` (`AsyncValue`), `cachedRows`,
  `isStale`, `overlays`, `commandError`.
- **Repositories** (`data/block_repository.dart`, …): wrap the generated
  client (`Result`, never throws), own the Drift write path: success
  upserts inside one transaction (snapshot-replace for lists, per the
  `flutter-offline-scope` requirements), failure leaves the cache
  untouched. Cache tables: `blocks`, `episodes`, `scenes`,
  `costume_categories` — one Drift migration adding all four.
- **Reads:** screens read through the cache view (seeded local rows →
  network refresh), exactly as the seasons screen does — last-seen state
  on cold start, brief-connectivity read-only survival.

## 3. Reconciliation extraction (D2)

`lib/domain/reconciliation/` gets, extracted from
`features/seasons/seasons_controller.dart` with behavior parity:

- `ReconciliationScheduler` + `ExponentialBackoffScheduler` (move;
  the provider becomes shared),
- generic `OverlayBookkeeping` mixin (add / markReconciling / dropProjected
  / markAllStale) for `OverlayEntry<Id, DisplayFields>` rows,
- the single-flight + acknowledgement-generation reconcile runner,
  parameterized by a projection fetch callback.

Rules preserved: overlay only after 2xx; controller state only (never
Drift); bounded retries (4 attempts, injectable scheduler — tests stay
deterministic); exhaustion retains the overlay with a stale indicator +
pull-to-refresh; late acknowledgements during a pass get a follow-up
pass. The seasons screen migrates onto the shared module in the same
change; seasons goldens must be byte-stable (proof of parity).

## 4. Navigation & adaptive UX (D1)

- Season row tap → `Navigator.push(BlocksScreen(season))`; block row →
  `EpisodesScreen(block)`; episode row → `ScenesScreen(episode)`;
  category action opens from the season screen's toolbar (a
  `costume_categories` entry point on the blocks screen toolbar — the
  categories are season-scoped siblings of blocks, not children of
  blocks).
- Up/back: Android system back and macOS mouse-back both pop via the
  default `Navigator`; `AppBar` back implies the parent.
- **Android (compact):** `ListView` cards, 48 dp targets,
  pull-to-refresh (`RefreshIndicator`), FAB for create (bottom-right).
- **macOS (compact/expanded width):** same pushed pages; wider content
  gutter via `token`-based margins; macOS pointer affordances (hover on
  the equivalents, focus traversal over rows, Escape closes sheets);
  the create form opens as a centered dialog (side-sheet width cap
  480 dp) instead of a FAB. No `NavigationRail` is introduced — the
  hierarchy is depth-first, not parallel-top-level; a rail would invent
  navigation semantics before a routing change exists (documented;
  revisit with declarative routing).
- All screens use `Theme.of(context)` roles + `lib/design` tokens; no
  hardcoded colors/spacing/typography. Goldens: light + dark AND
  `TargetPlatform.android` + `TargetPlatform.macOS` variants
  (4 variants per non-trivial surface).
- Accessibility: semantic row labels (title + subtitle via `Semantics`
  on the merged row), `find.text`-paired widget tests, no `byType`-only
  assertions.

## 5. Membership read (D6)

`lib/auth/season_membership_provider.dart`:

```
@riverpod Future<Result<SeasonMembershipDto>> seasonMembership(ref, seasonId)
```

- Strict capability parsing: an unknown capability string rejects the
  DTO (`Err(ProblemError code: 'authz.membership.capability_unknown')`)
  — the client never guesses policy (the handshake rule for Phase 2+) .
- Not keepAlive; TTL-cache alongside the season rows so the chip does not
  refetch on every navigation; pull-to-refresh refreshes it too.
- UI: a `capabilities` chip / "no role in this season" chip on the
  BlocksScreen `AppBar` (season context) — display-only in Phase 1
  (the v1 vector contains only Phase-2 capabilities today).

## 6. Costume categories specifics (D4)

- List ordered by `order_key` ascending (server semantics `ORDER BY
  order_key ASC` — the client never re-sorts beyond presentation of the
  same key).
- **Next-order-key derivation** (pure function, unit-tested): append
  after the last current key — successor of the last key's final byte
  over the fixed printable-ASCII alphabet `!`..`~` (byte 33..=126);
  overflow of the last position grows the key length (`~` → `!!`);
  empty list → `!`. Documented honesty note: the server-side
  `LexicalSortKey::midpoint` semantic is not replicated — insertion is
  append-only, which is order-preserving by construction; full
  reordering is a non-goal.
- Rename: `PATCH` with the `version` echoed from the read row; 409
  surfaces "changed elsewhere — refresh" copy keyed on `code`.
- Archive: 204 → optimistic remove from the local rows (overlay-less:
  the command result carries no id/version beyond the route id, so the
  row is marked archived optimistically and confirmed by refetch).
- Archived categories hidden by default with a toggle to reveal
  (no destructive dark pattern: nothing is silently discarded).

## 7. Failure states (encoded in specs)

- 404 on parent/row GET (deleted elsewhere) → typed 404 narrative +
  pop-back affordance (D5).
- Create: transport failure / 5xx → no overlay; 409/422 → no overlay,
  copy keyed on `code`; projector-lag overlay lifecycle as seasons.
- Empty states for every list ("No blocks yet", …) + the create CTA when
  the session gate allows.
- Projector-lag windows: `reconciling` overlay rows with the same
  spinner / stale warning text pattern as seasons.

## 8. Test plan (tiers)

- **Tier 1 unit:** repositories (Ok/Err; cache untouched on Err);
  episodes group-by-`block_id` mapper; next-order-key function
  (including overflow + empty); strict membership capability parser
  (unknown entry → Err); reconciliation runner with fake scheduler
  (attempt budget, exhaustion, late-ack follow-up) — parity tests
  against the seasons behavior.
- **Tier 2 widget + golden:** each screen — data, empty, error, stale,
  overlay states × {light, dark} × {android, macos}; 404 narrative;
  membership chip states; category toggle/rename/archive dialogs;
  goldens for every non-trivial surface.
- **Tier 3 Gherkin:** none — hierarchy navigation is not one of the
  designated critical flows; the default is widget tests
  (`flutter-gherkin-hybrid` policy).
- **Tier 4 integration:** on-emulator smoke against dev-auth backend:
  create season → block → episode → scene → category; verify each
  appears after projector lag (bounded polling ≤ the reconciliation
  budget), sign-out mid-navigation returns to the login gate.
- Determinism: fake clocks/schedulers only; no wall-clock budgets.
