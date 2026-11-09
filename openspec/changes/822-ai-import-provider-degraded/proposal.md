<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 822 — A degraded LLM provider reads as a degraded LLM provider

## Why

Observed live (2026-11-04): a 42-chunk script import sat at chunk 25 while three
consecutive provider 503s, ~17 minutes apart, wrote three identical history rows
— each rendered as "a service was temporarily unreachable — the next attempt may
succeed" (`aiJobReasonServiceUnavailable`). The reviewer therefore read a
repeated, upstream, wait-it-out condition as three unrelated one-off blips, and
nothing named *which* dependency had failed.

Two independent defects produce that reading:

1. **No attribution.** `domain.service-unavailable` is emitted by the LLM chat
   client (`infra/src/ai/client.rs`: `classify_http_status_with_detail` for
   HTTP 429/5xx, `classify_transport_error` for timeout/connect) **and** by the
   mapping DB (`mapping.rs`), the pricing read model (`pricing.rs`), the model
   catalog (`catalog.rs`) and payload storage. The attempt row's only stable
   signal is that shared `code`, so a client that refuses to parse `last_error`
   (AGENTS.md §5) cannot honestly say "the AI provider".
2. **No aggregation.** Every surface renders per attempt. The job-status card
   shows the newest attempt's reason, the jobs row shows the retry budget; no
   component concludes "the provider is down right now, this is not your
   document, and the next attempt is at 07:10".

A third, smaller defect rides along: a job whose retry budget is **spent**
(`dead_letter`) renders the per-attempt narrative through
`jobStatusTerminalError` → `aiJobFailureReason`, so its terminal card still
promises "the next attempt may succeed" — a promise the state cannot keep.

## What changes

### Backend (attribution + list-read parity)

- New registered problem code **`ai-import.llm-provider-unavailable`**
  (503, retryable), emitted **only** by the LLM chat-client classifiers. It reuses
  the existing `DomainError::ServiceUnavailable` shape, whose `code` field is
  already the variant's own registry entry — so retryability, the 503 status and
  the `mark_failed`/attempt persistence path are unchanged; only the recorded
  `attempts[].code` and `last_error` prefix change.
- Every non-provider dependency keeps `domain.service-unavailable`: the mapping
  DB, the pricing read model, payload storage, and the catalog's own
  parse/client-policy/DNS classifications. The catalog's and Ollama's *provider
  HTTP/transport* faults do inherit the new code, because they literally are
  provider failures (both call the same two classifiers) — the attribution is a
  property of the failure, not of the surface that reports it. No attempt row
  carries a catalog failure, so the client aggregate is unaffected either way;
  the AI-config screen keeps its own reachability seam (#809).
- `AiImportQueue::list_for_user` populates `attempts` with the newest attempts of
  each job (one batch windowed query per page, no N+1), so the jobs **list** can
  derive the same aggregate as the single-job read instead of guessing from
  `last_error`. The field already exists on the wire (`serde(default)`), so this
  is a read-path change, not a contract change.

### Client (aggregate + terminal honesty)

- One pure derivation, `aiProviderDegradation`, over the job's own history: the
  **consecutive newest** attempts whose `code` is the provider code, firing at
  `>= 2`. It yields count, window (first → last failure), `nextAttemptAt` and
  whether the retry budget is spent.
- Job-status screen: a first-class **"AI provider degraded"** banner (provider
  named, attempt count, window, and the existing live `_NextRetryEta` for the
  next attempt) instead of only the per-attempt rows.
- Jobs row: the **compact** form of the same derivation, so the condition is
  visible without opening the status screen.
- `dead_letter` / `payload_unavailable` after provider failures: terminal copy
  that states the retry budget is spent and what the user can do — never "the
  next attempt may succeed".
- A single provider failure keeps the transient per-attempt narrative: the
  aggregate does not fire.

## Decisions recorded (issue acceptance criteria)

1. **Distinct problem code, not a `dependency` field.** A new registered code is
   the additive change: `attempts[].code` already exists and already is the
   client's only permitted error identity (#639), while a `dependency` field would
   need a migration, a new wire field and a Dart-client regeneration to answer a
   question the code registry already answers. Precedent: `dependency.auth-failed`
   (#637) separates a *permanent* dependency failure from the transient one with
   exactly this mechanism; this change does the same for the *attributed* one.
   Naming: the registry's context segment for this bounded context is `ai-import`
   (all 13 existing AI-import codes), so the entry is
   `ai-import.llm-provider-unavailable`; published codes are never renamed
   (ADR-021), so the issue text's `ai_import.*` spelling is not adopted.
2. **The upload screen does not pre-warn (deferred, not dropped).** There is no
   provider-health probe: `backendHealthProbeProvider` answers "is *our* backend
   reachable", and #816's `GET /v1/me/capabilities` is a different concern. A
   warning derived from the client's job cache would only see jobs this device
   listed — silent on exactly the cold-start case it exists for. The jobs list
   (always visible before a new upload) carries the compact degraded line instead;
   a real pre-warn needs a provider-health endpoint and its own change.

## Affected packages / artifacts

| Package / Artifact | Action | Reason |
|---|---|---|
| `core` | minor bump (`0.64.0 → 0.65.0`) | New registry entry + `DomainError::llm_provider_unavailable` constructor. |
| `infra` | minor bump (`0.74.0 → 0.75.0`) | LLM classifiers emit the new code; `list_for_user` populates `attempts`. |
| `api` | minor bump (`0.62.0 → 0.63.0`) | `x-code-registry` gains the entry (regenerated `backend/openapi.yaml`); Fluent bundles. |
| `breakdown_api` (Dart client) | regenerated | `openapi.yaml` changes (registry list + view doc comments). |
| `frontend-flutter` (`pubspec.yaml`) | bump `0.4.0-beta.44+136 → 0.4.0-beta.45+137` | New user-visible banner/compact line + terminal copy. |
| `frontend-flutter` ARB (`de`/`en`) | new keys | Provider narrative, degraded banner, terminal copy. |
| OpenSpec | new change `822-ai-import-provider-degraded` | Delta specs + tasks. |

## Non-goals

- A circuit breaker / fail-fast that pauses the worker instead of consuming the
  retry budget, and chunk-level resume so a retry does not re-extract from chunk 0
  (the cost multiplier the issue names) — both need their own spec.
- An upload-screen pre-warn (see decision 2).
- Re-attributing the catalog/mapping/pricing/storage failures; their generic code
  is correct and their surfaces key on it.
- Backfilling attempt codes: a pre-#822 attempt keeps
  `domain.service-unavailable` and therefore keeps the generic transient
  narrative. The aggregate is derived from what the wire actually says.
