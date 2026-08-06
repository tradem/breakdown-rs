# Prompt: Encryption & Secrets-Management ADR Set for `breakdown-rs`

> **Role**
> Act as a senior security architect with deep expertise in encryption-at-rest, TLS/PKI, event-sourcing security, and secrets management on Linux VPS deployments. You produce pragmatic, implementation-ready ADRs for engineering teams.
>
> **Background**
> The system is `breakdown-rs`, a collaborative costume-scheduling application. PostgreSQL and SierraDB (RESP3 protocol, pinned image `tqwewe/sierradb:0.3.1`) are the two storage tiers. An Axum HTTP API is the edge. The host is a self-managed VPS running Arch Linux (rolling release; kernel and package updates must be operated manually). We must avoid data theft. A privileged user role — the **Kostüm-Designer** — owns external integrations: Google Drive access credentials and, in future, AI-backend access tokens. These credentials must be reachable from an admin/settings panel and are modeled as domain "Settings Aggregates". The team strongly prefers open-source, self-hostable components that run inside the existing `docker-compose` setup; solutions that require a paid SaaS or manual user-side setup of external systems are out of scope.
>
> **Task**
> Produce a set of ADRs (Architecture Decision Records) in formal Markdown. Each ADR must state its decision, justify it against alternatives, and list consequences, risks, and open questions. Recommend one concrete primary tool per decision (open-source, docker-compose-hostable) and mark any other named tools as "alternatives".
> 1. Database encryption **at rest** — for both PostgreSQL and SierraDB.
> 2. Database encryption **in transit** — TLS between app↔Postgres, app↔SierraDB, projector↔Postgres.
> 3. HTTPS transport encryption at the edge — decide on the reverse proxy and the certificate-issuance/rotation approach that best fits a single-VPS, Docker-based setup. Justify the choice.
> 4. Hosting-hardening baseline for the Arch Linux VPS.
> 5. Secure handling of external credentials (GDrive access data, AI tokens). **The EventStore must NOT carry raw secrets.** It must carry only non-sensitive references (e.g. a vault key/id) pointing to a secrets vault. Recommend a specific open-source vault service to run as an additional service in `docker-compose`. The vault's lifecycle (provisioning, key wrapping, rotation) must be transparent to the end user — the backend handles it automatically; the user must never configure the vault manually. Address how credentials are stored, rotated, accessed, and revoked within this reference pattern while remaining compatible with the event-sourced architecture.
> 6. Access control for the Kostüm-Designer "Settings Aggregates" view in the admin panel.
> 7. GDPR compliance, focusing on **data-subject rights — in particular the right to erasure (Art. 17)**. Address honestly how erasure is achieved (or cannot be achieved) when personal data and credential references live in an append-only, immutable event log, and define a defensible strategy (e.g. crypto-shredding for the vault-stored secrets, tombstoning, retention/compaction, and projection-side deletion).
>
> **Limitations and boundaries**
> - Do not propose approaches that rely on a third-party managed SaaS KMS — the deployment is self-managed on a single VPS.
> - Do not store plaintext or reversibly-encrypted secrets in events, source code, logs, backups, or OpenAPI specs. The EventStore carries only non-sensitive references; the secret material lives in the vault.
> - The vault must be open-source and run inside the existing `docker-compose`. No paid SaaS, no manual user-side setup of external systems.
> - `.env` files are acceptable only to bootstrap the vault's own root key on first boot, nothing more.
> - Do not dodge the Arch Linux operating risk — call out honestly where rolling-release makes a control impractical.
> - No invented facts. If a control depends on a SierraDB version feature you cannot verify, mark it "assume" and flag it.
>
> **Output format**
> One Markdown document containing the ADR set. Use the MADR-lite structure for each ADR: "Title", "Status", "Context", "Decision", "Consequences (positive/negative)", "Alternatives considered", "Security/compliance notes". Include a top-level table of contents. Where you reference a concrete tool, state whether it is the **recommended** primary tool or listed as an alternative.
>
> **Edge cases**
> - Vault is offline/unreachable at boot — graceful degradation behavior of the API.
> - A GDrive or AI token is revoked by the upstream provider while still referenced by an aggregate.
> - Log output (including tracing spans) accidentally capturing a credential or vault unwrap response.
> - Full-disk encryption on a VPS whose host does not support remote unlock at reboot.
> - Postgres / SierraDB backups and dumps becoming a bypass for at-rest encryption.
> - A GDPR erasure request arrives for a user whose data is referenced by immutable events and whose secret in the vault is shared by reference across multiple aggregates (crypto-shredding scope question).
> - Vault root-key compromise on the single VPS — blast radius and recovery path.
