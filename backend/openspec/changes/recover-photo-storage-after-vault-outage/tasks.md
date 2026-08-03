## 1. Recoverable Vault SSE-C key resolution (storage adapter)

- [x] 1.1 Add `PhotoStorageKeySource` trait + `RecoverableInner` (lazy operator cache) to `crates/infra/src/photo/storage.rs`; make `operator()` async and retry resolution on miss
- [x] 1.2 Add `recoverable(key_source)` constructor; keep `new`/`with_bucket`/`unavailable`
- [x] 1.3 Implement `PhotoStorageKeySource for VaultClient` in `crates/infra/src/vault.rs`
- [x] 1.4 Update `main.rs` to construct `OpenDalPhotoStorage::recoverable(Arc::new(credential_vault.clone()))` instead of the boot-time key resolution + `unavailable()` fallback

## 2. Saga retry on transient ServiceUnavailable

- [x] 2.1 Add `retry_transient` helper (backoff, no budget for transient errors) in `crates/infra/src/photo/sagas/mod.rs`
- [x] 2.2 Wrap `PhotoThumbnailSaga::process_upload` and `PhotoBytesCleanupSaga` deletion in `retry_transient`; change storage `map_err` to `anyhow::Error::new(e)` so `downcast_ref::<DomainError>()` works

## 3. kameo_es: ack only after successful processing

- [x] 3.1 Add cursor field to `UnprocessedEvent`; remove pre-processing batch ack from `EventHandlerStream::next()`
- [x] 3.2 Add `AckTracker` (processed high-water mark + batch trigger) and ack in `run()`/`process_next()` only after successful processing
- [x] 3.3 Add deterministic unit tests for `AckTracker` (ack cursor = last processed cursor; failure does not advance)

## 4. Deterministic tests

- [x] 4.1 Add Vault-recovery test for `OpenDalPhotoStorage` in `crates/infra/tests/photo_storage_recovery.rs` (fake key source that recovers; operator cached after recovery)
- [x] 4.2 Add `retry_transient` tests in `crates/infra/tests/photo_saga_retry.rs` (retries ServiceUnavailable until success; propagates permanent errors immediately)
- [x] 4.3 Add `AckTracker` ack-after-processing tests in `.patches/kameo_es/tests/ack_tracker.rs` (tests/ layout per Issue #127 Variante B)
- [x] 4.4 Keep/verify the existing fail-closed integration test (`unavailable_photo_storage_does_not_write`) still passes

## 5. Specs, docs, verification

- [x] 5.1 Sync delta specs to `openspec/specs/photo-sse-c-encryption`
- [x] 5.2 Run `cargo build` + unit tests (`cargo test -p infra -p core`) + `cargo clippy --workspace --all-targets -- -D warnings` + `cargo fmt --all -- --check`
- [x] 5.3 Run `cargo test -p architecture_tests` and `cargo deny check bans`; run OpenSpec validation
