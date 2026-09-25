#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: space-bunny-free (opencode)
"""Verify the implemented ARB inventory embedded in docs/design/glossary.md.

The glossary keeps two key namespaces (see its "Two distinct key namespaces"
section): the dotted *logical design* vocabulary used by the table, and the
flat `camelCase` *ARB identifiers* the Dart code actually calls.

This check makes the second one trustworthy: every identifier listed in the
`implemented-inventory` table must exist in BOTH ARB catalogs, and both
catalogs must stay key-identical. It cannot prove the mapping is 1:1 (the
mapping is intentionally not mechanical), so it only guards against rot —
a typo, a removed key, or a catalog that drifted apart.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GLOSSARY = REPO / "docs/design/glossary.md"
ARB_DE = REPO / "frontend-flutter/lib/l10n/app_de.arb"
ARB_EN = REPO / "frontend-flutter/lib/l10n/app_en.arb"

MARKER = "<!-- implemented-inventory:start -->"
END = "<!-- implemented-inventory:end -->"
# The inventory lists area rows whose second cell is a comma-separated list
# of backticked ARB identifiers, e.g. ``| Auth | `appTitle`, `navMore` |``.
IDENTIFIER = re.compile(r"`([A-Za-z][A-Za-z0-9_]*)`")


def catalog_keys(path: Path) -> set[str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    return {key for key in data if not key.startswith("@")}


def main() -> int:
    text = GLOSSARY.read_text(encoding="utf-8")
    if MARKER not in text or END not in text:
        print(f"FAIL: glossary is missing the {MARKER} inventory block", file=sys.stderr)
        return 1

    block = text.split(MARKER, 1)[1].split(END, 1)[0]
    listed: set[str] = set()
    for line in block.splitlines():
        if not line.startswith("|"):
            continue
        listed.update(IDENTIFIER.findall(line))

    de, en = catalog_keys(ARB_DE), catalog_keys(ARB_EN)

    errors: list[str] = []
    if de != en:
        errors.append(
            "ARB catalogs diverged: "
            f"de-only={sorted(de - en)} en-only={sorted(en - de)}"
        )
    if not listed:
        errors.append("inventory block lists no ARB identifiers")
    missing = sorted(key for key in listed if key not in de or key not in en)
    if missing:
        errors.append(f"inventory references unknown ARB identifiers: {missing}")

    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1

    print(
        f"glossary inventory OK: {len(listed)} ARB identifiers documented, "
        f"catalogs in parity ({len(de)} keys)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
