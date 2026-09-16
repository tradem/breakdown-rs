// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// DTCG conformance check for the token source under `design/tokens/`
// (spec `design-tokens`, task 1.5). Invoked by `scripts/build-tokens.sh`
// BEFORE generation: a build never runs on a non-conformant source.
//
// Checks (W3C Design Tokens Community Group format, stable 2025-10):
//   1. Only DTCG-reserved `$`-prefixed properties are used (`$value`,
//      `$type`, `$description`) — no invented `$` keys.
//   2. Every leaf token has a `$value` and a `$type` from the
//      supported set (`color`, `dimension`).
//   3. Every `{alias.reference}` in a `$value` resolves to an existing
//      token path in the merged token tree.
//
// Exit code 0 = conformant; 1 = violations listed on stderr.

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const repoRoot = new URL('../', import.meta.url).pathname;
const tokensDir = join(repoRoot, 'design', 'tokens');

const SUPPORTED_TYPES = new Set(['color', 'dimension']);
const RESERVED_KEYS = new Set(['$value', '$type', '$description']);

/** @type {string[]} */
const violations = [];

/** Collect raw JSON token trees. */
function collectFiles(dir) {
  return readdirSync(dir, { withFileTypes: true })
    .filter((e) => e.isFile() && e.name.endsWith('.json'))
    .map((e) => join(dir, e.name));
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
  const aliases = typeof value === 'string' ? [...value.matchAll(ALIAS_RE)] : [];
  for (const alias of aliases) {
    const ref = alias[1].replace(/\.value$/, '');
    if (!allTokenPaths.has(ref)) {
      violations.push(
        `${relFile}: token "${path}" has an unresolvable alias "{${ref}}"`,
      );
    }
  }
  if (node.$type === 'color' && typeof value === 'string') {
    // Primitive hex colors (#rgb, #rrggbb, #aarrggbb).
    if (!/^(#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})|{[^{}]+})$/i.test(value)) {
      violations.push(
        `${relFile}: color token "${path}" has a non-hex "$value": "${value}"`,
      );
    }
  }
  if (node.$type === 'dimension' && typeof value !== 'number') {
    violations.push(
      `${relFile}: dimension token "${path}" must have a numeric "$value" ` +
        `(logical px, unitless) — got: ${JSON.stringify(value)}`,
    );
  }
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

// 1. Parse every token file (JSON validity is itself part of conformance).
/** @type {[string, object][]} */
const trees = [];
for (const entry of readdirSync(tokensDir, { withFileTypes: true })) {
  if (!e_isJson(entry)) continue;
  const file = join(tokensDir, entry.name);
  const rel = relative(repoRoot, file);
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(file, 'utf8'));
  } catch (err) {
    violations.push(`${rel}: invalid JSON (${err.message})`);
    continue;
  }
  trees.push([rel, parsed]);
}

function e_isJson(entry) {
  return entry.isFile() && entry.name.endsWith('.json');
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
  `design/tokens: DTCG conformance OK (${trees.length} file(s), ` +
    `${allTokenPaths.size} token(s))`,
);
