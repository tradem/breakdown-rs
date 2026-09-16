// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// DTCG conformance check for the token source under `design/tokens/`
// (spec `design-tokens`, task 1.5). Invoked by `scripts/build-tokens.sh`
// BEFORE generation: a build never runs on a non-conformant source.
//
// Checks (W3C Design Tokens Format Module 2025.10):
//   1. Only DTCG-reserved `$`-prefixed properties are used (`$value`,
//      `$type`, `$description`) — no invented `$` keys.
//   2. Every leaf token has a `$value` and a `$type` from the
//      supported set, with the structured `$value` shape the spec
//      mandates:
//        * `color` → `{colorSpace, components, alpha?, hex?}` (bare hex
//          strings are NOT valid in 2025.10); `colorSpace: "srgb"` is
//          validated fully (3 components in [0,1], optional alpha in
//          [0,1], optional 6-digit `hex` fallback consistent with
//          components).
//        * `dimension` → `{value: number, unit: "px"|"rem"}` (unit
//          mandatory even for 0); the Flutter pipeline only implements
//          `"px"` (logical px → Dart double 1:1), so the validator
//          requires it.
//        * `fontWeight` → number 100–900.
//   3. Every `{alias.reference}` in a `$value` resolves to an existing
//      token path in the merged token tree.
//   4. Recursion: every JSON file under `design/tokens/**` is checked —
//      matching the Style Dictionary source glob
//      `design/tokens/**/*.json` (nested files get no free pass).
//
// Exit code 0 = conformant; 1 = violations listed on stderr.

import { readFileSync, readdirSync } from 'node:fs';
import { join, relative as relPath } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRootAbs = fileURLToPath(new URL('../', import.meta.url));
const tokensDir = join(repoRootAbs, 'design', 'tokens');

const SUPPORTED_TYPES = new Set(['color', 'dimension', 'fontWeight']);
const RESERVED_KEYS = new Set(['$value', '$type', '$description']);
const SUPPORTED_COLOR_SPACES = new Set(['srgb']); // extended when a token needs it

/** @type {string[]} */
const violations = [];

// Recursively enumerate JSON files under dir (matches the "dir/**/*.json" glob
// of the Style Dictionary source).
function collectFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return collectFiles(path);
    return entry.isFile() && entry.name.endsWith('.json') ? [path] : [];
  });
}

/** Every group → leaf path in the merged tree, e.g. `color.brand.seed`. */
function allPaths(node, prefix = '', acc = new Set()) {
  if (typeof node !== 'object' || node === null) return acc;
  for (const [key, value] of Object.entries(node)) {
    if (key.startsWith('$')) continue; // reserved attributes are not paths
    if (typeof value === 'object' && value !== null && !('$value' in value)) {
      allPaths(value, prefix ? `${prefix}.${key}` : key, acc);
    } else {
      acc.add(prefix ? `${prefix}.${key}` : key);
    }
  }
  return acc;
}

/** Alias references like `{color.brand.seed}` (or several, interpolated). */
const ALIAS_RE = /\{([^{}]+)\}/g;
// Non-global twin for existence tests: a /g regex's `.test()` mutates
// `lastIndex`, which would silently truncate a later `matchAll` scan.
const ALIAS_TEST_RE = /\{([^{}]+)\}/;

function checkAliasRefs(relFile, path, rawValue, allTokenPaths) {
  if (typeof rawValue !== 'string') return;
  for (const alias of rawValue.matchAll(ALIAS_RE)) {
    const ref = alias[1].replace(/\.value$/, '');
    if (!allTokenPaths.has(ref)) {
      violations.push(
        `${relFile}: token "${path}" has an unresolvable alias "{${ref}}"`,
      );
    }
  }
}

function checkColorValue(relFile, path, value) {
  if (typeof value === 'string') {
    // Alias reference to another color token is permitted.
    if (!ALIAS_TEST_RE.test(value)) {
      violations.push(
        `${relFile}: color token "${path}" uses a scalar "$value" ` +
          `("${value}") — DTCG 2025.10 requires {colorSpace, components, alpha?, hex?} ` +
          '("hex" alone is only an optional fallback inside the object)',
      );
    }
    return;
  }
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    violations.push(
      `${relFile}: color token "${path}" "$value" must be a structured object`,
    );
    return;
  }
  if (value.colorSpace !== 'srgb') {
    violations.push(
      `${relFile}: color token "${path}" has unsupported "colorSpace": ` +
        `${JSON.stringify(value.colorSpace)} (supported: ${[...SUPPORTED_COLOR_SPACES].join(', ')})`,
    );
  }
  if (
    !Array.isArray(value.components) ||
    value.components.length !== 3 ||
    value.components.some((c) => typeof c !== 'number' || c < 0 || c > 1)
  ) {
    violations.push(
      `${relFile}: color token "${path}" "components" must be 3 numbers in [0,1] (srgb)`,
    );
  }
  if ('alpha' in value && (typeof value.alpha !== 'number' || value.alpha < 0 || value.alpha > 1)) {
    violations.push(
      `${relFile}: color token "${path}" "alpha" must be a number in [0,1]`,
    );
  }
  if ('hex' in value) {
    const m = typeof value.hex === 'string' && value.hex.match(/^#([0-9a-f]{6})$/i);
    if (!m) {
      violations.push(
        `${relFile}: color token "${path}" "hex" fallback must be 6-digit CSS hex`,
      );
    } else if (Array.isArray(value.components) && value.components.length === 3) {
      // The authored hex and components must agree exactly (no rounding drift
      // between the two encodings of the same color).
      for (let i = 0; i < 3; i++) {
        const comp255 = Math.round(value.components[i] * 255);
        const hexComp = parseInt(m[1].slice(i * 2, i * 2 + 2), 16);
        if (comp255 !== hexComp) {
          violations.push(
            `${relFile}: color token "${path}" "hex" (${value.hex}) does not match ` +
              `"components" (component ${i}: ${comp255} ≠ ${hexComp})`,
          );
        }
      }
    }
  }
}

function checkDimensionValue(relFile, path, value) {
  if (
    typeof value !== 'object' ||
    value === null ||
    typeof value.value !== 'number' ||
    !Number.isFinite(value.value)
  ) {
    violations.push(
      `${relFile}: dimension token "${path}" "$value" must be ` +
        `{value: number, unit: "px"|"rem"} per DTCG 2025.10 (unit mandatory even for 0)`,
    );
    return;
  }
  if (value.unit !== 'px') {
    violations.push(
      `${relFile}: dimension token "${path}" has unit ${JSON.stringify(value.unit)} — ` +
        `the Flutter pipeline implements only "px" (logical px → Dart double)`,
    );
  }
}

function checkLeaf(relFile, path, node, allTokenPaths) {
  if (!('$value' in node)) {
    violations.push(`${relFile}: token "${path}" is missing "$value"`);
    return;
  }
  if (!('$type' in node)) {
    violations.push(`${relFile}: token "${path}" is missing "$type"`);
    return;
  }
  if (!SUPPORTED_TYPES.has(node.$type)) {
    violations.push(
      `${relFile}: token "${path}" has unsupported "$type": "${node.$type}" ` +
        `(supported: ${[...SUPPORTED_TYPES].join(', ')})`,
    );
    return;
  }
  const value = node.$value;
  if (node.$type === 'color') checkColorValue(relFile, path, value);
  else if (node.$type === 'dimension') checkDimensionValue(relFile, path, value);
  else if (
    typeof value !== 'number' ||
    !Number.isInteger(value) ||
    value < 100 ||
    value > 900
  ) {
    violations.push(
      `${relFile}: fontWeight token "${path}" must be a number 100–900`,
    );
  }
  checkAliasRefs(relFile, path, typeof value === 'string' ? value : undefined, allTokenPaths);
}

function walk(relFile, node, prefix, allTokenPaths) {
  for (const [key, value] of Object.entries(node)) {
    if (key.startsWith('$')) {
      if (!RESERVED_KEYS.has(key)) {
        violations.push(
          `${relFile}: unknown DTCG-reserved property "${key}" ` +
            `(allowed: ${[...RESERVED_KEYS].join(', ')})`,
        );
      }
      continue;
    }
    const path = prefix ? `${prefix}.${key}` : key;
    if (typeof value === 'object' && value !== null && !('$value' in value)) {
      walk(relFile, value, path, allTokenPaths);
    } else {
      checkLeaf(relFile, path, value, allTokenPaths);
    }
  }
}

// 1. Parse every token file recursively (JSON validity is itself part of
//    conformance); the recursive enumeration mirrors the Style Dictionary
//    source glob `design/tokens/**/*.json`.
/** @type {[string, object][]} */
const trees = [];
for (const file of collectFiles(tokensDir)) {
  const rel = relPath(repoRootAbs, file);
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(file, 'utf8'));
  } catch (err) {
    violations.push(`${rel}: invalid JSON (${err.message})`);
    continue;
  }
  trees.push([rel, parsed]);
}

// 2. Build the merged alias-resolution universe (before checking refs).
const allTokenPaths = new Set();
for (const [, tree] of trees) allPaths(tree, '', allTokenPaths);

// 3. Walk and check.
for (const [rel, tree] of trees) {
  walk(rel, tree, '', allTokenPaths);
}

if (violations.length > 0) {
  for (const v of violations) console.error(`DTCG violation: ${v}`);
  console.error(
    `design/tokens: ${violations.length} DTCG conformance violation(s) — ` +
      'fix the token source before building.',
  );
  process.exit(1);
}
console.log(
  `design/tokens: DTCG 2025.10 conformance OK (${trees.length} file(s), ` +
    `${allTokenPaths.size} token(s))`,
);
