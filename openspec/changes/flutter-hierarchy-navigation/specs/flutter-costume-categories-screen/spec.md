<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-costume-categories-screen Specification (delta)

## ADDED Requirements

### Requirement: Season-Scoped Costume-Category List
A costume-categories screen (entered from the season context) SHALL list
`CostumeCategoryView` rows for the season ordered ascending by
`order_key`, via the Result-typed repository with the Drift cache
discipline of the hierarchy screens (TTL staleness, snapshot replace on
success, cache untouched on failure). Archived categories SHALL be hidden
behind an explicit toggle, never silently unlisted without that toggle.

#### Scenario: Listing categories
- **WHEN** the user opens the categories screen for a season with
  categories.
- **THEN** rows render ordered by `order_key`; the archived toggle is
  visible and off by default.

#### Scenario: Empty season vocabulary
- **WHEN** the season has no categories.
- **THEN** a plain-language empty state with the create affordance
  (session-gated) renders.

### Requirement: Create With Client-Derived Append Order Key
Creating a category SHALL POST `CreateCostumeCategoryRequest` whose
`order_key` is derived from the same season projection's existing keys
(append-after-last over the fixed printable-ASCII alphabet `!`..`~`,
growing length on last-position overflow; `!` for an empty list) —
never from a parallel client-side ordering scheme. The optimistic
overlay and bounded-retry reconciliation SHALL follow the shared screen
pattern.

#### Scenario: First and subsequent creates
- **WHEN** the user creates a category in an empty list, then a second
  one.
- **THEN** the first POST carries order key `!` and the next carries the
  appended successor of the last displayed key; the list order after
  reconciliation matches server `order_key ASC`.

#### Scenario: Order-key derivation edge
- **WHEN** the last existing key ends in `~` (last alphabet position).
- **THEN** the derived key grows in length (append-position rule); the
  pure derivation function is unit-tested for both edge cases.

### Requirement: Rename With Version Echo and Archive
Renaming SHALL PATCH `UpdateCostumeCategoryRequest` echoing the `version`
of the specific read row the user acted on; a 409 SHALL surface
"changed elsewhere — refresh" copy keyed on `code` and MUST NOT
silently overwrite. Archiving SHALL invoke `POST …/archive`; success
marks the row archived in local state (optimistic, reconciled by the
bounded-refetch pattern), and the archived toggle reveals it.

#### Scenario: Rename succeeds
- **WHEN** the user renames a category and the PATCH returns a new
  aggregate version.
- **THEN** the row shows the new name after reconciliation or the
  optimistic update, keyed by the projected row id.

#### Scenario: Rename hits optimistic-locking conflict
- **WHEN** another client renamed the category first (PATCH → 409).
- **THEN** the copy explains the stale view and offers refresh; the
  client does not retry the write with a bumped version on its own.

#### Scenario: Auth-gate before commands
- **WHEN** any create/rename/archive command dispatches without a
  resolved authenticated session.
- **THEN** the client denies before the network call (`// AUTHZ-GATE:`
  annotated, `authz.denied` copy) — the same session gate as the other
  hierarchy commands.
