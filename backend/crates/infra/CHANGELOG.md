<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (opencode-go) -->

# Changelog

All notable changes to the `infra` crate are documented here. Versioning
follows per-crate Semantic Versioning (ADR-020 D2); this changelog is the
crate-level companion to the release notes generated from conventional
commits (ADR-020 D5).

## [0.5.0] - 2026-08-06

### Security fix — AI import provider transport (issue #170)

- Hosted AI providers (OpenAI-compatible) are now reachable over **HTTPS
  only**, and the Ollama endpoint is restricted to **local addresses**.
  Outgoing requests carry a curated redirect policy
  (`curated_provider_redirect_policy`) that blocks redirects to
  non-`https:` hosts for hosted providers and to non-local hosts for Ollama,
  preventing SSRF / credential-exfiltration via redirects.
- `OpenAiCompatibleModelCatalog::new` now builds its own HTTP client with the
  redirect policy and a fixed 30-second request deadline. **Breaking change:**
  the `new(http: reqwest::Client) -> Self` signature was replaced by
  `new() -> Result<Self, DomainError>` (under major-zero semver this is
  released as a minor bump; no in-tree caller used the old signature). A
  test seam `with_http(client)` remains for injected clients.

### Added (additive public API)

- New `ai::transport` module with the redirect-policy constructors
  `curated_provider_redirect_policy`, `hosted_provider_redirect_policy` and
  `ollama_redirect_policy` (re-exported from `ai`).

### Internal

- Follow-up refinements to the ADR-020/ADR-021 versioning rollout: projector
  `projector_version` guards, event/wire fixture contract tests and
  integration-test fixtures aligned with the released projection schema.

### Dependency updates (ADR-020 D7 bookkeeping)

- opendal 0.52 → 0.58 (S3 / GDrive storage)
- aes-gcm 0.10 → 0.11, base64 0.22 → 0.23, getrandom 0.3 → 0.4,
  rand_core 0.6 → 0.10, redis 1.4 → 1.5, schemars 1.2.1 → 1.2.2,
  serde 1.0.228 → 1.0.229, sha2 0.10 → 0.11
