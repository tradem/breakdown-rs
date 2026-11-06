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
