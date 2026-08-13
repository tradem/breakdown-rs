// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

#import "template.typ": *


= Risks and Technical Debt

== Active Risks

#table(
  columns: 4,
  table.header([Risk], [Probability], [Impact], [Mitigation]),
  [CQRS projection lag], [Medium], [Medium], [Idempotency, version guards, retries in projectors],
  [Event schema drift], [Medium], [High], [Version events, upcast pattern, never delete old event types],
  [SaaS dependency drift (SierraDB, Garage, Vault)], [Medium], [Medium], [Pin images / lockfiles; keep adapters thin],
  [AI-provisional semantics], [Low], [Low], [AI is opt-in (`AI_IMPORT_ENABLED` default false); retries are bounded],
  [Lost audit context from swallowed errors], [Low], [Critical], [Compiler denial + `ast-grep` `discard-result` rule],
)

== Known Technical Debt

== ADR-024 follow-up: TLS everywhere

  Some drivers and dev compose still allow plaintext for convenience
  (`DATABASE_URL` fallback, dev `rediss://` gating). Requires the TLS
  rollout to complete before hard requirement can be the only option.

==  AI import queue semantics

  The AI import queue lives in Postgres for now — there is no event sourcing for
  the job lifecycle itself. A transition to SierraDB job streams is
  deliberately deferred until the queue includes user interactivity commands.

==  SceneShoot planned-order semantics

  Freezing `planned_order` alongside execution is a v1 compromise. Reordering
  after start requires an explicit command (scenes are only reorganized by
  day managers).

== Archived Items (Resolved, Listed for Context)

- Dependency injection framework adoption → settled on Poor Man's DI
  (ADR-001).
- Pure Markdown arc42 in AsciiDoc format → switched to Typst for the
  single-binary toolchain (ADR-008).
- ndb-based photo blob storage → S3 (OpenDAL/Garage) via S3-compatible API (ADR-009).

// TODO: regular risk review and retirement of resolved items
