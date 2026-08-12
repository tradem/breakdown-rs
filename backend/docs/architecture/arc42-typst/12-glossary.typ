// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

#import "template.typ": *


= Glossary

== Domain Terms

| Term | Definition |
|------|------------|
| *Aggregate* | Cluster of domain objects treated as a unit; owns invariants and emits events |
| *Binding* (photo) | What a photo belongs to — `Costume { id }` or `Continuity { scene_shoot_id, costume_id? }` |
| *Block* | Part of a season, groups episodes |
| *Continuity* | Tracking of actual vs. planned shoot appearances to keep costumes consistent |
| *Continuity photo* | Photo taken on set showing the current state of a costume for a scene |
| *Costume* | Outfit/scene element typically worn by a character |
| *Costume category* | Season-scoped classification vocabulary (e.g. *Oberteil*, *Unterteil*), maintained per season |
| *Dispo* | Short for *Disposition* — the day's shoot plan |
| *Episode* | Production unit with scenes and shooting days |
| *Production* | Overall Season/Series/Block/Episode/Scene hierarchy name |
| *Scene* | Filming unit within an episode |
| *SceneShoot* | One planned execution of a scene on a specific shooting day, with planned vs. actual order |
| *Season* | Release period containing blocks/episodes |
| *Series* | Opaque top-level seam for future additive aggregation |
| *Shooting day* | A calendar day (or work block) during which scenes are filmed |
| *Soll-Ist* | German for *planned vs. actual*; the core continuity report |
| *Wrapped* | Shooting day finalized — its `wrapped_at` timestamp is set, and reports mark it `final` |

== Technical Terms

| Term            | Definition |
|-----------------|------------|
| *Arc42*         | Architecture-documentation template (12 chapters) |
| *CQRS*          | Commands modify events; projections serve queries — write and read paths deliberately separated |
| *DI*            | Dependency Injection (here: Poor Man's DI — explicit constructors, no framework) |
| *Fencing*       | Lease-based job claim with worker-id fencing to prevent split brain |
| *Fluent*        | Rust localization library used to translate error `detail` text |
| *Fluent FTL*    | Fluent text localization format |
| *Garage*        | Self-hosted S3-compatible object storage used for photos and AI payloads |
| *gitleaks*      | Secret-scanning tool used to prevent committing secrets |
| *kameo*         | Rust actor framework used for aggregates |
| *kameo_es*      | Event-sourcing extension for kameo aggregate actors |
| *Lexical sort key* | String key that sorts lexically and never needs renumbering (insert-in-between) |
| *OIDC*          | OpenID Connect — SSO standard used for authentication |
| *OpenDAL*       | Rust abstraction over object stores (S3, GDrive, memory, etc.) |
| *PlantUML*      | Text-based diagram generator used for all documentation diagrams |
| *Postgres Processor* | Named sides of architecture code reacting to events and updating projections |
| *Projection*    | Read-optimized, flat table maintained specifically to serve queries |
| *Saga*          | Event-driven composer: reacts to an event and dispatches follow-up commands |
| *SierraDB*      | RESP3-compatible event store (rewrite of SierraDB concepts) |
| *testcontainers* | Testcontainers-based integration tests (tiers 1-4) |
| *Typst*         | New typesetting language used for this documentation and PDF reports |
| *UUIDv7*        | Time-ordered UUID (per RFC 9562) |

// TODO: extend with terms as they appear in new aggregates (membership, settings, audit)
