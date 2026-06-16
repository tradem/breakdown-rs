# Breakdown RS - Architecture Documentation

This directory contains the architecture documentation for Breakdown RS, following the [arc42](https://arc42.org/) template.

## Structure

```
arc42/
├── 01-introduction/       # Chapter 1: Introduction and Goals
├── 02-constraints/        # Chapter 2: Constraints
├── 03-context/           # Chapter 3: Context and Scope
├── 04-solution-strategy/  # Chapter 4: Solution Strategy
├── 05-building-blocks/   # Chapter 5: Building Block View
├── 06-runtime/           # Chapter 6: Runtime View
├── 07-deployment/        # Chapter 7: Deployment View
├── 08-crosscutting/      # Chapter 8: Cross-cutting Concepts
├── 09-decisions/         # Chapter 9: Architecture Decisions
├── 10-quality/           # Chapter 10: Quality Requirements
├── 11-risks/             # Chapter 11: Risks and Technical Debt
└── 12-glossary/         # Chapter 12: Glossary
```

## Format

The documentation will be written in **AsciiDoc** (`.adoc`) for better tooling support:
- Includes and cross-references
- Diagram support (PlantUML, Mermaid)
- Professional PDF/HTML output

## Getting Started

To build the documentation (once content is added):

```bash
# Install Asciidoctor
gem install asciidoctor asciidoctor-pdf asciidoctor-diagram

# Build HTML
asciidoctor arc42/master.adoc -o dist/architecture.html

# Build PDF
asciidoctor-pdf arc42/master.adoc -o dist/architecture.pdf
```

## Current Status

✅ **ADRs created** (see `../adrs/`):
- ADR-001: Hexagonal Architecture
- ADR-002: Event Sourcing and CQRS

⏳ **arc42 documentation**: Structure created, content pending

## Next Steps

1. Start with **Chapter 4: Solution Strategy** (describes the big picture)
2. Fill in **Chapter 5: Building Block View** (describe crates and modules)
3. Add **Chapter 6: Runtime View** (describe how Event Sourcing flows work)

## Resources

- [arc42 Template](https://arc42.org/template/)
- [arc42 in AsciiDoc](https://github.com/arc42/arc42-asciidoc)
- [C4 Model](https://c4model.com/) for system context diagrams

---

**Note**: This is a living document. Update it as the architecture evolves.
