<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 805 — Tasks

## 1. Backend: the blocking run's age and the window on the 409

- [x] 1.1 `core/error_registry.rs`: `AI_IMPORT_APPLY_IN_FLIGHT` declares
      `apply_run_age_seconds` + `stale_after_seconds`; the doc comment says
      what the client may conclude from each.
- [x] 1.2 `api/problems/mod.rs`: `ApiError::AiImportApplyInFlight
      { age_seconds: Option<u64>, stale_after_seconds: u64 }` renders both
      declared extensions (the age only when the owner published a payload).
- [x] 1.3 `api/handlers/mod.rs`: `apply_ai_import` catches the claim conflict
      (`DomainError::Conflict` with the in-flight code), reads the run slot
      (`apply_run_state`) for the owner's last publication, and answers
      `ApplyProgress::STALE_AFTER` as the window — never a second constant.
- [x] 1.4 API tests: a live claim yields 409 + both extensions (age ≈ held
      payload's age, window = 600 s); a claim without a payload carries no
      `apply_run_age_seconds`.
- [x] 1.5 Regenerate `backend/openapi.yaml`
      (`UPDATE_OPENAPI=1 cargo test -p api --test contract openapi_drift`).

## 2. Client data layer: classify the refusal

- [x] 2.1 `applyInFlightInfo(ProblemError)` → `ApplyInFlightWindow
      { age, staleAfter }` (`null` for another code or a missing window).
- [x] 2.2 `ApplyInFlight` outcome (`error`, `age`, `staleAfter`) on
      `ApplyReconciliation`.
- [x] 2.3 `applyWithReconciliation`: dead (or un-ageable-but-past-window)
      refusal → stop and return `ApplyInFlight`; live refusal → keep the
      bounded budget and report a live exhaustion as `ApplyInFlight`; no
      extensions → unchanged pre-#805 wait.

## 3. Client UI: say which one it is, and offer the way out

- [x] 3.1 `AiApplyState.applyInFlight` (clock-stamped observation, so the age
      keeps growing while the card is open) + `copyWith` slot.
- [x] 3.2 `AiApplyController.apply` maps the outcome; success/blocked/unresolved
      clear it.
- [x] 3.3 Apply card: live copy + takeover countdown; dead copy + explicit
      "take over now" button that re-dispatches (same AUTHZ-GATE'd path).
- [x] 3.4 ARB de/en keys + `flutter gen-l10n`; no hardcoded copy.

## 4. Tests

- [x] 4.1 Unit: extension parser (present / missing / no extensions).
- [x] 4.2 Unit: loop — live budget exhaustion → `ApplyInFlight`; dead →
      immediate `ApplyInFlight`, one request only; no extensions → old wait.
- [x] 4.3 Widget: dead-run card + takeover dispatches; live run still blocks
      (no takeover button, countdown copy).

## 5. Docs

- [x] 5.1 `docs/design/screens/ai-import-jobs.md`: the blocked-run section.
- [x] 5.2 CHANGELOG entries (`core`, `api`, `frontend-flutter`).

## 6. Review follow-ups (PR #862)

- [x] 6.1 The reconciliation loop re-checks the locally aged refusal AFTER each
      backoff and stops before a dispatch would cross the window (waiting is not
      consent); `onAttempt` is not fired for a dispatch that does not happen.
- [x] 6.2 Strict stale boundary on BOTH sides of the wire contract: the client
      treats `age > window` as abandoned (`age == window` stays live), matching
      the claim's `payload.updated_at < now - STALE_AFTER`.
- [x] 6.3 An ambiguous timeout discards the remembered refusal, so a budget that
      ends on an unknown outcome reports `ApplyUnresolved`, not a live-run card.
- [x] 6.4 New "unaged" card state (no fabricated age, no countdown, apply stays
      available) for a refusal that carries no `apply_run_age_seconds`.
- [x] 6.5 The notice clears on the apply-run stream's end frame
      (`AiApplyRunFinished`) — never on `AiApplyRunIdle`, which proves nothing.
- [x] 6.6 Takeover obeys the normal apply preconditions (review acknowledgement,
      resolved target) and `mounted` is re-checked before the post-apply routing.
- [x] 6.7 Backend age assertion is bounded ANALYTICALLY from the payload stamp and
      the request window, so no wall-clock guess can break it.
- [x] 6.8 A progress frame from the apply-run stream re-anchors the stored notice
      (arrival-based, no cross-clock comparison), so a publishing run is never
      labelled abandoned by an older countdown; widget test drives the frame.

