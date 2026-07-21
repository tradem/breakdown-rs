# Design — enrich-scene-with-shooting-day

## Context & prior decisions

This change captures the conclusion of an explore-mode session. The locked
decisions that shape the design below:

1. **ShootingDay is an Episode-scoped aggregate** (not an embedded VO). Breakdown
   RS owns the Drehtag schedule; an AI extraction increment will later import
   Drehtags from call sheets, and manual creation/edits coexist with imports.
2. **Scene ↔ ShootingDay is many-to-many.** A scene may be filmed across multiple
   Drehtags (continuity revisits / pickups); a Drehtag films many scenes.
3. **Ordering uses a fractional lexicographic sort key** (`LexicalSortKey`) rather
   than an `i32` rank, so inserting a day between two existing ones emits exactly
   one event instead of renumbering siblings.
4. **Cross-aggregate references use soft-archive** as the standing rule. A
   ShootingDay cannot be hard-deleted while a Scene references it; it is
   archived instead.
5. **AI-import provenance is reserved in the event shape from day one**
   (`source`, `external_ref`). The AI feature is a later increment, but retrofitting
   these onto already-persisted events would be impossible, so the field exists now.
6. **Backward-deserialization is a non-issue**: the system is pre-production; old
   SierraDB streams may be discarded. New `Option` fields deserialize as `None`
   from older JSON regardless.

## Glossary

| Term | Meaning |
|---|---|
| Drehtag | A shoot day — a calendar unit on which one or more scenes are filmed |
| `order_key` | Opaque, lexicographically-sortable string; canonical Episode-internal ordering |
| `LexicalSortKey` | Shared VO wrapping the string with validation + comparison |
| Saga (projector-issues-commands) | An event subscriber that, on observing an upstream event, dispatches commands to one or more aggregates. Introduced as a pattern by the sibling change `categorize-costume-parts`; this change does not require it. |

## Module layout

```
crates/core/src/
├── shared.rs                          + ShootingDayId, LexicalSortKey
├── scene/
│   ├── events.rs        SceneDetails gains summary; +ShootingDayScheduled/Unscheduled
│   ├── commands.rs      CreateScene/UpdateSceneDetails carry summary; +ScheduleSceneOnShootingDay/UnscheduleSceneFromShootingDay
│   ├── aggregate.rs     state.shooting_day_ids: Vec<ShootingDayId>; apply the two new events
│   ├── views.rs         SceneView.summary; +shooting_day_ids
│   └── ports.rs         unchanged shape; ports already wired generically
└── shooting_day/                       (new)
    ├── mod.rs           pub re-exports
    ├── aggregate.rs     ShootingDayAggregate { id, episode_id, label, order_key, date, source, archived, version }
    ├── commands.rs      CreateShootingDay, RenameShootingDay, RescheduleShootingDay, ReorderShootingDay, ArchiveShootingDay
    ├── events.rs        ShootingDayCreated/Renamed/Rescheduled/Reordered/Archived + ShootingDaySource enum
    ├── views.rs         ShootingDayView { ... + scene_ids: Vec<Uuid> (denormalized via join) }
    ├── error.rs         ShootingDayError (incl. ArchivedCannotBeMutated, DuplicateOrderKey)
    └── ports.rs         ShootingDayCommands, ShootingDayRepository
```

## The `LexicalSortKey` Value Object

Lives in `core::shared` so the sibling `categorize-costume-parts` change can
reuse it for `CostumeCategory` ordering. **Whichever change lands first introduces
it; the second consumes it.** The two changes are otherwise independent.

```text
LexicalSortKey(String)
```

- **Validation**: non-empty; ASCII printable in a fixed alphabet
  (`!"#$%&'()*+,-./0-9:;<=>?@A-Z[\]^_\`a-z{|}~`); no whitespace; bounded length
  (e.g. ≤ 64 chars) to stop pathological growth.
- **Comparison**: Rust `String` / `[u8]` lexicographic byte comparison. ASCII-only
  alphabet guarantees byte-order == expected order.
- **Midpoint generation**: inserting between keys `a` and `b` produces a key
  strictly greater than `a` and strictly less than `b`. A simple implementation
  uses a base-62 or base-94 fractional alphabet and appends a midpoint character
  (e.g. between `"a"` and `"b"` → `"aV"` where `V` is the alphabet midpoint).
- **Degenerate compaction**: when two adjacent keys share a prefix down to the
  maximum length and no midpoint fits, a `ReorderShootingDay` command emits a
  compaction pass over the whole Episode's keys (rare; bounded by length cap).
- **Why fractional**: in ES every mutation is an immutable persisted event. `i32`
  ordering makes inserting day 3.5 between 3 and 4 require renumbering 4,5,6…
  emitting N events. Fractional keys emit exactly ONE. This is the decisive ES
  argument and the reason it wins over a naive `order: i32`.

## ShootingDay aggregate

### State

```text
ShootingDayAggregate {
    id: Uuid,
    episode_id: EpisodeId,
    label: Option<String>,
    order_key: LexicalSortKey,
    date: Option<NaiveDate>,
    source: ShootingDaySource,
    archived: bool,
    version: AggregateVersion,
}

enum ShootingDaySource {
    Manual,
    AiExtracted { document_id: Uuid, external_ref: Option<String>, confidence: f32 },
}
```

### Commands / Events

| Command | Event(s) | Notes |
|---|---|---|
| `CreateShootingDay { id, episode_id, label, order_key, date?, source }` | `ShootingDayCreated` | New stream. `order_key` validated. |
| `RenameShootingDay { id, label, version }` | `ShootingDayRenamed` | Free-text label only; `order_key` unaffected. |
| `RescheduleShootingDay { id, date, version }` | `ShootingDayRescheduled` | Changes `date`. `None` allowed (unscheduled). |
| `ReorderShootingDay { id, order_key, version }` | `ShootingDayReordered` | Single-key move; emits one event. |
| `ArchiveShootingDay { id, version }` | `ShootingDayArchived` | Soft delete. |
| *(no unarchive)* | — | Intentional: archive is one-way. A scene referencing an archived day keeps displaying it; pickers hide it. |

All mutation commands except `Create` reject with `ArchivedCannotBeMutated` when `archived` is `true`.

### Cross-aggregate integrity (Scene references)

A `ShootingDay` has no knowledge of which Scenes reference it (Scene owns the
collection). Hard-delete is therefore not offered at all: the only "removal" is
`ArchiveShootingDay`. The read model hides archived days from *picker* queries
(list-by-episode for scheduling) but keeps them resolvable on historical Scene
views. This is the project's **standing rule for cross-aggregate references**;
`sibling change categorize-costume-parts` applies the same rule to
`CostumeCategory`.

### Validation against read model

`ArchiveShootingDay` does **not** consult the Scene projection at command time
(archiving is always permitted — references survive). No read-model lookup is
required in the command path, which keeps the write side pure (`core` has no
projection dependency).

## Scene ↔ ShootingDay many-to-many

The Scene aggregate owns the link:

```text
SceneAggregate {
    ...,
    shooting_day_ids: Vec<ShootingDayId>,
}
```

| Command | Event | Notes |
|---|---|---|
| `ScheduleSceneOnShootingDay { id, shooting_day_id, version }` | `ShootingDayScheduled { id, shooting_day_id, version }` | Idempotent push. |
| `UnscheduleSceneFromShootingDay { id, shooting_day_id, version }` | `ShootingDayUnscheduled { id, shooting_day_id, version }` | Errors if not present. |

No existence check against the ShootingDay aggregate is performed in the Scene
command path (would violate aggregate isolation). The read model joins and may
show a "(missing)" badge for dangling references — though with soft-archive as
the only removal path, dangling references cannot occur in practice.

## Scene summary

Additive, low-risk:

```text
SceneDetails {
    scene_number: Option<u32>,
    location: Option<String>,
    mood: Option<String>,
    is_schedule_set: bool,
+   summary: Option<String>,
}
```

Flows through `SceneCreated` / `SceneDetailsUpdated`. `UpdateSceneDetails`
already derives `PartialEq` on `SceneDetails`, so the "details unchanged" guard
works unchanged. `SceneView` gains `summary: Option<String>`.

## Projection schema (migration)

```sql
ALTER TABLE projection_scene ADD COLUMN summary TEXT;

CREATE TABLE projection_shooting_day (
    id          UUID PRIMARY KEY,
    episode_id  UUID NOT NULL,
    label       TEXT,
    order_key   TEXT NOT NULL,
    date        DATE,
    source      JSONB NOT NULL,            -- {"Manual":null} | {"AiExtracted":{document_id,external_ref,confidence}}
    archived    BOOLEAN NOT NULL DEFAULT false,
    version     BIGINT NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_projection_shooting_day_episode_id
    ON projection_shooting_day(episode_id, order_key);

CREATE TABLE projection_scene_shooting_day (
    scene_id       UUID NOT NULL REFERENCES projection_scene(id) ON DELETE CASCADE,
    shooting_day_id UUID NOT NULL REFERENCES projection_shooting_day(id) ON DELETE CASCADE,
    version        BIGINT NOT NULL,
    PRIMARY KEY (scene_id, shooting_day_id)
);
CREATE INDEX idx_projection_scene_shooting_day_day
    ON projection_scene_shooting_day(shooting_day_id);
```

A projector on the `shooting_day` stream updates `projection_shooting_day`.
The existing scene projector handles `ShootingDayScheduled`/`Unscheduled` by
maintaining the join table.

List-by-episode queries use `ORDER BY order_key ASC` — the textual sort yields
the canonical order without numeric parsing.

## Projector & wiring

- New `PostgresProcessor` instance subscribed to the `shooting_day` SierraDB
  stream, mirroring the existing four projectors (`main.rs` spawns a fifth).
- The existing scene projector's event-handler arm gains two new cases for
  `ShootingDayScheduled` / `ShootingDayUnscheduled`.
- No new projector-supervision rules; the supervisor already restarts on
  backpressure (ADR: projector-stream-supervision).

## Testing strategy

- **Core unit tests** (`shooting_day/aggregate_test.rs`): creation, rename,
  reschedule, reorder-with-midpoint, archive-is-terminal, archived-rejects-mutations,
  `LexicalSortKey` validation + midpoint insertion + comparison invariants.
- **Scene unit tests**: scheduling add/remove idempotency, version bump, summary
  round-trip through `UpdateSceneDetails` "unchanged" guard.
- **Mutation surface**: the midpoint generator and the archived-guard are prime
  mutation targets — cover both with mutation-kill assertions.
- **Integration tests (Tier 4)**: `CreateShootingDay` → persisted → projector
  catches up → `ShootingDayRepository` lists by Episode in `order_key` order;
  `ScheduleSceneOnShootingDay` → join-table populated; `ArchiveShootingDay` keeps
  historical Scene view resolvable.

## Out of scope (explicitly)

- The AI extraction feature. Only the event *shape* is reserved.
- Rescheduling propagation (auto-renumbering other days' labels) — out of scope.
- Block/Season-scoped ShootingDays — identity stays Episode-scoped; lifting is
  additive later via id references.
- A `LexicalSortKey` compaction auto-trigger — `ReorderShootingDay` exists; an
  automatic compaction policy is a future increment.
