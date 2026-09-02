<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Tasks: AI Import

## 1. Data layer
- [ ] 1.1 `data/ai_config_repository.dart` — providers/models lists,
       credential submission (`POST /v1/settings/credentials` →
       `IdVersionResponse`) + `vault_key_id` hand-off read
       (`GET /v1/settings/{id}` → `SettingsView`), config
       create/get/update/revoke (Result-typed; version echo on
       update/revoke), and the rollback path (`DELETE
       /v1/settings/{id}` + `VersionRequest`, bounded retry, orphaned-
       credential surfacing) — all `/v1`-prefixed routes only
- [ ] 1.2 `data/ai_import_repository.dart` — raw-body `uploadSchedule`
       / `uploadScript` (declared content-type; 200-duplicate vs 202
       branching), `getJob`, `getPreview`, `apply`. The ambiguous-
       timeout path reconciles by re-reading the config/settings
       before any credential cleanup (never delete a credential that
       a committed config may reference). NOTE: server-side apply
       idempotency is tracked in backend issue #338 — until it lands,
       the client MUST NOT auto-retry an apply whose outcome is
       unknown; it surfaces the reconcile state instead
- [ ] 1.3 Secure-storage `ai_config_id` + recent-`job_ids` hand-off
       store (bounded N) — **keyed by the authenticated `sub`** and
       cleared by the Phase 1a sign-out reset; unit test asserts the
       user A → B switch exposes no state of A
- [ ] 1.4 Drift `ai_import_jobs` table + migration; repository
       cache-write discipline (success only, snapshot rules)
- [ ] 1.5 Unit tests: every route Ok/Err (incl. 200/202/413/415/404/
       403); secret-in-payload-only assertion covering ALL sinks on
       both success and failure — persistent store writes
       (interception), cache/Drift writes, and logger/telemetry
       output (capturing sink) — plus the hand-off store round-trip.
       gitleaks is a repo-wide CI control, NOT runtime evidence: it is
       not cited as the proof for these assertions

## 2. Configuration feature
- [ ] 2.1 `features/ai_import/ai_config/` — first-run → provider →
       models → masked key → create; edit with version echo; revoke
       with confirm; 403 credential-role narrative (documented
       no-pre-gate exception)
- [ ] 2.2 Widget tests + goldens (light/dark × android/macos):
       first-run/edit/denied/conflict states; masked-key field
       semantics

## 3. Submission + status feature
- [ ] 3.1 `features/ai_import/import_jobs/import_submit_screen.dart`
       — kind picker (schedule CSV/PDF/plain, script PDF), paste
       field, `file_picker`, upload with linear progress; duplicate
       callout branch (D-flow)
- [ ] 3.2 `job_status_screen.dart` + `jobRepository.watch(jobId)`
       — bounded backoff, foreground-only, terminal stop; status
       matrix UI (pending/running indeterminate, failed retryable,
       terminal error cards); honest "no cancel route" copy
- [ ] 3.3 Unit tests: watch state machine (fake scheduler; terminal
       + unsubscribe stop; no wall-clock gating)
- [ ] 3.4 Widget tests + goldens: all six statuses, duplicate
       callout, 413/415/403/404 copy

## 4. Preview + apply feature
- [ ] 4.1 `preview_screen.dart` + `PreviewRowAdapter` —
       runtime-validated rows, degraded unrecognized-row cards,
       404-empty state
- [ ] 4.2 `apply_controller.dart` — mapping request builder (Create /
       Update-from-picked-DTO / skip; verbatim `draft_ref`s), episode
       context **persisted with the job** (not read from the
       navigation stack; explicit episode picker when the persisted
       context is missing), `accept_as_is` + `edit_distance` from real
       selection state; outcome summary card + deep navigation
- [ ] 4.3 Unit tests: adapter (recognized/unrecognized/empty);
       mapping builder; apply round-trip against a fake; episode
       context for fresh-job AND remembered-job entry (incl. the
       missing-context → picker-required path)
- [ ] 4.4 Widget tests + goldens: preview cards, degraded rows,
       apply summary, 409/403 branches

## 5. AUTHZ-GATE seam
- [ ] 5.1 Uploads pre-gated via the Phase 2 capability gate
       (`// AUTHZ-GATE:` annotated); config screens session-only
       (documented exception, no capability surface)
- [ ] 5.2 Unit test: denial short-circuit — fake repository call
       count of zero

## 6. Integration + housekeeping
- [ ] 6.1 Integration smoke (emulator, repository-seamed fake
       pipeline): submit → job → preview → apply → summary;
       deterministic (no network LLM in CI)
- [ ] 6.2 Entry point: seasons toolbar "AI import" action
- [ ] 6.3 SPDX headers; format/analyze/breakdown_lints clean;
       coverage + coverde gate; gitleaks (confirms no secret material
       — masked input, stored id only)
- [ ] 6.4 `openspec` coverage audit: every scenario in
       `flutter-ai-config` and `flutter-ai-import-workflow` has a
       passing test
