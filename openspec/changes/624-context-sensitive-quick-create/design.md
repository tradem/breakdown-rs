<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

## Context

Issue #612 (PR #623) landed the shell plus FAB and the quick-create sheet as
a **data-driven** affordance list. Its v1 list is context-free on purpose
("keep v1 dumb"); the sheet comment explicitly names "new scene/day inside
Script/Schedule" as the later decision. Issue #624 is that decision.

Verified facts:

- The shell already resolves the active tab's topmost `PlanningLocation`
  (issue #548) — `EpisodeLocation` / `SceneLocation` carry a full
  `EpisodeView`. That is per-route context, not sticky.
- The shell tracks a **sticky** active-block scope (`activeBlockProvider`,
  issue #378) persisted per season (issue #382) and surfaced by
  `ActiveScopeChip`. There is no episode-level equivalent.
- Both create commands need only an `episode_id`: `POST /v1/scenes`
  (`CreateSceneRequest.episode_id`) and
  `POST /v1/episodes/{episode_id}/shooting-days`.
- The two create flows are modal bottom sheets (`showCreateSceneSheet`, a
  private `_CreateShootingDaySheet`); the other quick-create entries push
  full-screen routes.

## Goals / Non-Goals

**Goals**
- A sticky **active-episode scope** set by entering an episode's context and
  changeable via a top-bar episode chip, persisted per season.
- `shellQuickCreateActions` gains the two context-sensitive entries
  additively; with no scope the shipped list is byte-for-byte unchanged.
- The two entries push **full-screen** create pages.
- One form implementation per command, shared by the quick-create page and
  the existing in-context sheet.
- The existing auth-only client gate is preserved for every create path.

**Non-Goals**
- No backend or OpenAPI change. No new command, no new route on the wire.
- No change to the existing per-screen create FABs' presentation (they stay
  sheets/dialogs); only their form body is shared.
- No cross-episode or cross-season "create into another episode" flow — the
  scope is the acted-on context.
- No offline command queue (unchanged scope, AGENTS.md §8).

## Decisions

### D1 — Sticky active-episode scope mirrors the block scope

`ActiveEpisode` is a `@Riverpod(keepAlive: true)` notifier holding an
`ActiveEpisodeScope { seasonId, blockId, episodeId, episodeNumber,
episodeName }`. It mirrors `ActiveBlock` exactly: in-memory state updates
synchronously (call sites must observe it before navigating), persistence is
fire-and-forget through `ActiveEpisodeStore` (secure storage, per-season
document), and a store failure never breaks the in-memory scope.

*Why sticky and not route-derived:* the PO chose the sticky chip so an
episode can be pinned and a scene/day created from anywhere in the shell,
independent of where the current route happens to be. Route-derived context
disappears on pop; a pinned scope survives it.

*Why not reuse the block store:* the block document is keyed by season and
holds a bare block id (+ number). An episode needs its block id and its
number/name for the chip label. A separate key/document keeps the two
lifetimes independent (an episode scope can be set without changing the
block scope).

### D2 — Scope set sites

The scope is set from the acted-on `EpisodeView` at every episode-entry
point (CQRS boundary — never a second projection lookup):

1. `EpisodesScreen` row tap → `ScenesScreen`
2. `EpisodesScreen` episode shooting-days icon → `ShootingDaysScreen`
3. `ScriptTabScreen` scene row → `SceneDetailScreen` (the row carries its
   episode)
4. `ScheduleTabScreen` day row → `ShootingDaysScreen`

Each site sets the scope **before** the push (synchronous), the same
discipline `BlocksScreen` uses for the block scope. The chip's picker is the
manual override; it resolves the scope block's episodes through the existing
`episodesListFetchProvider(blockId, seasonId)` seam (read-only, TTL-cached).

### D3 — Additive entries, no `QuickCreateAction` change

The context entries are plain full-screen routes, exactly like AI import and
the wizard, so `QuickCreateAction`'s `routeBuilder` contract is unchanged.
`shellQuickCreateActions(AppLocalizations, {ActiveEpisodeScope? episode})`
returns the context-free list when `episode == null` and prepends the two
context entries when it is non-null. The sheet renders whatever list it is
handed — no branching in the sheet.

*Order:* context entries first (the immediate task), then the context-free
pair. The list stays data-driven; a future entry appends without touching the
sheet.

### D4 — Full-screen create pages, shared forms

`CreateSceneScreen({required String episodeId})` and
`CreateShootingDayScreen({required String episodeId})` are `ConsumerWidget`
scaffolds (AppBar title + shared form body + the command-error banner keyed
on the same `scenesCommandErrorProvider` / `shootingDaysCommandErrorProvider`
the list screens use). The form bodies are extracted into public widgets
`CreateSceneForm` / `CreateShootingDayForm`, each taking `episodeId`, and are
reused by the existing sheets. `ScenesController.create` changes its
`EpisodeView` parameter to a plain `episodeId` — the only field it ever read.

*Why full-screen:* PO decision; consistent with the other quick-create
entries; avoids the modal dialog the PO rejected. The existing FAB sheets
keep their presentation so the in-context flows and their goldens are
untouched beyond the shared form extraction.

### D5 — Episode chip in the shell context bar

`ActiveEpisodeChip` renders next to `SeasonScopeChip` / `ActiveScopeChip`:
visible label `Episode {n}` (name wins when set) with a glossary icon, a tap
opening the episode picker for the scope block. Hidden when no scope is set.
Foreign-season handling mirrors the block chip (a scope whose season differs
from the navigated season says so instead of pretending it applies).

## Risks / Trade-offs

- **Sign-out/backend-switch teardown** must cover the new store and provider
  (mirroring the block scope), otherwise an identity could inherit a
  previous session's episode. Handled in `sign_out.dart` at the same three
  seams the block scope uses.
- **Scope staleness**: a persisted episode may have been archived/deleted.
  The chip degrades to a visible label from the persisted number/name (no
  live refetch on a hot path); the create command itself fails with the
  server's problem `code`, which the create page surfaces. This matches the
  block chip's honest degradation.
- **Chip crowding**: the context bar now carries up to three chips plus the
  location strip. The episode chip hides when unset and the bar already
  wraps/hides per morphology; goldens cover compact and wide.

## Migration

No data migration. The episode store is a new, separate secure-storage key;
its absence reads as "no scope". The block document shape is untouched.
