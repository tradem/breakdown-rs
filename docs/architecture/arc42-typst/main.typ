// Breakdown RS - Architecture Documentation
// arc42 Template in Typst
// Based on: https://arc42.org/template/

#import "template.typ": *

#show: doc.with(
  title: "Breakdown RS - Architecture Documentation",
  subtitle: "arc42 Template for Architecture Documentation",
  version: "1.0",
  date: "2024-06-17",
  authors: ("Breakdown RS Team",),
)

= Introduction

This documentation follows the https://arc42.org/[arc42] template for architecture documentation.

*Status*: Structure created, content pending.

*Format*: Typst (`.typ`) - easier toolchain than AsciiDoc (no Ruby required).

*Related*: See #link("../adrs/README.md")[ADRs] for detailed architecture decisions.

#pagebreak()

// Include all arc42 chapters
#include "01-introduction-and-goals.typ"
#include "02-architecture-constraints.typ"
#include "03-system-scope-context.typ"
#include "04-solution-strategy.typ"
#include "05-building-block-view.typ"
#include "06-runtime-view.typ"
#include "07-deployment-view.typ"
#include "08-crosscutting-concepts.typ"
#include "09-architecture-decisions.typ"
#include "10-quality-requirements.typ"
#include "11-risks-technical-debt.typ"
#include "12-glossary.typ"

#pagebreak()

= Appendix

== Build Instructions

To generate the PDF from this Typst source:

```bash
# Install Typst
cargo install --git https://github.com/typst/typst --locked

# Or download pre-built binary from:
# https://github.com/typst/typst/releases

# Compile to PDF
typst compile main.typ architecture.pdf

# Watch mode (auto-recompile on changes)
typst watch main.typ architecture.pdf
```

== Tooling Comparison

| Feature | Typst | AsciiDoc |
|---------|-------|----------|
| Dependencies | Single binary | Ruby + Gems |
| Compilation speed | Milliseconds | Seconds |
| PDF output | Native | Needs extensions |
| Syntax | Intuitive | Verbose |
| Ecosystem | Growing | Mature |

== Next Steps

1. *Start with Chapter 4* (Solution Strategy) - describes the big picture
2. *Fill in Chapter 5* (Building Block View) - describe crates and modules
3. *Add Chapter 6* (Runtime View) - describe how Event Sourcing flows work
4. *Link ADRs* in Chapter 9 (Architecture Decisions)

---

*This is a living document. Update it as the architecture evolves.*
