<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# 548 — `PlanningLocation` + hierarchy context strip + visible scope chip

## Why

The user cannot see **which season, block, or episode** they are navigating
in, and the **active block scope that silently filters every `BlockMember`
request is invisible**. The ancestor DTO chain is broken at every level
(each screen receives only its direct parent), and `ActiveScope` — attached
to every request as `X-Active-Block`, `keepAlive`, persisted across cold
starts — is shown exactly once, by `BlockScopePickerScaffold`, and never
again. A user can be looking at a costume list filtered to one block with no
indication a filter exists: a data-correctness trap, not a navigation
polish item.

The screen-spec template also has no slot for a context surface — adding
`## Location & Context` is a prerequisite of this change, not a follow-up.

## Decision

Three separable pieces, one shared contract:

1. **`PlanningLocation`** (`lib/features/shell/planning_location.dart`) — a
   plain `const` **sealed ladder** (deliberately not freezed, not a wire
   DTO): `season → block → episode → scene`, each step requiring the
   previous one so a non-contiguous chain is a compile error. Holds the
   ancestor read DTOs it was built from (CQRS boundary: zero extra reads)
   and derives labels in one place.
2. **`RouteSettings.arguments` as the transport** — every hierarchy push
   site passes the deepened location; the strip resolves it from the
   topmost route of the active tab's nested navigator via
   `locationOf(NavigatorState)` (pure function). Pop is free; tab switches
   are free (each tab has its own navigator + `LocationRouteObserver`);
   no shell state to keep in sync. `ShellController.location` + explicit
   pop-path clearing is recorded as **rejected** (it reintroduces exactly
   the drift this change fixes).
3. **The strip lives in the shell** (`lib/features/shell/location_strip.dart`
   + `ShellContextBar` in `app_shell.dart`), not in each screen's app bar —
   only the shell tests/goldens are touched; the ~60 per-feature goldens
   pump their screens directly and stay untouched.

`ActiveScopeChip` (`lib/features/shell/active_scope_chip.dart`) is a
**separate** widget next to the strip: the strip says *where you navigated*
(per-route), the chip says *what filters your requests* (sticky, persists
across seasons and cold starts). Prerequisite: `ActiveScope` is extended
with the picked block's `blockNumber` (from the acted-on `BlockView`,
locale-neutral — the chip renders `blockTileLabel(number)`); the store
migrates from `Map<seasonId, blockId>` to a typed document that accepts
**both** shapes, degrading label-less scopes to "unknown" and re-resolving
once cache-only from `blockRepository.readCached` (never a network fetch).

## Spec delta

`MODIFIED` on `openspec/specs/flutter-hierarchy-navigation` →
`Requirement: Hierarchy Navigation Spine`: "the parent read DTO" becomes
"the full ancestor chain as an immutable `PlanningLocation`", the visible
strip and scope chip become required surfaces, season-direct screens take
the season level only, and the Back-navigation scenario becomes strip-
assertable.

## Non-goals

- No deep links / URL routing.
- No tab-history back (D3).
- No tap-to-jump-up on strip segments (follow-up; the scope chip is the one
  actionable segment because it opens a picker, not a navigation).
- No change to what the scope filters (server-side `X-Active-Block`
  middleware unchanged).

## Effects

- New: `planning_location.dart`, `location_strip.dart`,
  `active_scope_chip.dart` (+ tests, l10n keys, goldens).
- Modified: `active_block.dart` (scope label), `active_block_store.dart`
  (document shape v2, both-shapes read), `active_block_gate.dart`
  (restore carries the block number), `app_shell.dart` (context bar), all
  hierarchy push sites, `docs/design/screens/README.md`,
  `docs/design/glossary.md`, ARB catalogs (de/en parity).
- 6 shell goldens may regenerate; per-feature goldens untouched.
