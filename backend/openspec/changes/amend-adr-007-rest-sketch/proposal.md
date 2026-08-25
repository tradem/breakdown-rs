<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

# Proposal: Amend ADR-007 to Correct the Command-Bus Sketch

## Why
ADR-007 §"CQRS-Aware API Design" sketches a stylized
`POST /api/v1/commands/{aggregate}/{action}` command-bus shape. The actual
checked-in `backend/openapi.yaml` is **resource-oriented REST** with CQRS
semantics (`POST /seasons`, `POST /costumes/{id}/assign`, …). The Flutter
foundation (`flutter-openapi-client` spec) already documents the correction;
this change amends the ADR itself so the architecture record matches reality
and future agents don't build the wrong mental model.

## What changes
- Edit `backend/docs/architecture/adrs/ADR-007-frontend-technologies-and-api-communication.md`
  §"CQRS-Aware API Design" to replace the command-bus sketch with the
  resource-REST reality, citing `openapi.yaml` as the source of truth.
- Add a "Supersedes" note linking to the foundation's
  `flutter-openapi-client` spec.
- Per ADR-008 inline-amendment convention: mark the amended section and date.

## Dependencies
- **Depends on:** `add-flutter-app-foundation` (merged; its spec documents
  the correction).

## Non-goals
- No backend API route changes (the API is already resource-REST; this is a
  docs-only correction).
- No OpenSpec spec content beyond the doc-amendment requirement.
- No Flutter code.
