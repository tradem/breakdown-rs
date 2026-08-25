<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## 1. Amend the ADR
- [ ] 1.1 Replace the `POST /api/v1/commands/{aggregate}/{action}` sketch in
       ADR-007 §"CQRS-Aware API Design" with the resource-REST reality
       (`POST /seasons`, `POST /costumes/{id}/assign`, …)
- [ ] 1.2 Add a "Supersedes sketch — see `flutter-openapi-client` spec" note
- [ ] 1.3 Mark the amended section per ADR-008 inline-amendment convention
       (date + author)

## 2. Cross-references
- [ ] 2.1 Update ADR-007 "Related ADRs" / "Next Steps" if they reference the
       stale sketch
- [ ] 2.2 Verify the foundation `design.md` §1 / `flutter-openapi-client`
       spec still agree with the amended ADR wording