// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)
// Co-authored-by: gemini-4-carbon (google)

#import "template.typ": *


= Introduction and Goals

== Requirements Overview

Breakdown RS is a collaborative costume scheduling and scene continuity system
for film, television, and stage productions. The system answers *who wears which
outfit, in which scene, on which day*. It also shows how the actual shoot
differs from the plan.

The monorepo contains two coordinated subsystems:

- *Rust backend (`backend/`)*: an event-sourced HTTP API with CQRS projections,
  object storage, secret management, PDF rendering, and optional AI import workers.
- *Flutter client (`frontend-flutter/`)*: an Android-first client (desktop
  later) that uses the generated OpenAPI client, syncs projection lag, and
  caches reads in SQLite.

=== Core Functions

- *Production hierarchy*: organize productions below a `ProjectId` tenant seam
  as `Season` → `Block` → `Episode` → `Scene`, with `ShootingDay` records per
  episode (#adr-ref(num: "035", slug: "production-kind-flexible-hierarchy", title: "Production-Kind-Flexible Hierarchy")).
- *Split wardrobe model*: manage fundus garments as `Piece` aggregates with a
  season repertoire and optional `CostumeCategory`. Manage character looks as
  `Outfit` aggregates (`0..n` pieces and `variant_of` forks). Scenes cast
  outfits through ordered `SceneOutfitBeat` entries.
- *Continuity tracking*: record planned order (`Soll`) and actual order (`Ist`)
  per scene and shooting day (`SceneShoot`), together with set notes and
  continuity photos.
- *PDF reporting and archival*: render `Dispo`, `Shoot Day`, and `Soll-Ist`
  reports in-process with Typst (#adr-ref(num: "022", slug: "pdf-reporting-and-archival", title: "PDF Reporting and Archival")).
  Archive day reports to S3 or Google Drive when needed.
- *AI script and schedule import*: parse scripts and CSV schedules into static
  previews and stream progress over SSE (#adr-ref(num: "030", slug: "ai-import-bounded-context", title: "AI Import Bounded Context"),
  #adr-ref(num: "038", slug: "ai-import-sse-progress-and-event-hub", title: "AI Import SSE Progress"),
  #adr-ref(num: "039", slug: "target-less-ai-import-declared-season-and-set-once-attach", title: "Target-Less AI Import")).
  Apply reviewed changes through standard commands.
- *Mobile-first client workflow*: read cached views from Drift SQLite and apply
  optimistic overlays after `2xx` replies. Localize all UI copy in German and
  English (#adr-ref(num: "034", slug: "flutter-app-localization-gen-l10n", title: "Flutter Localization")).
- *Immutable audit trail*: store every domain change as an append-only event
  and project an insert-only audit journal.

=== Stakeholders

#table(
  columns: 3,
  table.header([Role], [Primary Goal], [Key Artifacts]),
  [Production Manager], [Plan seasons, blocks, episodes, and shooting days], [Dispo and Soll-Ist PDF reports],
  [Costume Designer], [Manage fundus pieces, categories, and character outfits], [Piece repertoire, outfit variants, photos],
  [Wardrobe Supervisor], [Track set continuity and record outfit changes], [Continuity photos, scene shoot notes, Soll-Ist],
  [Script and Continuity], [Import scripts and schedules, compare plan with shoot], [AI import previews, scene lists],
  [Actor], [Check assigned outfits for scheduled scenes (planned, current scene reads need active block membership)], [Planned read-only scene and outfit views],
  [Platform Operator], [Run a secure, observable, and recoverable deployment], [Health endpoints, Vault, runbooks],
)

== Quality Goals

#table(
  columns: 3,
  table.header([Priority], [Quality Goal], [Architectural Enforcement]),
  [1 (Highest)], [Auditability and data integrity], [Append-only SierraDB streams, insert-only app-role audit access, byte-identical `jiff` timestamps],
  [2 (High)], [Functional correctness], [CQRS boundary lints, ES reservation streams, CI mutation tests, nightly fuzzing],
  [3 (High)], [Security and privacy], [OIDC RS256, deny-by-default AuthZ, public HTTPS edge + store TLS, Vault DEK crypto-shredding],
  [4 (Medium)], [Operability and resilience], [RFC 9457 error registry, dead-letter isolation, lease fencing, circuit breakers],
  [5 (Medium)], [Maintainability and extensibility], [Hexagonal Rust crates, Riverpod codegen, code-first OpenAPI drift checks],
  [6 (Standard)], [Performance and offline tolerance], [Split app and projector DB pools, direct SQL reads, client Drift read cache],
)

#note[
  *Quality Goal 1* is a strict rule across the codebase. Audit metadata must
  never block a command, and production code must never panic or discard a
  fallible result.
]
