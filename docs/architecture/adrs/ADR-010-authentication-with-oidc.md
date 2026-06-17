# ADR-010: Authentication with OpenID Connect (OIDC)

**Status**: Accepted
**Date**: 2026-06-17
**Author**: Architecture Decision

---

## Context

Breakdown RS needs authentication and authorization for users (actors, costume designers, production staff) to securely access the collaborative costume scheduling application. We need to decide on an authentication strategy that balances:

- **Time-to-Market (TTM)**: We want to move fast and validate the product
- **Security**: Protection against unauthorized access and supply chain attacks
- **Maintainability**: Ease of updates, patches, and potential provider changes
- **Multi-tenancy**: Support for organizations/theaters with isolated user bases
- **Future flexibility**: Ability to switch auth providers if requirements change

### Constraints:
- Rust backend must remain clean and not be tightly coupled to any auth provider
- Frontend (Svelte) and future mobile app (Flutter) need easy integration
- Team has limited operations capacity for self-hosting infrastructure
- Supply chain security is a growing concern across all ecosystems (npm, Go, Rust)

## Decision

We will use **OpenID Connect (OIDC)** as our authentication protocol with **Logto** as the initial identity provider (IdP), deployed via their **Managed Cloud (free tier)** for the first release.

### Key Architectural Decisions:

1. **Standardized OIDC Protocol**: The Rust backend will only validate cryptographically signed JWTs. It will not depend on any provider-specific SDK. This means switching from Logto to another OIDC provider (e.g., Zitadel, Keycloak) later is architecturally manageable:
   - Only configuration changes needed (`iss` issuer and JWKS URL)
   - Most work would be in the frontend (SDK swap)

2. **Managed Cloud for First Release**: Use Logto's free cloud tier to:
   - Eliminate supply chain risk (Logto's code runs on their servers)
   - Reduce maintenance overhead (no auth container patching)
   - Minimize server costs (0 MB RAM on our infrastructure)
   - Focus 100% on Rust backend and domain logic development

3. **Architecture as an Evolutionary Process**: We optimize for TTM now, accepting that we may revisit this decision later. The OIDC standard ensures we're not locked in.

## Consequences

### Positive
- ✅ **Fast Time-to-Market**: Managed cloud + OIDC standard = authentication working in days, not weeks
- ✅ **No Vendor Lock-in**: Backend only validates JWTs; switching IdP is a configuration change
- ✅ **Zero Auth Infrastructure**: No servers to patch, no containers to monitor
- ✅ **Multi-tenancy Support**: Logto Cloud includes Organizations/Multi-Tenancy and Social Logins in free tier
- ✅ **Standard Compliance**: OIDC is battle-tested and widely supported

### Negative
- ⚠️ **Supply Chain Risk (Logto's Code)**: Logto is Node.js/npm-based. npm ecosystem has high fragmentation and many transitive dependencies (higher attack surface)
- ⚠️ **Dependency on External Cloud**: Relying on Logto Cloud means we're subject to their uptime and pricing changes
- ⚠️ **Limited Control**: Managed cloud means less control over auth features and data residency

### Supply Chain Security Mitigation

Since we use multiple ecosystems (Rust backend, Node.js/Svelte frontend, Dart/Flutter mobile), we will implement the following safeguards:

1. **Strict Lockfile Commitment**:
   - `Cargo.lock`, `package-lock.json`, `pubspec.lock` are always committed
   - Dependency updates happen consciously, never automatically

2. **Automated Vulnerability Scanning in CI/CD**:
   - **Rust**: `cargo-audit` in CI pipeline
   - **Node.js**: GitHub Dependabot or Renovate
   - **Additionally**: Integrate Trivy or Socket.dev for comprehensive scanning

3. **Avoid Self-Hosting for Now**:
   - By using Logto Cloud, we shift the supply chain risk to Logto's team
   - If we later self-host, we'll evaluate Go-based solutions (Zitadel) which have:
     - Stronger culture of avoiding third-party libs
     - Integrated checksum database (`sum.golang.org`)
     - Lower supply chain attack surface

## Alternatives Considered

1. **Zitadel (Go-based, Self-Hosted)**:
   - ✅ Better supply chain security (Go culture, fewer deps)
   - ✅ More features, mature product
   - ❌ Slower setup (self-hosting, Docker, configuration)
   - ❌ Higher maintenance overhead
   - **Why not chosen**: We prioritize TTM and want to validate the product before investing in self-hosted auth

2. **Keycloak (Java-based)**:
   - ✅ Mature, feature-rich
   - ❌ Heavy Java stack, high resource usage
   - ❌ Complex configuration
   - **Why not chosen**: Too heavy for our current needs

3. **Supabase Auth**:
   - ✅ Easy integration, managed service
   - ❌ Vendor-specific (not standard OIDC)
   - ❌ Less suitable for multi-tenancy with organizations
   - **Why not chosen**: Not OIDC standard, would lock us in

4. **Custom JWT Implementation**:
   - ✅ Full control
   - ❌ High security risk (implementing auth correctly is hard)
   - ❌ No standard protocols (harder to integrate with frontend/mobile)
   - **Why not chosen**: Security risk and reinventing the wheel

## Notes

### Future Migration Path (Logto → Zitadel)

If we need to switch from Logto to Zitadel later:

**Backend (Rust)**:
- Update OIDC configuration (`iss` issuer URL, JWKS endpoint)
- No code changes needed (we only validate standard JWTs)

**Frontend (Svelte)**:
- Replace Logto SDK with Zitadel SDK (or standard OIDC client)
- Update authentication flows

**Infrastructure**:
- Deploy Zitadel container (if self-hosting) or configure Zitadel Cloud
- Migrate users (both support standard OIDC user export/import)

### Ecosystem Supply Chain Comparison

| Ecosystem | Supply Chain Risk | Culture | Tooling |
|-----------|------------------|---------|---------|
| **Node.js/npm (Logto)** | High (many transitive deps) | Micro-packages | Socket.dev, npm audit |
| **Go (Zitadel)** | Low (few deps, std lib powerful) | Avoid third-party libs | `govulncheck`, sum.golang.org |
| **Rust/crates.io (backend)** | Medium (many small crates) | Vigilant community | `cargo-audit`, crates.io security |

### References

- [Logto Cloud Free Tier](https://logto.io/pricing)
- [OpenID Connect Specification](https://openid.net/specs/openid-connect-core-1_0.html)
- [Supply Chain Security in Go](https://go.dev/blog/package-version-validation)
- [cargo-audit for Rust](https://github.com/rustsec/rustsec/tree/main/cargo-audit)

---

**Related ADRs**:
- None yet (first auth-related ADR)

**Follow-up Actions**:
- [ ] Add `cargo-audit` to CI pipeline
- [ ] Configure Logto Cloud instance
- [ ] Implement OIDC JWT validation in Rust backend
- [ ] Integrate Logto SDK in Svelte frontend
- [ ] Document auth flow in `AGENTS.md`
