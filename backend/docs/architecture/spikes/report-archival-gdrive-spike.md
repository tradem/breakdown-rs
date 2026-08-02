<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
  Co-authored-by: deepseek-v4-flash (opencode-go)
-->

# Spike: OpenDAL `services-gdrive` for report archival (ADR-022 D6)

**Change:** `add-report-archival-backup`  
**Gate:** lock external Google Drive adapter only after this spike's evidence.

## Required semantics

| Capability | Required? | OpenDAL `services-gdrive` (0.52) |
|---|---|---|
| Read / write / delete / stat | yes | Supported (docs: capabilities list) |
| Refresh-token + client_id/secret auth | yes | Supported via `refresh_token` + `client_id` + `client_secret` builder |
| Access-token (short-lived) auth | optional | Supported via `access_token` |
| Folder / root scoping (least privilege) | yes | Supported via `root` |
| Shared-drive targeting | yes | **Not first-class** in builder — relies on OAuth scope + folder id in `root`; needs live verification |
| Conditional write / If-Match | nice | **Not exposed** in the OpenDAL writer API used here |
| Idempotent overwrite by path | yes | Write to the same path overwrites (contract test with memory/S3; gdrive live TBD) |
| Retry under transient 5xx | yes | Caller-side (worker exponential backoff); OpenDAL does not auto-retry writes |

## Licence + RustSec inventory

| Crate | Licence | Notes |
|---|---|---|
| `opendal` (+ `services-gdrive`) | Apache-2.0 | Already in tree for S3/Garage photos |
| Transitive HTTP/TLS stack | MIT / Apache-2.0 / BSD | Covered by `deny.toml` allow-list |
| Fallback `google-drive3` | MIT | **Not added** unless gate fails |
| Fallback `yup-oauth2` | MIT OR Apache-2.0 | **Not added** unless gate fails |

RustSec: existing `deny.toml` ignores for quick-xml (via opendal) remain; no new advisories introduced by enabling `services-gdrive` at spike time. Re-run `cargo deny check` on merge.

## Contract tests (always-on)

In-tree unit/contract tests exercise the port semantics without live Google credentials:

- `MemoryReportArchiveStorage`: put → overwrite → fetch → delete → exists
- Staging-reuse-on-retry (backup worker unit tests): external failure keeps staged bytes; renderer is not re-invoked
- Dedup key stability across triggers

Live Google Drive integration (upload → idempotent-overwrite → fetch → delete)
uses a dedicated Settings/Vault binding and must never receive credentials as
GitHub Actions or API process environment variables. The test environment may
provide only the opaque `REPORT_BACKUP_SETTINGS_ID`; the Vault app token is
mounted through the normal runtime secret volume.

For an existing deployment, run the explicit one-time importer first:

```bash
cargo run -p api --bin migrate_gdrive_credentials -- \
  --confirm-legacy-env --settings-id <uuid> --actor <oidc-sub>
# remove the legacy variables from .env, CI and deployment secrets afterwards
```

The live contract test is intentionally not enabled by generic unit-test runs;
it requires an operator-managed Vault binding and a dedicated Drive folder.

## Gate decision

**Provisional lock: OpenDAL `services-gdrive`.**

Rationale:

1. Auth (refresh token + client credentials) and folder root scoping are exposed.
2. Idempotent overwrite is achievable at the worker layer via deterministic destination keys (path-addressed put).
3. Conditional-write absence is acceptable: the worker records content digest + provider object id after put; retries re-put the same staged bytes under the same key.
4. Shared-drive support needs a one-time live check against the operator's Drive; if it fails, **only** the external adapter swaps to `google-drive3` + `yup-oauth2` — `core` port, worker, and Garage staging stay unchanged.

## Follow-ups

- [ ] Run the live GDrive contract test against a dedicated test shared drive
      using a Settings/Vault binding before production enablement.
- [ ] Confirm least-privilege OAuth scope (`drive.file` vs `drive`) with the operator.
- [ ] If shared-drive folder writes fail under OpenDAL, execute the adapter-only fallback.
