<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gpt-5.6-luna (opencode-go) -->

# ADR-030: AI Import Bounded Context

**Status**: Accepted
**Date**: 2026-08-02
**Author**: Tobias Rademacher (@tradem)
**Reference**: OpenSpec change `add-ai-script-and-schedule-import`

## Context

Script and shooting-schedule documents are sensitive, asynchronous inputs. The
system needs provider selection, bounded cost, human review, deterministic
merge semantics, and safe retry behavior without coupling the write side to
read projections.

## Decisions

A. **Operational jobs, not aggregates.** Script, schedule, and merge work live
   in the dedicated `ai_import` PostgreSQL schema. The queue is not business
   truth and emits no domain events.

B. **Preview before apply.** LLM output is stored as a reviewable static DTO.
   Applying a preview dispatches existing validated commands only.

C. **Curated providers.** `LlmProvider` is non-exhaustive and contains OpenAI, OpenRouter, EURouter, and Ollama. OpenRouter and EURouter are
   separate providers with separate hardcoded base URLs in infra; users cannot
   provide arbitrary URLs.

D. **Static constrained output.** Infra derives the provider JSON schema from
   a static schema mirror and sends it using `response_format`. Ollama falls
   back to JSON mode with bounded parse retries.

E. **Bounds and resilience.** Chunk count, request tokens, document size,
   global concurrency, per-user concurrency, and retries are bounded. 429,
   5xx, and timeouts are transient; 4xx responses are permanent failures.

F. **Derived merge.** Schedule rows join applied scenes by scene number. The
   merge is deterministic, zero-token, replayable, and blocked until scenes
   exist.

G. **Hard ordering.** A block's script must be applied before schedule merge
   and schedule-side apply.

H. **User-driven idempotency mapping.** Each preview row is explicitly chosen
   as new or update-existing. `projection_ai_import_mapping` is checked before
   every dispatch and written with a version guard.

I. **Uncertainty gate and telemetry.** The model must leave unreadable values
   null and report an uncertainty with an optional marked suggestion. Open
   uncertainties and unmatched merge rows block apply. Telemetry stores only
   counts and metadata (`accept_as_is`, `edit_distance`), never script text.

## Consequences

The AI context can be disabled with `AI_IMPORT_ENABLED` without changing
existing aggregates. Provider credentials remain in the shared
`CredentialVault`; `AiConfig` stores only an opaque vault binding. The review
boundary protects production state from non-deterministic model output, while
explicit mappings make crash retries safe.
