# Architecture Decision Records (ADRs)

This directory contains Architecture Decision Records for the Breakdown RS project.

## What are ADRs?

ADRs are short documents that capture important architectural decisions made along with their context and consequences.

## Format

Each ADR follows this format:
- **Title**: Short present tense description
- **Status**: Proposed | Accepted | Deprecated | Superseded
- **Context**: What is the issue we're facing?
- **Decision**: What have we decided to do?
- **Consequences**: What becomes easier or more difficult?

## List of ADRs

| ID | Title | Status | Date |
|----|-------|--------|------|
| [001](./ADR-001-hexagonal-architecture.md) | Use Hexagonal Architecture | Accepted | 2024-01-16 |
| [002](./ADR-002-event-sourcing-cqrs.md) | Use Event Sourcing and CQRS | Accepted | 2024-01-16 |

## Creating a New ADR

Use the template in `templates/ADR-template.md`:

```bash
cp templates/ADR-template.md adrs/ADR-$(printf "%03d" $(ls -1 adrs/ADR-*.md | wc -l | xargs -I {} expr {} + 1))-your-title.md
```

Or manually:
1. Copy `templates/ADR-template.md`
2. Name it `ADR-XXX-short-title.md` (use next available number)
3. Fill in the sections
4. Update this README with the new ADR

## Tools

- [adr-tools](https://github.com/npryce/adr-tools) - CLI tool for managing ADRs
- [adr-log](https://github.com/maroun-baydoun/adr-log) - Generate ADR index

## Resources

- [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) by Michael Nygard
- [ADR GitHub Organization](https://github.com/adr)
