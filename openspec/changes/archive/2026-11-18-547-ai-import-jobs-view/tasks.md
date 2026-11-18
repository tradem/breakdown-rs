<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# Tasks — `aiImportJobsView` (issue #547)

## 1. Controller (`lib/features/ai_import/import_jobs/jobs_controller.dart`)

- [x] **1.1 `aiImportJobsFetch` seam** — `@riverpod` async provider over
      `AiImportRepository.listJobsAndCache()` (the wiring gap closes here);
      resolves the authenticated session BEFORE the call (no session → no
      request, `authz.denied`); tests override the provider.
- [x] **1.2 `AiImportJobsPrevRows`** retained snapshot store (keepAlive
      Notifier, seasons/blocks pattern).
- [x] **1.3 `AiImportJobsViewController`** — cache-first seed
      (`readCached(sub)`, identity-scoped), then revalidate via the fetch
      seam; `Result`-mapped to `AsyncValue`; retained snapshot converges on
      every success (including empty); no watch.
- [x] **1.4 `aiImportJobsView` selector + `AiImportJobsState`** — rows /
      isStale / error resolved from the controller with the retained
      snapshot fallback (loading + error never blank the list).
- [x] **1.5 `jobIds` reconciliation** — `missingRememberedIds` pure helper;
      after a successful list fetch, `forgetJob` for remembered ids the list
      no longer returns (best-effort).
- [x] **1.6 `aiJobsListErrorCopy`** — code-keyed list-error copy
      (`ai-import.forbidden` → `jobWatchForbidden`, `ai-import.not-found`,
      transport arms, `aiJobsLoadError({code})` fallback; never `detail`).

## 2. Screen (`lib/features/ai_import/import_jobs/jobs_screen.dart`)

- [x] **2.1 `AiImportJobsScreen`** — states: loading skeleton, empty
      (`aiJobsEmpty` + `aiJobsEmptyCta` → submit screen), data, error per
      `code` (with retry via the list refresh), pull-to-refresh = list
      route. `// AUTHZ-GATE:` comment on the entry (server-authoritative,
      session-resolved fetch seam).
- [x] **2.2 `_JobRow`** — kind label (`aiImportSchedule`/`aiImportScript`) +
      created date (`aiJobsRowSubtitle`), status label (`jobStatusCopy`, all
      six), retry budget for `failed` (`aiJobRetryBudget`), `last_error`
      presence indicator, status icon per `JobStatus` (text stays visible —
      glossary rule). Tap → `AiJobStatusScreen(jobId)`; the row never
      dispatches.

## 3. Planen tab

- [x] **3.1 Summary row** in `planning_tab_screen.dart` — visible while any
      known job is non-`succeeded` (`hourglass_top` + `planningActiveJobRow`
      label); pushes `AiImportJobsScreen`; reads the controller's state,
      arms no watch.

## 4. `jobIds` wiring

- [x] **4.1 `AiImportSubmitController.submit`** — `rememberJob(sub, jobId)`
      after the upload ack (best-effort; a hand-off fault never hides the
      ack).

## 5. Localization

- [x] **5.1 New ARB keys (de template + en, parity):** `aiJobsTitle`,
      `aiJobsEmpty`, `aiJobsEmptyCta`, `aiJobsActiveBadge`,
      `aiJobsRowSubtitle`, `planningActiveJobRow`, `aiJobsLoadError`.
      Reuse: `jobStatus*` (six), `jobWatch*`, `aiJobRetryBudget`,
      `aiJobCheckAgain`, `aiImportSchedule`, `aiImportScript`,
      `aiImportTitle`. `flutter gen-l10n`; generated output committed;
      `l10n-untranslated.json` stays `{}`.

## 6. Design docs (AGENTS.md §11 — same change)

- [x] **6.1 `docs/design/screens/ai-import-jobs.md`** — full screen spec
      (template sections) + Salt wireframes (compact + expanded); static
      layout only.
- [x] **6.2 `docs/design/glossary.md`** — glossary rows for the new labels
      and the per-status icons (`hourglass_top`, `autorenew`,
      `check_circle_outline`, `error_outline`, `block`, `cloud_off`);
      implemented-inventory row extended with the new ARB keys.
- [x] **6.3 `scripts/check-design-diagrams.sh` green.**

## 7. Tests

- [x] **7.1 Unit (tier 1):** `rowViewFromJob` mapping (unknown future
      status degrades, never guesses); `missingRememberedIds`; status label
      matrix incl. `dead_letter`/`payload_unavailable`; `aiJobsListErrorCopy`
      per code; **the list controller arms no watch** (fake-repository watch
      counter stays 0); cache-then-revalidate ordering (cached rows paint
      before the fetch resolves; fetch replaces them; a failed fetch keeps
      the retained rows with the error).
- [x] **7.2 Widget (tier 2):** rows render kind + date + status text +
      icon; tap pushes the status screen; empty state + CTA; error state per
      code; Planen summary row visible for non-terminal jobs, hidden when
      all succeeded, tap opens the list; semantic finders only.
- [x] **7.3 Goldens:** jobs list {light,dark}×{android,macos}; the existing
      `ai_job_status_*` goldens stay valid.
- [x] **7.4 Submit flow:** `rememberJob` is called on creation (handoff
      store contains the acked id after submit); a hand-off write failure is
      non-fatal.

## 8. Release hygiene

- [x] **8.1 Version bump** `0.3.0-alpha.32+42 → 0.3.0-alpha.33+43` +
      CHANGELOG entry.
- [x] **8.2 Gates:** `dart format --set-exit-if-changed`, `flutter analyze`,
      `breakdown_lints` runner, `flutter test`, `flutter gen-l10n` +
      parity, gitleaks-clean, `check_glossary_catalog.py`,
      `check_inline_copy.sh`, `check-design-diagrams.sh`.
