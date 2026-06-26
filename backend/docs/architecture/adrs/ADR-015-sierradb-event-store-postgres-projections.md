# ADR-015: SierraDB event store + PostgreSQL projections (CQRS split)

- **Status:** Accepted (the "container image unknown" note is superseded by ADR-016)
- **Date:** 2026-06-23
- **Supersedes:** ADR-003 (PostgreSQL as the sole persistence tier)
- **Related:** ADR-002 (event-sourcing / CQRS), ADR-004 (UUIDv7), ADR-014 (Testcontainers), ADR-016 (SierraDB runtime & round-trip)
- **Source change:** `openspec/changes/archive/2026-06-23-persistence-layer-v1`

## Context

ADR-002 prescribes CQRS + Event Sourcing. ADR-003 originally chose PostgreSQL
for all persistence, but event-store workloads (append-only, partitioned event
streams, RESP3 subscriptions) are a poor fit for a relational store. We needed
a concrete two-tier split: an append-only event store and a query-optimised
read model.

## Decision

- **SierraDB** is the event store, accessed via `kameo_es` over the RESP3
  protocol using the `redis::Client` (SierraDB speaks RESP3, Redis-compatible).
  Cargo pin: `kameo_es` from `git+https://github.com/sierra-db/kameo_es?branch=main`;
  `sierradb-client` from crates.io; `redis` 0.32 as the RESP3 transport.
- **PostgreSQL** holds the CQRS projections, populated by `kameo_es`'s
  `PostgresProcessor` (one per aggregate, each with an independent checkpoint
  stream in `sierradb_event_checkpoints`).
- The two tiers are decoupled and eventually consistent. Projector writes use
  idempotent `INSERT ... ON CONFLICT DO UPDATE` upserts so at-least-once
  redelivery is safe.

## Alternatives Considered

- **PostgreSQL for both tiers:** relational event-store performance and
  subscription semantics are weaker than a purpose-built event store.
- **Single transactional projection update:** not possible across two tiers;
  rejected in favour of idempotent replay from per-processor checkpoints.

## Consequences

- Reads are eventually consistent; `version` is exposed on `*View` DTOs so the
  frontend can detect staleness and retry.
- A projector crash between append and projection update is recoverable only via
  idempotent replay from the checkpoint, not a single-DB transaction (by design).
- **Open question at v1 time:** SierraDB's container image availability was
  unknown — ADR-015 pinned the Cargo dep but not a container tag. This note is
  **superseded by ADR-016**, which records the chosen image path and pinned tag.
- SierraDB speaks RESP3, **not** Redis-cluster semantics; see ADR-016's
  RESP3≠Redis caveats runbook section.
