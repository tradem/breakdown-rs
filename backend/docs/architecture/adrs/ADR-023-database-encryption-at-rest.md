# ADR-023: Database Encryption at Rest (PostgreSQL + SierraDB)

**Status**: Proposed
**Date**: 2026-08-01
**Author**: Tobias Rademacher (@tradem); glm-5.2 (neuralwatt)
**Related**: ADR-003 (PostgreSQL), ADR-015 (SierraDB event store), ADR-026 (host hardening), ADR-027 (secrets vault), ADR-029 (GDPR erasure)

---

## Context

`breakdown-rs` persists two storage tiers on a single self-managed VPS:

- **PostgreSQL 16** — CQRS read-model projections (and, in v1 dev, also the
  backing store for some aux tables).
- **SierraDB** (`tqwewe/sierradb:0.3.1`, RESP3) — the append-only event store
  (write model, ADR-015/016).

The threat we must defend against is **data theft from storage at rest**: disk
images, stolen or cloned volumes, decommissioned disks, and backup dumps that
escape the runtime trust boundary. The event store is of particular concern
because it is the system of record and contains audit/personal data that,
per ADR-027 and ADR-029, must never hold raw secrets but does hold
business-critical and personal data.

Constraints:

- Single VPS, self-managed, Arch Linux rolling release (ADR-026).
- No third-party managed KMS.
- DB-level column encryption (e.g. `pgcrypto`) is undesirable because the CQRS
  projection layer executes arbitrary `WHERE`/`ORDER BY` against many columns;
  encrypting them would break projector/read-model queries and the SQL-safety
  guards in `docs/security/README.md`.
- Postgres and SierraDB both run as Docker containers with bind-mounted data
  volumes; everything Docker writes lives under the host path backing those
  volumes.

## Decision

Encrypt **at the block-device layer** with **LUKS2**, applied to the partition
or logical volume that backs all persistent storage for the stack:

1. The Docker data root (the partition holding `/var/lib/docker` and any named
   volumes not bind-mounted elsewhere).
2. The bind-mounted host directories for `postgres_dev_data`,
   `sierradb_dev_data`, `garage_dev_data` (and their production equivalents).

**LUKS2 is the recommended primary mechanism.** Both Postgres and SierraDB sit
on top of the same encrypted volume; no per-engine encryption is configured.
This gives one uniform threat model ("the disk is unreadable off-host") and
keeps the DB engines unaware of crypto, so projections and the RESP3 client
work unchanged.

**Backups and dumps are treated as first-class bypass vectors** (see edge
cases): `pg_dump` output, SierraDB data snapshots, and LUKS-volume *images*
must all be encrypted. Concretely:

- Logical backups (`pg_dump`) are streamed through `age` (or GPG) to an
  encrypted backup key handled by the vault (ADR-027) — never written plaintext
  to disk.
- Volume-level snapshots of the LUKS container are taken with the volume
  **mounted and unlocked** (copy-on-write at the filesystem level, e.g. LVM
  snapshots or `borgbackup` of the mounted tree) and are themselves stored
  inside the encrypted volume or re-encrypted at rest.

We deliberately **do not** use `pgcrypto`/column-level encryption for at-rest
protection of projections. Application-layer encryption of specific sensitive
fields (credential material) is handled separately by the vault in ADR-027,
not by DB crypto.

For SierraDB there is no verified at-rest feature in the `tqwewe/sierradb:0.3.1`
image; we rely entirely on LUKS2 under its data directory. This is the
"assume" flag called out by the prompt: if a future SierraDB build exposes its
own encryption knob, it would be defense-in-depth, not a replacement.

## Consequences

### Positive
- One threat model, one key, one unlock procedure for both tiers.
- Projection queries, projectors, and the RESP3 event-store client are
  unchanged — no crypto leakage into the query layer.
- Protects against disk theft, cloning of volumes, and lost/decommissioned
  media.
- Backups get encrypted by default because they live on the same encrypted
  volume (with `pg_dump` re-encrypted additionally).

### Negative
- LUKS does **not** protect against a live host compromise: a process running
  as root on the VPS, or a container-escaped attacker, can read the unlocked
  volume and the keys in RAM. This gap is closed by ADR-026 (host hardening)
  and ADR-027 (secrets vault), not by at-rest crypto.
- Adds operational complexity: unlock at boot, key custody, and a remote-unlock
  story (see edge cases / open questions).
- Snapshot and backup tooling must be encryption-aware end-to-end.

## Alternatives Considered

1. **`pgcrypto` column-level encryption** — rejected: breaks the read-model
   query patterns and the SQL-safety guards; only protects against a subset of
   threats (DB-user level) and is the wrong layer for "disk stolen".
2. **Filesystem-level encryption (eCryptfs / fscrypt)** — rejected: `ecryptfs`
   is deprecated/unmaintained upstream; `fscrypt` is viable on ext4/f2fs but only
   protects file contents, not file metadata, and sits awkwardly below Docker
   bind-mounts. LUKS2 is simpler and stronger for a single-host deployment.
3. **Vault Transit envelope encryption of projection rows** — rejected as the
   *at-rest* mechanism (it belongs to ADR-027 for *secret* material). Using it
   for all projection rows would couple the read path to vault availability
   and break the CQRS query layer.

## Security / Compliance Notes
- LUKS2 with Argon2id key-derivation; LUKS header backed up separately, offline.
- Backup/restore runbook must verify a restore succeeds *against the encrypted
  form* (cannot just `cat` a dump).
- Generates a dependency on ADR-026 for host-level key custody and ADR-027 for
  the root key that protects logical backups.
- Open question (edge case): full-disk encryption on a VPS whose host does not
  support remote unlock at reboot. Preferred mitigation: a small unencrypted
  `/boot` plus a dropbear/initramfs SSH unlock, or a hoster that supports a
  "rescue console" to type the passphrase once on boot. Honest caveat: many
  cheap VPS providers (incl. the Netcup-class hosts targeted by ADR-009) do not
  expose initramfs/dropbear; on those we must either (a) accept the operational
  nuisance of manual unlock after each reboot, or (b) scope LUKS to the data
  volumes only and keep the rootfs unencrypted — the recommended choice here,
  because the data volumes are the asset, not the OS.
