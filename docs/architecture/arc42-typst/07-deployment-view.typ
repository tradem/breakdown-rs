= Deployment View

== Infrastructure Overview

#note[
  This chapter describes the physical deployment of the system and its infrastructure requirements.
]

== Deployment Diagram

```mermaid
flowchart TB
    subgraph "Production Environment"
        LB[Load Balancer<br/>nginx]
        APP1[App Server 1<br/>breakdown-rs]
        APP2[App Server 2<br/>breakdown-rs]
        DB[(PostgreSQL<br/>Primary)]
        DBR[(PostgreSQL<br/>Replica)]
    end

    subgraph "Developer Machine"
        DEV[cargo run<br/>localhost:3000]
        DEVDB[(PostgreSQL<br/>Docker)]
    end

    Internet --> LB
    LB --> APP1
    LB --> APP2
    APP1 --> DB
    APP2 --> DB
    APP1 --> DBR
    APP2 --> DBR
```

== Deployment Units

=== Backend Application

| Property | Value |
|----------|-------|
| *Artifact* | `breakdown-rs` (binary) |
| *Build* | `cargo build --release` |
| *Runtime* | Linux x86_64 |
| *Memory* | ~100MB (estimated) |
| *CPU* | 2 cores minimum |

=== Database

| Property | Value |
|----------|-------|
| *System* | PostgreSQL 15+ |
| *Storage* | SSD recommended |
| *Backup* | Daily pg_dump |
| *Replication* | Streaming replication |

== Environment Configuration

=== Development

```bash
# .env
DATABASE_URL=postgres://localhost/breakdown_dev
RUST_LOG=debug
```

=== Production

```bash
# Environment variables
DATABASE_URL=postgres://user:pass@db/breakdown_prod
RUST_LOG=info
```

// TODO: Add detailed infrastructure requirements
// TODO: Add monitoring and logging deployment
// TODO: Add CI/CD pipeline diagram
