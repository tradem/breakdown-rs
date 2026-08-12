// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

#import "template.typ": *


= System Scope and Context

== Business Context

Breakdown RS is the single point where costume planning meets actual filming.
Production staff (production manager, costume designer, wardrobe supervisor,
script/continuity) interact with the system to plan, verify and document
costumes and continuity.

#diagram("business-context", caption: [Business context — actors and use cases])

=== Business Responsibilities

| Responsibility                    | Description |
|-----------------------------------|-------------|
| Episode/Script import             | Fed by AI or manual entry; becomes the plan. |
| Shooting-day planning             | Planned order, notes, wrap status per shooting day. |
| Costume assignment                | Characters scoped to season; costumes assigned to characters. |
| Continuity                        | Actual shoot order recorded; differences surfaced as Soll-Ist. |
| Photo documentation               | Costume and continuity photos stored and versioned. |
| Reporting                         | Breakdown and Soll-Ist PDFs per production state. |

== Technical Context

=== External Interfaces

The API is the only entry point. Everything else is infrastructure.

#diagram("technical-context", caption: [Technical context and protocols])

| System | Interface | Protocol | Auth |
|--------|-----------|----------|------|
| Web / Frontend | REST API (JSON) | HTTPS | OIDC JWT |
| OIDC IdP       | Token validation | HTTPS JWKS | mTLS-pinned root (optional) |
| SierraDB       | Event streams    | RESP3    | TLS, passwordless |
| PostgreSQL     | Projections      | SQL      | TLS, least-privilege role |
| Garage         | Object store     | S3 API   | S3 access key |
| Vault          | Secrets          | HTTPS    | AppRole / token |
| LLM Provider   | AI script import | HTTPS    | Bearer token |

#note[
  SierraDB speaks RESP3 only — no Redis-specific commands beyond the RESP3
  subset it implements. All interaction goes through the `SIERRADB_URL`
  connection string.
]
