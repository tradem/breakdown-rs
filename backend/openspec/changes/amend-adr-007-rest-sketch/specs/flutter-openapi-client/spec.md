<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## ADDED Requirements

### Requirement: ADR-007 REST Sketch Corrected
ADR-007 §"CQRS-Aware API Design" SHALL describe the API as resource-oriented
REST with CQRS semantics (write = `POST` to resource/collection routes, read
= `GET` to projection-backed routes), citing `backend/openapi.yaml` as the
source of truth — replacing the stylized `POST /commands/{aggregate}/{action}`
command-bus sketch.

#### Scenario: A reader consults ADR-007 for the API shape
- **WHEN** a contributor reads ADR-007 to understand the client API contract.
- **THEN** the section describes resource-REST matching `openapi.yaml`, with
  a "Supersedes" note linking to the `flutter-openapi-client` spec, and no
  stale command-bus sketch remains.
