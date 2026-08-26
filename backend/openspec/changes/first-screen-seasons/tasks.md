<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

## 1. Controller
- [ ] 1.1 `features/seasons/seasons_controller.dart` — `@riverpod`
       `SeasonsController` returning `AsyncValue<List<SeasonDto>>`
- [ ] 1.2 `create(name)` returns `Result<SeasonDto, ProblemError>`;
       Ok → optimistic insert, Err → propagated to widget

## 2. Repository
- [ ] 2.1 `SeasonsRepository` wrapping the generated client + Drift cache
- [ ] 2.2 `list()` → `Result<List<SeasonDto>, ProblemError>`
- [ ] 2.3 `create(cmd)` → `Result<SeasonDto, ProblemError>` (problem+json
       → `ProblemError(code)`)

## 3. Screen
- [ ] 3.1 `SeasonsScreen` `ConsumerWidget` (no StatefulWidget/setState)
- [ ] 3.2 AppBar, ListView, FAB → bottom-sheet Create Season form
- [ ] 3.3 AUTHZ-GATE on the FAB (hide if no create role)

## 4. Optimistic + lag reconciliation
- [ ] 4.1 Optimistic insert **after** `POST /v1/seasons` 2xx, as a
       controller-state overlay (NOT a Drift write) keyed by the server `id`
       (Design Decision D1/D2)
- [ ] 4.2 Bounded-retry refetch; on timeout retain the overlay with
       `stale = true` (overlay only, Drift untouched) + pull-to-refresh
       (Design Decision D2/D3)
- [ ] 4.3 Pull-to-refresh

## 5. Tests
- [ ] 5.1 Unit: mapper, repository Ok + Err branches
- [ ] 5.2 Widget test + golden for `SeasonsScreen`
- [ ] 5.3 integration_test smoke against a mocked API
- [ ] 5.4 Unit + widget: POST network/5xx failure → no overlay, Drift
       untouched, `AsyncError` keyed on `code` (Design Decision D3)
- [ ] 5.5 Unit + widget: `409` conflict → no overlay, optimistic reverted,
       error keyed on `code` (spec scenario)
- [ ] 5.6 Unit + widget: bounded-retry exhaustion → overlay retained
       `stale`, non-fatal warning + pull-to-refresh, Drift untouched
       (Design Decision D3)

## 6. Pattern documentation
- [ ] 6.1 Note in `AGENTS.md` §9 that this screen is the reference pattern
       (already in `design.md`; verify)

## Spec-hardening (issue #272) — design resolved
The PR #269 review asked where the optimistic row lives and for the
failure-path tests. Resolved in `proposal.md` (Design Decisions D1–D3) and
encoded as requirements in `specs/flutter-first-screen/spec.md`.
Implementation Tasks 1–6 remain open; the design gap is closed.
- [x] Optimistic-create flow defined (D1: insert only after `POST` 2xx with
      server `id`)
- [x] Optimistic row location defined (D2: controller-state overlay, NOT
      Drift; Drift holds only projected rows; reconcile by `id`)
- [x] Failure-path tests defined (D3: POST failure rollback, `409` rollback,
      bounded-retry exhaustion retains stale overlay) — see Tasks 5.4–5.6
