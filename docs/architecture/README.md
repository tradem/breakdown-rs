# Architecture Documentation

This directory contains the architecture documentation for Breakdown RS.

## Structure

```
architecture/
├── adrs/              # Architecture Decision Records (Markdown)
│   ├── README.md
│   ├── templates/
│   ├── ADR-001-hexagonal-architecture.md
│   └── ADR-002-event-sourcing-cqrs.md
│
└── arc42/             # arc42 Architecture Documentation (AsciiDoc)
    ├── master.adoc    # Main document (includes all chapters)
    ├── 01-introduction-and-goals/
    ├── 02-architecture-constraints/
    ├── 03-system-scope-context/
    ├── 04-solution-strategy/
    ├── 05-building-block-view/
    ├── 06-runtime-view/
    ├── 07-deployment-view/
    ├── 08-crosscutting-concepts/
    ├── 09-architecture-decisions/
    ├── 10-quality-requirements/
    ├── 11-risks-technical-debt/
    └── 12-glossary/
```

## Getting Started

### ADRs (Ready to use ✅)
Navigate to `adrs/` and read the existing ADRs. To create a new ADR:

```bash
cp adrs/templates/ADR-template.md adrs/ADR-$(ls adrs/ADR-*.md | wc -l | xargs -I {} expr {} + 1)-your-title.md
```

### arc42 (Structure ready, content pending ⏳)
The arc42 structure is set up. Content will be added incrementally.

To build the documentation (once content is added):

```bash
# Install Asciidoctor
gem install asciidoctor asciidoctor-pdf asciidoctor-diagram

# Build HTML
asciidoctor arc42/master.adoc -o dist/architecture.html

# Build PDF
asciidoctor-pdf arc42/master.adoc -o dist/architecture.pdf
```

## Next Steps

1. **Start with Chapter 4** (Solution Strategy) - describes the big picture
2. **Fill in Chapter 5** (Building Block View) - describe crates and modules
3. **Add Chapter 6** (Runtime View) - describe how Event Sourcing flows work

## Resources

- arc42 Template: https://arc42.org/template/
- arc42 in AsciiDoc: https://github.com/arc42/arc42-asciidoc
- C4 Model: https://c4model.com/ (for system context diagrams)

---

**Note**: This is a living document. Update it as the architecture evolves.
