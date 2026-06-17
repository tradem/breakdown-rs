# ADR 0001: Use OpenDAL with S3-Compatible API for Photo Storage

**Status:** Accepted

**Date:** 2026-01-17

**Authors:** breakdown-rs Contributors

## Context

The costume scheduling application needs to store and retrieve photos uploaded by users (e.g., costume images, reference photos). We need a storage solution that:

1. Integrates well with our Rust backend
2. Supports our Docker-based deployment on budget VPS (e.g., Netcup)
3. Allows future migration without code changes
4. Minimizes resource usage on small VPS instances
5. Provides flexibility in storage backend choice

## Decision

We will use **Apache OpenDAL** as the abstraction layer for photo storage, with an S3-compatible API as the interface standard.

### Implementation Strategy

1. **Storage Abstraction:** Use the `opendal` Rust crate to abstract all storage operations (upload, download, delete, list)
2. **Initial Deployment:** Configure OpenDAL to use the `fs` service (local filesystem) with Docker volumes for persistence
3. **Future Migration Path:** When needed, switch to S3-compatible backends (Garage, MinIO, Cloudflare R2, Backblaze B2) by changing only configuration

### Recommended Storage Backends (by deployment phase)

**Phase 1 - MVP/Early Production:**
- OpenDAL with local filesystem (`fs` service)
- Photos stored in Docker volume on host system
- Advantages: Zero overhead, simple backups, no additional containers

**Phase 2 - Growth:**
- Add Garage (Rust-based S3-compatible server) as Docker container
- Extremely resource-efficient (< 1 GB RAM)
- Optimized for self-hosting on budget hardware

**Phase 3 - Scale:**
- Migrate to cloud S3-compatible storage (Cloudflare R2, Backblaze B2)
- No code changes required, only configuration update

## Consequences

### Positive

- **Vendor Independence:** S3 API is an industry standard supported by几乎所有modern libraries and tools
- **Zero Code Changes:** Backend code remains identical when switching storage backends
- **Resource Efficiency:** Phase 1 requires no additional RAM/CPU for storage services
- **Cost Effective:** Start with local storage, migrate to cheap cloud options later
- **Rust Ecosystem:** OpenDAL is written in Rust, well-maintained, and type-safe
- **Docker-Friendly:** Easy to persist data via volumes, simple backup strategy

### Negative

- **Abstraction Overhead:** OpenDAL adds a thin abstraction layer (minimal performance impact)
- **Local Storage Limitations:** Phase 1 setup doesn't support distributed storage or advanced S3 features

### Risks

- **Garage Maturity:** If choosing Garage in Phase 2, it's less battle-tested than MinIO (though more resource-efficient)
- **Local Storage Backup:** Responsible for implementing proper backup strategy for Docker volumes

## Alternatives Considered

### MinIO
- **Pros:** Mature, excellent UI, large community
- **Cons:** Resource-heavy, AGPLv3 license, enterprise-focused
- **Verdict:** Overkill for initial phases, viable for Phase 2 if Garage proves insufficient

### RustFS
- **Pros:** Rust-based, performance-focused
- **Cons:** Beta status, bleeding edge, complex for small installations
- **Verdict:** Too early for production use in core features

### Direct Filesystem Access (no abstraction)
- **Pros:** Simplest approach
- **Cons:** No migration path, vendor lock-in to local storage
- **Verdict:** Rejected due to lack of flexibility

## Compliance with Architecture

This decision aligns with our hexagonal architecture:
- **Port:** Define `PhotoStorage` trait in `crates/core`
- **Adapter:** Implement using OpenDAL in `crates/infra`
- **Configuration:** Inject backend type via environment configuration

## References

- [OpenDAL Documentation](https://opendal.apache.org/)
- [Garage S3-compatible Server](https://garagehq.deuxfleurs.fr/)
- [MinIO](https://min.io/)
- S3 API Compatibility Standard
