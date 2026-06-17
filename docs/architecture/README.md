# Architecture Documentation

This directory contains the architecture documentation for Breakdown RS.

## Structure

```
architecture/
├── adrs/                    # Architecture Decision Records (Markdown)
│   ├── README.md
│   ├── templates/
│   ├── ADR-001-hexagonal-architecture.md
│   ├── ADR-002-event-sourcing-cqrs.md
│   ├── ...
│   └── ADR-008-documentation-tooling-and-structure.md
│
└── arc42-typst/             # arc42 Architecture Documentation (Typst)
    ├── main.typ             # Main document (entry point)
    ├── template.typ         # Styling template
    ├── 01-introduction-and-goals.typ
    ├── 02-architecture-constraints.typ
    ├── 03-system-scope-context.typ
    ├── 04-solution-strategy.typ
    ├── 05-building-block-view.typ
    ├── 06-runtime-view.typ
    ├── 07-deployment-view.typ
    ├── 08-crosscutting-concepts.typ
    ├── 09-architecture-decisions.typ
    ├── 10-quality-requirements.typ
    ├── 11-risks-technical-debt.typ
    └── 12-glossary.typ
```

## Documentation Strategy

We use a **multi-format approach** based on audience and purpose (see ADR-008):

| Type | Format | Tool | Hosting |
|------|--------|------|--------|
| **ADRs** | Markdown | - | GitHub (versioned) |
| **arc42** | Typst | `typst` | GitHub Releases (PDF) |
| **Diátaxis Docs** | Markdown | `mdbook` | GitHub Pages |

### Why Typst instead of AsciiDoc?

- ✅ **No Runtime Dependencies**: Single binary (Rust-native)
- ✅ **Fast Compilation**: Milliseconds vs seconds
- ✅ **Simple Toolchain**: No Ruby/Gem management
- ✅ **Native PDF**: No extensions needed

## Getting Started

### ADRs (Ready to use ✅)
Navigate to `adrs/` and read the existing ADRs. To create a new ADR:

```bash
cp adrs/templates/ADR-template.md adrs/ADR-$(ls adrs/ADR-*.md | wc -l | xargs -I {} expr {} + 1)-your-title.md
```

### arc42 in Typst (Structure ready, content pending ⏳)
The arc42 structure is set up in Typst format. Content will be added incrementally.

#### Install Typst

```bash
# Option 1: Install via Cargo (Rust)
cargo install --git https://github.com/typst/typst --locked

# Option 2: Download pre-built binary
# Visit: https://github.com/typst/typst/releases
```

#### Build PDF

```bash
cd arc42-typst

# Build once
typst compile main.typ architecture.pdf

# Watch mode (auto-recompile on changes)
typst watch main.typ architecture.pdf
```

#### Preview in Browser (Optional)

```bash
# Install typst-preview (VS Code extension or CLI)
# VS Code: Install "Typst LSP" and "Typst Preview" extensions
```

## Next Steps

1. **Start with Chapter 4** (Solution Strategy) - describes the big picture
2. **Fill in Chapter 5** (Building Block View) - describe crates and modules
3. **Add Chapter 6** (Runtime View) - describe how Event Sourcing flows work
4. **Link ADRs** in Chapter 9 (Architecture Decisions)

## Typst Template Features

The `template.typ` provides:
- 📄 Professional PDF styling (A4, margins, headers/footers)
- 🎨 Admonition boxes (`#note[...]`, `#warning[...]`, etc.)
- 📊 Table styling
- 🔗 ADR cross-references (`#adr-ref(num: 5, title: "...")`)
- 📝 Code listing with captions
- 🖼️ Mermaid diagram support (via ````mermaid` blocks)

## Resources

- **arc42 Template**: https://arc42.org/template/
- **Typst Documentation**: https://typst.app/docs/
- **Typst GitHub**: https://github.com/typst/typst
- **Diátaxis Framework**: https://diataxis.fr/
- **C4 Model**: https://c4model.com/ (for system context diagrams)

---

**Note**: This is a living document. Update it as the architecture evolves.
