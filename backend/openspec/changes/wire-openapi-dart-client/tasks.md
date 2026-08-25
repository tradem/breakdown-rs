<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## 1. Generator wiring
- [ ] 1.1 `frontend-flutter/scripts/regen-client.sh` running
       `openapi-generator-cli generate -i ../backend/openapi.yaml -g dart -o
       lib/api/generated --additional-properties=pubName=breakdown_api`
- [ ] 1.2 `// GENERATED — do not edit` banner added via generator template
- [ ] 1.3 Document regen procedure in `frontend-flutter/AGENTS.md` (§3 is
       already written; add the concrete script invocation)

## 2. First generated client
- [ ] 2.1 Run `regen-client.sh` against the current `backend/openapi.yaml`
- [ ] 2.2 Commit `lib/api/generated/` (formatting stable enough to diff in CI)
- [ ] 2.3 Verify generated types compile against the scaffold (`flutter
       analyze` clean)

## 3. Repository wrappers
- [ ] 3.1 `data/` repository per aggregate boundary (seasons, costumes,
       scenes, shooting_days, scene_shoots, characters, costume_categories,
       photos) wrapping the generated client
- [ ] 3.2 Each repo returns `Result<Dto, ProblemError>` — never raw `http`
       types, never throws
- [ ] 3.3 Map RFC 9457 problem+json responses into `ProblemError(code, ...)`,
       branching surfaces the stable `code` (never `detail` text)

## 4. CI drift check
- [ ] 4.1 Enable the deferred drift step in `flutter-ci.yml`
- [ ] 4.2 Scenario: spec changed, client not regenerated → CI fails with
       regenerate instruction
- [ ] 4.3 Scenario: hand-edit to `lib/api/generated/` → CI fails
