# Font Assets for Report Rendering

This directory will contain a reviewed OFL-1.1 font bundle for deterministic
Latin text rendering in PDF reports.

## Planned Fonts

- **Noto Sans** (Google, OFL-1.1) — Primary Latin font for de-DE reports
- **Noto Serif** (Google, OFL-1.1) — Serif fallback if needed

## Status

⚠️ **Pending review**: Font files and licence notices need to be reviewed
and added before the first production release.

## How to Add Fonts

1. Download OFL-1.1 licensed font files (e.g., from Google Fonts)
2. Place `.ttf` files in this directory
3. Add licence notices in `NOTICE.md`
4. Update the `TypstReportRenderer::with_defaults()` to load from this directory

## Licence

All fonts in this directory must be OFL-1.1 licensed.
See https://scripts.sil.org/OFL for the full licence text.
