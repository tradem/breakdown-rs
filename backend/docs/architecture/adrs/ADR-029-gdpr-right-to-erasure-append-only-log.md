# ADR-029: GDPR Art. 17 (Right to Erasure) in an Append-Only Event-Sourced System

**Status**: Proposed
**Date**: 2026-08-01
**Author**: Tobias Rademacher (@tradem); glm-5.2 (neuralwatt)
**Related**: ADR-002 (event sourcing), ADR-010 (OIDC identity),
ADR-015/016 (SierraDB event store), ADR-023 (at-rest crypto),
ADR-027 (secrets vault / crypto-shredding), ADR-028 (settings authz & audit)

---

## Context

GDPR Article 17 gives a data subject the right to erasure ("right to be
forgotten"). `breakdown-rs` is event-sourced (ADR-002): the SierraDB event
store is **append-only and immutable**, and projections in PostgreSQL are
rebuilt by replaying events. Personal data appears in three places:

1. **The immutable event log** (SierraDB) — audit/system-of-record rows that
   historically carry fields like a user `sub`, email, actor references, and
   (per ADR-027) only *references* to vault keys, never secret material.
2. **Postgres projections** — read-model rows populated by projectors, many of
   which denormalise personal data (e.g. creator `sub`, uploader identity).
3. **The secrets vault** (ADR-027) — ciphertexts + Transit-wrapped DEKs for
   external credentials.

Honest framing: **a true, retroactive "delete this person from history" is
incompatible with an append-only event log** — rewriting or deleting past
events breaks the event-sourcing invariants (replay determinism, audit
integrity) and the system-of-record guarantee. We therefore do not promise
literal log rewriting. Instead we define a **defensible, layered erasure
strategy** that satisfies the *effect* Art. 17 is concerned with (the data
subject can no longer be identified or have their data processed) while
preserving the integrity of the audit log.

## Decision

Combine four complementary controls, each scoped to where personal data lives:

### 1. Crypto-shredding for vault-stored secrets (ADR-027) — primary exit ramp
For any personal/secret material held via the vault (external credentials
owned by the data subject), destroy the per-credential **Transit DEK**. The
ciphertext references in the event log remain, but are permanently
un-decryptable: the data subject's secret material is effectively erased
without touching the immutable log. Scope is one-DEK-per-credential (ADR-027),
so shredding one subject does not collaterally erase another's data.

### 2. Minimisation at write time (event log is reference-first)
Persist **references, not raw PII**, in events wherever the domain allows:
actor identity is the OIDC `sub` (a stable, opaque identifier, ADR-010), not a
name/email; credential material is a `vault_key_id` (ADR-027); emails/names
are NOT stored as event fields. This minimises the personal-data footprint in
the immutable log to identifiers that are meaningless without the IdP, which
is the legitimate retention baseline for an audit log.

### 3. Tombstoning + projection-side deletion
Emit a new domain event `UserErasureRequested { subject_id, requested_by,
requested_at }` to the subject's stream. Projectors react with **deletion
semantics** on the read model:

- Projection tables that denormalise the subject's PII run a projector-driven
  `DELETE` (or an anonymising `UPDATE` that replaces identifying columns with
  `<erased>`) for that `subject_id`. The read model — the surface users and
  operators actually see — is thereby scrubbed.
- Existing projector idempotency/version-guard patterns (AGENTS §1) apply.
- The event log retains the `UserErasureRequested` tombstone (and the original
  history) for audit and lawful-basis records.

This gives erasure *where users and operators observe data* (projections,
admin panel, reports) without rewriting history.

### 4. Retention / compaction policy for the immutable log
Define a documented retention window for the event log. Within that window the
referenced identifiers remain (lawful basis: audit/contract); after the window,
perform **event-stream compaction** under explicit controls: compaction
re-writes a *new* stream that drops events carrying the erased subject's PII
identifiers, while preserving aggregate state semantics. Compaction is a
controlled, audited, infrequent operation, never part of normal request flow.
Honest caveat: compaction weakens bit-exact historical audit; it is gated
behind a documented retention policy and used only when lawful retention no
longer applies.

### Backups
Dumps and snapshots (ADR-023) are themselves immutable copies. Erasure cannot
retroactively edit them. Mitigations: (a) short backup retention aligned with
the retention window above; (b) because secrets live in the vault and
projections are rebuilt from events, a restored backup yields identifiers but
the shredded vault DEKs are still destroyed — i.e. secret material stays
unrecoverable; (c) projection-side erasure is *re-applied* on restore by
replaying the `UserErasureRequested` tombstone.

### Logging / traces
Tracing spans and audit tables (ADR-028) must not capture credentials or
unwrapped secrets (ADR-027 log hygiene). For erasure specifically, the audit
row records that an erasure was performed for a `subject_id` — this itself is
a legitimate processing record (Art. 17(3) exceptions: the controller's
right/obligation to keep records).

## Consequences

### Positive
- Honours the *effect* of Art. 17 (data subject no longer identifiable or
  processable) across projection surface, secret material, and backups.
- Preserves the append-only audit integrity that ADR-002 mandates.
- Crypto-shredding is a clean, instant, verifiable act for vault-stored data.

### Negative
- We cannot promise literal, byte-level deletion from the historical event log
  within the retention window — only identifier-minimisation + projection-side
  erasure + post-retention compaction. This is the honest limit; it must be
  stated plainly in the privacy notice and the DPA record.
- Compaction is a non-trivial, risky operation (re-writing streams); it needs
  tooling, tests, and a documented trigger.
- Bursts of projector-driven `DELETE`s must be rate/throttled to avoid
  starving the read path on the small VPS.

## Alternatives Considered

1. **Rewrite/scrub the event store in place** — rejected: breaks event-sourcing
   invariants, breaks determininism of replay, breaks audit; only acceptable
   as the compaction step under §4, in a controlled batch.
2. **Pseudonymisation-only (no erasure promises)** — insufficient for Art. 17;
  offered only as an interim within the retention window, not as the model.
3. **Offload erasure to the IdP only** — a partner control (have the IdP
   rotate/invalidate the `sub`), but does not erase data already in our log; it
   is complementary, not a substitute.

## Security / Compliance Notes
- A `UserErasureRequested` event plus its projector handlers is the
  implementation surface for this ADR; an architecture test should assert that
  every projection carrying personal fields has a handler reacting to it.
- The privacy notice and DPA must state the retention window and the
  compaction policy explicitly; this ADR is technical and assumes legal signs
  off on the window.
- Edge case (crypto-shredding scope): only per-credential DEKs are destroyed
  (ADR-027), never a shared master — so erasing one subject cannot break
  another's secrets. If a shared reference ever appears, the reference-count
  guard in ADR-027 §edge-cases applies here too.
- Edge case (subject referenced by immutable events + shared vault key):
  resolved by the per-credential DEK rule; if a credential *is* legitimately
  shared across aggregates, projection-side reference counting must hit zero
  before the DEK is destroyed, and an explicit retention override is recorded.
