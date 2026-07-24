# ADR-008: Documentation Tooling and Structure

**Status**: Accepted
**Date**: 2026-06-17
**Author**: Tobias Rademacher (@tradem)

---

## Context

Breakdown RS needs a clear, maintainable documentation strategy that serves different audiences and purposes:

1. **Architecture Documentation**: Detailed technical documentation following arc42 template
2. **Decision Records**: ADRs for tracking architectural decisions
3. **User/Developer Guides**: Operational documentation, tutorials, how-tos

Current situation:
- ADRs are in Markdown (working well)
- arc42 is set up for AsciiDoc (`.adoc`) but content not yet written
- No clear strategy for user/developer documentation
- AsciiDoc requires Ruby/Asciidoctor installation which adds complexity to the toolchain

Requirements:
- **Simple toolchain**: Minimize dependencies for generating documentation
- **Version control friendly**: Text-based formats that diff well
- **Multiple output formats**: Ability to generate PDF, HTML, or host on GitHub Pages
- **Framework alignment**: Documentation structure should follow established best practices

## Decision

We will adopt a **multi-format documentation strategy** based on audience and purpose:

### 1. Documentation Formats

| Documentation Type | Format | Tool | Hosting |
|-------------------|--------|------|---------|
| **ADRs** | Markdown | - | GitHub (versioned) |
| **arc42 Architecture** | Typst | `typst` | GitHub Releases (PDF), GitHub Repo (source) |
| **Tutorials (Learning-oriented)** | Markdown | `mdbook` or GitHub Pages | GitHub Pages |
| **How-to Guides (Problem-oriented)** | Markdown | `mdbook` or GitHub Pages | GitHub Pages |
| **Reference (Information-oriented)** | Markdown | `mdbook` or GitHub Pages | GitHub Pages |
| **Explanation (Understanding-oriented)** | Markdown | `mdbook` or GitHub Pages | GitHub Pages |

### 2. Typst for arc42

We will use **Typst** instead of AsciiDoc for the arc42 architecture documentation:

**Rationale**:
- ✅ **No Runtime Dependencies**: Typst is a single binary (written in Rust), no Ruby/Python/Node required
- ✅ **Fast Compilation**: Typst compiles documents in milliseconds
- ✅ **Modern Syntax**: Typst's markup is more intuitive than AsciiDoc
- ✅ **PDF by Default**: Native PDF generation without extensions
- ✅ **Version Control Friendly**: Clean diffs, no generated intermediate files
- ✅ **Rust Ecosystem**: Fits our technology stack (Rust project)

### 3. Diátaxis Framework for User/Developer Documentation

All non-architecture documentation will follow the **Diátaxis Framework**:
- **Tutorials**: Learning-oriented, getting started guides
- **How-to Guides**: Problem-oriented, step-by-step recipes
- **Reference**: Information-oriented, technical descriptions
- **Explanation**: Understanding-oriented, background context

### 4. Hosting Strategy

- **ADRs**: Stored in `docs/architecture/adrs/` (versioned with code)
- **arc42**: Source in `docs/architecture/arc42-typst/`, PDF releases in GitHub Releases
- **Diátaxis Docs**: GitHub Pages via `docs/` folder or separate `mdbook` output
- **GitHub Wiki**: Considered but **not adopted** (Diátaxis works better with structured documentation in repo)

## Consequences

### Positive
- ✅ **Simplified Toolchain**: Only need `typst` CLI (single binary) for architecture docs
- ✅ **Fast Feedback**: Typst's fast compilation enables quick preview during writing
- ✅ **Clear Structure**: Diátaxis provides proven documentation taxonomy
- ✅ **Version Control**: All docs versioned with code (except generated PDFs)
- ✅ **Rust Alignment**: Typst is Rust-native, fits project identity
- ✅ **No Vendor Lock-in**: Markdown/Typst are open formats

### Negative
- ⚠️ **Typst Ecosystem**: Younger than AsciiDoc, fewer templates/examples
- ⚠️ **Learning Curve**: Team must learn Typst syntax (though simpler than AsciiDoc)
- ⚠️ **Conversion Effort**: Existing arc42 structure needs migration from AsciiDoc to Typst
- ⚠️ **Diátaxis Discipline**: Requires ongoing effort to categorize docs correctly

### Mitigation
- Create Typst templates for arc42 to reduce boilerplate
- Document Typst snippets in `AGENTS.md` or project wiki
- Use `mdbook` for Diátaxis docs (simple, Rust-native, supports Markdown)

## Alternatives Considered

### 1. AsciiDoc (Status Quo)
- **Pros**: Mature, arc42 templates available, powerful features
- **Cons**: Requires Ruby, Asciidoctor gem management, slower compilation
- **Why not**: Toolchain complexity outweighs benefits for our needs

### 2. LaTeX
- **Pros**: Powerful, professional output
- **Cons**: Steep learning curve, heavy toolchain, verbose syntax
- **Why not**: Overkill for our documentation needs

### 3. MkDocs/Material
- **Pros**: Beautiful output, easy to use
- **Cons**: Requires Python, another dependency
- **Why not**: Prefer Rust-native toolchain where possible

### 4. GitHub Wiki Only
- **Pros**: Easy to edit, good for collaboration
- **Cons**: Not versioned with code, disorganized over time
- **Why not**: Diátaxis needs structure; wikis tend to become messy

## Implementation Plan

1. **Remove AsciiDoc**: Delete `docs/architecture/arc42/` (placeholder only, no content)
2. **Create Typst Template**: Set up `docs/architecture/arc42-typst/` with arc42-compliant Typst template
3. **Create arc42 Entry Point**: `main.typ` as the main document that includes all chapters
4. **Migrate Structure**: Create Typst files for all 12 arc42 chapters
5. **Set Up mdbook**: Initialize `mdbook` for Diátaxis documentation (optional, can start with plain Markdown)
6. **Update README**: Document the new toolchain and how to build docs

## Notes

### Typst Installation
```bash
# Install Typst (Rust-native, single binary)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
cargo install --git https://github.com/typst/typst --locked
# Or download pre-built binary from GitHub releases
```

### Building arc42 PDF
```bash
cd docs/architecture/arc42-typst
typst compile main.typ architecture.pdf
```

### Diátaxis Resources
- Website: https://diataxis.fr/
- Framework: https://diataxis.fr/how-to-use-diataxis/
- mdbook: https://rust-lang.github.io/mdbook/

### Typst Resources
- Website: https://typst.app/
- Docs: https://typst.app/docs/
- arc42 in Typst: Custom template (see `docs/architecture/arc42-typst/`)

---

**Related ADRs**:
- None yet (this is the foundational documentation ADR)

**Related Docs**:
- [Diátaxis Framework](https://diataxis.fr/)
- [Typst Documentation](https://typst.app/docs/)
- [arc42 Template](https://arc42.org/template/)
