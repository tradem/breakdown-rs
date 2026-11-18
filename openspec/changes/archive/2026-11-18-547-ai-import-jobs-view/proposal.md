<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# 547 — `aiImportJobsView`: a started AI-import job stays reachable

## Why

Once an AI-import job is started, leaving the job-status screen loses it
permanently: there is no list, no deep link, and no route back to a running
job. Every layer below the UI already exists and is unused —
`GET /v1/ai-import/jobs` (registered backend route), the generated
`HandlersApi.listAiImportJobs`, `AiImportRepository.listJobsAndCache()`
(**zero production call sites**), the identity-scoped
`AiImportJobsCacheDao`, the `AiImportHandoffState.jobIds` fast path
(`rememberJob`/`forgetJob` — **zero callers**), and the complete
`jobStatus*`/`jobWatch*`/`aiJob*` localization catalog.

The sharpest consequence is a **silent dead-letter**: a job that ends in
`dead_letter` or `payload_unavailable` after the user left the status screen
can never be learned about — all three terminal-failure copies only ever
rendered on the screen the user already left. This is an operational hole,
not a navigation annoyance.

## Decision

Ship a **shared cache-then-revalidate jobs controller** and two thin
consumers of it:

1. **`AiImportJobsViewController` + `aiImportJobsView` selector**
   (`lib/features/ai_import/import_jobs/jobs_controller.dart`) — the
   seasons/blocks seam shape: cache-first paint (`readCached(sub)`, already
   identity-scoped), revalidation through `listJobsAndCache()` (server-
   authoritative, newest-first), retained last-good snapshot, `Result`-typed
   throughout, `Err` → `AsyncError` with copy keyed on the stable `code`.
   **No watch** — the list renders cached status and arms nothing; the
   single foreground watch stays owned by `AiJobStatusScreen`.
2. **`AiImportJobsScreen`** (`jobs_screen.dart`) — newest-first list; rows
   show document kind + created date + the localized status (all six,
   including `dead_letter`/`payload_unavailable`), the retry budget for the
   retryable `failed` state, and a `last_error` presence indicator. Row tap
   pushes the existing `AiJobStatusScreen(jobId)` — the screen that owns the
   single watch. Pull-to-refresh hits the list route.
3. **Planen-tab summary row** — a single row above the season list while any
   known job needs attention (any non-`succeeded` status). It reads the
   controller's state and pushes the jobs screen; it never arms a watch.

### The `jobIds` fast path: wire it (user-approved)

`AiImportHandoffStore.jobIds` is wired, not deleted (the decision the issue
left explicit; confirmed by the user in this session):

- `AiImportSubmitController.submit` calls `rememberJob(sub, jobId)` after the
  upload acknowledgement (best-effort — a storage fault never hides a created
  job; the ack survives, mirroring the context-stamp discipline).
- After a successful list fetch, the jobs controller calls `forgetJob` for
  every remembered id the authoritative list no longer returns — the method
  exists precisely for this and had no caller.

### Hard constraints honoured

- **At most ONE active watch (D5):** the list controller arms no watch (a
  unit test pins the fake-repository watch-call count at zero). Tapping a row
  opens the status screen, which re-arms the watch it already owns; leaving
  it disposes it.
- **No fabricated progress:** `AiImportJob` carries `retries`/`max_retries`,
  never a percentage — rows show a status, `aiJobRetryBudget` for `failed`.
- **AUTHZ-GATE unchanged:** the Planen-tab AI-import entry keeps its
  block-scope gate (`import_submit_controller.dart`). The jobs list route is
  ownership-scoped server-side; the client resolves the authenticated session
  before the call (no session → no request) and denials route through the
  code-keyed copy (`jobWatchForbidden` / `aiJobsLoadError`), never `detail`.
- **CQRS boundary:** the summary row and the list render the projection DTOs
  the user is acting on; no command context is re-derived from a second
  projection lookup.

### Deliberate scope readings (recorded for review)

- The per-row `aiJobReviewPreview` / `aiJobCheckAgain` affordances stay on
  `AiJobStatusScreen` (which owns the watch and the preview path). A list row
  is a navigation target, never a dispatch surface — a row-level "check
  again" would either duplicate the re-arm seam or poll per row, both
  D5 regressions. Terminal-failure rows are visibly distinct (error-colored
  status icon + status copy + `last_error` indicator) and one tap away from
  the affordances.
- "Unseen" tracking for the summary row is simplified to
  "any non-`succeeded` job": a `dead_letter` job keeps the row visible until
  it is replaced — honest and persistent, with no extra seen-state to
  persist. The acceptance criterion ("summary row while a job is
  non-terminal") is met and exceeded for the terminal-failure case that
  motivates the issue.
- Tier-4 integration is not added: the tier-2 widget tests cover the
  return-path flow with a mocked API; a device smoke test is recorded as a
  possible follow-up, not a gate (issue Tests section marks it optional).

## Non-goals

- No cancel, no manual retry trigger (no `DELETE` route; retries are
  server-side `retries`/`max_retries`).
- No live dashboard, no per-row polling, no background execution (D5 stands).
- No push/local notifications.
- No import-history diffing (apply-side reporting).
- No `backend/openapi.yaml` change — the route exists; the generated client
  is untouched (no `vendor/breakdown_api` regen).
