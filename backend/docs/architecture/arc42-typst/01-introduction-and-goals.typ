// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

#import "template.typ": *


= Introduction and Goals

== Requirements Overview

Breakdown RS is a collaborative costume scheduling and scene continuity
application for film and stage productions. Its job is to answer one core
question reliably: *who wears what, in which scene, on which day* — and how
did the plan change.

=== Core Capabilities

- *Production planning*: organize work as a four-level hierarchy of
  aggregates (Season → Block → Episode → Scene) below an opaque *Series*
  seam, with shooting days per episode.
- *Costume management*: season-scoped characters and costumes, with
  categories (Oberteil, Unterteil, Schuhe) maintained per season.
- *Continuity tracking*: planned vs. actual shoot order per day
  (`SceneShoot`), plus continuity and costume photos.
- *Reporting*: Soll-Ist diff, Dispo, and shoot-day reports generated from
  the read model, archived as PDF when needed.
- *AI-assisted import*: optional pipeline that parses scripts and shooting
  schedules into structured scene/shooting-day candidates for review.
- *Full audit trail*: every state change is an immutable event; no state is
  silently overwritten.

=== Stakeholders

| Role            | Primary Goal                                     | Key Artifact               |
|-----------------|--------------------------------------------------|----------------------------|
| Production Manager | Plan blocks, episodes, days; assess schedules | Breakdown reports (PDF)     |
| Costume Designer   | Define costumes per character per season        | Costume photos, categories |
| Wardrobe Supervisor| Keep continuity, note changes after each shoot  | Continuity photos, Soll-Ist|
| Script / Continuity| Import scripts; compare plan vs. reality       | AI import, scene lists     |
| End User (Actor)   | See own costume assignments                     | (read-only) overview       |
| Platform Operator  | Keep service running, secure and observable     | Deployment view            |

== Quality Goals

| Priority | Quality             | How it is enforced                                          |
|----------|---------------------|-------------------------------------------------------------|
| 1 (must) | Auditability / integrity | Event sourcing, insert-only audit projections, no panics |
| 2 (must) | Correctness         | CQRS write guard, mutation testing, architecture tests      |
| 3 (should)| Operability        | OIDC auth, structured error surface (RFC 9457), metrics      |
| 4 (should)| Extensibility      | Hexagonal ports/adapters; new aggregates without cross-cuts  |
| 5 (could) | Performance        | Projections read directly from PostgreSQL; async projectors  |

#note[
  *Quality goal 1* is a hard rule in this codebase: audit metadata must never
  be lost because of a silent crash or a swallowed error. Panics and
  discarded fallible results are lint-level errors.
]

// TODO: add measurable success metrics (e.g. adoption, report delivery time)
