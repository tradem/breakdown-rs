<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

# ADR-032: Flutter Client TLS Certificate Pinning & Production Rotation Policy

**Status**: Proposed
**Date**: 2026-09-01
**Author**: Tobias Rademacher (@tradem); hy3 (opencode-go)
**Supersedes**: —
**Related**: ADR-025 (HTTPS edge & cert issuance), ADR-024 (in-transit TLS),
ADR-010 (OIDC), ADR-007 (frontend tech)
**Source change**: GitHub issue #313 (dev CA alignment, PR #316) + prod
follow-up discussion; see also `openspec/changes/313-replace-dev-ca-placeholder`.

---

## Context

The Flutter client (Android first, macOS later) pins a per-flavor CA bundled
in `assets/certs/<flavor>/ca.pem` and constructs its `SecurityContext` with
`withTrustedRoots: false` (fail-closed, no system roots — the "D4" pinned-CA
stance in `frontend-flutter/AGENTS.md` §5, realized in
`frontend-flutter/lib/src/network/api_client.dart`). Issue #313 (PR #316)
replaced the **dev** placeholder with the real dev CA; `prod/ca.pem` remains a
placeholder.

ADR-025 establishes the backend edge (Caddy + ACME / Let's Encrypt) and states
that certificate issuance/rotation is "transparent to the end user and to the
application." But ADR-025 covers only the **server edge** — it does **not**
specify what the *client* pins, nor how client re-delivery interacts with cert
rotation. This ADR closes that gap.

The open questions, raised during the prod-readiness review:

- The backend's certs rotate on the ACME rhythm (~90 days). Does that force us
  to re-ship the app and require users to update *immediately*?
- Can we give users a **transition window** instead of an instant deprecation?
- How do we keep the shipped **APK (Android) / macOS** binary from being
  compromised?

Key technical fact that dissolves the first fear: **ACME rotates LEAF
certificates (~90 days); the public ROOT (ISRG X1, with ISRG X2 as successor)
is stable for years.** Pinning the *root* (not the leaf) makes leaf rotation
invisible to the client. Root rotation is rare and can be handled with a
dual-root overlap (a built-in transition window). The "immediate re-ship"
scenario only arises if one pins the wrong thing (the leaf).

Constraints:

- `withTrustedRoots: false` (D4) means we bundle the trust anchor; a pin/root
  mismatch is fail-closed → a total connection outage for affected clients.
  Therefore root rollover MUST ship to clients before the old root is retired.
- Android is the first target; macOS is explicitly later (`frontend-flutter/
  AGENTS.md`). Binary-integrity controls differ per platform but the pinning
  policy is shared.

## Decision

1. **Pin the public root, never the leaf.** `assets/certs/prod/ca.pem` SHALL
   contain the Let's Encrypt root **ISRG X1** plus **ISRG X2** as a backup
   trust anchor. Bundling both PEM blocks in one file yields multiple trust
   anchors through the existing `SecurityContext.setTrustedCertificatesBytes`
   call — no client code change is required for backup pinning.
2. **Leaf rotation is transparent.** Because we pin the root, the backend's
   ACME leaf rotation (ADR-025) requires **no app update and no user action**.
3. **Root transition via dual-root overlap (transition window).** On a Let's
   Encrypt root change (X1 → X2), `prod/ca.pem` is updated to include the new
   root while retaining the old, then shipped in a normal release. The old
   root is removed only after the backend stops using it **and** the majority
   of users run the new app — giving users weeks/months, never an instant
   cut-over.
4. **Binary integrity is orthogonal to pinning.** APK integrity (Play App
   Signing, upload-key separation, APK Signature Scheme v3/v4, no debug keys in
   release) and macOS integrity (Developer ID + Notarization + Gatekeeper)
   protect the *binary*; TLS pinning protects the *channel*. A compromised
   signing key is mitigated by store integrity and key management, not by CA
   pinning.
5. **We hold no CA key.** Choosing a public CA (Modell A) means we never hold
   the CA private key, eliminating the "CA-key compromise → attacker mints leaf
   for our domain" risk. Residual risk shifts to the ACME account key + DNS-01
   control (mitigated by the vault per ADR-027, short-lived leaves, and
   immediate re-issue on suspicion).

## Consequences

### Positive
- Routine cert rotation (ACME ~90-day leaves) is fully invisible to clients —
  no forced updates, no user-facing disruption.
- Root transition has a built-in transition window via dual-root overlap; no
  instant deprecation of older app versions.
- No CA private key to safeguard (vs a private-CA model).
- Consistent with the existing backend decision (ADR-025 already uses LE/
  ACME).

### Negative
- Requires ops discipline: monitor Let's Encrypt root plans and proactively
  ship new roots before old-root retirement.
- fail-closed D4 means a root/pin mismatch is a total client outage, so old-
  root removal must lag client rollout (never remove before majority adoption).
- Remains dependent on the public CA ecosystem (Let's Encrypt); a LE-wide
  incident would affect us (mitigated by the X2 backup pin and, ultimately, by
  the dual-root pattern which also supports a private-CA fallback).

## Alternatives Considered

1. **Private Prod-CA (scaled dev model):** own root in `prod/ca.pem`. Rejected
   (for now) as primary because it requires a full CA lifecycle process (HSM
   for the CA key, CRL/OCSP, compromise-response plan) and we would hold a
   high-value CA key. The dual-root pattern in this ADR is agnostic and would
   apply equally if we later move to a private CA.
2. **Pin the leaf / leaf SPKI:** rejected — would force app updates on every
   rotation, exactly the scenario we want to avoid.
3. **Allow system roots (`withTrustedRoots: true`):** rejected by D4
   (`frontend-flutter/AGENTS.md` §5) — would let a compromised device/system
   trust store MITM the client. We keep `withTrustedRoots: false` and bundle
   the root.

## Notes

- **Operational runbook / CI gate (follow-up):** add a CI job — analogous to
  the OpenAPI drift check — that verifies (a) `assets/certs/prod/ca.pem`
  contains the current LE root(s) and (b) the backend's served leaf chains to
  one of them; alert on Let's Encrypt root-rotation announcements. This is the
  concrete control that keeps the fail-closed risk bounded.
- **Placeholder replacement (follow-up):** filling `prod/ca.pem` with
  ISRG X1 + X2 is a separate change, not part of issue #313 / PR #316.
- This ADR is the **client-side counterpart** to ADR-025: ADR-025 covers
  server-edge issuance/rotation; this ADR covers client pinning and app
  re-delivery.
- **Doc discrepancy to fix:** `frontend-flutter/AGENTS.md` §5 cites
  "ADR-024 (pinned-CA stance)", but in this store ADR-024 is "Database
  Encryption in Transit". The pinned-CA client stance is actually realized in
  `frontend-flutter/lib/src/network/api_client.dart` (D4,
  `withTrustedRoots: false`); the AGENTS.md cross-reference should be corrected
  (and this ADR linked) in a follow-up doc edit.
