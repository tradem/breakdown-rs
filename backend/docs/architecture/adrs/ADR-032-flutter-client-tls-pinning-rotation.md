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
certificates (~90 days); the public ROOT (ISRG X1, with ISRG X2 as its ECDSA
counterpart) is stable for years.** Pinning the *root* (not the leaf) makes
leaf rotation invisible to the client. Root rotation is rare and can be
handled with a dual-root overlap (a built-in transition window). The
"immediate re-ship" scenario only arises if one pins the wrong thing (the
leaf).

Caveat (Generation Y): Let's Encrypt's *Generation Y* hierarchy (roots **ISRG
Root YR** and **ISRG Root YE**) entered production and now appears in
supported issuance profiles. LE cross-signs YR/YE under the Generation X roots
for compatibility, so the **default** chain still terminates at X1/X2 where
possible — but if we opt into a Gen Y chain, YR/YE must be in the bundle.
Because `withTrustedRoots: false` trusts *only* the bundled roots, a served
chain that terminates at an unbundled root fails closed. Therefore the bundle
MUST stay in lock-step with the edge's chosen ACME `preferred_chain` / profile
(see Decision 1 and 3).

Constraints:

- `withTrustedRoots: false` (D4) means we bundle the trust anchor; a pin/root
  mismatch is fail-closed → a total connection outage for affected clients.
  Therefore root rollover MUST ship to clients before the old root is retired.
- Android is the first target; macOS is explicitly later (`frontend-flutter/
  AGENTS.md`). Binary-integrity controls differ per platform but the pinning
  policy is shared.

## Decision

1. **Pin the public root, never the leaf.** `assets/certs/prod/ca.pem` SHALL
   contain the Let's Encrypt roots that the edge's served chain actually
   terminates at. For the current default LE chain this is **ISRG X1** plus
   **ISRG X2** (X1's ECDSA counterpart) as a backup trust anchor; if/when the
   edge opts into the **Generation Y** chain, **ISRG Root YR** and **ISRG Root
   YE** MUST be added to the bundle *before* the edge serves that chain.
   Bundling multiple PEM blocks in one file yields multiple trust anchors
   through the existing `SecurityContext.setTrustedCertificatesBytes` call — no
   client code change is required for backup/multi-root pinning. The exact set
   is pinned down by the edge's ACME `preferred_chain` / issuance profile
   (Decision 3), and the bundle is updated in lock-step with any chain change.
2. **Leaf rotation is transparent.** Because we pin the root, the backend's
   ACME leaf rotation (ADR-025) requires **no app update and no user action**.
3. **Root transition via dual-root overlap (transition window) with an explicit
   server-side compatibility path.** On a Let's Encrypt root change (X1 → X2,
   or Generation X → Generation Y), `prod/ca.pem` is updated to include the
   new root(s) while retaining the old, then shipped in a normal release.
   - **Server-side mechanism:** during the overlap the edge (Caddy) MUST keep
     serving a chain that terminates at a root present in the *currently
     shipped* app bundle(s) — i.e. retain the legacy/cross-signed
     `preferred_chain` until the cutoff. This guarantees X1-only (or Gen-X-
     only) clients already in the field can still validate.
   - **Cutoff & migration deadline:** the old root is removed from the bundle
     only after (a) the backend has switched the served chain to the new root
     **and** (b) a migration deadline has passed (e.g. ≥ N release cycles or ≥
     X% client adoption, recorded in the runbook). Until that cutoff, old
     clients remain able to validate the server.
   - **Rollback:** if adoption lags or incidents surface, the removed root is
     re-added to the bundle and the app re-released — no server binary change
     is needed because the legacy chain is still available at the edge.
   This gives users weeks/months, never an instant cut-over.
4. **Binary integrity is orthogonal to pinning.** APK integrity (Play App
   Signing, upload-key separation, APK Signature Scheme v3/v4, no debug keys in
   release) and macOS integrity (Developer ID + Notarization + Gatekeeper)
   protect the *binary*; TLS pinning protects the *channel*. A compromised
   signing key is mitigated by store integrity and key management, not by CA
   pinning.
5. **We hold no *internally managed* CA key — but public-CA misissuance risk
   remains.** Choosing a public CA (Modell A) means we never hold a CA private
   key, which removes only the risk of compromising an *internally held* CA
   key (an attacker could otherwise mint arbitrary leaves). It does **NOT**
   remove public-CA misissuance risk: with `withTrustedRoots: false` +
   `setTrustedCertificatesBytes`, the client trusts **every** certificate for
   our API hostname that chains to a bundled anchor — it does not pin the leaf
   or its SPKI. A leaf erroneously or maliciously issued for our domain (e.g.
   via a compromised ACME account key or DNS-01 control) therefore still
   validates. Residual risk is the ACME account key + DNS-01 control (vault per
   ADR-027, short-lived leaves) **plus** the need for an active incident
   response (see Notes) — re-issuing alone is insufficient.

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
  contains the current LE root(s) for the edge's `preferred_chain` / profile
  and (b) the backend's served leaf chains to one of them; alert on Let's
  Encrypt root-rotation announcements. This is the concrete control that keeps
  the fail-closed risk bounded.
- **ACME/DNS-01 incident response (not just re-issuance):** if the ACME
  account key or DNS-01 credentials are suspected compromised, the response is
  **not** limited to re-issuing the certificate. It MUST include: (1) rotate or
  deactivate the compromised DNS API credentials and/or ACME account key
  (account deactivation is irreversible — use only when contained); (2) revoke
  identified unauthorized certificates (reason `keyCompromise`) via the
  certificate's own private key; (3) sweep for and remove rogue
  `_acme-challenge` TXT records; (4) review the ACME issuance log for
  unauthorized orders. Re-issuing a clean leaf is necessary but does not revoke
  attacker-issued certificates nor stop further issuance on its own.
- **Placeholder replacement (follow-up):** filling `prod/ca.pem` with the
  current default LE roots (ISRG X1 + X2; YR/YE if the Gen Y chain is chosen)
  is a separate change, not part of issue #313 / PR #316.
- This ADR is the **client-side counterpart** to ADR-025: ADR-025 covers
  server-edge issuance/rotation; this ADR covers client pinning and app
  re-delivery.
- **Doc discrepancy to fix:** `frontend-flutter/AGENTS.md` §5 cites
  "ADR-024 (pinned-CA stance)", but in this store ADR-024 is "Database
  Encryption in Transit". The pinned-CA client stance is actually realized in
  `frontend-flutter/lib/src/network/api_client.dart` (D4,
  `withTrustedRoots: false`); the AGENTS.md cross-reference should be corrected
  (and this ADR linked) in a follow-up doc edit.
