// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)
// Co-authored-by: gemini-4-carbon (google)

#import "template.typ": *


= Glossary

#note[
  Under ASD-STE100 rules, this chapter also serves as the project register for
  approved *Technical Names (TN)* and *Technical Verbs (TV)*.
]

== Domain Technical Names

#table(
  columns: 2,
  table.header([Term (TN)], [Definition]),
  [*Aggregate*], [Domain unit that checks business invariants and emits immutable events.],
  [*Block*], [Production grouping inside a season that contains episodes and block memberships.],
  [*Character*], [Role in a production, scoped to one season, with measurements and outfits.],
  [*Continuity*], [Consistency of outfits and appearance across scenes filmed out of story order.],
  [*Continuity photo*], [On-set photo linked to a `SceneShoot` to document actual appearance.],
  [*Costume category*], [Season-scoped classification label for pieces (for example *Oberteil* or *Schuhe*).],
  [*Dispo*], [Daily shooting schedule (*Disposition*) ordered by `planned_order`.],
  [*Episode*], [Production unit inside a block that owns scenes and shooting days.],
  [*Fundus*], [Wardrobe inventory of reusable garments (`Piece` aggregates).],
  [*Outfit*], [Composed look for one character that layers `0..n` pieces and supports `variant_of` forks.],
  [*Outfit beat*], [Ordered assignment (`SceneOutfitBeat`) of an outfit to a character inside a scene.],
  [*Photo binding*], [Discriminator (`Piece`, `Outfit`, or `Continuity`) that records what a photo belongs to.],
  [*Piece*], [Single garment in the fundus with an `m:n` season repertoire and no character owner.],
  [*Project*], [Top-level tenant container (`ProjectId`), renamed from the historical term *Series*.],
  [*Repertoire*], [Set of seasons in which a fundus `Piece` is available for use.],
  [*Scene*], [Script unit inside an episode that casts characters and outfit beats.],
  [*SceneShoot*], [Planned and actual execution record of one scene on one shooting day.],
  [*Season*], [Production container below a project that owns blocks, characters, and categories.],
  [*Series*], [Historical name for `Project`, kept in persisted `series_id` event keys and the public `GET /v1/series/{id}/membership` route (which stays `/series`, not `/projects`).],
  [*Shooting day*], [Calendar shoot unit (*Drehtag*) inside an episode.],
  [*Soll-Ist*], [Comparison report between planned shoot order (*Soll*) and actual shoot order (*Ist*).],
  [*Wrapped*], [Closed state of a shooting day (`wrapped_at` set), which marks day reports `final`.],
)

== Software Technical Names and Verbs

#table(
  columns: 2,
  table.header([Term (TN / TV)], [Definition]),
  [*arc42*], [Twelve-chapter template for software architecture documentation.],
  [*ASD-STE100*], [Simplified Technical English specification for clear, unambiguous documentation.],
  [*AUTHZ-GATE*], [Explicit authorization check inside an API handler or Flutter controller.],
  [*CQRS*], [Command Query Responsibility Segregation: separate models for writes and reads.],
  [*Crypto-shredding*], [Destroying a Vault Transit encryption key so stored ciphertext becomes unreadable.],
  [*Dead-letter table*], [`projection_dead_letter` table that isolates permanently failing events.],
  [*Drift*], [Typed SQLite persistence library used for the Flutter read-only projection cache.],
  [*Fencing*], [Lease ownership check (`claimed_by`) that stops expired workers from overwriting state.],
  [*Fluent*], [Localization system (`errors.ftl`) that translates RFC 9457 `detail` messages on the server.],
  [*Garage*], [Self-hosted S3-compatible object store for photos, AI payloads, and report backups.],
  [*gitleaks*], [Scanner that blocks committed secrets in CI and pre-commit hooks.],
  [*Idempotent*], [Property where repeating an operation or event replay produces the same state.],
  [*jiff*], [Rust date and time library that replaced `chrono` with identical RFC 3339 output.],
  [*kameo* / *kameo_es*], [Rust actor framework and vendored event-sourcing runtime for aggregates.],
  [*LexicalSortKey*], [Fractional string key that inserts items between rows without renumbering.],
  [*OIDC*], [OpenID Connect identity protocol used for JWT authentication.],
  [*OpenDAL*], [Rust data-access abstraction over S3 (Garage) and Google Drive.],
  [*OpenSpec*], [Specification-driven change workflow stored at `/openspec/`.],
  [*PlantUML*], [Text notation used to generate SVG architecture diagrams.],
  [*Problem Details*], [RFC 9457 `application/problem+json` HTTP error format.],
  [*Project* (TV) / *Projection* (TN)], [Write event state into a flat SQL read table (`projection_*`).],
  [*Projector*], [Background `PostgresProcessor` worker that subscribes to SierraDB and updates projections.],
  [*Reservation stream*], [Synthetic `reservation-*` SierraDB stream that enforces global uniqueness at write time.],
  [*Riverpod*], [Compile-safe state management and dependency injection framework in `frontend-flutter/`.],
  [*Saga*], [Event listener that reacts to domain events and sends follow-up commands.],
  [*SierraDB*], [Append-only event store accessed through the RESP3 protocol.],
  [*SSE*], [Server-Sent Events HTTP stream used for live AI import progress.],
  [*step-ca*], [Internal Certificate Authority that issues short-lived TLS certificates in production.],
  [*testcontainers*], [Test harness that runs real PostgreSQL and SierraDB containers in Tiers 1–4.],
  [*Typst*], [Typesetting engine used both for this arc42 document and for in-process PDF reports.],
  [*utoipa*], [Rust macro library that generates `backend/openapi.yaml` from handler types.],
  [*UUIDv7*], [Time-ordered 128-bit identifier defined in RFC 9562.],
  [*Vault*], [HashiCorp Vault secret store with Transit key wrapping and KV-v2 storage.],
)
