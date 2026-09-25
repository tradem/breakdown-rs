<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

# Proposal: AI-import provider replacement with retained credentials (issue #528)

## Summary

Allow a configured AI-import to switch providers without re-entering a
credential that was already supplied for another provider. The backend permits
a provider change only when the request carries a different vault key, keeping
the provider/vault binding invariant intact. The Flutter client performs the
safe hand-off and remembers the resulting Settings reference per provider in
its existing per-user secure hand-off document.

## Decisions

- `UpdateAiConfig` keeps rejecting a provider change paired with the current
  vault key, but accepts a provider change paired with a different vault key.
  This is the minimal backend contract change; the existing request and response
  shapes remain unchanged.
- The client uses a two-phase hand-off: resolve an already remembered credential
  for the selected provider, or submit a new provider-bound credential and
  resolve its opaque vault key, then PATCH the AI configuration. The previous
  credential is never revoked, so rollback and retry remain safe.
- The hand-off document stores only the opaque Settings id/version and vault-key
  reference for each provider, never the API secret. A replacement reuses a
  remembered reference and never asks for the secret again. A newly created
  credential is retained even when the subsequent config PATCH fails, allowing
  a later retry without re-entry.
- An ambiguous PATCH response is reconciled by reading the config. A config
  carrying the new provider/vault pair is committed; otherwise the new
  credential remains retained and the original command error is surfaced. No
  credential is destroyed during provider replacement.
- The configured form enables the provider picker, shows a masked credential
  field only when no remembered credential exists for the selected provider, and
  keeps the existing model/prompt editing and optimistic version behavior.
- The PATCH handler pre-checks an INTRODUCED vault key against the
  reference-only settings projection: the key must be an active credential of
  the requested provider. The aggregate only ever sees the opaque key and
  cannot resolve its provider, and the read-model lookup stays at the API edge
  (the only legitimate projection consumer). Unknown, revoked, and
  foreign-provider keys all surface the existing scoped
  `ai-config.provider-mismatch` 409 — the same code the aggregate emits for the
  mirrored case (new provider + current key) — so the client branches on one
  stable code. An unchanged key is not re-validated, so a prompt/model-only
  edit cannot be blocked by a projection miss.

## Validation

- Core aggregate tests cover rejection of provider replacement with the old
  vault key and acceptance with a new key.
- API port tests cover a provider replacement request reaching the command port
  with the new provider and vault key, plus the provider-binding pre-check: a
  foreign-provider key, an unknown key, and an unchanged key (no re-validation)
  each prove the command is dispatched only for a valid provider/key pair.
- Flutter repository/unit tests cover per-provider hand-off persistence and
  reuse, including missing/empty secret paths.
- Flutter widget/wire tests cover provider selection, retained credentials
  avoiding a key prompt, new-credential submission, and PATCH failure behavior.

## Non-goals

- No API secret retrieval or server-side credential listing endpoint.
- No automatic revocation of old credentials; retaining them is intentional so
  switching back does not require re-entry.
- No changes to Drift or offline command behavior.
