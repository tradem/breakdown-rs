<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

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
- [ ] 4.1 Optimistic insert on command acknowledgement
- [ ] 4.2 Bounded-retry refetch; on timeout retain optimistic + stale flag
- [ ] 4.3 Pull-to-refresh

## 5. Tests
- [ ] 5.1 Unit: mapper, repository Ok + Err branches
- [ ] 5.2 Widget test + golden for `SeasonsScreen`
- [ ] 5.3 integration_test smoke against a mocked API

## 6. Pattern documentation
- [ ] 6.1 Note in `AGENTS.md` §9 that this screen is the reference pattern
       (already in `design.md`; verify)
