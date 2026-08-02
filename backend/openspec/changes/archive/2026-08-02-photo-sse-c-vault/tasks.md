## 1. Vault bucket-key lifecycle

- [x] 1.1 Extend `VaultClient` with a fixed `photo-sse-c` bucket-key lifecycle: ensure Transit key, read existing KV-v2 wrapped DEK, provision missing record with KV-v2 CAS=0, retry the committed record after a race, decrypt and validate exactly 32 bytes, and zeroize temporary decoded buffers.
- [x] 1.2 Add Vault adapter tests for wrapped-key parsing/validation, first-use behavior, concurrent CAS conflict handling, and Vault-down/service-unavailable errors without logging secret response bodies.
- [x] 1.3 Extend `scripts/vault-bootstrap.sh` least-privilege policy for the `photo-sse-c` Transit/KV paths without granting unrelated secret access.

## 2. SSE-C photo adapter and boot wiring

- [x] 2.1 Add an SSE-C-specific OpenDAL S3 builder path that uses `server_side_encryption_with_customer_key("AES256", key)` while preserving report-storage behavior and redacted debug output.
- [x] 2.2 Update `OpenDalPhotoStorage` to require the Vault-derived key for production construction, validate key length, and add an explicit unavailable state whose CRUD/list operations return `ServiceUnavailable` rather than using plaintext.
- [x] 2.3 Reorder API composition so `VaultClient` loads/provisions the bucket DEK before photo storage construction; keep the API bootable on Vault outage while wiring the unavailable adapter and retaining normal Vault credential-port behavior.
- [x] 2.4 Verify all photo paths (API upload/download/delete, thumbnail/deletion sagas, and GC) share the SSE-C-configured operator and no code path invokes a plaintext `from_env` constructor.

## 3. Contract and integration tests

- [x] 3.1 Update Garage integration fixtures to configure a deterministic 32-byte SSE-C key and add adapter coverage for store/fetch/stat/delete round trips with the customer key.
- [x] 3.2 Add a negative Garage contract test proving an SSE-C object cannot be fetched with an operator lacking the matching customer key, plus a test that the unavailable adapter performs no backend write.
- [x] 3.3 Run focused core/infra/API/integration tests and ensure existing photo saga and GC tests still pass with SSE-C.

## 4. Documentation and operations

- [x] 4.1 Update ADR-023 and ADR-027 with the accepted bucket-level DEK decision, Vault custody, fail-closed behavior, and explicit per-photo/per-season limitation.
- [x] 4.2 Add a runbook section for first provisioning, inspection without exposing key material, two-key rotation/backfill/rollback, verification, and deliberate whole-bucket crypto-shredding.
- [x] 4.3 Add or update OpenSpec/main photo-storage requirements and validate the change artifacts with OpenSpec.

## 5. Verification and hardening

- [x] 5.1 Run `cargo fmt --all -- --check`, focused tests, `cargo clippy --workspace --all-targets -- -D warnings`, and architecture/security checks applicable to changed files.
- [x] 5.2 Run `gitleaks`/secret scans and inspect the final diff for customer-key material, interpolated secrets, panics, and accidental changes to the pre-existing untracked `backend/prompts/` files.
